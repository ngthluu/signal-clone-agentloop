use std::{env, net::SocketAddr};

use test_chat_backend::{app, db};

struct Config {
    db_path: String,
    port: u16,
}

impl Config {
    fn from_env_args() -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let mut db_path = env::var("DATABASE_PATH").unwrap_or_else(|_| "backend.sqlite3".into());
        let mut port = env::var("PORT")
            .ok()
            .map(|value| value.parse())
            .transpose()?
            .unwrap_or(3000);

        let mut args = env::args().skip(1);
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--db-path" => {
                    db_path = args.next().ok_or("--db-path requires a value")?;
                }
                "--port" => {
                    port = args.next().ok_or("--port requires a value")?.parse()?;
                }
                _ => return Err(format!("unknown argument: {arg}").into()),
            }
        }

        Ok(Self { db_path, port })
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let config = Config::from_env_args()?;
    let pool = db::init_pool(&config.db_path).await?;
    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    let listener = tokio::net::TcpListener::bind(addr).await?;

    axum::serve(listener, app(pool)).await?;

    Ok(())
}
