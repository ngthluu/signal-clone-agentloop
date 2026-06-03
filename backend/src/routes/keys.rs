use axum::{
    extract::{rejection::JsonRejection, Path, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, put},
    Json, Router,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};
use sqlx::{Row, SqlitePool};

use crate::routes::session_auth::{authenticate, rfc3339_now};

pub fn router() -> Router<SqlitePool> {
    Router::new()
        .route("/keys", put(publish))
        .route("/keys/:username", get(fetch))
}

#[derive(Deserialize)]
struct PublishPrekeyRequest {
    x25519_public_key: String,
    key_signature: String,
}

#[derive(Serialize)]
struct PrekeyResponse {
    user_id: String,
    username: String,
    identity_public_key: String,
    x25519_public_key: String,
    key_signature: String,
}

async fn publish(
    State(pool): State<SqlitePool>,
    headers: HeaderMap,
    payload: Result<Json<PublishPrekeyRequest>, JsonRejection>,
) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let Json(payload) = match payload {
        Ok(payload) => payload,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };

    let x25519_public_key_bytes = match decode_fixed::<32>(&payload.x25519_public_key) {
        Some(bytes) => bytes,
        None => return StatusCode::BAD_REQUEST.into_response(),
    };
    let signature_bytes = match decode_fixed::<64>(&payload.key_signature) {
        Some(bytes) => bytes,
        None => return StatusCode::BAD_REQUEST.into_response(),
    };
    let identity_public_key =
        match sqlx::query("SELECT identity_public_key FROM users WHERE id = ?")
            .bind(&authed.user_id)
            .fetch_optional(&pool)
            .await
        {
            Ok(Some(row)) => row.get::<String, _>("identity_public_key"),
            Ok(None) => return StatusCode::UNAUTHORIZED.into_response(),
            Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
        };
    let identity_public_key_bytes = match decode_fixed::<32>(&identity_public_key) {
        Some(bytes) => bytes,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let verifying_key = match VerifyingKey::from_bytes(&identity_public_key_bytes) {
        Ok(key) => key,
        Err(_) => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let signature = Signature::from_bytes(&signature_bytes);

    if verifying_key
        .verify(&x25519_public_key_bytes, &signature)
        .is_err()
    {
        return StatusCode::BAD_REQUEST.into_response();
    }

    let created_at = rfc3339_now();
    let result = sqlx::query(
        "INSERT INTO device_keys (user_id, x25519_public_key, key_signature, created_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET
             x25519_public_key = excluded.x25519_public_key,
             key_signature = excluded.key_signature,
             created_at = excluded.created_at",
    )
    .bind(&authed.user_id)
    .bind(&payload.x25519_public_key)
    .bind(&payload.key_signature)
    .bind(&created_at)
    .execute(&pool)
    .await;

    match result {
        Ok(_) => StatusCode::OK.into_response(),
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

async fn fetch(State(pool): State<SqlitePool>, Path(username): Path<String>) -> Response {
    let row = match sqlx::query(
        "SELECT users.id AS user_id, users.username, users.identity_public_key,
                device_keys.x25519_public_key, device_keys.key_signature
         FROM users
         JOIN device_keys ON device_keys.user_id = users.id
         WHERE users.username = ?",
    )
    .bind(username)
    .fetch_optional(&pool)
    .await
    {
        Ok(Some(row)) => row,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    (
        StatusCode::OK,
        Json(PrekeyResponse {
            user_id: row.get("user_id"),
            username: row.get("username"),
            identity_public_key: row.get("identity_public_key"),
            x25519_public_key: row.get("x25519_public_key"),
            key_signature: row.get("key_signature"),
        }),
    )
        .into_response()
}

fn decode_fixed<const N: usize>(value: &str) -> Option<[u8; N]> {
    STANDARD.decode(value).ok()?.try_into().ok()
}
