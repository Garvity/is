use axum::{
    body::Body,
    extract::State,
    http::{header::AUTHORIZATION, Request},
    middleware::Next,
    response::Response,
};
use uuid::Uuid;
use crate::{error::AppError, services::auth_service::verify_jwt, state::AppState};

#[derive(Clone)]
pub struct AuthenticatedUser {
    pub id: Uuid,
}

pub async fn auth_middleware(
    State(state): State<AppState>,
    mut req: Request<Body>,
    next: Next,
) -> Result<Response, AppError> {
    let auth_header = req
        .headers()
        .get(AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .ok_or_else(|| AppError::Unauthorized("Missing authorization header".to_string()))?;

    let token = auth_header
        .strip_prefix("Bearer ")
        .ok_or_else(|| AppError::Unauthorized("Invalid authorization header format".to_string()))?;

    let user_id = verify_jwt(token, &state.config.jwt_secret)?;

    req.extensions_mut().insert(AuthenticatedUser { id: user_id });

    Ok(next.run(req).await)
}
