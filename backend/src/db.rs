use std::{path::Path, str::FromStr};

use sqlx::{
    migrate::MigrateError,
    sqlite::{SqliteConnectOptions, SqlitePoolOptions},
    SqlitePool,
};

pub async fn init_pool(
    db_path: &str,
) -> Result<SqlitePool, Box<dyn std::error::Error + Send + Sync>> {
    create_parent_dir(db_path)?;

    let options = SqliteConnectOptions::from_str(db_path)?.create_if_missing(true);
    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(options)
        .await?;

    run_migrations(&pool).await?;

    Ok(pool)
}

async fn run_migrations(pool: &SqlitePool) -> Result<(), MigrateError> {
    sqlx::migrate!("./migrations").run(pool).await
}

fn create_parent_dir(db_path: &str) -> std::io::Result<()> {
    if db_path == ":memory:" || db_path.starts_with("sqlite:") {
        return Ok(());
    }

    if let Some(parent) = Path::new(db_path)
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
    {
        std::fs::create_dir_all(parent)?;
    }

    Ok(())
}
