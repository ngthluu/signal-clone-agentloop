const README: &str = include_str!("../../README.md");

fn assert_mentions(needle: &str) {
    assert!(
        README.contains(needle),
        "README.md should mention `{needle}`"
    );
}

#[test]
fn readme_describes_project_build_run_and_crypto_contracts() {
    for required in [
        "Test Chat App",
        "Architecture",
        "Data Flows",
        "Prerequisites",
        "Build And Test",
        "Run Locally",
        "Configuration",
        "Security Model",
        "Troubleshooting",
        "Swift",
        "Rust",
        "Axum",
        "SQLite",
        "mac-app",
        "backend",
        "cargo build",
        "cargo test",
        "cargo run -- --db-path",
        "DATABASE_PATH",
        "PORT",
        "swift build",
        "swift test",
        "swift run ChatApp",
        "CHATAPP_LIVE_BACKEND_URL",
        "http://127.0.0.1:3000",
        "E2E",
        "Keychain",
        "Application Support",
        "bash backend/scripts/reap_stale_backends.sh",
        "MessageCrypto",
        "GroupCrypto",
        "FileCrypto",
        "zero-knowledge",
        "end-to-end",
        "docs/zero-knowledge-relay.md",
    ] {
        assert_mentions(required);
    }
}
