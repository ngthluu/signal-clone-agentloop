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

    async fn register_and_sign_in(&self, username: &str, seed: u8) -> SignedInUser {
        let signing_key = SigningKey::from_bytes(&[seed; 32]);
        let public_key = STANDARD.encode(signing_key.verifying_key().to_bytes());
        let register = self
            .post_json(
                "/register",
                json!({
                    "username": username,
                    "identity_public_key": public_key
                }),
            )
            .await;
        assert_eq!(register.status, 201);
        let user_id = serde_json::from_str::<serde_json::Value>(&register.body).unwrap()["user_id"]
            .as_str()
            .unwrap()
            .to_string();

        let challenge = self
            .post_json("/auth/challenge", json!({ "username": username }))
            .await;
        assert_eq!(challenge.status, 201);
        let challenge_body: serde_json::Value = serde_json::from_str(&challenge.body).unwrap();
        let nonce = STANDARD
            .decode(challenge_body["nonce"].as_str().unwrap())
            .unwrap();
        let signature = signing_key.sign(&nonce);

        let verify = self
            .post_json(
                "/auth/verify",
                json!({
                    "challenge_id": challenge_body["challenge_id"].as_str().unwrap(),
                    "signature": STANDARD.encode(signature.to_bytes())
                }),
            )
            .await;
        assert_eq!(verify.status, 200);
        let verify_body: serde_json::Value = serde_json::from_str(&verify.body).unwrap();

        SignedInUser {
            user_id,
            username: username.to_string(),
            token: verify_body["token"].as_str().unwrap().to_string(),
        }
    }

    async fn insert_message(
        &self,
        id: &str,
        sender: &SignedInUser,
        recipient: &SignedInUser,
        ciphertext: &str,
        created_at: &str,
    ) {
        sqlx::query(
            "INSERT INTO messages (id, sender_id, recipient_id, ciphertext, created_at)
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(id)
        .bind(&sender.user_id)
        .bind(&recipient.user_id)
        .bind(ciphertext)
        .bind(created_at)
        .execute(&self.pool)
        .await
        .unwrap();
    }

    async fn post_json(&self, path: &str, body: serde_json::Value) -> HttpResponse {
        self.request_with_body("POST", path, None, body.to_string())
            .await
    }

    async fn get(&self, path: &str) -> HttpResponse {
        let request = format!(
            "GET {path} HTTP/1.1\r\nHost: {}\r\nConnection: close\r\n\r\n",
            self.addr
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

    async fn request_with_body(
        &self,
        method: &str,
        path: &str,
        token: Option<&str>,
        body: String,
    ) -> HttpResponse {
        let auth = token
            .map(|token| format!("Authorization: Bearer {token}\r\n"))
            .unwrap_or_default();
        let request = format!(
            "{method} {path} HTTP/1.1\r\nHost: {}\r\nContent-Type: application/json\r\n{}Content-Length: {}\r\nConnection: close\r\n\r\n{}",
            self.addr,
            auth,
            body.len(),
            body
        );

        send_request(self.addr, request).await
    }
}

struct SignedInUser {
    user_id: String,
    username: String,
    token: String,
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
async fn conversations_requires_bearer_token() {
    let server = TestServer::start().await;

    let without_token = server.get("/conversations").await;
    let bad_token = server
        .get_bearer("/conversations", "not-a-real-token")
        .await;

    assert_eq!(without_token.status, 401);
    assert_eq!(bad_token.status, 401);
}

#[tokio::test]
async fn conversations_lists_distinct_peers_ordered_by_recent_activity() {
    let server = TestServer::start().await;
    let viewer = server.register_and_sign_in("viewer_convs", 51).await;
    let peer_one = server.register_and_sign_in("peer_one_convs", 52).await;
    let peer_two = server.register_and_sign_in("peer_two_convs", 53).await;

    server
        .insert_message(
            "00000000-0000-0000-0000-000000000101",
            &viewer,
            &peer_one,
            "cipher-v-to-p1-old",
            "2026-01-01T00:00:01Z",
        )
        .await;
    server
        .insert_message(
            "00000000-0000-0000-0000-000000000102",
            &viewer,
            &peer_two,
            "cipher-v-to-p2",
            "2026-01-01T00:00:02Z",
        )
        .await;
    server
        .insert_message(
            "00000000-0000-0000-0000-000000000103",
            &peer_one,
            &viewer,
            "cipher-p1-to-v-new",
            "2026-01-01T00:00:03Z",
        )
        .await;

    let response = server.get_bearer("/conversations", &viewer.token).await;

    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let conversations = body["conversations"].as_array().unwrap();
    assert_eq!(conversations.len(), 2);
    assert_eq!(conversations[0]["peer_id"], peer_one.user_id);
    assert_eq!(conversations[0]["peer_username"], peer_one.username);
    assert_eq!(conversations[0]["last_message_id"], "00000000-0000-0000-0000-000000000103");
    assert_eq!(conversations[0]["last_ciphertext"], "cipher-p1-to-v-new");
    assert_eq!(conversations[0]["last_created_at"], "2026-01-01T00:00:03Z");
    assert_eq!(conversations[1]["peer_id"], peer_two.user_id);
    assert_eq!(conversations[1]["peer_username"], peer_two.username);
    assert_eq!(conversations[1]["last_message_id"], "00000000-0000-0000-0000-000000000102");
    assert_eq!(conversations[1]["last_ciphertext"], "cipher-v-to-p2");
    assert_eq!(conversations[1]["last_created_at"], "2026-01-01T00:00:02Z");
}

#[tokio::test]
async fn conversations_scope_excludes_unrelated_pairs_and_names_the_peer() {
    let server = TestServer::start().await;
    let viewer = server.register_and_sign_in("viewer_scope", 61).await;
    let peer_one = server.register_and_sign_in("peer_scope_one", 62).await;
    let peer_two = server.register_and_sign_in("peer_scope_two", 63).await;

    server
        .insert_message(
            "00000000-0000-0000-0000-000000000201",
            &viewer,
            &peer_one,
            "viewer-peer-one",
            "2026-02-01T00:00:01Z",
        )
        .await;
    server
        .insert_message(
            "00000000-0000-0000-0000-000000000202",
            &peer_one,
            &peer_two,
            "unrelated-peer-pair",
            "2026-02-01T00:00:02Z",
        )
        .await;

    let response = server.get_bearer("/conversations", &viewer.token).await;

    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let conversations = body["conversations"].as_array().unwrap();
    assert_eq!(conversations.len(), 1);
    assert_eq!(conversations[0]["peer_id"], peer_one.user_id);
    assert_eq!(conversations[0]["peer_username"], peer_one.username);
    assert_ne!(conversations[0]["peer_id"], viewer.user_id);
    assert_ne!(conversations[0]["peer_username"], viewer.username);
    assert_eq!(conversations[0]["last_message_id"], "00000000-0000-0000-0000-000000000201");
    assert_eq!(conversations[0]["last_ciphertext"], "viewer-peer-one");
    assert_eq!(conversations[0]["last_created_at"], "2026-02-01T00:00:01Z");
}

#[tokio::test]
async fn conversations_include_inbound_only_peer_started_while_viewer_was_offline() {
    let server = TestServer::start().await;
    let viewer = server.register_and_sign_in("viewer_inbound_only", 94).await;
    let peer = server.register_and_sign_in("peer_inbound_only", 95).await;

    server
        .insert_message(
            "ffffffff-ffff-ffff-ffff-fffffffffff0",
            &peer,
            &viewer,
            "peer-started-while-viewer-offline",
            "2026-06-01T00:00:00Z",
        )
        .await;

    let response = server.get_bearer("/conversations", &viewer.token).await;

    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let conversations = body["conversations"].as_array().unwrap();
    assert_eq!(conversations.len(), 1);
    assert_eq!(conversations[0]["peer_id"], peer.user_id);
    assert_eq!(conversations[0]["peer_username"], peer.username);
    assert_eq!(
        conversations[0]["last_message_id"],
        "ffffffff-ffff-ffff-ffff-fffffffffff0"
    );
    assert_eq!(
        conversations[0]["last_ciphertext"],
        "peer-started-while-viewer-offline"
    );
}

#[tokio::test]
async fn conversations_use_rowid_tiebreaks_instead_of_random_uuid_order() {
    let server = TestServer::start().await;
    let viewer = server.register_and_sign_in("viewer_order", 81).await;
    let peer_first = server.register_and_sign_in("peer_order_first_inserted", 82).await;
    let peer_second = server.register_and_sign_in("peer_order_second_inserted", 83).await;
    let created_at = "2026-04-01T00:00:10Z";

    server
        .insert_message(
            "ffffffff-ffff-ffff-ffff-ffffffffffff",
            &viewer,
            &peer_first,
            "first-peer-first-message",
            created_at,
        )
        .await;
    server
        .insert_message(
            "ffffffff-ffff-ffff-ffff-fffffffffff1",
            &viewer,
            &peer_second,
            "second-peer-message",
            created_at,
        )
        .await;
    server
        .insert_message(
            "00000000-0000-0000-0000-000000000001",
            &peer_first,
            &viewer,
            "first-peer-second-message",
            created_at,
        )
        .await;

    let response = server.get_bearer("/conversations", &viewer.token).await;

    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let conversations = body["conversations"].as_array().unwrap();
    assert_eq!(conversations.len(), 2);
    assert_eq!(conversations[0]["peer_id"], peer_first.user_id);
    assert_eq!(conversations[0]["peer_username"], peer_first.username);
    assert_eq!(
        conversations[0]["last_message_id"],
        "00000000-0000-0000-0000-000000000001"
    );
    assert_eq!(conversations[0]["last_ciphertext"], "first-peer-second-message");
    assert_eq!(conversations[0]["last_created_at"], created_at);
    assert_eq!(conversations[1]["peer_id"], peer_second.user_id);
    assert_eq!(
        conversations[1]["last_message_id"],
        "ffffffff-ffff-ffff-ffff-fffffffffff1"
    );
}

#[tokio::test]
async fn conversations_return_ciphertext_and_metadata_without_plaintext() {
    let server = TestServer::start().await;
    let viewer = server.register_and_sign_in("viewer_ciphertext", 71).await;
    let peer = server.register_and_sign_in("peer_ciphertext", 72).await;
    let ciphertext = "AQIDBAUGBwg=.opaque-envelope-only";

    server
        .insert_message(
            "00000000-0000-0000-0000-000000000301",
            &viewer,
            &peer,
            ciphertext,
            "2026-03-01T00:00:01Z",
        )
        .await;

    let response = server.get_bearer("/conversations", &viewer.token).await;

    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let conversation = &body["conversations"].as_array().unwrap()[0];
    assert_eq!(conversation["last_ciphertext"], ciphertext);

    let keys = conversation
        .as_object()
        .unwrap()
        .keys()
        .cloned()
        .collect::<Vec<_>>();
    assert_eq!(
        keys,
        vec![
            "last_ciphertext",
            "last_created_at",
            "last_message_id",
            "peer_id",
            "peer_username",
        ]
    );

    for forbidden in ["plaintext", "body", "text", "content"] {
        assert!(
            conversation.get(forbidden).is_none(),
            "unexpected plaintext-like field {forbidden}"
        );
        assert!(
            body.get(forbidden).is_none(),
            "unexpected top-level plaintext-like field {forbidden}"
        );
    }

    let stored_ciphertext = sqlx::query("SELECT ciphertext FROM messages WHERE id = ?")
        .bind("00000000-0000-0000-0000-000000000301")
        .fetch_one(&server.pool)
        .await
        .unwrap()
        .get::<String, _>("ciphertext");
    assert_eq!(stored_ciphertext, ciphertext);
}

#[tokio::test]
async fn conversations_empty_for_user_with_no_messages() {
    let server = TestServer::start().await;
    let viewer = server.register_and_sign_in("viewer_empty", 91).await;
    let other_one = server.register_and_sign_in("other_empty_one", 92).await;
    let other_two = server.register_and_sign_in("other_empty_two", 93).await;

    server
        .insert_message(
            "00000000-0000-0000-0000-000000000401",
            &other_one,
            &other_two,
            "unrelated",
            "2026-05-01T00:00:01Z",
        )
        .await;

    let response = server.get_bearer("/conversations", &viewer.token).await;

    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    assert_eq!(body["conversations"].as_array().unwrap().len(), 0);
}
