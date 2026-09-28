use axum::extract::{Path, Query, State};
use axum::routing::{get, patch, post};
use axum::{Json, Router};
use fishers_db::repos::orders as orders_repo;
use fishers_domain::{
    CreateProductRequest, Order, Permission, PlaceOrderRequest, Product, UpdateProductRequest,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use crate::auth::AuthUser;
use crate::error::{ApiError, ApiResult};
use crate::rbac::{require_club_member, require_club_permission};
use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/clubs/{id}/products", get(list_products).post(create_product))
        .route("/clubs/{id}/products/{product_id}", patch(update_product))
        .route("/clubs/{id}/products/{product_id}/photo", post(upload_photo))
        // Across every club, not one: a club with a spare set of pads needs a
        // bigger room than its own membership.
        .route("/marketplace", get(marketplace))
        .route("/marketplace/{id}", get(market_item))
        .route("/orders", post(place_order))
        .route("/orders/mine", get(my_orders))
}

async fn create_product(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<CreateProductRequest>,
) -> ApiResult<Json<Product>> {
    body.validate()?;
    require_club_permission(&state, id, auth.user_id, Permission::ManageClubOps).await?;
    Ok(Json(
        orders_repo::create_product(&state.pool, id, &body).await?,
    ))
}

/// Change a listing: drop the price, add the last photo, or take it off sale
/// because somebody has collected it.
async fn update_product(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, product_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<UpdateProductRequest>,
) -> ApiResult<Json<Product>> {
    body.validate()?;
    require_club_permission(&state, club_id, auth.user_id, Permission::ManageClubOps).await?;
    orders_repo::update_product(&state.pool, club_id, product_id, &body)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("no such product in this club"))
}

#[derive(Debug, Deserialize)]
struct MarketQuery {
    condition: Option<fishers_domain::ProductCondition>,
    q: Option<String>,
}

/// Everything on sale, across every club.
///
/// Any signed-in player, not just members of the selling club — that is the
/// point. Only what a secretary listed publicly, and only what is still in
/// stock: a sold bat on the front page wastes somebody's evening.
async fn marketplace(
    State(state): State<AppState>,
    _auth: AuthUser,
    Query(q): Query<MarketQuery>,
) -> ApiResult<Json<Vec<Product>>> {
    let term = q.q.as_deref().map(str::trim).filter(|t| !t.is_empty());
    Ok(Json(
        orders_repo::marketplace(&state.pool, q.condition, term, 100).await?,
    ))
}

/// A photograph for a listing.
///
/// Nobody buys a second-hand bat they cannot see, and a club secretary
/// photographing one in a clubhouse is not going to resize it first. Up to six
/// per listing, appended in the order they arrive.
async fn upload_photo(
    State(state): State<AppState>,
    auth: AuthUser,
    Path((club_id, product_id)): Path<(Uuid, Uuid)>,
    mut form: axum::extract::Multipart,
) -> ApiResult<Json<Product>> {
    require_club_permission(&state, club_id, auth.user_id, Permission::ManageClubOps).await?;
    let storage = state
        .storage
        .as_ref()
        .ok_or_else(|| ApiError::bad_request("uploads are not configured on this server"))?;

    let mut bytes: Option<Vec<u8>> = None;
    while let Some(field) = form
        .next_field()
        .await
        .map_err(|e| ApiError::bad_request(format!("could not read the upload: {e}")))?
    {
        if field.name() == Some("file") {
            let data = field
                .bytes()
                .await
                .map_err(|e| ApiError::bad_request(format!("could not read the file: {e}")))?;
            if data.len() > MAX_PHOTO_BYTES {
                return Err(ApiError::bad_request("that picture is over 5MB"));
            }
            bytes = Some(data.to_vec());
            break;
        }
    }
    let bytes = bytes.ok_or_else(|| ApiError::bad_request("no file was sent"))?;
    let (content_type, ext) = crate::routes::users::sniff_image(&bytes)
        .ok_or_else(|| ApiError::bad_request("that is not a JPEG, PNG or WebP"))?;

    let product = orders_repo::get_product(&state.pool, club_id, product_id)
        .await?
        .ok_or_else(|| ApiError::not_found("no such product in this club"))?;
    if product.photos.len() >= MAX_PHOTOS {
        return Err(ApiError::bad_request(
            "that listing already has six photographs — remove one first",
        ));
    }

    let key = format!("products/{product_id}/{}.{ext}", Uuid::new_v4());
    storage
        .put(&key, content_type, bytes)
        .await
        .map_err(|e| ApiError::internal(format!("could not store the picture: {e}")))?;

    let mut photos = product.photos;
    photos.push(storage.public_url(&key));
    orders_repo::update_product(
        &state.pool,
        club_id,
        product_id,
        &UpdateProductRequest {
            photos: Some(photos),
            ..Default::default()
        },
    )
    .await?
    .map(Json)
    .ok_or_else(|| ApiError::not_found("no such product in this club"))
}

/// Six is what a listing needs: the whole thing, the face, the toe, the grip,
/// and two for whatever is wrong with it.
const MAX_PHOTOS: usize = 6;
/// Larger than an avatar: a phone photograph of a bat in a clubhouse is not
/// going to be small, and asking a secretary to resize it is asking them not
/// to bother.
const MAX_PHOTO_BYTES: usize = 5 * 1024 * 1024;

/// One listing, in full.
///
/// Any signed-in player, which is the point: somebody at another club has
/// followed a link to a bat and wants the description, every photograph and
/// whether the price moves.
async fn market_item(
    State(state): State<AppState>,
    _auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Product>> {
    orders_repo::public_product(&state.pool, id)
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("that listing is not for sale"))
}

async fn list_products(
    State(state): State<AppState>,
    auth: AuthUser,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<Vec<Product>>> {
    require_club_member(&state, id, auth.user_id).await?;
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
    if body.items.iter().any(|i| i.quantity < 1) {
        return Err(ApiError::bad_request("a quantity has to be at least one"));
    }
    let (order, items) = orders_repo::place_order(&state.pool, auth.user_id, &body)
        .await
        .map_err(|e| match e {
            // The repo cannot tell these apart without another query, and the
            // buyer does not care which it was — they care that it is gone and
            // that they did not do anything wrong. Losing the race for the last
            // second-hand bat is the commonest of the three by far.
            sqlx::Error::RowNotFound => ApiError::conflict(
                "that is no longer available — somebody may have just taken the last one",
            ),
            other => other.into(),
        })?;
    // Whoever can list a bat is whoever hears that somebody wants it. In the
    // background and never fatal: an order that succeeded must not fail
    // because a notification did not write.
    let bus_state = state.clone();
    let club_id = body.club_id;
    let order_id = order.id;
    let buyer = auth.user_id;
    let lines = items.len();
    tokio::spawn(async move {
        let officers = match fishers_db::repos::clubs::officers(&bus_state.pool, club_id).await {
            Ok(list) => list,
            Err(e) => {
                tracing::warn!(error = %e, "could not find who to tell about the reservation");
                return;
            }
        };
        let payload = serde_json::json!({
            "order_id": order_id,
            "club_id": club_id,
            "buyer_id": buyer,
            "items": lines,
        });
        for officer in officers {
            // Not the buyer, when the buyer is the secretary listing their own
            // club's kit to themselves — a notification about your own tap is
            // noise.
            if officer == buyer {
                continue;
            }
            if let Err(e) = fishers_db::repos::notifications::record(
                &bus_state.pool,
                officer,
                "shop_reserved",
                &payload,
            )
            .await
            {
                tracing::warn!(error = %e, "could not record the reservation notification");
            }
        }
    });

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
