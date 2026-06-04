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
        self.request_with_body(
            "POST",
            path,
            None,
            "application/json",
            body.to_string().into_bytes(),
        )
        .await
    }

    async fn post_raw_json_bearer(&self, path: &str, token: &str, body: &str) -> HttpResponse {
        self.request_with_body(
            "POST",
            path,
            Some(token),
            "application/json",
            body.as_bytes().to_vec(),
        )
        .await
    }

    async fn put_json_bearer(
        &self,
        path: &str,
        token: &str,
        body: serde_json::Value,
    ) -> HttpResponse {
        self.request_with_body(
            "PUT",
            path,
            Some(token),
            "application/json",
            body.to_string().into_bytes(),
        )
        .await
    }

    async fn get(&self, path: &str) -> HttpResponse {
        let request = format!(
            "GET {path} HTTP/1.1\r\nHost: {}\r\nConnection: close\r\n\r\n",
            self.addr
        )
        .into_bytes();

        send_request(self.addr, request).await
    }

    async fn get_bearer(&self, path: &str, token: &str) -> HttpResponse {
        let request = format!(
            "GET {path} HTTP/1.1\r\nHost: {}\r\nAuthorization: Bearer {}\r\nConnection: close\r\n\r\n",
            self.addr, token
        )
        .into_bytes();

        send_request(self.addr, request).await
    }

    async fn upload_attachment(&self, token: &str, body: Vec<u8>) -> HttpResponse {
        self.request_with_body(
            "POST",
            "/attachments",
            Some(token),
            "application/octet-stream",
            body,
        )
        .await
    }

    async fn request_with_body(
        &self,
        method: &str,
        path: &str,
        token: Option<&str>,
        content_type: &str,
        body: Vec<u8>,
    ) -> HttpResponse {
        let auth = token
            .map(|token| format!("Authorization: Bearer {token}\r\n"))
            .unwrap_or_default();
        let head = format!(
            "{method} {path} HTTP/1.1\r\nHost: {}\r\nContent-Type: {content_type}\r\n{}Content-Length: {}\r\nConnection: close\r\n\r\n",
            self.addr,
            auth,
            body.len(),
        );
        let mut request = head.into_bytes();
        request.extend_from_slice(&body);

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
    headers: String,
    body: String,
    body_bytes: Vec<u8>,
}

async fn send_request(addr: SocketAddr, request: Vec<u8>) -> HttpResponse {
    let mut stream = TcpStream::connect(addr).await.unwrap();
    stream.write_all(&request).await.unwrap();

    let mut response = Vec::new();
    stream.read_to_end(&mut response).await.unwrap();
    let header_end = response
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .map(|position| position + 4)
        .unwrap();
    let headers = String::from_utf8(response[..header_end].to_vec()).unwrap();
    let body_bytes = response[header_end..].to_vec();
    let body = String::from_utf8_lossy(&body_bytes).to_string();
    let status = headers
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
        headers,
        body,
        body_bytes,
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
    let (pad, encrypted) = encrypt_without_plaintext_substring(sentinel_bytes);
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

    let attach_sentinel = format!("ZK_ATTACH_SENTINEL_{}", &run_hex[..16]);
    let attach_sentinel_bytes = attach_sentinel.as_bytes();
    let (attach_pad, attach_ciphertext) =
        encrypt_without_plaintext_substring(attach_sentinel_bytes);
    assert!(!contains_bytes(
        &attach_ciphertext,
        attach_sentinel.as_bytes()
    ));

    let upload = server
        .upload_attachment(&sender.token, attach_ciphertext.clone())
        .await;
    assert_eq!(upload.status, 201, "{}", upload.body);
    let upload_body: serde_json::Value = serde_json::from_str(&upload.body).unwrap();
    let attachment_id = upload_body["attachment_id"].as_str().unwrap().to_string();
    assert!(!attachment_id.is_empty());

    let attachment_columns = sqlx::query("PRAGMA table_info(attachments)")
        .fetch_all(&server.pool)
        .await
        .unwrap()
        .into_iter()
        .map(|row| row.get::<String, _>("name"))
        .collect::<Vec<_>>();
    assert_eq!(
        attachment_columns,
        vec!["id", "uploader_id", "ciphertext", "byte_size", "created_at"]
    );

    let attachment_row = sqlx::query(
        "SELECT id, uploader_id, ciphertext, byte_size, created_at FROM attachments WHERE id = ?",
    )
    .bind(&attachment_id)
    .fetch_one(&server.pool)
    .await
    .unwrap();
    assert_eq!(attachment_row.get::<String, _>("id"), attachment_id);
    assert_eq!(
        attachment_row.get::<String, _>("uploader_id"),
        sender.user_id
    );
    let stored_attachment_ciphertext = attachment_row.get::<Vec<u8>, _>("ciphertext");
    assert_eq!(stored_attachment_ciphertext, attach_ciphertext);
    assert_eq!(
        attachment_row.get::<i64, _>("byte_size"),
        stored_attachment_ciphertext.len() as i64
    );
    assert!(attachment_row.get::<String, _>("created_at").ends_with('Z'));

    let recovered_attachment = stored_attachment_ciphertext
        .iter()
        .zip(&attach_pad)
        .map(|(cipher, key)| cipher ^ key)
        .collect::<Vec<_>>();
    assert_eq!(recovered_attachment, attach_sentinel_bytes);

    sqlx::query("PRAGMA wal_checkpoint(TRUNCATE)")
        .execute(&server.pool)
        .await
        .unwrap();
    let raw_storage = read_db_and_sidecars(&db_path);
    assert!(
        !contains_bytes(&raw_storage, attach_sentinel.as_bytes()),
        "raw SQLite bytes contained plaintext attachment sentinel {attach_sentinel}"
    );
    assert!(
        contains_bytes(&raw_storage, &stored_attachment_ciphertext),
        "raw SQLite bytes did not contain the stored attachment ciphertext"
    );

    let download = server
        .get_bearer(&format!("/attachments/{attachment_id}"), &sender.token)
        .await;
    assert_eq!(download.status, 200, "{}", download.body);
    assert!(
        download
            .headers
            .to_ascii_lowercase()
            .contains("content-type: application/octet-stream"),
        "{}",
        download.headers
    );
    assert_eq!(download.body_bytes, stored_attachment_ciphertext);
    assert!(!contains_bytes(
        &download.body_bytes,
        attach_sentinel.as_bytes()
    ));

    if let Some(artifacts) = &artifacts {
        artifacts.write(
            &db_path_str,
            &sentinel,
            &message_id,
            &wire_body,
            &attach_sentinel,
            &attachment_id,
        );
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
    attach_sentinel_out: Option<PathBuf>,
    attach_id_out: Option<PathBuf>,
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
            attach_sentinel_out: std::env::var_os("ZK_SENTINEL_ATTACH_VALUE_OUT").map(Into::into),
            attach_id_out: std::env::var_os("ZK_SENTINEL_ATTACH_ID_OUT").map(Into::into),
        })
    }

    fn write(
        &self,
        db_path: &str,
        sentinel: &str,
        message_id: &str,
        wire_body: &str,
        attach_sentinel: &str,
        attachment_id: &str,
    ) {
        std::fs::write(&self.db_out, db_path).unwrap();
        std::fs::write(&self.sentinel_out, sentinel).unwrap();
        std::fs::write(&self.message_id_out, message_id).unwrap();
        std::fs::write(&self.wire_out, wire_body).unwrap();
        if let Some(path) = &self.attach_sentinel_out {
            std::fs::write(path, attach_sentinel).unwrap();
        }
        if let Some(path) = &self.attach_id_out {
            std::fs::write(path, attachment_id).unwrap();
        }
    }
}

fn encrypt_without_plaintext_substring(plaintext: &[u8]) -> (Vec<u8>, Vec<u8>) {
    loop {
        let mut pad = vec![0u8; plaintext.len()];
        getrandom::getrandom(&mut pad).unwrap();
        let ciphertext = plaintext
            .iter()
            .zip(&pad)
            .map(|(plain, key)| plain ^ key)
            .collect::<Vec<_>>();

        if !contains_bytes(&ciphertext, plaintext) {
            return (pad, ciphertext);
        }
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
