CREATE TABLE groups (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    creator_id TEXT NOT NULL,
    current_epoch INTEGER NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE group_members (
    group_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    joined_epoch INTEGER NOT NULL,
    added_at TEXT NOT NULL,
    PRIMARY KEY (group_id, user_id)
);

CREATE TABLE group_keys (
    group_id TEXT NOT NULL,
    epoch INTEGER NOT NULL,
    member_id TEXT NOT NULL,
    wrapped_key TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (group_id, epoch, member_id)
);

CREATE TABLE group_messages (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL,
    sender_id TEXT NOT NULL,
    epoch INTEGER NOT NULL,
    ciphertext TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE INDEX idx_group_messages_group ON group_messages (group_id, created_at, id);
