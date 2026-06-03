use axum::{
    extract::{rejection::JsonRejection, Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::post,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sqlx::{Row, SqlitePool};
use uuid::Uuid;

use crate::routes::session_auth::{authenticate, rfc3339_now};

pub fn router() -> Router<SqlitePool> {
    Router::new().route("/messages", post(send).get(history))
}

#[derive(Deserialize)]
struct SendMessageRequest {
    recipient_username: String,
    ciphertext: String,
}

#[derive(Serialize)]
struct SendMessageResponse {
    message_id: String,
    created_at: String,
}

#[derive(Deserialize)]
struct HistoryQuery {
    #[serde(rename = "with")]
    with_username: String,
    since: Option<String>,
}

#[derive(Serialize)]
struct HistoryResponse {
    messages: Vec<MessageRecord>,
}

#[derive(Serialize)]
struct MessageRecord {
    id: String,
    sender_id: String,
    recipient_id: String,
    ciphertext: String,
    created_at: String,
}

async fn send(
    State(pool): State<SqlitePool>,
    headers: HeaderMap,
    payload: Result<Json<SendMessageRequest>, JsonRejection>,
) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let Json(payload) = match payload {
        Ok(payload) => payload,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };

    let recipient_id = match user_id_for_username(&pool, &payload.recipient_username).await {
        Ok(Some(user_id)) => user_id,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    let message_id = Uuid::new_v4().to_string();
    let created_at = rfc3339_now();
    let result = sqlx::query(
        "INSERT INTO messages (id, sender_id, recipient_id, ciphertext, created_at)
         VALUES (?, ?, ?, ?, ?)",
    )
    .bind(&message_id)
    .bind(&authed.user_id)
    .bind(&recipient_id)
    .bind(&payload.ciphertext)
    .bind(&created_at)
    .execute(&pool)
    .await;

    match result {
        Ok(_) => (
            StatusCode::CREATED,
            Json(SendMessageResponse {
                message_id,
                created_at,
            }),
        )
            .into_response(),
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

async fn history(
    State(pool): State<SqlitePool>,
    headers: HeaderMap,
    query: Result<Query<HistoryQuery>, axum::extract::rejection::QueryRejection>,
) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let Query(query) = match query {
        Ok(query) => query,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };

    let peer_id = match user_id_for_username(&pool, &query.with_username).await {
        Ok(Some(user_id)) => user_id,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    let rows = if let Some(cursor) = query.since {
        if let Some((created_at, id)) = cursor.split_once(',') {
            sqlx::query(
                "SELECT id, sender_id, recipient_id, ciphertext, created_at
                 FROM messages
                 WHERE ((sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?))
                   AND (created_at > ? OR (created_at = ? AND id > ?))
                 ORDER BY created_at, id",
            )
            .bind(&authed.user_id)
            .bind(&peer_id)
            .bind(&peer_id)
            .bind(&authed.user_id)
            .bind(created_at)
            .bind(created_at)
            .bind(id)
            .fetch_all(&pool)
            .await
        } else {
            sqlx::query(
                "SELECT id, sender_id, recipient_id, ciphertext, created_at
                 FROM messages
                 WHERE ((sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?))
                   AND created_at > ?
                 ORDER BY created_at, id",
            )
            .bind(&authed.user_id)
            .bind(&peer_id)
            .bind(&peer_id)
            .bind(&authed.user_id)
            .bind(cursor)
            .fetch_all(&pool)
            .await
        }
    } else {
        sqlx::query(
            "SELECT id, sender_id, recipient_id, ciphertext, created_at
             FROM messages
             WHERE ((sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?))
             ORDER BY created_at, id",
        )
        .bind(&authed.user_id)
        .bind(&peer_id)
        .bind(&peer_id)
        .bind(&authed.user_id)
        .fetch_all(&pool)
        .await
    };

    let rows = match rows {
        Ok(rows) => rows,
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    let messages = rows
        .into_iter()
        .map(|row| MessageRecord {
            id: row.get("id"),
            sender_id: row.get("sender_id"),
            recipient_id: row.get("recipient_id"),
            ciphertext: row.get("ciphertext"),
            created_at: row.get("created_at"),
        })
        .collect();

    (StatusCode::OK, Json(HistoryResponse { messages })).into_response()
}

async fn user_id_for_username(
    pool: &SqlitePool,
    username: &str,
) -> Result<Option<String>, sqlx::Error> {
    sqlx::query("SELECT id FROM users WHERE username = ?")
        .bind(username)
        .fetch_optional(pool)
        .await
        .map(|row| row.map(|row| row.get("id")))
}
