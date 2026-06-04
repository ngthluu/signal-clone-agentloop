use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
    Json, Router,
};
use serde::Serialize;
use sqlx::{Row, SqlitePool};

use crate::routes::session_auth::authenticate;

pub fn router() -> Router<SqlitePool> {
    Router::new().route("/conversations", get(list))
}

#[derive(Serialize)]
struct ConversationsResponse {
    conversations: Vec<ConversationRecord>,
}

#[derive(Serialize)]
struct ConversationRecord {
    peer_id: String,
    peer_username: String,
    last_message_id: String,
    last_ciphertext: String,
    last_created_at: String,
}

async fn list(State(pool): State<SqlitePool>, headers: HeaderMap) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };

    let rows = sqlx::query(
        "WITH dm AS (
            SELECT
                CASE WHEN sender_id = ? THEN recipient_id ELSE sender_id END AS peer_id,
                id,
                ciphertext,
                created_at,
                messages.rowid AS message_rowid,
                ROW_NUMBER() OVER (
                    PARTITION BY CASE WHEN sender_id = ? THEN recipient_id ELSE sender_id END
                    ORDER BY created_at DESC, messages.rowid DESC
                ) AS rn
            FROM messages
            WHERE sender_id = ? OR recipient_id = ?
        )
        SELECT
            dm.peer_id,
            u.username AS peer_username,
            dm.id AS last_message_id,
            dm.ciphertext AS last_ciphertext,
            dm.created_at AS last_created_at
        FROM dm
        JOIN users u ON u.id = dm.peer_id
        WHERE dm.rn = 1
        ORDER BY dm.created_at DESC, dm.message_rowid DESC",
    )
    .bind(&authed.user_id)
    .bind(&authed.user_id)
    .bind(&authed.user_id)
    .bind(&authed.user_id)
    .fetch_all(&pool)
    .await;

    let rows = match rows {
        Ok(rows) => rows,
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    let conversations = rows
        .into_iter()
        .map(|row| ConversationRecord {
            peer_id: row.get("peer_id"),
            peer_username: row.get("peer_username"),
            last_message_id: row.get("last_message_id"),
            last_ciphertext: row.get("last_ciphertext"),
            last_created_at: row.get("last_created_at"),
        })
        .collect();

    (
        StatusCode::OK,
        Json(ConversationsResponse { conversations }),
    )
        .into_response()
}
