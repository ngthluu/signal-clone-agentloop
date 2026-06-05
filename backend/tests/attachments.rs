use std::net::SocketAddr;

use base64::{engine::general_purpose::STANDARD, Engine as _};
use ed25519_dalek::{Signer, SigningKey};
use serde_json::json;
use sqlx::Row;
use test_chat_backend::{app, db};
use tokio::{io::AsyncReadExt, io::AsyncWriteExt, net::TcpStream};

const MAX_PLAINTEXT_ATTACHMENT_BYTES: usize = 10 * 1024 * 1024;

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

        let challenge = self
            .post_json("/auth/challenge", json!({ "username": username }))
            .await;
        assert_eq!(challenge.status, 201);
        let challenge_body: serde_json::Value = serde_json::from_slice(&challenge.body).unwrap();
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
        let verify_body: serde_json::Value = serde_json::from_slice(&verify.body).unwrap();

        SignedInUser {
            token: verify_body["token"].as_str().unwrap().to_string(),
        }
    }

    async fn post_json(&self, path: &str, body: serde_json::Value) -> HttpResponse {
        self.request_with_body(
            "POST",
            path,
            None,
            "application/json",
            body.to_string().into(),
        )
        .await
    }

    async fn upload_attachment(&self, token: Option<&str>, blob: Vec<u8>) -> HttpResponse {
        self.request_with_body(
            "POST",
            "/attachments",
            token,
            "application/octet-stream",
            blob,
        )
        .await
    }

    async fn get_attachment(&self, token: Option<&str>, attachment_id: &str) -> HttpResponse {
        let auth = token
            .map(|token| format!("Authorization: Bearer {token}\r\n"))
            .unwrap_or_default();
        let request = format!(
            "GET /attachments/{attachment_id} HTTP/1.1\r\nHost: {}\r\n{}Connection: close\r\n\r\n",
            self.addr, auth
        )
        .into_bytes();

        send_request(self.addr, request).await
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
}

struct SignedInUser {
    token: String,
}

struct HttpResponse {
    status: u16,
    headers: String,
    body: Vec<u8>,
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
        body: response[header_end..].to_vec(),
    }
}

#[tokio::test]
async fn attachment_upload_then_download_round_trips_exact_bytes() {
    let server = TestServer::start().await;
    let alice = server
        .register_and_sign_in("alice_attachment_roundtrip", 91)
        .await;
    let filename_sentinel = b"DM_ATTACHMENT_FILENAME_SENTINEL_backend.bin";
    let content_sentinel = b"DM_ATTACHMENT_CONTENT_SENTINEL_backend_payload";
    let encrypted_blob = (0..4096)
        .map(|index| ((index * 31 + 7) % 256) as u8)
        .collect::<Vec<_>>();
    assert!(!contains_bytes(&encrypted_blob, filename_sentinel));
    assert!(!contains_bytes(&encrypted_blob, content_sentinel));

    let upload = server
        .upload_attachment(Some(&alice.token), encrypted_blob.clone())
        .await;
    assert_eq!(upload.status, 201);
    let upload_body: serde_json::Value = serde_json::from_slice(&upload.body).unwrap();
    let attachment_id = upload_body["attachment_id"].as_str().unwrap();
    assert!(!attachment_id.is_empty());

    let row =
        sqlx::query("SELECT uploader_id, ciphertext, byte_size FROM attachments WHERE id = ?")
            .bind(attachment_id)
            .fetch_one(&server.pool)
            .await
            .unwrap();
    assert!(!row.get::<String, _>("uploader_id").is_empty());
    let stored_ciphertext = row.get::<Vec<u8>, _>("ciphertext");
    assert_eq!(stored_ciphertext, encrypted_blob);
    assert!(!contains_bytes(&stored_ciphertext, filename_sentinel));
    assert!(!contains_bytes(&stored_ciphertext, content_sentinel));
    assert_eq!(row.get::<i64, _>("byte_size"), encrypted_blob.len() as i64);

    let download = server
        .get_attachment(Some(&alice.token), attachment_id)
        .await;
    assert_eq!(download.status, 200);
    assert!(
        download
            .headers
            .to_ascii_lowercase()
            .contains("content-type: application/octet-stream"),
        "{}",
        download.headers
    );
    assert_eq!(download.body, encrypted_blob);
    assert!(!contains_bytes(&download.body, filename_sentinel));
    assert!(!contains_bytes(&download.body, content_sentinel));
}

#[tokio::test]
async fn attachment_upload_rejects_oversize_payload_with_413() {
    let server = TestServer::start().await;
    let alice = server
        .register_and_sign_in("alice_attachment_oversize", 92)
        .await;
    let too_large = vec![0xA5; MAX_PLAINTEXT_ATTACHMENT_BYTES + 1];

    let response = server
        .upload_attachment(Some(&alice.token), too_large)
        .await;

    assert_eq!(response.status, 413);
    let stored_count = sqlx::query("SELECT COUNT(*) AS count FROM attachments")
        .fetch_one(&server.pool)
        .await
        .unwrap()
        .get::<i64, _>("count");
    assert_eq!(stored_count, 0);
}

#[tokio::test]
async fn attachment_upload_accepts_exact_10mb_ciphertext_payload() {
    let server = TestServer::start().await;
    let alice = server
        .register_and_sign_in("alice_attachment_exact_limit", 94)
        .await;
    let at_limit = (0..MAX_PLAINTEXT_ATTACHMENT_BYTES)
        .map(|index| ((index * 17 + 0x5B) % 256) as u8)
        .collect::<Vec<_>>();

    let upload = server
        .upload_attachment(Some(&alice.token), at_limit.clone())
        .await;

    assert_eq!(upload.status, 201);
    let upload_body: serde_json::Value = serde_json::from_slice(&upload.body).unwrap();
    let attachment_id = upload_body["attachment_id"].as_str().unwrap();
    let row = sqlx::query("SELECT ciphertext, byte_size FROM attachments WHERE id = ?")
        .bind(attachment_id)
        .fetch_one(&server.pool)
        .await
        .unwrap();
    assert_eq!(row.get::<i64, _>("byte_size"), at_limit.len() as i64);
    assert_eq!(row.get::<Vec<u8>, _>("ciphertext"), at_limit);
}

#[tokio::test]
async fn attachment_requires_bearer_token() {
    let server = TestServer::start().await;

    let post_without_token = server.upload_attachment(None, vec![1, 2, 3]).await;
    let post_bad_token = server
        .upload_attachment(Some("not-a-real-token"), vec![1, 2, 3])
        .await;
    let get_without_token = server.get_attachment(None, "missing").await;
    let get_bad_token = server
        .get_attachment(Some("not-a-real-token"), "missing")
        .await;

    assert_eq!(post_without_token.status, 401);
    assert_eq!(post_bad_token.status, 401);
    assert_eq!(get_without_token.status, 401);
    assert_eq!(get_bad_token.status, 401);
}

#[tokio::test]
async fn attachment_download_unknown_id_is_404() {
    let server = TestServer::start().await;
    let alice = server
        .register_and_sign_in("alice_attachment_unknown", 93)
        .await;

    let response = server
        .get_attachment(Some(&alice.token), "00000000-0000-4000-8000-000000000000")
        .await;

    assert_eq!(response.status, 404);
}

#[tokio::test]
async fn attachments_table_stores_no_plaintext_columns() {
    let server = TestServer::start().await;
    let rows = sqlx::query("PRAGMA table_info(attachments)")
        .fetch_all(&server.pool)
        .await
        .unwrap();
    let column_names = rows
        .iter()
        .map(|row| row.get::<String, _>("name"))
        .collect::<Vec<_>>();

    assert_eq!(
        column_names,
        vec!["id", "uploader_id", "ciphertext", "byte_size", "created_at"]
    );

    let forbidden = [
        "filename",
        "file_name",
        "name",
        "mime",
        "mime_type",
        "media_type",
        "descriptor",
        "metadata",
        "plaintext",
        "body",
        "text",
        "content",
        "message",
        "cleartext",
        "private",
        "secret",
        "password",
        "passphrase",
        "privkey",
        "private_key",
        "secret_key",
        "seed",
        "mnemonic",
    ];
    for column in column_names {
        let normalized = column.to_ascii_lowercase();
        if normalized != "ciphertext" {
            assert!(
                forbidden
                    .iter()
                    .all(|forbidden| !normalized.contains(forbidden)),
                "attachments column must not expose plaintext, filename, MIME, descriptor, or content metadata: {column}"
            );
        }
        assert!(
            !["private", "secret", "password", "privkey", "mnemonic"]
                .iter()
                .any(|forbidden| normalized.contains(forbidden)),
            "attachments column must not expose key material semantics: {column}"
        );
    }
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    haystack
        .windows(needle.len())
        .any(|window| window == needle)
}
