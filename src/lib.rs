//! Import-free Dekopon provider for structured echo and Unicode transformations.

use dekopon_provider_sdk::{
    CapabilityId, EffectKind, Provider, ProviderApiVersion, ProviderCapability, ProviderError,
    ProviderManifest, RiskLevel, export_provider,
};
use serde_json::{Value, json};

struct EchoProvider;

impl Provider for EchoProvider {
    fn manifest() -> ProviderManifest {
        ProviderManifest {
            api_version: ProviderApiVersion::V1Alpha1,
            id: "echo".parse().expect("static provider ID is valid"),
            description: "Echoes structured input and transforms messages".to_owned(),
            command_words: Vec::new(),
            capabilities: vec![
                ProviderCapability {
                    id: "echo.echo".parse().expect("static capability ID is valid"),
                    description: "Returns the supplied JSON object unchanged".to_owned(),
                    effect: EffectKind::ReadOnly,
                    risk: RiskLevel::Low,
                    input_schema: json!({
                        "type": "object",
                        "additionalProperties": true
                    }),
                },
                message_capability(
                    "echo.reverse",
                    "Reverses the Unicode scalar values in a message",
                ),
                message_capability("echo.upcase", "Converts a message to Unicode uppercase"),
                message_capability("echo.downcase", "Converts a message to Unicode lowercase"),
                message_capability(
                    "echo.ransom-case",
                    "Alternates message letters between lowercase and uppercase",
                ),
            ],
        }
    }

    fn invoke(capability: &CapabilityId, input: Value) -> Result<Value, ProviderError> {
        match capability.as_str() {
            "echo.echo" => Ok(input),
            "echo.reverse" => transform_message(input, |message| message.chars().rev().collect()),
            "echo.upcase" => transform_message(input, str::to_uppercase),
            "echo.downcase" => transform_message(input, str::to_lowercase),
            "echo.ransom-case" => transform_message(input, ransom_case),
            _ => Err(ProviderError::new(
                "unsupported-capability",
                format!("echo does not implement {capability}"),
            )),
        }
    }
}

fn message_capability(id: &str, description: &str) -> ProviderCapability {
    ProviderCapability {
        id: id.parse().expect("static capability ID is valid"),
        description: description.to_owned(),
        effect: EffectKind::ReadOnly,
        risk: RiskLevel::Low,
        input_schema: json!({
            "type": "object",
            "properties": {"message": {"type": "string"}},
            "required": ["message"],
            "additionalProperties": false
        }),
    }
}

fn transform_message(
    input: Value,
    transform: impl FnOnce(&str) -> String,
) -> Result<Value, ProviderError> {
    let object = input.as_object().ok_or_else(invalid_message_input)?;
    if object.len() != 1 {
        return Err(invalid_message_input());
    }
    let message = object
        .get("message")
        .and_then(Value::as_str)
        .ok_or_else(invalid_message_input)?;
    Ok(json!({"message": transform(message)}))
}

fn invalid_message_input() -> ProviderError {
    ProviderError::new(
        "invalid-input",
        "input must contain exactly one string field named \"message\"",
    )
}

fn ransom_case(message: &str) -> String {
    let mut uppercase = false;
    let mut output = String::with_capacity(message.len());
    for character in message.chars() {
        if character.is_alphabetic() {
            if uppercase {
                output.extend(character.to_uppercase());
            } else {
                output.extend(character.to_lowercase());
            }
            uppercase = !uppercase;
        } else {
            output.push(character);
        }
    }
    output
}

export_provider!(EchoProvider);

#[cfg(test)]
mod tests {
    use super::*;

    const INVALID_MESSAGE: &str = "input must contain exactly one string field named \"message\"";

    fn capability(id: &str) -> CapabilityId {
        id.parse().expect("valid capability fixture")
    }

    fn invoke(id: &str, message: &str) -> Value {
        EchoProvider::invoke(&capability(id), json!({"message": message}))
            .expect("transformation succeeds")
    }

    #[test]
    fn manifest_preserves_the_complete_ordered_contract() {
        let manifest = EchoProvider::manifest();
        assert_eq!(manifest.api_version, ProviderApiVersion::V1Alpha1);
        assert_eq!(manifest.id.as_str(), "echo");
        assert_eq!(
            manifest.description,
            "Echoes structured input and transforms messages"
        );
        assert!(manifest.command_words.is_empty());
        assert_eq!(
            manifest
                .capabilities
                .iter()
                .map(|item| item.id.as_str())
                .collect::<Vec<_>>(),
            [
                "echo.echo",
                "echo.reverse",
                "echo.upcase",
                "echo.downcase",
                "echo.ransom-case",
            ]
        );
        for item in &manifest.capabilities {
            assert_eq!(item.effect, EffectKind::ReadOnly);
            assert_eq!(item.risk, RiskLevel::Low);
        }
        assert_eq!(
            manifest.capabilities[0].input_schema,
            json!({"type": "object", "additionalProperties": true})
        );
        for item in &manifest.capabilities[1..] {
            assert_eq!(
                item.input_schema,
                json!({
                    "type": "object",
                    "properties": {"message": {"type": "string"}},
                    "required": ["message"],
                    "additionalProperties": false
                })
            );
        }
    }

    #[test]
    fn plain_echo_returns_every_json_value_unchanged() {
        for input in [
            json!({}),
            json!({"nested": {"answer": 42}, "items": [null, true, "🦀"]}),
            json!([1, 2, 3]),
            json!("Straße"),
            json!(42),
            Value::Null,
        ] {
            assert_eq!(
                EchoProvider::invoke(&capability("echo.echo"), input.clone())
                    .expect("echo succeeds"),
                input
            );
        }
    }

    #[test]
    fn transformations_preserve_unicode_scalar_and_case_semantics() {
        let cases = [
            ("echo.reverse", "", ""),
            ("echo.reverse", "a🦀é", "é🦀a"),
            ("echo.upcase", "Hello, Straße!", "HELLO, STRASSE!"),
            ("echo.downcase", "Hello, Δ WORLD!", "hello, δ world!"),
            ("echo.ransom-case", "Hello, World!", "hElLo, WoRlD!"),
            ("echo.ransom-case", "A-1-БΓ", "a-1-Бγ"),
        ];
        for (id, input, expected) in cases {
            assert_eq!(invoke(id, input), json!({"message": expected}));
        }
    }

    #[test]
    fn malformed_transform_inputs_have_stable_code_and_message() {
        for input in [
            Value::Null,
            json!([]),
            json!({}),
            json!({"message": null}),
            json!({"message": 42}),
            json!({"message": "hello", "extra": true}),
        ] {
            let error = EchoProvider::invoke(&capability("echo.upcase"), input)
                .expect_err("malformed input must fail");
            assert_eq!(error.code(), "invalid-input");
            assert_eq!(error.message(), INVALID_MESSAGE);
        }
    }

    #[test]
    fn unsupported_capability_has_stable_code_and_interpolated_message() {
        let error = EchoProvider::invoke(&capability("other.read"), json!({}))
            .expect_err("unknown capability must fail");
        assert_eq!(error.code(), "unsupported-capability");
        assert_eq!(error.message(), "echo does not implement other.read");
    }
}
