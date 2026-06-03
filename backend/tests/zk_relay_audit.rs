use test_chat_backend::db;
use uuid::Uuid;

fn run_audit(db_path: &str) -> std::process::Output {
    std::process::Command::new("bash")
        .arg("scripts/zk_relay_audit.sh")
        .arg(db_path)
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .output()
        .unwrap()
}

async fn migrated_temp_db(prefix: &str) -> (std::path::PathBuf, sqlx::SqlitePool) {
    let db_path = std::env::temp_dir().join(format!("{prefix}-{}.sqlite", Uuid::new_v4()));
    let db_path_str = db_path.to_str().unwrap();
    let pool = db::init_pool(db_path_str).await.unwrap();

    (db_path, pool)
}

#[tokio::test]
async fn zk_relay_audit_passes_for_ciphertext_only_schema() {
    let (db_path, pool) = migrated_temp_db("zk-audit-pass").await;
    let db_path_str = db_path.to_str().unwrap();
    let sender_id = Uuid::new_v4().to_string();
    let recipient_id = Uuid::new_v4().to_string();

    sqlx::query(
        "INSERT INTO users (id, username, identity_public_key, created_at) VALUES (?, ?, ?, ?)",
    )
    .bind(&sender_id)
    .bind("zk_audit_sender")
    .bind("cHVibGljLWlkZW50aXR5LWtleQ==")
    .bind("2026-06-03T00:00:00Z")
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO users (id, username, identity_public_key, created_at) VALUES (?, ?, ?, ?)",
    )
    .bind(&recipient_id)
    .bind("zk_audit_recipient")
    .bind("cHVibGljLWlkZW50aXR5LWtleS0y")
    .bind("2026-06-03T00:00:01Z")
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO device_keys (user_id, x25519_public_key, key_signature, created_at) VALUES (?, ?, ?, ?)",
    )
    .bind(&sender_id)
    .bind("cHVibGljLXgyNTUxOS1wcmVrZXk=")
    .bind("cHVibGljLXByZWtleS1zaWduYXR1cmU=")
    .bind("2026-06-03T00:00:02Z")
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO messages (id, sender_id, recipient_id, ciphertext, created_at) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(Uuid::new_v4().to_string())
    .bind(&sender_id)
    .bind(&recipient_id)
    .bind("opaque-base64-ciphertext-envelope")
    .bind("2026-06-03T00:00:03Z")
    .execute(&pool)
    .await
    .unwrap();
    pool.close().await;

    let output = run_audit(db_path_str);
    let stdout = String::from_utf8(output.stdout).unwrap();
    let stderr = String::from_utf8(output.stderr).unwrap();

    assert!(
        output.status.success(),
        "zk_relay_audit.sh failed\nstdout:\n{stdout}\nstderr:\n{stderr}"
    );
    assert!(stdout.contains("messages"));
    assert!(stdout.contains("device_keys"));
    assert!(stdout.contains("users"));
    assert!(stdout.contains(
        "ZERO-KNOWLEDGE SCHEMA AUDIT: PASS — no plaintext or private-key columns in any table"
    ));
    assert!(!stdout.contains("forbidden column"));

    let _ = std::fs::remove_file(db_path);
}

#[tokio::test]
async fn zk_relay_audit_fails_when_plaintext_column_exists() {
    let (db_path, pool) = migrated_temp_db("zk-audit-leak").await;
    let db_path_str = db_path.to_str().unwrap();

    sqlx::query("CREATE TABLE audit_leak (id TEXT, plaintext TEXT)")
        .execute(&pool)
        .await
        .unwrap();
    pool.close().await;

    let output = run_audit(db_path_str);
    let stdout = String::from_utf8(output.stdout).unwrap();
    let stderr = String::from_utf8(output.stderr).unwrap();
    let combined = format!("{stdout}\n{stderr}");

    assert!(
        !output.status.success(),
        "zk_relay_audit.sh unexpectedly passed\nstdout:\n{stdout}\nstderr:\n{stderr}"
    );
    assert!(
        combined.contains("audit_leak.plaintext"),
        "audit output did not name the leaking column\nstdout:\n{stdout}\nstderr:\n{stderr}"
    );

    let _ = std::fs::remove_file(db_path);
}
