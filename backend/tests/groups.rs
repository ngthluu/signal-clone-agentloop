use std::net::SocketAddr;

use base64::{engine::general_purpose::STANDARD, Engine as _};
use ed25519_dalek::{Signer, SigningKey};
use serde_json::json;
use sqlx::Row;
use test_chat_backend::{app, db};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
    time::{timeout, Duration},
};

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

    async fn publish_prekey(&self, user: &SignedInUser, seed: u8) {
        let x25519_bytes = [seed; 32];
        let signature = user.signing_key.sign(&x25519_bytes);
        let response = self
            .put_json_bearer(
                "/keys",
                &user.token,
                json!({
                    "x25519_public_key": STANDARD.encode(x25519_bytes),
                    "key_signature": STANDARD.encode(signature.to_bytes())
                }),
            )
            .await;
        assert_eq!(response.status, 200);
    }

    async fn create_group(
        &self,
        creator: &SignedInUser,
        name: &str,
        members: &[&SignedInUser],
    ) -> serde_json::Value {
        let response = self
            .post_json_bearer(
                "/groups",
                &creator.token,
                json!({
                    "name": name,
                    "members": members.iter().map(|user| {
                        json!({
                            "username": user.username,
                            "wrapped_key": wrapped_key_for(&user.username, 0),
                        })
                    }).collect::<Vec<_>>()
                }),
            )
            .await;
        assert_eq!(response.status, 201, "{}", response.body);
        serde_json::from_str(&response.body).unwrap()
    }

    async fn insert_group_fixture(
        &self,
        id: &str,
        name: &str,
        creator: &SignedInUser,
        members: &[&SignedInUser],
        created_at: &str,
    ) {
        sqlx::query(
            "INSERT INTO groups (id, name, creator_id, current_epoch, created_at)
             VALUES (?, ?, ?, 0, ?)",
        )
        .bind(id)
        .bind(name)
        .bind(&creator.user_id)
        .bind(created_at)
        .execute(&self.pool)
        .await
        .unwrap();

        for member in members {
            sqlx::query(
                "INSERT INTO group_members (group_id, user_id, joined_epoch, added_at)
                 VALUES (?, ?, 0, ?)",
            )
            .bind(id)
            .bind(&member.user_id)
            .bind(created_at)
            .execute(&self.pool)
            .await
            .unwrap();
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

    async fn insert_group_message(
        &self,
        id: &str,
        group_id: &str,
        sender_id: &str,
        epoch: i64,
        ciphertext: &str,
        created_at: &str,
    ) {
        sqlx::query(
            "INSERT INTO group_messages (id, group_id, sender_id, epoch, ciphertext, created_at)
             VALUES (?, ?, ?, ?, ?, ?)",
        )
        .bind(id)
        .bind(group_id)
        .bind(sender_id)
        .bind(epoch)
        .bind(ciphertext)
        .bind(created_at)
        .execute(&self.pool)
        .await
        .unwrap();
    }
}

struct SignedInUser {
    user_id: String,
    username: String,
    signing_key: SigningKey,
    token: String,
}

struct HttpResponse {
    status: u16,
    body: String,
}

struct HttpHeadResponse {
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

async fn send_request_head_only(addr: SocketAddr, request: String) -> HttpHeadResponse {
    let mut stream = TcpStream::connect(addr).await.unwrap();
    stream.write_all(request.as_bytes()).await.unwrap();

    let mut response = Vec::new();
    let mut buffer = [0_u8; 256];
    loop {
        let count = stream.read(&mut buffer).await.unwrap();
        if count == 0 {
            break;
        }
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

    HttpHeadResponse {
        status,
        headers: head.to_string(),
    }
}

async fn open_stream_and_read_headers(addr: SocketAddr, request: String) -> TcpStream {
    let mut stream = TcpStream::connect(addr).await.unwrap();
    stream.write_all(request.as_bytes()).await.unwrap();

    let mut response = Vec::new();
    let mut buffer = [0_u8; 256];
    loop {
        let count = timeout(Duration::from_secs(2), stream.read(&mut buffer))
            .await
            .unwrap()
            .unwrap();
        assert_ne!(count, 0, "stream closed before headers");
        response.extend_from_slice(&buffer[..count]);
        if response.windows(4).any(|window| window == b"\r\n\r\n") {
            break;
        }
    }

    let head = String::from_utf8_lossy(&response);
    assert!(head.starts_with("HTTP/1.1 200"), "{head}");
    stream
}

async fn read_stream_until(stream: &mut TcpStream, needle: &str) -> String {
    let mut response = String::new();
    let mut buffer = [0_u8; 512];
    timeout(Duration::from_secs(2), async {
        loop {
            let count = stream.read(&mut buffer).await.unwrap();
            assert_ne!(count, 0, "stream closed before {needle}");
            response.push_str(&String::from_utf8_lossy(&buffer[..count]));
            if response.contains(needle) {
                return;
            }
        }
    })
    .await
    .unwrap();
    response
}

fn wrapped_key_for(username: &str, epoch: i64) -> String {
    STANDARD.encode(format!("wrapped-key:{username}:epoch:{epoch}"))
}

#[tokio::test]
async fn group_create_persists_name_membership_and_epoch_zero_keys() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("group_alice_create", 51).await;
    let bob = server.register_and_sign_in("group_bob_create", 52).await;
    let carol = server.register_and_sign_in("group_carol_create", 53).await;
    server.publish_prekey(&alice, 61).await;
    server.publish_prekey(&bob, 62).await;
    server.publish_prekey(&carol, 63).await;

    let body = server
        .create_group(&alice, "Launch team", &[&alice, &bob, &carol])
        .await;
    let group_id = body["group_id"].as_str().unwrap();
    assert_eq!(body["epoch"], 0);
    assert_eq!(body["members"].as_array().unwrap().len(), 3);

    let group_row = sqlx::query("SELECT name, creator_id, current_epoch FROM groups WHERE id = ?")
        .bind(group_id)
        .fetch_one(&server.pool)
        .await
        .unwrap();
    assert_eq!(group_row.get::<String, _>("name"), "Launch team");
    assert_eq!(group_row.get::<String, _>("creator_id"), alice.user_id);
    assert_eq!(group_row.get::<i64, _>("current_epoch"), 0);

    let member_count: i64 = sqlx::query(
        "SELECT COUNT(*) AS count FROM group_members WHERE group_id = ? AND joined_epoch = 0",
    )
    .bind(group_id)
    .fetch_one(&server.pool)
    .await
    .unwrap()
    .get("count");
    assert_eq!(member_count, 3);

    let key_count: i64 =
        sqlx::query("SELECT COUNT(*) AS count FROM group_keys WHERE group_id = ? AND epoch = 0")
            .bind(group_id)
            .fetch_one(&server.pool)
            .await
            .unwrap()
            .get("count");
    assert_eq!(key_count, 3);

    let detail = server
        .get_bearer(&format!("/groups/{group_id}"), &bob.token)
        .await;
    assert_eq!(detail.status, 200);
    let detail_body: serde_json::Value = serde_json::from_str(&detail.body).unwrap();
    assert_eq!(detail_body["name"], "Launch team");
    assert_eq!(detail_body["members"].as_array().unwrap().len(), 3);
}

#[tokio::test]
async fn group_create_requires_bearer_token() {
    let server = TestServer::start().await;

    let without_token = server
        .post_json(
            "/groups",
            json!({
                "name": "No token",
                "members": [{"username": "nobody", "wrapped_key": "opaque"}]
            }),
        )
        .await;
    let bad_token = server
        .post_json_bearer(
            "/groups",
            "not-a-token",
            json!({
                "name": "Bad token",
                "members": [{"username": "nobody", "wrapped_key": "opaque"}]
            }),
        )
        .await;

    assert_eq!(without_token.status, 401);
    assert_eq!(bad_token.status, 401);
}

#[tokio::test]
async fn group_create_requires_creator_plus_two_invited_members() {
    let server = TestServer::start().await;
    let alice = server
        .register_and_sign_in("group_alice_create_contract", 101)
        .await;
    let bob = server
        .register_and_sign_in("group_bob_create_contract", 102)
        .await;
    let carol = server
        .register_and_sign_in("group_carol_create_contract", 103)
        .await;
    let dave = server
        .register_and_sign_in("group_dave_create_contract", 104)
        .await;

    let member_payload = |users: &[&SignedInUser]| {
        users
            .iter()
            .map(|user| {
                json!({
                    "username": user.username,
                    "wrapped_key": wrapped_key_for(&user.username, 0),
                })
            })
            .collect::<Vec<_>>()
    };

    for (name, members) in [
        ("Creator only", member_payload(&[&alice])),
        ("One invite", member_payload(&[&alice, &bob])),
        ("Duplicate member", member_payload(&[&alice, &bob, &bob])),
        ("Missing creator", member_payload(&[&bob, &carol, &dave])),
        ("   ", member_payload(&[&alice, &bob, &carol])),
    ] {
        let response = server
            .post_json_bearer(
                "/groups",
                &alice.token,
                json!({
                    "name": name,
                    "members": members
                }),
            )
            .await;
        assert_eq!(response.status, 400, "{name}: {}", response.body);
    }

    let accepted = server
        .post_json_bearer(
            "/groups",
            &alice.token,
            json!({
                "name": "Creator plus two",
                "members": member_payload(&[&alice, &bob, &carol])
            }),
        )
        .await;
    assert_eq!(accepted.status, 201, "{}", accepted.body);
    let body: serde_json::Value = serde_json::from_str(&accepted.body).unwrap();
    let group_id = body["group_id"].as_str().unwrap();
    assert_eq!(body["epoch"], 0);
    assert_eq!(body["members"].as_array().unwrap().len(), 3);

    let member_count: i64 = sqlx::query(
        "SELECT COUNT(*) AS count FROM group_members WHERE group_id = ? AND joined_epoch = 0",
    )
    .bind(group_id)
    .fetch_one(&server.pool)
    .await
    .unwrap()
    .get("count");
    assert_eq!(member_count, 3);

    let key_count: i64 =
        sqlx::query("SELECT COUNT(*) AS count FROM group_keys WHERE group_id = ? AND epoch = 0")
            .bind(group_id)
            .fetch_one(&server.pool)
            .await
            .unwrap()
            .get("count");
    assert_eq!(key_count, 3);
}

#[tokio::test]
async fn group_list_returns_all_member_groups_in_rowid_order() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("group_alice_list", 31).await;
    let bob = server.register_and_sign_in("group_bob_list", 32).await;
    let carol = server.register_and_sign_in("group_carol_list", 33).await;
    let created_at = "2026-06-01T00:00:00Z";

    server
        .insert_group_fixture(
            "ffffffff-ffff-ffff-ffff-fffffffffff0",
            "First inserted member group",
            &alice,
            &[&alice, &bob],
            created_at,
        )
        .await;
    server
        .insert_group_fixture(
            "00000000-0000-0000-0000-000000000001",
            "Second inserted member group",
            &alice,
            &[&alice, &bob],
            created_at,
        )
        .await;
    server
        .insert_group_fixture(
            "88888888-8888-8888-8888-888888888888",
            "Unrelated group",
            &carol,
            &[&carol],
            created_at,
        )
        .await;

    let response = server.get_bearer("/groups", &bob.token).await;

    assert_eq!(response.status, 200, "{}", response.body);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let groups = body.as_array().unwrap();
    assert_eq!(groups.len(), 2);
    assert_eq!(groups[0]["id"], "ffffffff-ffff-ffff-ffff-fffffffffff0");
    assert_eq!(groups[0]["name"], "First inserted member group");
    assert_eq!(groups[0]["creator_id"], alice.user_id);
    assert_eq!(groups[0]["current_epoch"], 0);
    assert_eq!(groups[0]["joined_epoch"], 0);
    assert_eq!(groups[0]["created_at"], created_at);
    assert_eq!(groups[1]["id"], "00000000-0000-0000-0000-000000000001");
    assert_eq!(groups[1]["name"], "Second inserted member group");
    assert!(groups
        .iter()
        .all(|group| group["id"] != "88888888-8888-8888-8888-888888888888"));
}

#[tokio::test]
async fn group_created_by_signed_in_user_is_listed_for_invited_members_only() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("group_alice_visible", 41).await;
    let bob = server.register_and_sign_in("group_bob_visible", 42).await;
    let carol = server.register_and_sign_in("group_carol_visible", 43).await;
    let dave = server.register_and_sign_in("group_dave_visible", 44).await;

    let body = server
        .create_group(&alice, "Visible private team", &[&alice, &bob, &carol])
        .await;
    let group_id = body["group_id"].as_str().unwrap();

    for invited in [&bob, &carol] {
        let response = server.get_bearer("/groups", &invited.token).await;
        assert_eq!(response.status, 200, "{}", response.body);
        let groups: serde_json::Value = serde_json::from_str(&response.body).unwrap();
        let groups = groups.as_array().unwrap();
        assert!(
            groups.iter().any(|group| {
                group["id"] == group_id
                    && group["name"] == "Visible private team"
                    && group["creator_id"] == alice.user_id
                    && group["current_epoch"] == 0
                    && group["joined_epoch"] == 0
            }),
            "{} did not see created group in {}",
            invited.username,
            response.body
        );
    }

    let dave_list = server.get_bearer("/groups", &dave.token).await;
    assert_eq!(dave_list.status, 200, "{}", dave_list.body);
    let dave_groups: serde_json::Value = serde_json::from_str(&dave_list.body).unwrap();
    assert!(dave_groups
        .as_array()
        .unwrap()
        .iter()
        .all(|group| group["id"] != group_id));

    assert_eq!(
        server
            .get_bearer(&format!("/groups/{group_id}"), &dave.token)
            .await
            .status,
        403
    );
    assert_eq!(
        server
            .get_bearer(&format!("/groups/{group_id}/keys"), &dave.token)
            .await
            .status,
        403
    );
    assert_eq!(
        server
            .get_bearer(&format!("/groups/{group_id}/messages"), &dave.token)
            .await
            .status,
        403
    );
    assert_eq!(
        server
            .get_bearer(&format!("/groups/{group_id}/stream"), &dave.token)
            .await
            .status,
        403
    );
    assert_eq!(
        server
            .post_json_bearer(
                &format!("/groups/{group_id}/messages"),
                &dave.token,
                json!({"epoch": 0, "ciphertext": "opaque-ciphertext"})
            )
            .await
            .status,
        403
    );
    assert_eq!(
        server
            .post_json_bearer(
                &format!("/groups/{group_id}/members"),
                &dave.token,
                json!({"username": dave.username, "epoch": 1, "keys": []})
            )
            .await
            .status,
        403
    );
}

#[tokio::test]
async fn group_endpoints_reject_non_members_with_403() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("group_alice_403", 54).await;
    let bob = server.register_and_sign_in("group_bob_403", 55).await;
    let carol = server.register_and_sign_in("group_carol_403", 56).await;
    let dave = server.register_and_sign_in("group_dave_403", 57).await;

    let body = server
        .create_group(&alice, "Private team", &[&alice, &bob, &carol])
        .await;
    let group_id = body["group_id"].as_str().unwrap();

    assert_eq!(
        server
            .get_bearer(&format!("/groups/{group_id}"), &dave.token)
            .await
            .status,
        403
    );
    assert_eq!(
        server
            .get_bearer(&format!("/groups/{group_id}/keys"), &dave.token)
            .await
            .status,
        403
    );
    assert_eq!(
        server
            .get_bearer(&format!("/groups/{group_id}/messages"), &dave.token)
            .await
            .status,
        403
    );
    assert_eq!(
        server
            .post_json_bearer(
                &format!("/groups/{group_id}/messages"),
                &dave.token,
                json!({"epoch": 0, "ciphertext": "opaque"})
            )
            .await
            .status,
        403
    );
    assert_eq!(
        server
            .post_json_bearer(
                &format!("/groups/{group_id}/members"),
                &dave.token,
                json!({"username": dave.username, "epoch": 1, "keys": []})
            )
            .await
            .status,
        403
    );
    assert_eq!(
        server
            .get_bearer(&format!("/groups/{group_id}/stream"), &dave.token)
            .await
            .status,
        403
    );
}

#[tokio::test]
async fn group_stream_requires_bearer_token() {
    let server = TestServer::start().await;

    let without_token = server.get_bearer("/groups/nope/stream", "").await;
    let bad_token = server
        .get_bearer("/groups/nope/stream", "not-a-real-token")
        .await;

    assert_eq!(without_token.status, 401);
    assert_eq!(bad_token.status, 401);
}

#[tokio::test]
async fn group_stream_with_member_returns_sse_headers() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("group_alice_stream", 84).await;
    let bob = server.register_and_sign_in("group_bob_stream", 85).await;
    let carol = server.register_and_sign_in("group_carol_stream", 86).await;
    let body = server
        .create_group(&alice, "Live team", &[&alice, &bob, &carol])
        .await;
    let group_id = body["group_id"].as_str().unwrap();
    let request = format!(
        "GET /groups/{group_id}/stream HTTP/1.1\r\nHost: {}\r\nAuthorization: Bearer {}\r\nConnection: close\r\n\r\n",
        server.addr, bob.token
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
async fn group_add_member_broadcasts_epoch_event_to_members() {
    let server = TestServer::start().await;
    let alice = server
        .register_and_sign_in("group_alice_epoch_event", 87)
        .await;
    let bob = server
        .register_and_sign_in("group_bob_epoch_event", 88)
        .await;
    let carol = server
        .register_and_sign_in("group_carol_epoch_event", 89)
        .await;
    let dave = server
        .register_and_sign_in("group_dave_epoch_event", 90)
        .await;
    let body = server
        .create_group(&alice, "Epoch event team", &[&alice, &bob, &carol])
        .await;
    let group_id = body["group_id"].as_str().unwrap();
    let request = format!(
        "GET /groups/{group_id}/stream HTTP/1.1\r\nHost: {}\r\nAuthorization: Bearer {}\r\nConnection: keep-alive\r\n\r\n",
        server.addr, bob.token
    );
    let mut stream = open_stream_and_read_headers(server.addr, request).await;

    let add = server
        .post_json_bearer(
            &format!("/groups/{group_id}/members"),
            &alice.token,
            json!({
                "username": dave.username,
                "epoch": 1,
                "keys": [
                    {"member_id": alice.user_id, "wrapped_key": wrapped_key_for(&alice.username, 1)},
                    {"member_id": bob.user_id, "wrapped_key": wrapped_key_for(&bob.username, 1)},
                    {"member_id": carol.user_id, "wrapped_key": wrapped_key_for(&carol.username, 1)},
                    {"member_id": dave.user_id, "wrapped_key": wrapped_key_for(&dave.username, 1)}
                ]
            }),
        )
        .await;
    assert_eq!(add.status, 201, "{}", add.body);

    let event = read_stream_until(&mut stream, "\"epoch\":1").await;

    assert!(event.contains("event: epoch"), "{event}");
    assert!(
        event.contains(&format!("\"group_id\":\"{group_id}\"")),
        "{event}"
    );
    assert!(event.contains("\"epoch\":1"), "{event}");
}

#[tokio::test]
async fn group_message_post_stores_exactly_the_ciphertext_blob() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("group_alice_send", 58).await;
    let bob = server.register_and_sign_in("group_bob_send", 59).await;
    let carol = server.register_and_sign_in("group_carol_send", 60).await;
    let body = server
        .create_group(&alice, "Ciphertext only", &[&alice, &bob, &carol])
        .await;
    let group_id = body["group_id"].as_str().unwrap();
    let ciphertext = "AgAAAAAHb3BhcXVlLWdyb3VwLWNpcGhlcnRleHQ=";

    let response = server
        .post_json_bearer(
            &format!("/groups/{group_id}/messages"),
            &bob.token,
            json!({"epoch": 0, "ciphertext": ciphertext}),
        )
        .await;
    assert_eq!(response.status, 201, "{}", response.body);
    let body: serde_json::Value = serde_json::from_str(&response.body).unwrap();
    let message_id = body["message_id"].as_str().unwrap();
    assert_eq!(body["epoch"], 0);
    assert!(body["created_at"].as_str().unwrap().ends_with('Z'));

    let row = sqlx::query(
        "SELECT group_id, sender_id, epoch, ciphertext, created_at FROM group_messages WHERE id = ?",
    )
    .bind(message_id)
    .fetch_one(&server.pool)
    .await
    .unwrap();
    assert_eq!(row.get::<String, _>("group_id"), group_id);
    assert_eq!(row.get::<String, _>("sender_id"), bob.user_id);
    assert_eq!(row.get::<i64, _>("epoch"), 0);
    assert_eq!(row.get::<String, _>("ciphertext"), ciphertext);
}

#[tokio::test]
async fn group_message_history_returns_only_ciphertext_for_members() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("group_alice_history", 64).await;
    let bob = server.register_and_sign_in("group_bob_history", 65).await;
    let carol = server.register_and_sign_in("group_carol_history", 66).await;
    let body = server
        .create_group(&alice, "History team", &[&alice, &bob, &carol])
        .await;
    let group_id = body["group_id"].as_str().unwrap();

    let send = server
        .post_json_bearer(
            &format!("/groups/{group_id}/messages"),
            &alice.token,
            json!({"epoch": 0, "ciphertext": "AgAAAABoaXN0b3J5LWNpcGhlcnRleHQ="}),
        )
        .await;
    assert_eq!(send.status, 201);

    let history = server
        .get_bearer(&format!("/groups/{group_id}/messages"), &carol.token)
        .await;
    assert_eq!(history.status, 200);
    let body: serde_json::Value = serde_json::from_str(&history.body).unwrap();
    let messages = body["messages"].as_array().unwrap();
    assert_eq!(messages.len(), 1);
    let keys = messages[0]
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
            "epoch",
            "group_id",
            "id",
            "sender_id"
        ]
    );
    assert_eq!(
        messages[0]["ciphertext"],
        "AgAAAABoaXN0b3J5LWNpcGhlcnRleHQ="
    );
}

#[tokio::test]
async fn group_message_history_returns_same_second_messages_in_send_order() {
    let server = TestServer::start().await;
    let alice = server
        .register_and_sign_in("group_alice_history_order", 67)
        .await;
    let bob = server
        .register_and_sign_in("group_bob_history_order", 68)
        .await;
    let carol = server
        .register_and_sign_in("group_carol_history_order", 69)
        .await;
    let body = server
        .create_group(&alice, "Ordered History", &[&alice, &bob, &carol])
        .await;
    let group_id = body["group_id"].as_str().unwrap();
    let created_at = "2026-05-01T00:00:00Z";
    let inserted_ids = [
        "ffffffff-ffff-ffff-ffff-fffffffffff2",
        "00000000-0000-0000-0000-000000000002",
        "88888888-8888-8888-8888-888888888882",
    ];

    for (index, id) in inserted_ids.iter().enumerate() {
        server
            .insert_group_message(
                id,
                group_id,
                &bob.user_id,
                0,
                &format!("group-ciphertext-{index}"),
                created_at,
            )
            .await;
    }

    let history = server
        .get_bearer(&format!("/groups/{group_id}/messages"), &carol.token)
        .await;
    assert_eq!(history.status, 200);
    let body: serde_json::Value = serde_json::from_str(&history.body).unwrap();
    let returned_ids = body["messages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|message| message["id"].as_str().unwrap())
        .collect::<Vec<_>>();

    assert_eq!(returned_ids, inserted_ids);
}

#[tokio::test]
async fn group_add_member_bumps_epoch_and_blocks_prior_epoch_keys() {
    let server = TestServer::start().await;
    let alice = server.register_and_sign_in("group_alice_add", 67).await;
    let bob = server.register_and_sign_in("group_bob_add", 68).await;
    let carol = server.register_and_sign_in("group_carol_add", 69).await;
    let dave = server.register_and_sign_in("group_dave_add", 70).await;
    let erin = server.register_and_sign_in("group_erin_add", 71).await;
    let body = server
        .create_group(&alice, "Epoch team", &[&alice, &bob, &carol])
        .await;
    let group_id = body["group_id"].as_str().unwrap();

    let add = server
        .post_json_bearer(
            &format!("/groups/{group_id}/members"),
            &alice.token,
            json!({
                "username": dave.username,
                "epoch": 1,
                "keys": [
                    {"member_id": alice.user_id, "wrapped_key": wrapped_key_for(&alice.username, 1)},
                    {"member_id": bob.user_id, "wrapped_key": wrapped_key_for(&bob.username, 1)},
                    {"member_id": carol.user_id, "wrapped_key": wrapped_key_for(&carol.username, 1)},
                    {"member_id": dave.user_id, "wrapped_key": wrapped_key_for(&dave.username, 1)}
                ]
            }),
        )
        .await;
    assert_eq!(add.status, 201, "{}", add.body);
    let add_body: serde_json::Value = serde_json::from_str(&add.body).unwrap();
    assert_eq!(add_body["epoch"], 1);
    assert_eq!(add_body["member"]["user_id"], dave.user_id);

    let group_row = sqlx::query("SELECT current_epoch FROM groups WHERE id = ?")
        .bind(group_id)
        .fetch_one(&server.pool)
        .await
        .unwrap();
    assert_eq!(group_row.get::<i64, _>("current_epoch"), 1);
    let joined_epoch =
        sqlx::query("SELECT joined_epoch FROM group_members WHERE group_id = ? AND user_id = ?")
            .bind(group_id)
            .bind(&dave.user_id)
            .fetch_one(&server.pool)
            .await
            .unwrap()
            .get::<i64, _>("joined_epoch");
    assert_eq!(joined_epoch, 1);

    let backfill = server
        .post_json_bearer(
            &format!("/groups/{group_id}/members"),
            &alice.token,
            json!({
                "username": erin.username,
                "epoch": 0,
                "keys": [
                    {"member_id": erin.user_id, "wrapped_key": wrapped_key_for(&erin.username, 0)},
                    {"member_id": dave.user_id, "wrapped_key": wrapped_key_for(&dave.username, 0)}
                ]
            }),
        )
        .await;
    assert_eq!(backfill.status, 400);

    let keys = server
        .get_bearer(&format!("/groups/{group_id}/keys"), &dave.token)
        .await;
    assert_eq!(keys.status, 200);
    let keys_body: serde_json::Value = serde_json::from_str(&keys.body).unwrap();
    let epochs = keys_body
        .as_array()
        .unwrap()
        .iter()
        .map(|record| record["epoch"].as_i64().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(epochs, vec![1]);
}

#[tokio::test]
async fn group_records_store_only_metadata_public_material_and_wrapped_key_envelopes() {
    let server = TestServer::start().await;
    let alice = server
        .register_and_sign_in("group_alice_record_shape", 111)
        .await;
    let bob = server
        .register_and_sign_in("group_bob_record_shape", 112)
        .await;
    let carol = server
        .register_and_sign_in("group_carol_record_shape", 113)
        .await;
    let body = server
        .create_group(&alice, "Record shape", &[&alice, &bob, &carol])
        .await;
    let group_id = body["group_id"].as_str().unwrap();
    let ciphertext = "AgAAAABjaXBoZXJ0ZXh0LW9ubHktc2VudGluZWw=";
    let send = server
        .post_json_bearer(
            &format!("/groups/{group_id}/messages"),
            &bob.token,
            json!({"epoch": 0, "ciphertext": ciphertext}),
        )
        .await;
    assert_eq!(send.status, 201, "{}", send.body);

    let forbidden = [
        "plaintext",
        "body",
        "text",
        "content",
        "message",
        "cleartext",
        "private",
        "private_key",
        "identity_private_key",
        "x25519_private_key",
        "group_key",
        "secret",
    ];
    let expected_columns = [
        (
            "groups",
            vec!["id", "name", "creator_id", "current_epoch", "created_at"],
        ),
        (
            "group_members",
            vec!["group_id", "user_id", "joined_epoch", "added_at"],
        ),
        (
            "group_keys",
            vec![
                "group_id",
                "epoch",
                "member_id",
                "wrapped_key",
                "created_at",
            ],
        ),
        (
            "group_messages",
            vec![
                "id",
                "group_id",
                "sender_id",
                "epoch",
                "ciphertext",
                "created_at",
            ],
        ),
    ];

    for (table, expected) in expected_columns {
        let columns = sqlx::query(&format!("PRAGMA table_info({table})"))
            .fetch_all(&server.pool)
            .await
            .unwrap()
            .into_iter()
            .map(|row| row.get::<String, _>("name"))
            .collect::<Vec<_>>();

        assert!(!columns.is_empty(), "{table}");
        assert_eq!(columns, expected, "{table}");
        for column in columns {
            assert!(
                forbidden.iter().all(|forbidden| column != *forbidden),
                "{table}.{column}"
            );
        }
    }

    let group_columns = sqlx::query(
        "SELECT id, name, creator_id, current_epoch, created_at FROM groups WHERE id = ?",
    )
    .bind(group_id)
    .fetch_one(&server.pool)
    .await
    .unwrap();
    assert_eq!(group_columns.get::<String, _>("name"), "Record shape");
    assert_eq!(group_columns.get::<String, _>("creator_id"), alice.user_id);
    assert_eq!(group_columns.get::<i64, _>("current_epoch"), 0);

    let member_ids =
        sqlx::query("SELECT user_id FROM group_members WHERE group_id = ? ORDER BY user_id")
            .bind(group_id)
            .fetch_all(&server.pool)
            .await
            .unwrap()
            .into_iter()
            .map(|row| row.get::<String, _>("user_id"))
            .collect::<Vec<_>>();
    let mut expected_member_ids = vec![alice.user_id.clone(), bob.user_id.clone(), carol.user_id];
    expected_member_ids.sort();
    assert_eq!(member_ids, expected_member_ids);

    let wrapped_keys = sqlx::query(
        "SELECT member_id, wrapped_key FROM group_keys WHERE group_id = ? AND epoch = 0",
    )
    .bind(group_id)
    .fetch_all(&server.pool)
    .await
    .unwrap();
    assert_eq!(wrapped_keys.len(), 3);
    for row in wrapped_keys {
        let member_id = row.get::<String, _>("member_id");
        let wrapped_key = row.get::<String, _>("wrapped_key");
        assert!(expected_member_ids.contains(&member_id));
        assert!(wrapped_key.starts_with("d3JhcHBlZC1rZXk6"));
    }

    let message = sqlx::query(
        "SELECT group_id, sender_id, epoch, ciphertext FROM group_messages WHERE group_id = ?",
    )
    .bind(group_id)
    .fetch_one(&server.pool)
    .await
    .unwrap();
    assert_eq!(message.get::<String, _>("sender_id"), bob.user_id);
    assert_eq!(message.get::<i64, _>("epoch"), 0);
    assert_eq!(message.get::<String, _>("ciphertext"), ciphertext);
}
