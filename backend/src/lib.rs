use axum::Router;
use sqlx::SqlitePool;

pub mod db;
pub mod routes;

pub fn app(pool: SqlitePool) -> Router {
    Router::new()
        .merge(routes::health::router())
        .with_state(pool)
}
