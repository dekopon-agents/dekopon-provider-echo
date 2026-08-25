use std::path::PathBuf;

use dekopon_provider_sdk_testkit::{BrokerHostLimits, FakeBroker};
use serde_json::json;

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

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn broker_invokes_every_capability_concurrently_without_imports()
-> Result<(), Box<dyn std::error::Error>> {
    let Some(component) = component() else {
        return Ok(());
    };
    let defaults = BrokerHostLimits::default();
    assert_eq!(defaults.max_memory_bytes, 64 * 1024 * 1024);
    assert_eq!(defaults.max_input_bytes, 1_048_576);
    assert_eq!(defaults.max_output_bytes, 1_048_576);
    assert_eq!(defaults.max_timeout.as_secs(), 30);

    let broker = FakeBroker::builder()
        .component(component)
        .provider("echo")
        // No host facade is installed: the component has no imports or ambient authority.
        .host_limits(BrokerHostLimits {
            fuel: 50_000_000,
            ..defaults
        })
        .compile_cache(cache_directory()?)
        .build()
        .await?;

    let echo = broker.invoke("echo.echo", json!({"nested": [null, "🦀"]}));
    let reverse = broker.invoke("echo.reverse", json!({"message": "a🦀é"}));
    let upcase = broker.invoke("echo.upcase", json!({"message": "Straße"}));
    let downcase = broker.invoke("echo.downcase", json!({"message": "Δ WORLD"}));
    let ransom = broker.invoke("echo.ransom-case", json!({"message": "Hello, World!"}));
    let (echo, reverse, upcase, downcase, ransom) =
        tokio::join!(echo, reverse, upcase, downcase, ransom);

    assert_eq!(echo?, json!({"nested": [null, "🦀"]}));
    assert_eq!(reverse?, json!({"message": "é🦀a"}));
    assert_eq!(upcase?, json!({"message": "STRASSE"}));
    assert_eq!(downcase?, json!({"message": "δ world"}));
    assert_eq!(ransom?, json!({"message": "hElLo, WoRlD!"}));

    let failure = broker
        .invoke("echo.upcase", json!({"message": 42}))
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

    let stats = broker.registry().metrics().snapshot();
    assert!(stats.fuel_observations >= 6);
    assert!(stats.fuel_consumed > 0);
    Ok(())
}
