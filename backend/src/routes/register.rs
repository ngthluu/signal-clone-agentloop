use std::time::{SystemTime, UNIX_EPOCH};

use axum::{
    extract::{rejection::JsonRejection, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::post,
    Json, Router,
};
use sqlx::SqlitePool;
use uuid::Uuid;

use crate::models::{RegisterRequest, RegisterResponse};

pub fn router() -> Router<SqlitePool> {
    Router::new().route("/register", post(register))
}

async fn register(
    State(pool): State<SqlitePool>,
    payload: Result<Json<RegisterRequest>, JsonRejection>,
) -> Response {
    let Json(payload) = match payload {
        Ok(payload) => payload,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };

    if !valid_username(&payload.username) || !valid_base64(&payload.identity_public_key) {
        return StatusCode::BAD_REQUEST.into_response();
    }

    let user_id = Uuid::new_v4().to_string();
    let created_at = rfc3339_now();

    let result = sqlx::query(
        "INSERT INTO users (id, username, identity_public_key, created_at) VALUES (?, ?, ?, ?)",
    )
    .bind(&user_id)
    .bind(&payload.username)
    .bind(&payload.identity_public_key)
    .bind(&created_at)
    .execute(&pool)
    .await;

    match result {
        Ok(_) => (StatusCode::CREATED, Json(RegisterResponse { user_id })).into_response(),
        Err(sqlx::Error::Database(error)) if is_unique_username_error(error.as_ref()) => {
            StatusCode::CONFLICT.into_response()
        }
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

fn valid_username(username: &str) -> bool {
    let len = username.chars().count();
    (3..=32).contains(&len)
        && username
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn valid_base64(value: &str) -> bool {
    if value.is_empty() || value.len() % 4 != 0 {
        return false;
    }

    let mut padding = 0;
    for c in value.chars() {
        match c {
            'A'..='Z' | 'a'..='z' | '0'..='9' | '+' | '/' if padding == 0 => {}
            '=' => padding += 1,
            _ => return false,
        }

        if padding > 2 {
            return false;
        }
    }

    true
}

fn is_unique_username_error(error: &dyn sqlx::error::DatabaseError) -> bool {
    error
        .message()
        .contains("UNIQUE constraint failed: users.username")
}

fn rfc3339_now() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
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
