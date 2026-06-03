use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
pub struct RegisterRequest {
    pub username: String,
    pub identity_public_key: String,
}

#[derive(Serialize)]
pub struct RegisterResponse {
    pub user_id: String,
}
