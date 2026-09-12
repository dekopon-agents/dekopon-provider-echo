use std::path::PathBuf;

use dekopon_provider_sdk_testkit::{
    BrokerHostError, BrokerHostLimits, FakeBroker, FakeBrokerError,
};
use serde_json::{Value, json};

/// The release host settings the README documents, and what `BrokerHostLimits` defaults to.
const RELEASE_FUEL: u64 = 50_000_000;
const MAX_INPUT_BYTES: usize = 1_048_576;
const MAX_OUTPUT_BYTES: usize = 1_048_576;

fn component() -> Option<PathBuf> {
    std::env::var_os("DEKOPON_ECHO_COMPONENT").map(PathBuf::from)
}

fn cache_directory() -> Result<PathBuf, std::io::Error> {
    let directory = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("target")
        .join("broker-testkit-compile-cache");
    std::fs::create_dir_all(&directory)?;
    directory.canonicalize()
}

/// Loads the component behind the exact release host settings, with `fuel` the only dial a test
/// moves — that is what separates the 50M fuel ceiling from the 1 MiB byte ceilings.
async fn broker(component: PathBuf, fuel: u64) -> Result<FakeBroker, FakeBrokerError> {
    FakeBroker::builder()
        .component(component)
        .provider("echo")
        // No host facade is installed: the component has no imports or ambient authority.
        .host_limits(BrokerHostLimits {
            fuel,
            ..BrokerHostLimits::default()
        })
        .compile_cache(cache_directory().map_err(FakeBrokerError::from)?)
        .build()
        .await
}

/// Returns the host-imposed failure, asserting the guest was not the one that declined.
fn host_failure(error: &FakeBrokerError) -> &BrokerHostError {
    assert!(
        error.provider_failure().is_none(),
        "expected a host refusal, not a provider-declared failure: {error}"
    );
    match error {
        FakeBrokerError::Invocation(failure) => failure.error.as_ref(),
        other => panic!("expected an invocation failure, got {other}"),
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn broker_invokes_every_capability_concurrently_without_imports()
-> Result<(), Box<dyn std::error::Error>> {
    let Some(component) = component() else {
        return Ok(());
    };
    let defaults = BrokerHostLimits::default();
    assert_eq!(defaults.max_memory_bytes, 64 * 1024 * 1024);
    assert_eq!(defaults.max_input_bytes, MAX_INPUT_BYTES);
    assert_eq!(defaults.max_output_bytes, MAX_OUTPUT_BYTES);
    assert_eq!(defaults.max_timeout.as_secs(), 30);

    let broker = broker(component, RELEASE_FUEL).await?;

    // The host also bounds the aggregate of all live stores, at 256 MiB, so the exact release
    // per-invocation ceiling of 64 MiB admits four concurrent invocations and refuses the fifth.
    let echo = broker.invoke("echo.echo", json!({"nested": [null, "🦀"]}));
    let reverse = broker.invoke("echo.reverse", json!({"message": "a🦀é"}));
    let upcase = broker.invoke("echo.upcase", json!({"message": "Straße"}));
    let downcase = broker.invoke("echo.downcase", json!({"message": "Δ WORLD"}));
    let (echo, reverse, upcase, downcase) = tokio::join!(echo, reverse, upcase, downcase);

    assert_eq!(echo?, json!({"nested": [null, "🦀"]}));
    assert_eq!(reverse?, json!({"message": "é🦀a"}));
    assert_eq!(upcase?, json!({"message": "STRASSE"}));
    assert_eq!(downcase?, json!({"message": "δ world"}));
    assert_eq!(
        broker
            .invoke("echo.ransom-case", json!({"message": "Hello, World!"}))
            .await?,
        json!({"message": "hElLo, WoRlD!"})
    );

    for malformed in [
        json!({"message": 42}),
        json!({"message": "x", "extra": true}),
        json!({}),
    ] {
        let failure = broker
            .invoke("echo.upcase", malformed)
            .await
            .expect_err("provider rejection is preserved");
        let provider_failure = failure
            .provider_failure()
            .expect("failure was declared by provider");
        assert_eq!(provider_failure.0, "invalid-input");
        assert_eq!(
            provider_failure.1,
            "input must contain exactly one string field named \"message\""
        );
    }

    let failure = broker
        .invoke("other.read", json!({}))
        .await
        .expect_err("an unrouted capability never reaches the guest");
    assert!(matches!(
        host_failure(&failure),
        BrokerHostError::UnknownCapability { .. }
    ));
    Ok(())
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn release_host_ceilings_bound_wire_input_and_provider_output()
-> Result<(), Box<dyn std::error::Error>> {
    let Some(component) = component() else {
        return Ok(());
    };
    let broker = broker(component.clone(), RELEASE_FUEL).await?;

    // Just under the 1 MiB wire ceiling: the round trip has to succeed, in and out.
    let near_limit = json!({"data": "x".repeat(900_000)});
    assert!(serde_json::to_string(&near_limit)?.len() < MAX_INPUT_BYTES);
    let output = broker.invoke("echo.echo", near_limit).await?;
    assert_eq!(
        output["data"].as_str().map(str::len),
        Some(900_000),
        "the near-limit payload came back changed"
    );
    assert!(serde_json::to_string(&output)?.len() < MAX_OUTPUT_BYTES);

    // NUL escaping makes this semantic value exceed the serialized input limit: 180,000 NULs are
    // 180,000 source bytes but 1,080,000 `\u0000` wire bytes.
    let oversize = json!({"data": "\0".repeat(180_000)});
    assert!(serde_json::to_string(&oversize)?.len() > MAX_INPUT_BYTES);
    let failure = broker
        .invoke("echo.echo", oversize)
        .await
        .expect_err("over-1-MiB wire input must be refused before the guest runs");
    match host_failure(&failure) {
        BrokerHostError::InputTooLarge {
            length, maximum, ..
        } => {
            assert!(*length > MAX_INPUT_BYTES);
            assert_eq!(*maximum, MAX_INPUT_BYTES);
        }
        other => panic!("expected InputTooLarge, got {other}"),
    }

    // The exact release fuel must execute Unicode case expansion with ample headroom.
    let expanded = broker
        .invoke("echo.upcase", json!({"message": "Straße ".repeat(10_000)}))
        .await?;
    assert!(
        expanded["message"]
            .as_str()
            .is_some_and(|message| message.starts_with("STRASSE STRASSE"))
    );
    Ok(())
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn output_expansion_past_one_mebibyte_is_refused_with_fuel_to_spare()
-> Result<(), Box<dyn std::error::Error>> {
    let Some(component) = component() else {
        return Ok(());
    };
    // Isolate the 1 MiB output ceiling from the separate 50M release fuel ceiling: this expansion
    // needs extra fuel to finish producing the response the host then rejects.
    let broker = broker(component, 500_000_000).await?;

    // Lowercasing U+0130 expands its two-byte UTF-8 input to three bytes (i plus combining dot).
    let input = json!({"message": "İ".repeat(400_000)});
    assert!(serde_json::to_string(&input)?.len() < MAX_INPUT_BYTES);
    let failure = broker
        .invoke("echo.downcase", input)
        .await
        .expect_err("over-1-MiB provider output must be refused");
    match host_failure(&failure) {
        BrokerHostError::OutputTooLarge {
            length, maximum, ..
        } => {
            assert!(*length > MAX_OUTPUT_BYTES, "output was only {length} bytes");
            assert_eq!(*maximum, MAX_OUTPUT_BYTES);
        }
        other => panic!("expected OutputTooLarge, got {other}"),
    }
    Ok(())
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn the_component_declares_no_command_words() -> Result<(), Box<dyn std::error::Error>> {
    let Some(component) = component() else {
        return Ok(());
    };
    let broker = broker(component, RELEASE_FUEL).await?;
    assert_eq!(broker.registry().command_words(), Vec::<String>::new());
    // `echo.echo` returns any semantic JSON value unchanged, including the ones a schema with
    // `additionalProperties: true` still admits.
    assert_eq!(
        broker.invoke("echo.echo", json!({})).await?,
        Value::Object(serde_json::Map::new())
    );
    Ok(())
}
