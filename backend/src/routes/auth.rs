use axum::{
    extract::State,
    http::StatusCode,
    routing::{get, post},
    Extension, Json, Router,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use crate::{
    error::AppError,
    middleware::auth::AuthenticatedUser,
    services::auth_service::{create_jwt, hash_password, verify_password},
    state::AppState,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/register", post(register))
        .route("/login", post(login))
        .route("/me", get(me))
}

#[derive(Deserialize, Validate)]
pub struct RegisterRequest {
    #[validate(email)]
    email: String,
    #[validate(length(min = 8))]
    password: String,
}

#[derive(Serialize)]
pub struct AuthResponse {
    token: String,
}

pub async fn register(
    State(state): State<AppState>,
    Json(payload): Json<RegisterRequest>,
) -> Result<(StatusCode, Json<AuthResponse>), AppError> {
    payload.validate().map_err(|e| AppError::BadRequest(e.to_string()))?;

    let hashed_pw = hash_password(&payload.password)?;

    let user_id = Uuid::new_v4().to_string();
    sqlx::query!(
        "INSERT INTO users (id, email, password_hash) VALUES ($1, $2, $3)",
        user_id,
        payload.email,
        hashed_pw
    )
    .execute(&state.db)
    .await
    .map_err(|e| {
        if let sqlx::Error::Database(db_err) = &e {
            if db_err.is_unique_violation() {
                return AppError::BadRequest("Email already exists".to_string());
            }
        }
        AppError::Database(e)
    })?;

    let token = create_jwt(Uuid::parse_str(&user_id).unwrap(), &state.config.jwt_secret)?;

    Ok((StatusCode::CREATED, Json(AuthResponse { token })))
}

#[derive(Deserialize)]
pub struct LoginRequest {
    email: String,
    password: String,
}

pub async fn login(
    State(state): State<AppState>,
    Json(payload): Json<LoginRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    let user = sqlx::query!(
        "SELECT id, password_hash FROM users WHERE email = $1",
        payload.email
    )
    .fetch_optional(&state.db)
    .await?;

    let user = match user {
        Some(u) => u,
        None => return Err(AppError::Unauthorized("Invalid credentials".to_string())),
    };

    if !verify_password(&payload.password, &user.password_hash) {
        return Err(AppError::Unauthorized("Invalid credentials".to_string()));
    }

    let user_uuid = Uuid::parse_str(&user.id).unwrap();
    let token = create_jwt(user_uuid, &state.config.jwt_secret)?;

    Ok(Json(AuthResponse { token }))
}

#[derive(Serialize)]
pub struct MeResponse {
    id: Uuid,
    email: String,
}

pub async fn me(
    State(state): State<AppState>,
    Extension(user): Extension<AuthenticatedUser>,
) -> Result<Json<MeResponse>, AppError> {
    let user_id_str = user.id.to_string();
    let row = sqlx::query!(
        "SELECT id, email FROM users WHERE id = $1",
        user_id_str
    )
    .fetch_optional(&state.db)
    .await?;

    let row = match row {
        Some(r) => r,
        None => return Err(AppError::NotFound("User not found".to_string())),
    };

    let row_id_str: String = row.id;
    Ok(Json(MeResponse {
        id: Uuid::parse_str(&row_id_str).unwrap(),
        email: row.email,
    }))
}