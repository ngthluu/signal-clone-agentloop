use axum::{
    extract::{rejection::JsonRejection, Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sqlx::{Row, SqlitePool};
use uuid::Uuid;

use crate::routes::session_auth::{authenticate, rfc3339_now};

pub fn router() -> Router<SqlitePool> {
    Router::new()
        .route("/groups", post(create).get(list))
        .route("/groups/:id", get(detail))
        .route("/groups/:id/members", post(add_member))
        .route("/groups/:id/keys", get(keys))
        .route("/groups/:id/messages", post(send_message).get(history))
}

#[derive(Deserialize)]
struct CreateGroupRequest {
    name: String,
    members: Vec<GroupMemberKeyRequest>,
}

#[derive(Deserialize)]
struct GroupMemberKeyRequest {
    username: String,
    wrapped_key: String,
}

#[derive(Serialize)]
struct CreateGroupResponse {
    group_id: String,
    epoch: i64,
    members: Vec<GroupMemberRef>,
}

#[derive(Serialize)]
struct GroupMemberRef {
    user_id: String,
    username: String,
}

#[derive(Serialize)]
struct GroupSummary {
    id: String,
    name: String,
    creator_id: String,
    current_epoch: i64,
    joined_epoch: i64,
    created_at: String,
}

#[derive(Serialize)]
struct GroupDetail {
    id: String,
    name: String,
    creator_id: String,
    current_epoch: i64,
    created_at: String,
    members: Vec<GroupMember>,
}

#[derive(Serialize)]
struct GroupMember {
    user_id: String,
    username: String,
    joined_epoch: i64,
}

#[derive(Deserialize)]
struct AddMemberRequest {
    username: String,
    epoch: i64,
    keys: Vec<WrappedKeyRequest>,
}

#[derive(Deserialize)]
struct WrappedKeyRequest {
    member_id: String,
    wrapped_key: String,
}

#[derive(Serialize)]
struct AddMemberResponse {
    epoch: i64,
    member: GroupMemberRef,
}

#[derive(Serialize)]
struct GroupKeyRecord {
    epoch: i64,
    wrapped_key: String,
}

#[derive(Deserialize)]
struct SendGroupMessageRequest {
    epoch: i64,
    ciphertext: String,
}

#[derive(Serialize)]
struct SendGroupMessageResponse {
    message_id: String,
    created_at: String,
    epoch: i64,
}

#[derive(Deserialize)]
struct HistoryQuery {
    since: Option<String>,
}

#[derive(Serialize)]
struct GroupHistoryResponse {
    messages: Vec<GroupMessageRecord>,
}

#[derive(Serialize)]
struct GroupMessageRecord {
    id: String,
    group_id: String,
    sender_id: String,
    epoch: i64,
    ciphertext: String,
    created_at: String,
}

async fn create(
    State(pool): State<SqlitePool>,
    headers: HeaderMap,
    payload: Result<Json<CreateGroupRequest>, JsonRejection>,
) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let Json(payload) = match payload {
        Ok(payload) => payload,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };
    if payload.name.is_empty() || payload.members.is_empty() {
        return StatusCode::BAD_REQUEST.into_response();
    }

    let mut resolved = Vec::with_capacity(payload.members.len());
    for member in &payload.members {
        let user = match user_for_username(&pool, &member.username).await {
            Ok(Some(user)) => user,
            Ok(None) => return StatusCode::NOT_FOUND.into_response(),
            Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
        };
        if resolved
            .iter()
            .any(|existing: &(GroupMemberRef, String)| existing.0.user_id == user.user_id)
        {
            return StatusCode::BAD_REQUEST.into_response();
        }
        resolved.push((user, member.wrapped_key.clone()));
    }

    if !resolved
        .iter()
        .any(|(member, _)| member.user_id == authed.user_id)
    {
        return StatusCode::BAD_REQUEST.into_response();
    }

    let group_id = Uuid::new_v4().to_string();
    let created_at = rfc3339_now();
    let mut tx = match pool.begin().await {
        Ok(tx) => tx,
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    let insert_group = sqlx::query(
        "INSERT INTO groups (id, name, creator_id, current_epoch, created_at)
         VALUES (?, ?, ?, 0, ?)",
    )
    .bind(&group_id)
    .bind(&payload.name)
    .bind(&authed.user_id)
    .bind(&created_at)
    .execute(&mut *tx)
    .await;
    if insert_group.is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    for (member, wrapped_key) in &resolved {
        let added_at = rfc3339_now();
        let insert_member = sqlx::query(
            "INSERT INTO group_members (group_id, user_id, joined_epoch, added_at)
             VALUES (?, ?, 0, ?)",
        )
        .bind(&group_id)
        .bind(&member.user_id)
        .bind(&added_at)
        .execute(&mut *tx)
        .await;
        if insert_member.is_err() {
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }

        let insert_key = sqlx::query(
            "INSERT INTO group_keys (group_id, epoch, member_id, wrapped_key, created_at)
             VALUES (?, 0, ?, ?, ?)",
        )
        .bind(&group_id)
        .bind(&member.user_id)
        .bind(wrapped_key)
        .bind(&added_at)
        .execute(&mut *tx)
        .await;
        if insert_key.is_err() {
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    }

    if tx.commit().await.is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    (
        StatusCode::CREATED,
        Json(CreateGroupResponse {
            group_id,
            epoch: 0,
            members: resolved.into_iter().map(|(member, _)| member).collect(),
        }),
    )
        .into_response()
}

async fn list(State(pool): State<SqlitePool>, headers: HeaderMap) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let rows = match sqlx::query(
        "SELECT groups.id, groups.name, groups.creator_id, groups.current_epoch,
                group_members.joined_epoch, groups.created_at
         FROM groups
         JOIN group_members ON group_members.group_id = groups.id
         WHERE group_members.user_id = ?
         ORDER BY groups.created_at, groups.id",
    )
    .bind(&authed.user_id)
    .fetch_all(&pool)
    .await
    {
        Ok(rows) => rows,
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    let groups = rows
        .into_iter()
        .map(|row| GroupSummary {
            id: row.get("id"),
            name: row.get("name"),
            creator_id: row.get("creator_id"),
            current_epoch: row.get("current_epoch"),
            joined_epoch: row.get("joined_epoch"),
            created_at: row.get("created_at"),
        })
        .collect::<Vec<_>>();

    (StatusCode::OK, Json(groups)).into_response()
}

async fn detail(
    State(pool): State<SqlitePool>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };
    if !is_member(&pool, &group_id, &authed.user_id).await {
        return StatusCode::FORBIDDEN.into_response();
    }

    let row = match sqlx::query(
        "SELECT id, name, creator_id, current_epoch, created_at FROM groups WHERE id = ?",
    )
    .bind(&group_id)
    .fetch_optional(&pool)
    .await
    {
        Ok(Some(row)) => row,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    let member_rows = match sqlx::query(
        "SELECT users.id AS user_id, users.username, group_members.joined_epoch
         FROM group_members
         JOIN users ON users.id = group_members.user_id
         WHERE group_members.group_id = ?
         ORDER BY users.username",
    )
    .bind(&group_id)
    .fetch_all(&pool)
    .await
    {
        Ok(rows) => rows,
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    let members = member_rows
        .into_iter()
        .map(|row| GroupMember {
            user_id: row.get("user_id"),
            username: row.get("username"),
            joined_epoch: row.get("joined_epoch"),
        })
        .collect();

    (
        StatusCode::OK,
        Json(GroupDetail {
            id: row.get("id"),
            name: row.get("name"),
            creator_id: row.get("creator_id"),
            current_epoch: row.get("current_epoch"),
            created_at: row.get("created_at"),
            members,
        }),
    )
        .into_response()
}

async fn add_member(
    State(pool): State<SqlitePool>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
    payload: Result<Json<AddMemberRequest>, JsonRejection>,
) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let Json(payload) = match payload {
        Ok(payload) => payload,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };
    let caller_joined_epoch = match joined_epoch(&pool, &group_id, &authed.user_id).await {
        Ok(Some(epoch)) => epoch,
        Ok(None) => return StatusCode::FORBIDDEN.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    let current_epoch = match current_epoch(&pool, &group_id).await {
        Ok(Some(epoch)) => epoch,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    if caller_joined_epoch > current_epoch {
        return StatusCode::FORBIDDEN.into_response();
    }

    let new_member = match user_for_username(&pool, &payload.username).await {
        Ok(Some(user)) => user,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    if is_member(&pool, &group_id, &new_member.user_id).await {
        return StatusCode::CONFLICT.into_response();
    }
    if !payload
        .keys
        .iter()
        .any(|key| key.member_id == new_member.user_id)
    {
        return StatusCode::BAD_REQUEST.into_response();
    }
    if key_guard_fails(
        &pool,
        &group_id,
        payload.epoch,
        &payload.keys,
        Some(&new_member.user_id),
    )
    .await
    {
        return StatusCode::BAD_REQUEST.into_response();
    }
    if payload.epoch != current_epoch + 1 {
        return StatusCode::CONFLICT.into_response();
    }

    let now = rfc3339_now();
    let mut tx = match pool.begin().await {
        Ok(tx) => tx,
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };

    let insert_member = sqlx::query(
        "INSERT INTO group_members (group_id, user_id, joined_epoch, added_at)
         VALUES (?, ?, ?, ?)",
    )
    .bind(&group_id)
    .bind(&new_member.user_id)
    .bind(payload.epoch)
    .bind(&now)
    .execute(&mut *tx)
    .await;
    if insert_member.is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    let update_group = sqlx::query("UPDATE groups SET current_epoch = ? WHERE id = ?")
        .bind(payload.epoch)
        .bind(&group_id)
        .execute(&mut *tx)
        .await;
    if update_group.is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    for key in &payload.keys {
        let insert_key = sqlx::query(
            "INSERT INTO group_keys (group_id, epoch, member_id, wrapped_key, created_at)
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(&group_id)
        .bind(payload.epoch)
        .bind(&key.member_id)
        .bind(&key.wrapped_key)
        .bind(&now)
        .execute(&mut *tx)
        .await;
        if insert_key.is_err() {
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    }

    if tx.commit().await.is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    }

    // TODO(task-5-b4): broadcast membership/key epoch changes if the live group stream needs them.
    (
        StatusCode::CREATED,
        Json(AddMemberResponse {
            epoch: payload.epoch,
            member: new_member,
        }),
    )
        .into_response()
}

async fn keys(
    State(pool): State<SqlitePool>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };
    if !is_member(&pool, &group_id, &authed.user_id).await {
        return StatusCode::FORBIDDEN.into_response();
    }
    let rows = match sqlx::query(
        "SELECT epoch, wrapped_key
         FROM group_keys
         WHERE group_id = ? AND member_id = ?
         ORDER BY epoch",
    )
    .bind(&group_id)
    .bind(&authed.user_id)
    .fetch_all(&pool)
    .await
    {
        Ok(rows) => rows,
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    let keys = rows
        .into_iter()
        .map(|row| GroupKeyRecord {
            epoch: row.get("epoch"),
            wrapped_key: row.get("wrapped_key"),
        })
        .collect::<Vec<_>>();

    (StatusCode::OK, Json(keys)).into_response()
}

async fn send_message(
    State(pool): State<SqlitePool>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
    payload: Result<Json<SendGroupMessageRequest>, JsonRejection>,
) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };
    let Json(payload) = match payload {
        Ok(payload) => payload,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };
    let sender_joined_epoch = match joined_epoch(&pool, &group_id, &authed.user_id).await {
        Ok(Some(epoch)) => epoch,
        Ok(None) => return StatusCode::FORBIDDEN.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    let current_epoch = match current_epoch(&pool, &group_id).await {
        Ok(Some(epoch)) => epoch,
        Ok(None) => return StatusCode::NOT_FOUND.into_response(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    if payload.epoch < sender_joined_epoch || payload.epoch > current_epoch {
        return StatusCode::BAD_REQUEST.into_response();
    }

    let message_id = Uuid::new_v4().to_string();
    let created_at = rfc3339_now();
    let result = sqlx::query(
        "INSERT INTO group_messages (id, group_id, sender_id, epoch, ciphertext, created_at)
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(&message_id)
    .bind(&group_id)
    .bind(&authed.user_id)
    .bind(payload.epoch)
    .bind(&payload.ciphertext)
    .bind(&created_at)
    .execute(&pool)
    .await;

    match result {
        Ok(_) => {
            // TODO(task-5-b4): publish the inserted group message on the group SSE broadcaster.
            (
                StatusCode::CREATED,
                Json(SendGroupMessageResponse {
                    message_id,
                    created_at,
                    epoch: payload.epoch,
                }),
            )
                .into_response()
        }
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

async fn history(
    State(pool): State<SqlitePool>,
    headers: HeaderMap,
    Path(group_id): Path<String>,
    query: Result<Query<HistoryQuery>, axum::extract::rejection::QueryRejection>,
) -> Response {
    let authed = match authenticate(&pool, &headers).await {
        Some(authed) => authed,
        None => return StatusCode::UNAUTHORIZED.into_response(),
    };
    if !is_member(&pool, &group_id, &authed.user_id).await {
        return StatusCode::FORBIDDEN.into_response();
    }
    let Query(query) = match query {
        Ok(query) => query,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };

    let rows = if let Some(cursor) = query.since {
        if let Some((created_at, id)) = cursor.split_once(',') {
            sqlx::query(
                "SELECT id, group_id, sender_id, epoch, ciphertext, created_at
                 FROM group_messages
                 WHERE group_id = ?
                   AND (created_at > ? OR (created_at = ? AND id > ?))
                 ORDER BY created_at, id",
            )
            .bind(&group_id)
            .bind(created_at)
            .bind(created_at)
            .bind(id)
            .fetch_all(&pool)
            .await
        } else {
            sqlx::query(
                "SELECT id, group_id, sender_id, epoch, ciphertext, created_at
                 FROM group_messages
                 WHERE group_id = ? AND created_at > ?
                 ORDER BY created_at, id",
            )
            .bind(&group_id)
            .bind(cursor)
            .fetch_all(&pool)
            .await
        }
    } else {
        sqlx::query(
            "SELECT id, group_id, sender_id, epoch, ciphertext, created_at
             FROM group_messages
             WHERE group_id = ?
             ORDER BY created_at, id",
        )
        .bind(&group_id)
        .fetch_all(&pool)
        .await
    };

    let rows = match rows {
        Ok(rows) => rows,
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    let messages = rows
        .into_iter()
        .map(|row| GroupMessageRecord {
            id: row.get("id"),
            group_id: row.get("group_id"),
            sender_id: row.get("sender_id"),
            epoch: row.get("epoch"),
            ciphertext: row.get("ciphertext"),
            created_at: row.get("created_at"),
        })
        .collect::<Vec<_>>();

    (StatusCode::OK, Json(GroupHistoryResponse { messages })).into_response()
}

async fn user_for_username(
    pool: &SqlitePool,
    username: &str,
) -> Result<Option<GroupMemberRef>, sqlx::Error> {
    sqlx::query("SELECT id, username FROM users WHERE username = ?")
        .bind(username)
        .fetch_optional(pool)
        .await
        .map(|row| {
            row.map(|row| GroupMemberRef {
                user_id: row.get("id"),
                username: row.get("username"),
            })
        })
}

async fn joined_epoch(
    pool: &SqlitePool,
    group_id: &str,
    user_id: &str,
) -> Result<Option<i64>, sqlx::Error> {
    sqlx::query("SELECT joined_epoch FROM group_members WHERE group_id = ? AND user_id = ?")
        .bind(group_id)
        .bind(user_id)
        .fetch_optional(pool)
        .await
        .map(|row| row.map(|row| row.get("joined_epoch")))
}

async fn current_epoch(pool: &SqlitePool, group_id: &str) -> Result<Option<i64>, sqlx::Error> {
    sqlx::query("SELECT current_epoch FROM groups WHERE id = ?")
        .bind(group_id)
        .fetch_optional(pool)
        .await
        .map(|row| row.map(|row| row.get("current_epoch")))
}

async fn is_member(pool: &SqlitePool, group_id: &str, user_id: &str) -> bool {
    matches!(joined_epoch(pool, group_id, user_id).await, Ok(Some(_)))
}

async fn key_guard_fails(
    pool: &SqlitePool,
    group_id: &str,
    epoch: i64,
    keys: &[WrappedKeyRequest],
    pending_member_id: Option<&str>,
) -> bool {
    for key in keys {
        let joined_epoch = if Some(key.member_id.as_str()) == pending_member_id {
            Some(epoch)
        } else {
            match joined_epoch(pool, group_id, &key.member_id).await {
                Ok(value) => value,
                Err(_) => return true,
            }
        };
        let Some(joined_epoch) = joined_epoch else {
            return true;
        };
        if epoch < joined_epoch {
            return true;
        }
    }

    false
}
