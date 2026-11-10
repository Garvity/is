use serde::{Deserialize, Serialize};
use sqlx::FromRow;

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Share {
    pub id: String,
    pub user_id: String,
    pub item_id: String,
    pub wrapped_dek: String,
    pub access_type: String,
    pub password_hash: Option<String>,
    pub expires_at: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreateShareRequest {
    pub item_id: String,
    pub expires_at: Option<String>,
    pub access_type: String,
    pub password_hash: Option<String>,
    pub wrapped_dek: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ShareResponse {
    pub id: String,
    pub item_id: String,
    pub access_type: String,
    pub expires_at: Option<String>,
    pub created_at: String,
}