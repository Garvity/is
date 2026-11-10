use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::get,
    Extension, Json, Router,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::{
    error::AppError,
    middleware::auth::AuthenticatedUser,
    models::item::{FileRecord, Folder},
    state::AppState,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", get(list_items).post(create_item))
        .route("/{id}", get(get_item).patch(update_item).delete(delete_item))
}

pub async fn list_items(
    State(state): State<AppState>,
    Extension(user): Extension<AuthenticatedUser>,
) -> Result<Json<serde_json::Value>, AppError> {
    let user_id_str = user.id.to_string();
    let folders = sqlx::query_as!(Folder, "SELECT * FROM folders WHERE user_id = $1", user_id_str)
        .fetch_all(&state.db)
        .await?;

    let files = sqlx::query_as!(FileRecord, "SELECT * FROM files WHERE user_id = $1", user_id_str)
        .fetch_all(&state.db)
        .await?;

    Ok(Json(serde_json::json!({ "folders": folders, "files": files })))
}

#[derive(Deserialize)]
pub struct CreateItemRequest {
    name: String,
    item_type: String, // "folder" or "file"
    parent_id: Option<Uuid>,
}

pub async fn create_item(
    State(state): State<AppState>,
    Extension(user): Extension<AuthenticatedUser>,
    Json(payload): Json<CreateItemRequest>,
) -> Result<(StatusCode, Json<serde_json::Value>), AppError> {
    let user_id_str = user.id.to_string();
    match payload.item_type.as_str() {
        "folder" => {
            let folder_id = uuid::Uuid::new_v4().to_string();
            let parent_id_str = payload.parent_id.map(|u| u.to_string());
            let folder = sqlx::query_as!(
                Folder,
                "INSERT INTO folders (id, user_id, parent_id, name) VALUES ($1, $2, $3, $4) RETURNING *",
                folder_id,
                user_id_str,
                parent_id_str,
                payload.name
            )
            .fetch_one(&state.db)
            .await?;
            Ok((StatusCode::CREATED, Json(serde_json::json!(folder))))
        }
        "file" => {
            let file_id = uuid::Uuid::new_v4().to_string();
            let parent_id_str = payload.parent_id.map(|u| u.to_string());
            let r2_key = uuid::Uuid::new_v4().to_string();
            let file = sqlx::query_as!(
                FileRecord,
                "INSERT INTO files (id, user_id, folder_id, name, mime_type, size, r2_key) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *",
                file_id,
                user_id_str,
                parent_id_str,
                payload.name,
                "application/octet-stream",
                0,
                r2_key
            )
            .fetch_one(&state.db)
            .await?;
            Ok((StatusCode::CREATED, Json(serde_json::json!(file))))
        }
        _ => Err(AppError::BadRequest("Invalid item type".to_string())),
    }
}

pub async fn get_item(
    State(state): State<AppState>,
    Extension(user): Extension<AuthenticatedUser>,
    Path(id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    let user_id_str = user.id.to_string();
    let id_str = id.to_string();
    if let Some(folder) = sqlx::query_as!(Folder, "SELECT * FROM folders WHERE id = $1 AND user_id = $2", id_str, user_id_str)
        .fetch_optional(&state.db)
        .await? {
        return Ok(Json(serde_json::json!(folder)));
    }
    
    if let Some(file) = sqlx::query_as!(FileRecord, "SELECT * FROM files WHERE id = $1 AND user_id = $2", id_str, user_id_str)
        .fetch_optional(&state.db)
        .await? {
        return Ok(Json(serde_json::json!(file)));
    }
    
    Err(AppError::NotFound("Item not found".to_string()))
}

#[derive(Deserialize)]
pub struct UpdateItemRequest {
    name: Option<String>,
    expected_version: Option<String>,
}

pub async fn update_item(
    State(state): State<AppState>,
    Extension(user): Extension<AuthenticatedUser>,
    Path(id): Path<Uuid>,
    Json(payload): Json<UpdateItemRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    let user_id_str = user.id.to_string();
    let id_str = id.to_string();
    if let Some(name) = payload.name {
        // Check expected version if provided for CAS
        if let Some(expected_version) = payload.expected_version {
            // Verify the current version matches expected version
            let current_updated_at: Option<String> = sqlx::query_scalar!(
                "SELECT CAST(COALESCE((SELECT updated_at FROM folders WHERE id = $1 AND user_id = $2), (SELECT updated_at FROM files WHERE id = $1 AND user_id = $2)) AS TEXT)",
                id_str,
                user_id_str
            )
            .fetch_optional(&state.db)
            .await?
            .flatten();

            if let Some(current) = current_updated_at {
                if current != expected_version {
                    return Err(AppError::Conflict("Version conflict - item was modified by another device".to_string()));
                }
            }
        }

        if let Some(folder) = sqlx::query_as!(
            Folder,
            "UPDATE folders SET name = $1, updated_at = datetime('now') WHERE id = $2 AND user_id = $3 RETURNING *",
            name,
            id_str,
            user_id_str
        )
        .fetch_optional(&state.db)
        .await? {
            return Ok(Json(serde_json::json!(folder)));
        }

        if let Some(file) = sqlx::query_as!(
            FileRecord,
            "UPDATE files SET name = $1, updated_at = datetime('now') WHERE id = $2 AND user_id = $3 RETURNING *",
            name,
            id_str,
            user_id_str
        )
        .fetch_optional(&state.db)
        .await? {
            return Ok(Json(serde_json::json!(file)));
        }
    }

    Err(AppError::NotFound("Item not found or no changes".to_string()))
}

pub async fn delete_item(
    State(state): State<AppState>,
    Extension(user): Extension<AuthenticatedUser>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let user_id_str = user.id.to_string();
    let id_str = id.to_string();

    let folder_result = sqlx::query!(
        "DELETE FROM folders WHERE id = $1 AND user_id = $2",
        id_str,
        user_id_str
    )
    .execute(&state.db)
    .await?;

    if folder_result.rows_affected() > 0 {
        return Ok(StatusCode::NO_CONTENT);
    }

    let file_result = sqlx::query!(
        "DELETE FROM files WHERE id = $1 AND user_id = $2",
        id_str,
        user_id_str
    )
    .execute(&state.db)
    .await?;

    if file_result.rows_affected() > 0 {
        return Ok(StatusCode::NO_CONTENT);
    }

    Err(AppError::NotFound("Item not found".to_string()))
}