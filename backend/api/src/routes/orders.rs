use axum::extract::{Path, State};
use axum::routing::{get, post};
use axum::{Json, Router};
use fishers_db::repos::orders as orders_repo;
use fishers_domain::{CreateProductRequest, Order, PlaceOrderRequest, Product};
use serde::Serialize;
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::ApiResult;
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/clubs/{id}/products", get(list_products).post(create_product))
        .route("/orders", post(place_order))
        .route("/orders/mine", get(my_orders))
}

async fn create_product(
    State(state): State<AppState>,
    _auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<CreateProductRequest>,
) -> ApiResult<Json<Product>> {
    body.validate()?;
    Ok(Json(
        orders_repo::create_product(&state.pool, id, &body).await?,
    ))
}

async fn list_products(
    State(state): State<AppState>,
    _auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<Product>>> {
    Ok(Json(
        orders_repo::list_products(&state.pool, id).await?,
    ))
}

#[derive(Serialize)]
struct OrderResponse {
    order: Order,
    items: Vec<fishers_domain::OrderItem>,
}

async fn place_order(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(body): Json<PlaceOrderRequest>,
) -> ApiResult<Json<OrderResponse>> {
    body.validate()?;
    let (order, items) = orders_repo::place_order(&state.pool, auth.user_id, &body).await?;
    Ok(Json(OrderResponse { order, items }))
}

async fn my_orders(
    State(state): State<AppState>,
    auth: AuthUser,
) -> ApiResult<Json<Vec<Order>>> {
    Ok(Json(
        orders_repo::list_my_orders(&state.pool, auth.user_id).await?,
    ))
}
