use sqlx::Row;
use test_chat_backend::db;
use uuid::Uuid;

#[tokio::test]
async fn migration_creates_users_table_with_only_public_account_columns() {
    let pool = db::init_pool(":memory:").await.unwrap();

    let rows = sqlx::query("PRAGMA table_info(users)")
        .fetch_all(&pool)
        .await
        .unwrap();

    let columns: Vec<String> = rows
        .iter()
        .map(|row| row.get::<String, _>("name"))
        .collect();

    assert_eq!(
        columns,
        vec!["id", "username", "identity_public_key", "created_at"]
    );
    assert!(columns
        .iter()
        .all(|column| !column.contains("private") && !column.contains("secret")));
}

#[tokio::test]
async fn schema_dump_prints_schema_sample_row_and_rejects_private_material() {
    let db_path = std::env::temp_dir().join(format!("schema-dump-{}.sqlite", Uuid::new_v4()));
    let db_path_str = db_path.to_str().unwrap();
    let pool = db::init_pool(db_path_str).await.unwrap();

    sqlx::query(
        "INSERT INTO users (id, username, identity_public_key, created_at) VALUES (?, ?, ?, ?)",
    )
    .bind(Uuid::new_v4().to_string())
    .bind("dump_user")
    .bind("cHVibGljLWR1bXAta2V5")
    .bind("2026-06-03T00:00:00Z")
    .execute(&pool)
    .await
    .unwrap();
    pool.close().await;

    let output = std::process::Command::new("bash")
        .arg("scripts/schema_dump.sh")
        .arg(db_path_str)
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .output()
        .unwrap();

    let stdout = String::from_utf8(output.stdout).unwrap();
    let stderr = String::from_utf8(output.stderr).unwrap();
    assert!(
        output.status.success(),
        "schema_dump.sh failed\nstdout:\n{stdout}\nstderr:\n{stderr}"
    );
    assert!(stdout.contains("PRAGMA table_info(users)"));
    assert!(stdout.contains("identity_public_key"));
    assert!(stdout.contains("dump_user"));
    assert!(stdout.contains("confirmed no private/secret columns or private material"));
    assert!(!stdout.contains("identity_private_key"));
    assert!(!stdout.contains("PRIVATE_KEY_MUST_NOT_BE_STORED"));

    let _ = std::fs::remove_file(db_path);
}
