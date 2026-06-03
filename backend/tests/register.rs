use std::net::SocketAddr;

use serde_json::json;
use sqlx::Row;
use test_chat_backend::{app, db};
use tokio::{io::AsyncReadExt, io::AsyncWriteExt, net::TcpStream};
use uuid::Uuid;

struct TestServer {
    addr: SocketAddr,
    pool: sqlx::SqlitePool,
}

impl TestServer {
    async fn start() -> Self {
        let pool = db::init_pool(":memory:").await.unwrap();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server_pool = pool.clone();

        tokio::spawn(async move {
            axum::serve(listener, app(server_pool)).await.unwrap();
        });

        Self { addr, pool }
    }

    async fn post_json(&self, path: &str, body: serde_json::Value) -> HttpResponse {
        let body = body.to_string();
        let request = format!(
            "POST {path} HTTP/1.1\r\nHost: {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            self.addr,
            body.len(),
            body
        );

        send_request(self.addr, request).await
    }

    async fn post_raw(&self, path: &str, body: &str) -> HttpResponse {
        let request = format!(
            "POST {path} HTTP/1.1\r\nHost: {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            self.addr,
            body.len(),
            body
        );

        send_request(self.addr, request).await
    }
}

struct HttpResponse {
    status: u16,
    body: String,
}

async fn send_request(addr: SocketAddr, request: String) -> HttpResponse {
    let mut stream = TcpStream::connect(addr).await.unwrap();
    stream.write_all(request.as_bytes()).await.unwrap();

    let mut response = Vec::new();
    stream.read_to_end(&mut response).await.unwrap();
    let response = String::from_utf8(response).unwrap();
    let (head, body) = response
        .split_once("\r\n\r\n")
        .or_else(|| response.split_once("\n\n"))
        .unwrap_or((response.as_str(), ""));
    let status = head
        .lines()
        .next()
        .unwrap()
        .split_whitespace()
        .nth(1)
        .unwrap()
        .parse()
        .unwrap();

    HttpResponse {
        status,
        body: body.to_string(),
    }
}

#[tokio::test]
async fn register_stores_only_public_account_fields() {
    let server = TestServer::start().await;
    let public_key = "cHVibGljLWlkZW50aXR5LWtleQ==";
    let private_key = "PRIVATE_KEY_MUST_NOT_BE_STORED";

    let response = server
        .post_json(
            "/register",
            json!({
                "username": "alice_123",
                "identity_public_key": public_key,
                "identity_private_key": private_key
            }),
        )
        .await;

    assert_eq!(response.status, 201);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let user_id = body["user_id"].as_str().unwrap();
    assert_eq!(body.as_object().unwrap().len(), 1);
    Uuid::parse_str(user_id).unwrap();

    let row = sqlx::query("SELECT id, username, identity_public_key, created_at FROM users")
        .fetch_one(&server.pool)
        .await
        .unwrap();

    assert_eq!(row.get::<String, _>("id"), user_id);
    assert_eq!(row.get::<String, _>("username"), "alice_123");
    assert_eq!(row.get::<String, _>("identity_public_key"), public_key);
    assert!(row.get::<String, _>("created_at").ends_with('Z'));

    let columns = sqlx::query("PRAGMA table_info(users)")
        .fetch_all(&server.pool)
        .await
        .unwrap()
        .into_iter()
        .map(|row| row.get::<String, _>("name"))
        .collect::<Vec<_>>();

    assert_eq!(
        columns,
        vec!["id", "username", "identity_public_key", "created_at"]
    );
    assert!(columns
        .iter()
        .all(|column| !column.contains("private") && !column.contains("secret")));

    let stored_values = sqlx::query(
        "SELECT id || username || identity_public_key || created_at AS stored FROM users",
    )
    .fetch_one(&server.pool)
    .await
    .unwrap()
    .get::<String, _>("stored");
    assert!(!stored_values.contains(private_key));
}

#[tokio::test]
async fn register_rejects_duplicate_username_without_second_row() {
    let server = TestServer::start().await;
    let payload = json!({
        "username": "duplicate_user",
        "identity_public_key": "cHVibGljLWtleQ=="
    });

    let first = server.post_json("/register", payload.clone()).await;
    let second = server.post_json("/register", payload).await;

    assert_eq!(first.status, 201);
    assert_eq!(second.status, 409);

    let count = sqlx::query("SELECT COUNT(*) AS count FROM users WHERE username = ?")
        .bind("duplicate_user")
        .fetch_one(&server.pool)
        .await
        .unwrap()
        .get::<i64, _>("count");
    assert_eq!(count, 1);
}

#[tokio::test]
async fn register_rejects_malformed_input() {
    let server = TestServer::start().await;

    let cases = [
        ("bad json", "{"),
        (
            "missing username",
            r#"{"identity_public_key":"cHVibGljLWtleQ=="}"#,
        ),
        ("missing key", r#"{"username":"valid_user"}"#),
        (
            "short username",
            r#"{"username":"ab","identity_public_key":"cHVibGljLWtleQ=="}"#,
        ),
        (
            "long username",
            r#"{"username":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","identity_public_key":"cHVibGljLWtleQ=="}"#,
        ),
        (
            "illegal username",
            r#"{"username":"bad-name","identity_public_key":"cHVibGljLWtleQ=="}"#,
        ),
        (
            "non base64 key",
            r#"{"username":"valid_user","identity_public_key":"not base64!"}"#,
        ),
    ];

    for (name, body) in cases {
        let response = server.post_raw("/register", body).await;
        assert_eq!(response.status, 400, "{name}");
    }

    let count = sqlx::query("SELECT COUNT(*) AS count FROM users")
        .fetch_one(&server.pool)
        .await
        .unwrap()
        .get::<i64, _>("count");
    assert_eq!(count, 0);
}
