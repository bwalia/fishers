use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use crate::{OrderStatus, ProductCategory, ProductCondition};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Product {
    pub id: Uuid,
    pub club_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub price_cents: i32,
    pub currency: String,
    pub category: ProductCategory,
    /// `None` is "on request" — made to order, or a tea urn that does not run
    /// out. A second-hand item is almost always `Some(1)`.
    pub stock: Option<i32>,
    pub active: bool,
    pub created_at: DateTime<Utc>,
    /// New or used. `None` for the things it does not apply to.
    pub condition: Option<ProductCondition>,
    /// "Light wear on the toe, no cracks." The sentence that decides whether
    /// somebody drives an hour to look at it.
    pub condition_note: Option<String>,
    /// Short Handle, Harrow, Youth Large. Free text: bat sizes, pad sizes and
    /// glove sizes share no vocabulary.
    pub size: Option<String>,
    pub brand: Option<String>,
    pub photos: Vec<String>,
    /// Whether it appears outside the club.
    pub listed_publicly: bool,
    pub collection_note: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Order {
    pub id: Uuid,
    pub user_id: Uuid,
    pub club_id: Uuid,
    pub event_id: Option<Uuid>,
    pub status: OrderStatus,
    pub total_amount_cents: i32,
    pub currency: String,
    pub note: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct OrderItem {
    pub id: Uuid,
    pub order_id: Uuid,
    pub product_id: Uuid,
    pub quantity: i32,
    pub unit_price_cents: i32,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub struct CreateProductRequest {
    #[validate(length(min = 1, max = 160))]
    pub name: String,
    pub description: Option<String>,
    pub price_cents: i32,
    pub currency: Option<String>,
    pub category: ProductCategory,
    pub stock: Option<i32>,
    pub condition: Option<ProductCondition>,
    #[validate(length(max = 500))]
    pub condition_note: Option<String>,
    #[validate(length(max = 60))]
    pub size: Option<String>,
    #[validate(length(max = 80))]
    pub brand: Option<String>,
    pub listed_publicly: Option<bool>,
    #[validate(length(max = 300))]
    pub collection_note: Option<String>,
}

/// Changing a listing after it is up: the price comes down, the last photo
/// arrives, or it is sold and should stop being offered.
///
/// Every field optional and absent meaning "leave it" — a secretary lowering a
/// price should not have to resend the description they wrote last week.
#[derive(Debug, Clone, Default, Deserialize, Validate)]
pub struct UpdateProductRequest {
    #[validate(length(min = 1, max = 160))]
    pub name: Option<String>,
    pub description: Option<String>,
    pub price_cents: Option<i32>,
    pub stock: Option<i32>,
    pub condition: Option<ProductCondition>,
    #[validate(length(max = 500))]
    pub condition_note: Option<String>,
    #[validate(length(max = 60))]
    pub size: Option<String>,
    #[validate(length(max = 80))]
    pub brand: Option<String>,
    pub listed_publicly: Option<bool>,
    #[validate(length(max = 300))]
    pub collection_note: Option<String>,
    /// Taking it off sale. Kept rather than deleted, so an order that already
    /// names it still reads.
    pub active: Option<bool>,
    pub photos: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub struct PlaceOrderRequest {
    pub club_id: Uuid,
    pub event_id: Option<Uuid>,
    pub note: Option<String>,
    #[validate(length(min = 1))]
    pub items: Vec<OrderItemRequest>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub struct OrderItemRequest {
    pub product_id: Uuid,
    #[validate(range(min = 1, max = 99))]
    pub quantity: i32,
}
