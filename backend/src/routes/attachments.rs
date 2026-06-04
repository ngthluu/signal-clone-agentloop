use axum::{
    body::Bytes,
    extract::{DefaultBodyLimit, Path, State},
    http::{header::CONTENT_TYPE, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::Serialize;
use sqlx::{Row, SqlitePool};
use uuid::Uuid;

use crate::routes::session_auth::{authenticate, rfc3339_now};

const MAX_ATTACHMENT_BYTES: usize = 10 * 1024 * 1024;
const MAX_ATTACHMENT_BODY_BYTES: usize = MAX_ATTACHMENT_BYTES + 4096;

pub fn router() -> Router<SqlitePool> {
    Router::new()
        .route(
            "/attachments",
            post(upload).layer(DefaultBodyLimit::max(MAX_ATTACHMENT_BODY_BYTES)),
        )
        .route("/attachments/:id", get(download))
}

#[derive(Serialize)]
struct UploadAttachmentResponse {
    attachment_id: String,
}

async fn upload(State(pool): State<SqlitePool>, headers: HeaderMap, body: Bytes) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };
    if body.len() > MAX_ATTACHMENT_BYTES {
        return StatusCode::PAYLOAD_TOO_LARGE.into_response();
    }

    let attachment_id = Uuid::new_v4().to_string();
    let created_at = rfc3339_now();
    let result = sqlx::query(
        "INSERT INTO attachments (id, uploader_id, ciphertext, byte_size, created_at)
         VALUES (?, ?, ?, ?, ?)",
    )
    .bind(&attachment_id)
    .bind(&authed.user_id)
    .bind(body.as_ref())
    .bind(body.len() as i64)
    .bind(&created_at)
    .execute(&pool)
    .await;

    match result {
        Ok(_) => (
            StatusCode::CREATED,
            Json(UploadAttachmentResponse { attachment_id }),
        )
            .into_response(),
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

async fn download(
    State(pool): State<SqlitePool>,
    headers: HeaderMap,
    Path(attachment_id): Path<String>,
) -> Response {
    if authenticate(&pool, &headers).await.is_none() {
        return StatusCode::UNAUTHORIZED.into_response();
    }

    let row = match sqlx::query("SELECT ciphertext FROM attachments WHERE id = ?")
        .bind(attachment_id)
        .fetch_optional(&pool)
        .await
    {
        Ok(Some(row)) => row,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    let ciphertext = row.get::<Vec<u8>, _>("ciphertext");

    ([(CONTENT_TYPE, "application/octet-stream")], ciphertext).into_response()
}
