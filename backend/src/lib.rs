use axum::Router;
use sqlx::SqlitePool;

pub mod db;
pub mod models;
pub mod routes;

pub fn app(pool: SqlitePool) -> Router {
    Router::new()
        .merge(routes::health::router())
        .merge(routes::register::router())
        .merge(routes::auth::router())
        .merge(routes::keys::router())
        .merge(routes::messages::router())
        .with_state(pool)
}
