use std::{net::SocketAddr, path::PathBuf};

use base64::{engine::general_purpose::STANDARD, Engine as _};
use ed25519_dalek::{Signer, SigningKey};
use serde_json::json;
use sqlx::Row;
use test_chat_backend::{app, db};
use tokio::{io::AsyncReadExt, io::AsyncWriteExt, net::TcpStream};
use uuid::Uuid;

struct TestServer {
    addr: SocketAddr,
    pool: sqlx::SqlitePool,
    task: tokio::task::JoinHandle<()>,
}

impl TestServer {
    async fn start(db_path: &str) -> Self {
        let pool = db::init_pool(db_path).await.unwrap();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let server_pool = pool.clone();

        let task = tokio::spawn(async move {
            axum::serve(listener, app(server_pool)).await.unwrap();
        });

        Self { addr, pool, task }
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
        assert_eq!(register.status, 201, "{}", register.body);
        let user_id = serde_json::from_str::<serde_json::Value>(&register.body).unwrap()["user_id"]
            .as_str()
            .unwrap()
            .to_string();

        let challenge = self
            .post_json("/auth/challenge", json!({ "username": username }))
            .await;
        assert_eq!(challenge.status, 201, "{}", challenge.body);
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
        assert_eq!(verify.status, 200, "{}", verify.body);
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
        assert!(
            response.status == 200 || response.status == 201,
            "{}",
            response.body
        );

        PublishedPrekey {
            x25519_public_key,
            key_signature,
        }
    }

    async fn post_json(&self, path: &str, body: serde_json::Value) -> HttpResponse {
        self.request_with_body("POST", path, None, body.to_string())
            .await
    }

    async fn post_raw_json_bearer(&self, path: &str, token: &str, body: &str) -> HttpResponse {
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

    async fn shutdown(self) {
        self.task.abort();
        self.pool.close().await;
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
async fn zk_sentinel_roundtrip_stores_only_ciphertext_in_raw_db() {
    let run_id = Uuid::new_v4();
    let run_hex = run_id.simple().to_string();
    let db_path = std::env::temp_dir().join(format!("zk-sentinel-{run_id}.sqlite"));
    let db_path_str = db_path.to_str().unwrap().to_string();
    let artifacts = ArtifactPaths::from_env();
    let server = TestServer::start(&db_path_str).await;
    let sender_username = format!("zk_s_{}", &run_hex[..12]);
    let recipient_username = format!("zk_r_{}", &run_hex[12..24]);

    let sender = server.register_and_sign_in(&sender_username, 21).await;
    let recipient = server.register_and_sign_in(&recipient_username, 22).await;
    let prekey = server.publish_prekey(&sender, 23).await;

    let sentinel = format!("ZK_SENTINEL_{}", &run_hex[24..32]);
    let sentinel_bytes = sentinel.as_bytes();
    let mut pad = vec![0u8; sentinel_bytes.len()];
    getrandom::getrandom(&mut pad).unwrap();
    let encrypted = sentinel_bytes
        .iter()
        .zip(&pad)
        .map(|(plain, key)| plain ^ key)
        .collect::<Vec<_>>();
    let wire_ciphertext = STANDARD.encode(encrypted);
    assert!(!wire_ciphertext.contains(&sentinel));

    let wire_body = json!({
        "recipient_username": recipient.username,
        "ciphertext": wire_ciphertext
    })
    .to_string();
    let send = server
        .post_raw_json_bearer("/messages", &sender.token, &wire_body)
        .await;
    assert_eq!(send.status, 201, "{}", send.body);
    let send_body: serde_json::Value = serde_json::from_str(&send.body).unwrap();
    let message_id = send_body["message_id"].as_str().unwrap().to_string();
    assert!(!message_id.is_empty());

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

    let row = sqlx::query(
        "SELECT id, sender_id, recipient_id, ciphertext, created_at FROM messages WHERE id = ?",
    )
    .bind(&message_id)
    .fetch_one(&server.pool)
    .await
    .unwrap();
    assert_eq!(row.get::<String, _>("id"), message_id);
    assert_eq!(row.get::<String, _>("sender_id"), sender.user_id);
    assert_eq!(row.get::<String, _>("recipient_id"), recipient.user_id);
    let stored_ciphertext = row.get::<String, _>("ciphertext");
    assert_eq!(stored_ciphertext, wire_ciphertext);
    assert!(row.get::<String, _>("created_at").ends_with('Z'));

    let decoded = STANDARD.decode(&stored_ciphertext).unwrap();
    let recovered = decoded
        .iter()
        .zip(&pad)
        .map(|(cipher, key)| cipher ^ key)
        .collect::<Vec<_>>();
    assert_eq!(recovered, sentinel_bytes);

    sqlx::query("PRAGMA wal_checkpoint(TRUNCATE)")
        .execute(&server.pool)
        .await
        .unwrap();
    let raw_storage = read_db_and_sidecars(&db_path);
    assert!(
        !contains_bytes(&raw_storage, sentinel.as_bytes()),
        "raw SQLite bytes contained plaintext sentinel {sentinel}"
    );
    assert!(
        contains_bytes(&raw_storage, stored_ciphertext.as_bytes()),
        "raw SQLite bytes did not contain the stored ciphertext"
    );

    let history = server
        .get_bearer(
            &format!("/messages?with={}", sender.username),
            &recipient.token,
        )
        .await;
    assert_eq!(history.status, 200, "{}", history.body);
    assert!(!history.body.contains(&sentinel));
    assert!(history.body.contains(&stored_ciphertext));
    let history_body: serde_json::Value = serde_json::from_str(&history.body).unwrap();
    let messages = history_body["messages"].as_array().unwrap();
    assert_eq!(messages.len(), 1);
    let message = messages[0].as_object().unwrap();
    assert_eq!(
        message.keys().cloned().collect::<Vec<_>>(),
        vec![
            "ciphertext",
            "created_at",
            "id",
            "recipient_id",
            "sender_id"
        ]
    );
    for forbidden in ["plaintext", "body", "text"] {
        assert!(message.get(forbidden).is_none(), "{forbidden}");
        assert!(history_body.get(forbidden).is_none(), "{forbidden}");
    }

    let keys = server.get(&format!("/keys/{}", sender.username)).await;
    assert_eq!(keys.status, 200, "{}", keys.body);
    let keys_body: serde_json::Value = serde_json::from_str(&keys.body).unwrap();
    let keys_object = keys_body.as_object().unwrap();
    assert_eq!(
        keys_object.keys().cloned().collect::<Vec<_>>(),
        vec![
            "identity_public_key",
            "key_signature",
            "user_id",
            "username",
            "x25519_public_key"
        ]
    );
    assert_eq!(keys_body["user_id"], sender.user_id);
    assert_eq!(keys_body["username"], sender.username);
    assert_eq!(keys_body["x25519_public_key"], prekey.x25519_public_key);
    assert_eq!(keys_body["key_signature"], prekey.key_signature);
    for forbidden in ["private", "secret"] {
        assert!(keys_object.get(forbidden).is_none(), "{forbidden}");
    }

    let stored_public_key =
        sqlx::query("SELECT x25519_public_key FROM device_keys WHERE user_id = ?")
            .bind(&sender.user_id)
            .fetch_one(&server.pool)
            .await
            .unwrap()
            .get::<String, _>("x25519_public_key");
    assert_eq!(stored_public_key, prekey.x25519_public_key);

    if let Some(artifacts) = &artifacts {
        artifacts.write(&db_path_str, &sentinel, &message_id, &wire_body);
    }

    server.shutdown().await;

    if artifacts.is_none() {
        remove_db_and_sidecars(&db_path);
    }
}

struct ArtifactPaths {
    db_out: PathBuf,
    sentinel_out: PathBuf,
    message_id_out: PathBuf,
    wire_out: PathBuf,
}

impl ArtifactPaths {
    fn from_env() -> Option<Self> {
        if std::env::var("ZK_SENTINEL_KEEP_DB").ok().as_deref() != Some("1") {
            return None;
        }

        Some(Self {
            db_out: std::env::var_os("ZK_SENTINEL_DB_OUT")?.into(),
            sentinel_out: std::env::var_os("ZK_SENTINEL_VALUE_OUT")?.into(),
            message_id_out: std::env::var_os("ZK_SENTINEL_MSGID_OUT")?.into(),
            wire_out: std::env::var_os("ZK_SENTINEL_WIRE_OUT")?.into(),
        })
    }

    fn write(&self, db_path: &str, sentinel: &str, message_id: &str, wire_body: &str) {
        std::fs::write(&self.db_out, db_path).unwrap();
        std::fs::write(&self.sentinel_out, sentinel).unwrap();
        std::fs::write(&self.message_id_out, message_id).unwrap();
        std::fs::write(&self.wire_out, wire_body).unwrap();
    }
}

fn read_db_and_sidecars(db_path: &std::path::Path) -> Vec<u8> {
    let mut bytes = Vec::new();
    for path in [
        db_path.to_path_buf(),
        PathBuf::from(format!("{}-wal", db_path.display())),
        PathBuf::from(format!("{}-shm", db_path.display())),
    ] {
        if let Ok(mut file_bytes) = std::fs::read(path) {
            bytes.append(&mut file_bytes);
        }
    }
    bytes
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty()
        && haystack
            .windows(needle.len())
            .any(|window| window == needle)
}

fn remove_db_and_sidecars(db_path: &std::path::Path) {
    for path in [
        db_path.to_path_buf(),
        PathBuf::from(format!("{}-wal", db_path.display())),
        PathBuf::from(format!("{}-shm", db_path.display())),
    ] {
        let _ = std::fs::remove_file(path);
    }
}
