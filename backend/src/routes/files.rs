use axum::{
    body::Body,
    extract::{Extension, Path, State},
    http::{header, HeaderMap, StatusCode},
    response::Response,
    routing::{delete, get, put},
    Router,
};

use crate::{
    error::AppError,
    middleware::auth::AuthenticatedUser,
    state::AppState,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/{r2_key}/download", get(download_file))
        .route("/{r2_key}/upload", put(upload_file))
        .route("/{r2_key}", delete(delete_file))
}

pub async fn download_file(
    State(state): State<AppState>,
    Extension(user): Extension<AuthenticatedUser>,
    Path(r2_key): Path<String>,
) -> Result<Response, AppError> {
    // Find the file by r2_key
    let user_id_str = user.id.to_string();
    let file = sqlx::query!(
        "SELECT id, name, mime_type, size, r2_key FROM files WHERE r2_key = $1 AND user_id = $2",
        r2_key,
        user_id_str
    )
    .fetch_optional(&state.db)
    .await?;

    let Some(file) = file else {
        return Err(AppError::NotFound("File not found".to_string()));
    };

    // In a real implementation, this would download from R2/S3
    // For now, we'll return a placeholder response
    // TODO: Implement actual R2/S3 download
    let body = Body::from(format!("File content for: {} (r2_key: {})", file.name, r2_key));

    let mut headers = HeaderMap::new();
    headers.insert(header::CONTENT_TYPE, file.mime_type.parse().unwrap_or("application/octet-stream".parse().unwrap()));
    headers.insert(header::CONTENT_DISPOSITION, format!("attachment; filename=\"{}\"", file.name).parse().unwrap());
    headers.insert(header::CONTENT_LENGTH, file.size.to_string().parse().unwrap());

    Ok(Response::builder()
        .status(StatusCode::OK)
        .body(body)
        .unwrap())
}

pub async fn upload_file(
    State(state): State<AppState>,
    Extension(user): Extension<AuthenticatedUser>,
    Path(r2_key): Path<String>,
    body: axum::body::Bytes,
) -> Result<StatusCode, AppError> {
    // Find the file by r2_key to update its metadata
    let user_id_str = user.id.to_string();
    let file = sqlx::query!(
        "SELECT id FROM files WHERE r2_key = $1 AND user_id = $2",
        r2_key,
        user_id_str
    )
    .fetch_optional(&state.db)
    .await?;

    let Some(file) = file else {
        return Err(AppError::NotFound("File not found".to_string()));
    };

    // Update file size and updated_at
    let file_size = body.len() as i64;
    sqlx::query!(
        "UPDATE files SET size = $1, updated_at = datetime('now') WHERE id = $2",
        file_size,
        file.id
    )
    .execute(&state.db)
    .await?;

    // In a real implementation, this would upload to R2/S3
    // For now, just return success
    Ok(StatusCode::OK)
}

pub async fn delete_file(
    State(state): State<AppState>,
    Extension(user): Extension<AuthenticatedUser>,
    Path(r2_key): Path<String>,
) -> Result<StatusCode, AppError> {
    let user_id_str = user.id.to_string();
    let result = sqlx::query!(
        "DELETE FROM files WHERE r2_key = $1 AND user_id = $2",
        r2_key,
        user_id_str
    )
    .execute(&state.db)
    .await?;

    if result.rows_affected() > 0 {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::NotFound("File not found".to_string()))
    }
}