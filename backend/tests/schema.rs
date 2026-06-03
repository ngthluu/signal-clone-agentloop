use sqlx::Row;
use test_chat_backend::db;

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
