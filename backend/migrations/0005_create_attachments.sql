CREATE TABLE attachments (
    id TEXT PRIMARY KEY,
    uploader_id TEXT NOT NULL,
    ciphertext BLOB NOT NULL,
    byte_size INTEGER NOT NULL,
    created_at TEXT NOT NULL
);
