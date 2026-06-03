CREATE TABLE users (
    id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    identity_public_key TEXT NOT NULL,
    created_at TEXT NOT NULL
);

