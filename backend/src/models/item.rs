use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Folder {
    pub id: String,
    pub user_id: String,
    pub parent_id: Option<String>,
    pub name: String,
    pub created_at: String,
    pub updated_at: String,
}

impl Folder {
    pub fn uuid(&self) -> Result<Uuid, uuid::Error> {
        Uuid::parse_str(&self.id)
    }
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct FileRecord {
    pub id: String,
    pub user_id: String,
    pub folder_id: Option<String>,
    pub name: String,
    pub mime_type: String,
    pub size: i64,
    pub r2_key: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

impl FileRecord {
    pub fn uuid(&self) -> Result<Uuid, uuid::Error> {
        Uuid::parse_str(&self.id)
    }
}