CREATE TABLE device_keys (
    user_id TEXT PRIMARY KEY,
    x25519_public_key TEXT NOT NULL,
    key_signature TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    sender_id TEXT NOT NULL,
    recipient_id TEXT NOT NULL,
    ciphertext TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE INDEX idx_messages_pair ON messages (sender_id, recipient_id, created_at, id);
