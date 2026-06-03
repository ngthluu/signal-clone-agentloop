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
            signing_key,
            token: verify_body["token"].as_str().unwrap().to_string(),
        }
    }

    async fn publish_prekey(&self, user: &SignedInUser, seed: u8) -> PublishedPrekey {
        let x25519_bytes = [seed; 32];
        let signature = user.signing_key.sign(&x25519_bytes);
        let x25519_public_key = STANDARD.encode(x25519_bytes);
        let key_signature = STANDARD.encode(signature.to_bytes());
        let response = self
            .put_json_bearer(
                "/keys",
                &user.token,
                json!({
                    "x25519_public_key": x25519_public_key,
                    "key_signature": key_signature
                }),
            )
            .await;
        assert!(response.status == 200 || response.status == 201);

        PublishedPrekey {
            x25519_public_key,
            key_signature,
        }
    }

    async fn post_json(&self, path: &str, body: serde_json::Value) -> HttpResponse {
        self.request_with_body("POST", path, None, body.to_string())
            .await
    }

    async fn post_json_bearer(
        &self,
        path: &str,
        token: &str,
        body: serde_json::Value,
    ) -> HttpResponse {
        self.request_with_body("POST", path, Some(token), body.to_string())
            .await
    }

    async fn put_json_bearer(
        &self,
        path: &str,
        token: &str,
        body: serde_json::Value,
    ) -> HttpResponse {
        self.request_with_body("PUT", path, Some(token), body.to_string())
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

    async fn insert_message(
        &self,
        id: &str,
        sender_id: &str,
        recipient_id: &str,
        ciphertext: &str,
        created_at: &str,
    ) -> i64 {
        sqlx::query(
            "INSERT INTO messages (id, sender_id, recipient_id, ciphertext, created_at)
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(id)
        .bind(sender_id)
        .bind(recipient_id)
        .bind(ciphertext)
        .bind(created_at)
        .execute(&self.pool)
        .await
        .unwrap();

        sqlx::query("SELECT rowid FROM messages WHERE id = ?")
            .bind(id)
            .fetch_one(&self.pool)
            .await
            .unwrap()
            .get("rowid")
    }
}

struct SignedInUser {
    user_id: String,
    username: String,
    signing_key: SigningKey,
    token: String,
}

struct PublishedPrekey {
    x25519_public_key: String,
    key_signature: String,
}

struct HttpResponse {
    status: u16,
    body: String,
}

struct HttpHead {
    status: u16,
    headers: String,
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

async fn send_request_head_only(addr: SocketAddr, request: String) -> HttpHead {
    let mut stream = TcpStream::connect(addr).await.unwrap();
    stream.write_all(request.as_bytes()).await.unwrap();

    let mut response = Vec::new();
    let mut buffer = [0u8; 1024];
    loop {
        let count = stream.read(&mut buffer).await.unwrap();
        assert_ne!(count, 0, "connection closed before response headers");
        response.extend_from_slice(&buffer[..count]);
        if response.windows(4).any(|window| window == b"\r\n\r\n") {
            break;
        }
    }

    let response = String::from_utf8(response).unwrap();
    let (head, _) = response
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

    HttpHead {
        status,
        headers: head.to_string(),
    }
}

#[tokio::test]
async fn keys_publish_requires_valid_identity_signature() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("alice_keys", 11).await;

    let good = server.publish_prekey(&alice, 31).await;
    let row =
        sqlx::query("SELECT x25519_public_key, key_signature FROM device_keys WHERE user_id = ?")
            .bind(&alice.user_id)
            .fetch_one(&server.pool)
            .await
            .unwrap();
    assert_eq!(
        row.get::<String, _>("x25519_public_key"),
        good.x25519_public_key
    );
    assert_eq!(row.get::<String, _>("key_signature"), good.key_signature);

    let bad_key = STANDARD.encode([32u8; 32]);
    let bad_signature = STANDARD.encode(alice.signing_key.sign(b"not the prekey").to_bytes());
    let rejected = server
        .put_json_bearer(
            "/keys",
            &alice.token,
            json!({
                "x25519_public_key": bad_key,
                "key_signature": bad_signature
            }),
        )
        .await;

    assert_eq!(rejected.status, 400);
    let stored = sqlx::query("SELECT x25519_public_key FROM device_keys WHERE user_id = ?")
        .bind(&alice.user_id)
        .fetch_one(&server.pool)
        .await
        .unwrap()
        .get::<String, _>("x25519_public_key");
    assert_eq!(stored, good.x25519_public_key);
}

#[tokio::test]
async fn keys_fetch_returns_published_prekey_for_username() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("alice_fetch", 12).await;
    let bob = server.register_and_sign_in("bob_fetch", 13).await;
    let prekey = server.publish_prekey(&alice, 33).await;

    let response = server.get("/keys/alice_fetch").await;
    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    assert_eq!(body["user_id"], alice.user_id);
    assert_eq!(body["username"], alice.username);
    assert_eq!(body["x25519_public_key"], prekey.x25519_public_key);
    assert_eq!(body["key_signature"], prekey.key_signature);
    assert_eq!(
        body["identity_public_key"],
        STANDARD.encode(alice.signing_key.verifying_key().to_bytes())
    );

    assert_eq!(server.get("/keys/missing_user").await.status, 404);
    assert_eq!(
        server.get(&format!("/keys/{}", bob.username)).await.status,
        404
    );
}

#[tokio::test]
async fn messages_post_requires_bearer_token() {
    let server = TestServer::start().await;

    let without_token = server
        .post_json(
            "/messages",
            json!({
                "recipient_username": "nobody",
                "ciphertext": "opaque"
            }),
        )
        .await;
    let bad_token = server
        .post_json_bearer(
            "/messages",
            "not-a-real-token",
            json!({
                "recipient_username": "nobody",
                "ciphertext": "opaque"
            }),
        )
        .await;

    assert_eq!(without_token.status, 401);
    assert_eq!(bad_token.status, 401);
}

#[tokio::test]
async fn messages_stream_requires_bearer_token() {
    let server = TestServer::start().await;

    let without_token = server.get("/messages/stream").await;
    let bad_token = server
        .get_bearer("/messages/stream", "not-a-real-token")
        .await;

    assert_eq!(without_token.status, 401);
    assert_eq!(bad_token.status, 401);
}

#[tokio::test]
async fn messages_stream_with_valid_token_returns_sse_headers() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("alice_stream", 41).await;
    let request = format!(
        "GET /messages/stream HTTP/1.1\r\nHost: {}\r\nAuthorization: Bearer {}\r\nConnection: close\r\n\r\n",
        server.addr, alice.token
    );

    let response = send_request_head_only(server.addr, request).await;

    assert_eq!(response.status, 200);
    assert!(
        response
            .headers
            .to_ascii_lowercase()
            .contains("content-type: text/event-stream"),
        "{}",
        response.headers
    );
}

#[tokio::test]
async fn messages_post_stores_exactly_the_ciphertext_blob() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("alice_send", 14).await;
    let bob = server.register_and_sign_in("bob_send", 15).await;
    let ciphertext = "AQIDBAUGBwgJCgsMDQ4PEA==.opaque.blob";

    let response = server
        .post_json_bearer(
            "/messages",
            &alice.token,
            json!({
                "recipient_username": bob.username,
                "ciphertext": ciphertext
            }),
        )
        .await;
    assert_eq!(response.status, 201);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let message_id = body["message_id"].as_str().unwrap();
    assert!(!message_id.is_empty());
    assert!(body["created_at"].as_str().unwrap().ends_with('Z'));

    let row = sqlx::query(
        "SELECT sender_id, recipient_id, ciphertext, created_at FROM messages WHERE id = ?",
    )
    .bind(message_id)
    .fetch_one(&server.pool)
    .await
    .unwrap();
    assert_eq!(row.get::<String, _>("sender_id"), alice.user_id);
    assert_eq!(row.get::<String, _>("recipient_id"), bob.user_id);
    assert_eq!(row.get::<String, _>("ciphertext"), ciphertext);
}

#[tokio::test]
async fn messages_inbox_delivers_same_second_messages_in_send_order() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("alice_inbox_order", 51).await;
    let bob = server.register_and_sign_in("bob_inbox_order", 52).await;
    let created_at = "2026-06-04T00:00:00Z";
    let expected_ids = ["msg-c", "msg-a", "msg-b", "msg-aa"];

    for (index, id) in expected_ids.iter().enumerate() {
        server
            .insert_message(
                id,
                &alice.user_id,
                &bob.user_id,
                &format!("ciphertext-{index}"),
                created_at,
            )
            .await;
    }

    let response = server.get_bearer("/messages/inbox", &bob.token).await;

    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let messages = body["messages"].as_array().unwrap();
    let actual_ids = messages
        .iter()
        .map(|message| message["id"].as_str().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(actual_ids, expected_ids);
    assert_eq!(body["next_cursor"].as_i64().unwrap(), 4);

    for message in messages {
        let keys = message
            .as_object()
            .unwrap()
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        assert_eq!(
            keys,
            vec![
                "ciphertext",
                "created_at",
                "id",
                "recipient_id",
                "sender_id",
                "seq"
            ]
        );
        assert!(message.get("plaintext").is_none());
        assert!(message["seq"].as_i64().unwrap() > 0);
    }
}

#[tokio::test]
async fn messages_inbox_is_scoped_to_recipient_inbound_messages_only() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("alice_inbox_scope", 53).await;
    let bob = server.register_and_sign_in("bob_inbox_scope", 54).await;
    let carol = server.register_and_sign_in("carol_inbox_scope", 55).await;

    server
        .insert_message(
            "scope-alice-to-bob",
            &alice.user_id,
            &bob.user_id,
            "ciphertext-for-bob",
            "2026-06-04T00:00:01Z",
        )
        .await;
    server
        .insert_message(
            "scope-bob-to-alice",
            &bob.user_id,
            &alice.user_id,
            "sent-by-bob",
            "2026-06-04T00:00:02Z",
        )
        .await;
    server
        .insert_message(
            "scope-alice-to-carol",
            &alice.user_id,
            &carol.user_id,
            "ciphertext-for-carol",
            "2026-06-04T00:00:03Z",
        )
        .await;

    let response = server.get_bearer("/messages/inbox", &bob.token).await;

    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let messages = body["messages"].as_array().unwrap();
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0]["id"], "scope-alice-to-bob");
    assert_eq!(messages[0]["recipient_id"], bob.user_id);
}

#[tokio::test]
async fn messages_inbox_since_cursor_returns_only_later_rows_and_advances() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("alice_inbox_cursor", 56).await;
    let bob = server.register_and_sign_in("bob_inbox_cursor", 57).await;

    let first_seq = server
        .insert_message(
            "cursor-first",
            &alice.user_id,
            &bob.user_id,
            "first",
            "2026-06-04T00:00:04Z",
        )
        .await;
    let second_seq = server
        .insert_message(
            "cursor-second",
            &alice.user_id,
            &bob.user_id,
            "second",
            "2026-06-04T00:00:05Z",
        )
        .await;
    server
        .insert_message(
            "cursor-third",
            &alice.user_id,
            &bob.user_id,
            "third",
            "2026-06-04T00:00:06Z",
        )
        .await;

    let response = server
        .get_bearer(&format!("/messages/inbox?since={first_seq}"), &bob.token)
        .await;

    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let messages = body["messages"].as_array().unwrap();
    let actual_ids = messages
        .iter()
        .map(|message| message["id"].as_str().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(actual_ids, vec!["cursor-second", "cursor-third"]);
    assert_eq!(messages[0]["seq"].as_i64().unwrap(), second_seq);
    assert_eq!(
        body["next_cursor"].as_i64().unwrap(),
        messages.last().unwrap()["seq"].as_i64().unwrap()
    );
}

#[tokio::test]
async fn messages_inbox_requires_bearer_token() {
    let server = TestServer::start().await;

    let without_token = server.get("/messages/inbox").await;
    let bad_token = server
        .get_bearer("/messages/inbox", "not-a-real-token")
        .await;

    assert_eq!(without_token.status, 401);
    assert_eq!(bad_token.status, 401);
}

#[tokio::test]
async fn messages_inbox_empty_for_caller_with_no_inbound_messages() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("alice_inbox_empty", 58).await;

    let response = server.get_bearer("/messages/inbox", &alice.token).await;

    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    assert!(body["messages"].as_array().unwrap().is_empty());
    assert!(body["next_cursor"].is_null());
}

#[tokio::test]
async fn messages_history_returns_only_ciphertext_and_is_scoped_to_the_pair() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("alice_history", 16).await;
    let bob = server.register_and_sign_in("bob_history", 17).await;
    let carol = server.register_and_sign_in("carol_history", 18).await;

    let alice_to_bob = server
        .post_json_bearer(
            "/messages",
            &alice.token,
            json!({
                "recipient_username": bob.username,
                "ciphertext": "ciphertext-from-alice"
            }),
        )
        .await;
    assert_eq!(alice_to_bob.status, 201);
    let bob_to_alice = server
        .post_json_bearer(
            "/messages",
            &bob.token,
            json!({
                "recipient_username": alice.username,
                "ciphertext": "ciphertext-from-bob"
            }),
        )
        .await;
    assert_eq!(bob_to_alice.status, 201);
    let carol_to_alice = server
        .post_json_bearer(
            "/messages",
            &carol.token,
            json!({
                "recipient_username": alice.username,
                "ciphertext": "ciphertext-from-carol"
            }),
        )
        .await;
    assert_eq!(carol_to_alice.status, 201);

    let response = server
        .get_bearer("/messages?with=bob_history", &alice.token)
        .await;
    assert_eq!(response.status, 200);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let messages = body["messages"].as_array().unwrap();
    assert_eq!(messages.len(), 2);
    let ciphertexts = messages
        .iter()
        .map(|message| message["ciphertext"].as_str().unwrap())
        .collect::<Vec<_>>();
    assert!(ciphertexts.contains(&"ciphertext-from-alice"));
    assert!(ciphertexts.contains(&"ciphertext-from-bob"));
    assert!(!ciphertexts.contains(&"ciphertext-from-carol"));

    for message in messages {
        let keys = message
            .as_object()
            .unwrap()
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        assert_eq!(
            keys,
            vec![
                "ciphertext",
                "created_at",
                "id",
                "recipient_id",
                "sender_id"
            ]
        );
        assert!(message["created_at"].as_str().unwrap().ends_with('Z'));
    }
}

#[tokio::test]
async fn messages_table_stores_no_plaintext_columns() {
    let server = TestServer::start().await;
    let message_columns = sqlx::query("PRAGMA table_info(messages)")
        .fetch_all(&server.pool)
        .await
        .unwrap()
        .into_iter()
        .map(|row| row.get::<String, _>("name"))
        .collect::<Vec<_>>();
    assert_eq!(
        message_columns,
        vec![
            "id",
            "sender_id",
            "recipient_id",
            "ciphertext",
            "created_at"
        ]
    );

    let forbidden = [
        "plaintext",
        "body",
        "text",
        "content",
        "message",
        "cleartext",
        "private",
        "secret",
    ];

    for table in ["messages", "device_keys"] {
        let columns = sqlx::query(&format!("PRAGMA table_info({table})"))
            .fetch_all(&server.pool)
            .await
            .unwrap()
            .into_iter()
            .map(|row| row.get::<String, _>("name"))
            .collect::<Vec<_>>();

        assert!(!columns.is_empty(), "{table}");
        for column in columns {
            assert!(
                forbidden.iter().all(|forbidden| column != *forbidden),
                "{table}.{column}"
            );
        }
    }
}
