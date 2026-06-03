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
    peer_user_id: String,
    peer_username: String,
    last_activity: String,
    last_seq: i64,
}

async fn list(State(pool): State<SqlitePool>, headers: HeaderMap) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };

    let rows = sqlx::query(
        "WITH dm_conversations AS (
            SELECT
                CASE WHEN sender_id = ? THEN recipient_id ELSE sender_id END AS peer_id,
                MAX(rowid) AS last_seq,
                MAX(created_at) AS last_activity
            FROM messages
            WHERE sender_id = ? OR recipient_id = ?
            GROUP BY peer_id
        )
        SELECT
            dm_conversations.peer_id,
            u.username AS peer_username,
            dm_conversations.last_activity,
            dm_conversations.last_seq
        FROM dm_conversations
        JOIN users u ON u.id = dm_conversations.peer_id
        ORDER BY dm_conversations.last_seq DESC",
    )
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
            peer_user_id: row.get("peer_id"),
            peer_username: row.get("peer_username"),
            last_activity: row.get("last_activity"),
            last_seq: row.get("last_seq"),
        })
        .collect();

    (
        StatusCode::OK,
        Json(ConversationsResponse { conversations }),
    )
        .into_response()
}
