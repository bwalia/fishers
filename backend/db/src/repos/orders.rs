use fishers_domain::{
    CreateProductRequest, Order, OrderItem, OrderStatus, PlaceOrderRequest, Product,
};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn create_product(
    pool: &PgPool,
    club_id: Uuid,
    req: &CreateProductRequest,
) -> Result<Product, sqlx::Error> {
    let currency = req.currency.clone().unwrap_or_else(|| "GBP".to_string());
    sqlx::query_as::<_, Product>(
        r#"
        INSERT INTO products (club_id, name, description, price_cents, currency, category, stock)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id, club_id, name, description, price_cents, currency, category, stock, active, created_at
        "#,
    )
    .bind(club_id)
    .bind(&req.name)
    .bind(&req.description)
    .bind(req.price_cents)
    .bind(currency)
    .bind(req.category)
    .bind(req.stock)
    .fetch_one(pool)
    .await
}

pub async fn list_products(pool: &PgPool, club_id: Uuid) -> Result<Vec<Product>, sqlx::Error> {
    sqlx::query_as::<_, Product>(
        r#"
        SELECT id, club_id, name, description, price_cents, currency, category, stock, active, created_at
        FROM products WHERE club_id = $1 AND active = TRUE ORDER BY name
        "#,
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

pub async fn place_order(
    pool: &PgPool,
    user_id: Uuid,
    req: &PlaceOrderRequest,
) -> Result<(Order, Vec<OrderItem>), sqlx::Error> {
    let mut tx = pool.begin().await?;
    let mut total = 0i32;
    let mut line_items: Vec<(Uuid, i32, i32)> = Vec::new();

    for item in &req.items {
        let product = sqlx::query_as::<_, Product>(
            r#"
            SELECT id, club_id, name, description, price_cents, currency, category, stock, active, created_at
            FROM products WHERE id = $1 AND club_id = $2 AND active = TRUE
            "#,
        )
        .bind(item.product_id)
        .bind(req.club_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or(sqlx::Error::RowNotFound)?;

        total += product.price_cents * item.quantity;
        line_items.push((product.id, item.quantity, product.price_cents));
    }

    let order = sqlx::query_as::<_, Order>(
        r#"
        INSERT INTO orders (user_id, club_id, event_id, status, total_amount_cents, note)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, user_id, club_id, event_id, status, total_amount_cents, currency, note, created_at, updated_at
        "#,
    )
    .bind(user_id)
    .bind(req.club_id)
    .bind(req.event_id)
    .bind(OrderStatus::Placed)
    .bind(total)
    .bind(&req.note)
    .fetch_one(&mut *tx)
    .await?;

    let mut items = Vec::new();
    for (product_id, qty, unit) in line_items {
        let oi = sqlx::query_as::<_, OrderItem>(
            r#"
            INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents)
            VALUES ($1, $2, $3, $4)
            RETURNING id, order_id, product_id, quantity, unit_price_cents
            "#,
        )
        .bind(order.id)
        .bind(product_id)
        .bind(qty)
        .bind(unit)
        .fetch_one(&mut *tx)
        .await?;
        items.push(oi);
    }

    tx.commit().await?;
    Ok((order, items))
}

pub async fn list_my_orders(pool: &PgPool, user_id: Uuid) -> Result<Vec<Order>, sqlx::Error> {
    sqlx::query_as::<_, Order>(
        r#"
        SELECT id, user_id, club_id, event_id, status, total_amount_cents, currency, note, created_at, updated_at
        FROM orders WHERE user_id = $1 ORDER BY created_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
}
