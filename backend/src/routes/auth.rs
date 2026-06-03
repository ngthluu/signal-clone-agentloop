use std::time::{SystemTime, UNIX_EPOCH};

use axum::{
    extract::{rejection::JsonRejection, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};
use sqlx::{Row, SqlitePool};
use uuid::Uuid;

pub fn router() -> Router<SqlitePool> {
    Router::new()
        .route("/auth/challenge", post(challenge))
        .route("/auth/verify", post(verify))
        .route("/auth/session", get(session))
}

#[derive(Deserialize)]
struct ChallengeRequest {
    username: String,
}

#[derive(Serialize)]
struct ChallengeResponse {
    challenge_id: String,
    nonce: String,
}

#[derive(Deserialize)]
struct VerifyRequest {
    challenge_id: String,
    signature: String,
}

#[derive(Serialize)]
struct VerifyResponse {
    token: String,
    user_id: String,
    username: String,
}

#[derive(Serialize)]
struct SessionResponse {
    user_id: String,
    username: String,
}

async fn challenge(
    State(pool): State<SqlitePool>,
    payload: Result<Json<ChallengeRequest>, JsonRejection>,
) -> Response {
    let Json(payload) = match payload {
        Ok(payload) => payload,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };

    let user = match sqlx::query("SELECT id FROM users WHERE username = ?")
        .bind(&payload.username)
        .fetch_optional(&pool)
        .await
    {
        Ok(Some(row)) => row,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    let mut nonce_bytes = [0u8; 32];
    if getrandom::getrandom(&mut nonce_bytes).is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    let challenge_id = Uuid::new_v4().to_string();
    let created_at = rfc3339_now();
    let expires_at = rfc3339_from_now(5 * 60);
    let nonce = STANDARD.encode(nonce_bytes);
    let user_id = user.get::<String, _>("id");

    let result = sqlx::query(
        "INSERT INTO auth_challenges (id, user_id, nonce, created_at, expires_at) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(&challenge_id)
    .bind(&user_id)
    .bind(&nonce)
    .bind(&created_at)
    .bind(&expires_at)
    .execute(&pool)
    .await;

    match result {
        Ok(_) => (
            StatusCode::CREATED,
            Json(ChallengeResponse {
                challenge_id,
                nonce,
            }),
        )
            .into_response(),
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

async fn verify(
    State(pool): State<SqlitePool>,
    payload: Result<Json<VerifyRequest>, JsonRejection>,
) -> Response {
    let Json(payload) = match payload {
        Ok(payload) => payload,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };

    let now = rfc3339_now();
    let row = match sqlx::query(
        "SELECT auth_challenges.id, auth_challenges.user_id, auth_challenges.nonce, users.username, users.identity_public_key
         FROM auth_challenges
         JOIN users ON users.id = auth_challenges.user_id
         WHERE auth_challenges.id = ? AND auth_challenges.expires_at > ?",
    )
    .bind(&payload.challenge_id)
    .bind(&now)
    .fetch_optional(&pool)
    .await
    {
        Ok(Some(row)) => row,
        Ok(None) => return StatusCode::UNAUTHORIZED.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    let nonce = match STANDARD.decode(row.get::<String, _>("nonce")) {
        Ok(nonce) => nonce,
        Err(_) => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let public_key_bytes = match STANDARD.decode(row.get::<String, _>("identity_public_key")) {
        Ok(bytes) => bytes,
        Err(_) => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let signature_bytes = match STANDARD.decode(&payload.signature) {
        Ok(bytes) => bytes,
        Err(_) => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let public_key_bytes: [u8; 32] = match public_key_bytes.try_into() {
        Ok(bytes) => bytes,
        Err(_) => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let verifying_key = match VerifyingKey::from_bytes(&public_key_bytes) {
        Ok(key) => key,
        Err(_) => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let signature = match Signature::from_slice(&signature_bytes) {
        Ok(signature) => signature,
        Err(_) => return StatusCode::UNAUTHORIZED.into_response(),
    };

    if verifying_key.verify(&nonce, &signature).is_err() {
        return StatusCode::UNAUTHORIZED.into_response();
    }

    let user_id = row.get::<String, _>("user_id");
    let username = row.get::<String, _>("username");
    let token = Uuid::new_v4().to_string();
    let created_at = rfc3339_now();
    let expires_at = rfc3339_from_now(30 * 24 * 60 * 60);

    let mut tx = match pool.begin().await {
        Ok(tx) => tx,
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    let deleted = match sqlx::query("DELETE FROM auth_challenges WHERE id = ?")
        .bind(&payload.challenge_id)
        .execute(&mut *tx)
        .await
    {
        Ok(result) => result.rows_affected(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    if deleted == 0 {
        return StatusCode::UNAUTHORIZED.into_response();
    }

    let inserted = sqlx::query(
        "INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
    )
    .bind(&token)
    .bind(&user_id)
    .bind(&created_at)
    .bind(&expires_at)
    .execute(&mut *tx)
    .await;

    if inserted.is_err() || tx.commit().await.is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    (
        StatusCode::OK,
        Json(VerifyResponse {
            token,
            user_id,
            username,
        }),
    )
        .into_response()
}

async fn session(State(pool): State<SqlitePool>, headers: HeaderMap) -> Response {
    let token = match bearer_token(&headers) {
        Some(token) => token,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };

    let now = rfc3339_now();
    let row = match sqlx::query(
        "SELECT sessions.user_id, users.username
         FROM sessions
         JOIN users ON users.id = sessions.user_id
         WHERE sessions.token = ? AND sessions.expires_at > ?",
    )
    .bind(token)
    .bind(&now)
    .fetch_optional(&pool)
    .await
    {
        Ok(Some(row)) => row,
        Ok(None) => return StatusCode::UNAUTHORIZED.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    (
        StatusCode::OK,
        Json(SessionResponse {
            user_id: row.get("user_id"),
            username: row.get("username"),
        }),
    )
        .into_response()
}

fn bearer_token(headers: &HeaderMap) -> Option<&str> {
    let value = headers
        .get(axum::http::header::AUTHORIZATION)?
        .to_str()
        .ok()?;
    value
        .strip_prefix("Bearer ")
        .filter(|token| !token.is_empty())
}

fn rfc3339_now() -> String {
    rfc3339_from_now(0)
}

fn rfc3339_from_now(offset_seconds: u64) -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + offset_seconds;
    format_unix_seconds_utc(seconds)
}

fn format_unix_seconds_utc(seconds: u64) -> String {
    let days = (seconds / 86_400) as i64;
    let seconds_of_day = seconds % 86_400;
    let hour = seconds_of_day / 3_600;
    let minute = (seconds_of_day % 3_600) / 60;
    let second = seconds_of_day % 60;
    let (year, month, day) = civil_from_days(days);

    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z")
}

fn civil_from_days(days_since_epoch: i64) -> (i64, i64, i64) {
    let z = days_since_epoch + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    let year = year + if month <= 2 { 1 } else { 0 };

    (year, month, day)
}
