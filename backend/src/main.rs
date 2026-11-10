mod config;
mod error;
mod state;
mod models;
mod services;
mod middleware;
mod routes;

use axum::{routing::get, Router};
use sqlx::sqlite::SqlitePoolOptions;
use std::net::SocketAddr;
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::{config::Config, state::AppState};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new("debug"))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let config = Config::init();

    let db = SqlitePoolOptions::new()
        .max_connections(5)
        .connect(&config.database_url)
        .await?;

    sqlx::migrate!("./migrations").run(&db).await?;

    let state = AppState { db, config: config.clone() };

    // Public auth routes (no auth middleware)
    let public_auth = Router::new()
        .route("/register", axum::routing::post(routes::auth::register))
        .route("/login", axum::routing::post(routes::auth::login));

    // Protected auth routes (with auth middleware)
    let protected_auth = Router::new()
        .route("/me", axum::routing::get(routes::auth::me))
        .layer(axum::middleware::from_fn_with_state(state.clone(), crate::middleware::auth::auth_middleware));

    // Items routes (all protected)
    let items = Router::new()
        .route("/", axum::routing::get(routes::items::list_items))
        .route("/", axum::routing::post(routes::items::create_item))
        .route("/{id}", axum::routing::get(routes::items::get_item))
        .route("/{id}", axum::routing::patch(routes::items::update_item))
        .route("/{id}", axum::routing::delete(routes::items::delete_item))
        .layer(axum::middleware::from_fn_with_state(state.clone(), crate::middleware::auth::auth_middleware));

    // Files routes (for upload/download)
    let files = routes::files::router();

    // Shares routes - protected routes with auth, public download without auth
    let shares_protected = routes::shares::router()
        .layer(axum::middleware::from_fn_with_state(state.clone(), crate::middleware::auth::auth_middleware));
    let shares_public = Router::new()
        .route("/{share_id}/download", get(routes::shares::download_with_key));

    let app = Router::new()
        .route("/health", get(|| async { "OK" }))
        .nest("/auth", public_auth)
        .nest("/auth", protected_auth)
        .nest("/items", items)
        .nest("/files", files.layer(axum::middleware::from_fn_with_state(state.clone(), crate::middleware::auth::auth_middleware)))
        .nest("/shares", shares_public.merge(shares_protected))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    tracing::info!("Listening on {}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
