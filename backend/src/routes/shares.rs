use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    routing::{delete, get, post},
    Router,
};
use uuid::Uuid;

use crate::{
    error::AppError,
    middleware::auth::AuthenticatedUser,
    models::share::{CreateShareRequest, ShareResponse},
    state::AppState,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", post(create_share))
        .route("/{share_id}", get(get_share))
        .route("/{share_id}", delete(revoke_share))
}

pub async fn create_share(
    State(state): State<AppState>,
    axum::extract::Extension(user): axum::extract::Extension<AuthenticatedUser>,
    Json(payload): Json<CreateShareRequest>,
) -> Result<Json<ShareResponse>, AppError> {
    let share_id = Uuid::new_v4().to_string();
    let user_id_str = user.id.to_string();

    let share = sqlx::query_as!(
        crate::models::share::Share,
        r#"
        INSERT INTO shares (id, user_id, item_id, wrapped_dek, access_type, password_hash, expires_at, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, datetime('now'))
        RETURNING id, user_id, item_id, wrapped_dek, access_type, password_hash, expires_at, created_at
        "#,
        share_id,
        user_id_str,
        payload.item_id,
        payload.wrapped_dek,
        payload.access_type,
        payload.password_hash,
        payload.expires_at
    )
    .fetch_one(&state.db)
    .await?;

    let response = ShareResponse {
        id: share.id,
        item_id: share.item_id,
        access_type: share.access_type,
        expires_at: share.expires_at,
        created_at: share.created_at,
    };

    Ok(Json(response))
}

pub async fn get_share(
    State(state): State<AppState>,
    Path(share_id): Path<String>,
) -> Result<Json<crate::models::share::Share>, AppError> {
    let share = sqlx::query_as!(
        crate::models::share::Share,
        "SELECT id, user_id, item_id, wrapped_dek, access_type, password_hash, expires_at, created_at FROM shares WHERE id = $1",
        share_id
    )
    .fetch_optional(&state.db)
    .await?;

    match share {
        Some(share) => Ok(Json(share)),
        None => Err(AppError::NotFound("Share not found".to_string())),
    }
}

pub async fn download_with_key(
    State(state): State<AppState>,
    Path(share_id): Path<String>,
    axum::extract::Query(query): axum::extract::Query<std::collections::HashMap<String, String>>,
) -> Result<axum::response::Response, AppError> {
    let key = query.get("key").ok_or_else(|| AppError::BadRequest("Missing key parameter".to_string()))?;

    // Verify share exists and is not expired
    let now = chrono::Utc::now().to_rfc3339();
    let share = sqlx::query_as!(
        crate::models::share::Share,
        r#"
        SELECT id, user_id, item_id, wrapped_dek, access_type, password_hash, expires_at, created_at
        FROM shares
        WHERE id = $1 AND (expires_at IS NULL OR expires_at > $2)
        "#,
        share_id,
        now
    )
    .fetch_optional(&state.db)
    .await?;

    let Some(share) = share else {
        return Err(AppError::NotFound("Share not found or expired".to_string()));
    };

    // In a real implementation, we would:
    // 1. Unwrap DEK using the provided key
    // 2. Fetch the file with the decrypted key
    // 3. Stream the decrypted content

    // For now, return share info
    let body = axum::body::Body::from(format!(
        "Share ID: {}\nItem ID: {}\nAccess Type: {}\nKey provided: {}",
        share.id, share.item_id, share.access_type, key
    ));

    Ok(axum::response::Response::builder()
        .status(StatusCode::OK)
        .body(body)
        .unwrap())
}

pub async fn revoke_share(
    State(state): State<AppState>,
    axum::extract::Extension(user): axum::extract::Extension<AuthenticatedUser>,
    Path(share_id): Path<String>,
) -> Result<StatusCode, AppError> {
    let user_id_str = user.id.to_string();
    let result = sqlx::query!(
        "DELETE FROM shares WHERE id = $1 AND user_id = $2",
        share_id,
        user_id_str
    )
    .execute(&state.db)
    .await?;

    if result.rows_affected() > 0 {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::NotFound("Share not found".to_string()))
    }
}