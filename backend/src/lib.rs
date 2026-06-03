use axum::{Extension, Router};
use sqlx::SqlitePool;

pub mod db;
pub mod models;
pub mod routes;

pub fn app(pool: SqlitePool) -> Router {
    let broadcaster = routes::messages::Broadcaster::new();

    Router::new()
        .merge(routes::health::router())
        .merge(routes::register::router())
        .merge(routes::auth::router())
        .merge(routes::keys::router())
        .merge(routes::messages::router())
        .merge(routes::groups::router())
        .merge(routes::conversations::router())
        .layer(Extension(broadcaster))
        .with_state(pool)
}
