use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use crate::{OrderStatus, ProductCategory};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Product {
    pub id: Uuid,
    pub club_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub price_cents: i32,
    pub currency: String,
    pub category: ProductCategory,
    pub stock: Option<i32>,
    pub active: bool,
    pub created_at: DateTime<Utc>,
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
