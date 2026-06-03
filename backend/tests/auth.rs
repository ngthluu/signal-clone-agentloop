use std::net::SocketAddr;

use base64::{engine::general_purpose::STANDARD, Engine as _};
use ed25519_dalek::{Signer, SigningKey};
use serde_json::json;
use sqlx::Row;
use test_chat_backend::{app, db};
use tokio::{io::AsyncReadExt, io::AsyncWriteExt, net::TcpStream};

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

    async fn register_user(&self, username: &str, signing_key: &SigningKey) {
        let response = self
            .post_json(
                "/register",
                json!({
                    "username": username,
                    "identity_public_key": STANDARD.encode(signing_key.verifying_key().to_bytes())
                }),
            )
            .await;
        assert_eq!(response.status, 201);
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

    async fn get_bearer(&self, path: &str, token: &str) -> HttpResponse {
        let request = format!(
            "GET {path} HTTP/1.1\r\nHost: {}\r\nAuthorization: Bearer {}\r\nConnection: close\r\n\r\n",
            self.addr, token
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

fn fixed_signing_key() -> SigningKey {
    SigningKey::from_bytes(&[7u8; 32])
}

async fn request_challenge(server: &TestServer, username: &str) -> serde_json::Value {
    let response = server
        .post_json("/auth/challenge", json!({ "username": username }))
        .await;
    assert_eq!(response.status, 201);
    serde_json::from_str(&response.body).unwrap()
}

#[tokio::test]
async fn auth_challenge_returns_nonce_for_known_user() {
    let server = TestServer::start().await;
    let signing_key = fixed_signing_key();
    server.register_user("alice_123", &signing_key).await;

    let body = request_challenge(&server, "alice_123").await;
    let challenge_id = body["challenge_id"].as_str().unwrap();
    let nonce = body["nonce"].as_str().unwrap();

    assert!(!challenge_id.is_empty());
    assert_eq!(STANDARD.decode(nonce).unwrap().len(), 32);
}

#[tokio::test]
async fn auth_challenge_rejects_unknown_user() {
    let server = TestServer::start().await;

    let response = server
        .post_json("/auth/challenge", json!({ "username": "missing_user" }))
        .await;

    assert_eq!(response.status, 404);
}

#[tokio::test]
async fn auth_verify_with_valid_signature_issues_session_token() {
    let server = TestServer::start().await;
    let signing_key = fixed_signing_key();
    server.register_user("alice_123", &signing_key).await;
    let challenge = request_challenge(&server, "alice_123").await;
    let challenge_id = challenge["challenge_id"].as_str().unwrap();
    let nonce = STANDARD
        .decode(challenge["nonce"].as_str().unwrap())
        .unwrap();
    let signature = signing_key.sign(&nonce);

    let response = server
        .post_json(
            "/auth/verify",
            json!({
                "challenge_id": challenge_id,
                "signature": STANDARD.encode(signature.to_bytes())
            }),
        )
        .await;

    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let token = body["token"].as_str().unwrap();
    assert!(!token.is_empty());
    assert_eq!(body["username"], "alice_123");

    let session = server.get_bearer("/auth/session", token).await;
    assert_eq!(session.status, 200);
    let session_body: serde_json::Value = serde_json::from_str(&session.body).unwrap();
    assert_eq!(session_body["username"], "alice_123");
}

#[tokio::test]
async fn auth_verify_with_bad_signature_is_rejected() {
    let server = TestServer::start().await;
    let signing_key = fixed_signing_key();
    server.register_user("alice_123", &signing_key).await;
    let challenge = request_challenge(&server, "alice_123").await;
    let challenge_id = challenge["challenge_id"].as_str().unwrap();
    let bad_signature = SigningKey::from_bytes(&[9u8; 32]).sign(b"not the nonce");

    let response = server
        .post_json(
            "/auth/verify",
            json!({
                "challenge_id": challenge_id,
                "signature": STANDARD.encode(bad_signature.to_bytes())
            }),
        )
        .await;

    assert_eq!(response.status, 401);
    let count = sqlx::query("SELECT COUNT(*) AS count FROM sessions")
        .fetch_one(&server.pool)
        .await
        .unwrap()
        .get::<i64, _>("count");
    assert_eq!(count, 0);
}

#[tokio::test]
async fn auth_verify_rejects_unknown_or_reused_challenge() {
    let server = TestServer::start().await;
    let signing_key = fixed_signing_key();
    server.register_user("alice_123", &signing_key).await;
    let challenge = request_challenge(&server, "alice_123").await;
    let challenge_id = challenge["challenge_id"].as_str().unwrap();
    let nonce = STANDARD
        .decode(challenge["nonce"].as_str().unwrap())
        .unwrap();
    let signature = STANDARD.encode(signing_key.sign(&nonce).to_bytes());

    let unknown = server
        .post_json(
            "/auth/verify",
            json!({ "challenge_id": "unknown", "signature": signature }),
        )
        .await;
    assert_eq!(unknown.status, 401);

    let first = server
        .post_json(
            "/auth/verify",
            json!({ "challenge_id": challenge_id, "signature": signature }),
        )
        .await;
    let second = server
        .post_json(
            "/auth/verify",
            json!({ "challenge_id": challenge_id, "signature": signature }),
        )
        .await;

    assert_eq!(first.status, 200);
    assert_eq!(second.status, 401);
}

#[tokio::test]
async fn auth_session_rejects_unknown_token() {
    let server = TestServer::start().await;

    let response = server.get_bearer("/auth/session", "unknown-token").await;

    assert_eq!(response.status, 401);
}

#[tokio::test]
async fn auth_malformed_json_returns_bad_request() {
    let server = TestServer::start().await;

    let challenge = server.post_raw("/auth/challenge", "{").await;
    let verify = server.post_raw("/auth/verify", "{").await;

    assert_eq!(challenge.status, 400);
    assert_eq!(verify.status, 400);
}

#[tokio::test]
async fn auth_tables_store_no_private_material() {
    let server = TestServer::start().await;

    for table in ["auth_challenges", "sessions"] {
        let columns = sqlx::query(&format!("PRAGMA table_info({table})"))
            .fetch_all(&server.pool)
            .await
            .unwrap()
            .into_iter()
            .map(|row| row.get::<String, _>("name"))
            .collect::<Vec<_>>();

        assert!(!columns.is_empty(), "{table}");
        assert!(columns.iter().all(|column| {
            !column.contains("private")
                && !column.contains("secret")
                && !column.contains("password")
        }));
    }
}
