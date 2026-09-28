use fishers_domain::{
    CreateProductRequest, Order, OrderItem, OrderStatus, PlaceOrderRequest, Product,
    UpdateProductRequest,
};
use sqlx::PgPool;

/// Every column of a product. One list, because four queries returning three
/// different shapes of the same row is how a field gets added in one place and
/// missed in the others.
const PRODUCT_COLS: &str = "id, club_id, name, description, price_cents, currency, category, \
     stock, active, created_at, condition, condition_note, size, brand, photos, \
     listed_publicly, collection_note, negotiable, listed_by, show_contact";

use uuid::Uuid;

pub async fn create_product(
    pool: &PgPool,
    club_id: Uuid,
    listed_by: Uuid,
    req: &CreateProductRequest,
) -> Result<Product, sqlx::Error> {
    let currency = req.currency.clone().unwrap_or_else(|| "GBP".to_string());
    sqlx::query_as::<_, Product>(&format!(
        r#"
        INSERT INTO products (club_id, name, description, price_cents, currency, category, stock,
                              condition, condition_note, size, brand, listed_publicly,
                              collection_note, negotiable, listed_by, show_contact)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
        RETURNING {PRODUCT_COLS}
        "#
    ))
    .bind(club_id)
    .bind(&req.name)
    .bind(&req.description)
    .bind(req.price_cents)
    .bind(currency)
    .bind(req.category)
    .bind(req.stock)
    .bind(req.condition)
    .bind(&req.condition_note)
    .bind(&req.size)
    .bind(&req.brand)
    .bind(req.listed_publicly.unwrap_or(false))
    .bind(&req.collection_note)
    .bind(req.negotiable.unwrap_or(false))
    .bind(listed_by)
    .bind(req.show_contact.unwrap_or(false))
    .fetch_one(pool)
    .await
}

/// Change a listing. Absent fields keep what is there.
pub async fn update_product(
    pool: &PgPool,
    club_id: Uuid,
    product_id: Uuid,
    req: &UpdateProductRequest,
) -> Result<Option<Product>, sqlx::Error> {
    sqlx::query_as::<_, Product>(&format!(
        r#"
        UPDATE products SET
            name            = COALESCE($3, name),
            description     = COALESCE($4, description),
            price_cents     = COALESCE($5, price_cents),
            stock           = COALESCE($6, stock),
            condition       = COALESCE($7, condition),
            condition_note  = COALESCE($8, condition_note),
            size            = COALESCE($9, size),
            brand           = COALESCE($10, brand),
            listed_publicly = COALESCE($11, listed_publicly),
            collection_note = COALESCE($12, collection_note),
            active          = COALESCE($13, active),
            photos          = COALESCE($14, photos),
            negotiable      = COALESCE($15, negotiable),
            show_contact    = COALESCE($16, show_contact)
         WHERE id = $1 AND club_id = $2
        RETURNING {PRODUCT_COLS}
        "#
    ))
    .bind(product_id)
    .bind(club_id)
    .bind(&req.name)
    .bind(&req.description)
    .bind(req.price_cents)
    .bind(req.stock)
    .bind(req.condition)
    .bind(&req.condition_note)
    .bind(&req.size)
    .bind(&req.brand)
    .bind(req.listed_publicly)
    .bind(&req.collection_note)
    .bind(req.active)
    .bind(&req.photos)
    .bind(req.negotiable)
    .bind(req.show_contact)
    .fetch_optional(pool)
    .await
}

/// One product of a club, whatever state it is in.
pub async fn get_product(
    pool: &PgPool,
    club_id: Uuid,
    product_id: Uuid,
) -> Result<Option<Product>, sqlx::Error> {
    sqlx::query_as::<_, Product>(&format!(
        "SELECT {PRODUCT_COLS} FROM products WHERE id = $1 AND club_id = $2"
    ))
    .bind(product_id)
    .bind(club_id)
    .fetch_optional(pool)
    .await
}

/// One publicly listed item with whoever is selling it.
///
/// The contact columns are selected conditionally in SQL rather than fetched
/// and filtered in Rust: a number that was never read cannot be logged, put in
/// an error, or served by a later change that forgot why the filter was there.
pub async fn public_listing(
    pool: &PgPool,
    id: Uuid,
) -> Result<Option<fishers_domain::MarketListing>, sqlx::Error> {
    #[derive(sqlx::FromRow)]
    struct Row {
        club_name: String,
        seller_name: Option<String>,
        seller_email: Option<String>,
        seller_phone: Option<String>,
    }

    let Some(product) = public_product(pool, id).await? else {
        return Ok(None);
    };

    let row = sqlx::query_as::<_, Row>(
        "SELECT c.name AS club_name,
                u.name  AS seller_name,
                CASE WHEN p.show_contact THEN u.email END AS seller_email,
                CASE WHEN p.show_contact THEN u.phone END AS seller_phone
           FROM products p
           JOIN clubs c ON c.id = p.club_id
           LEFT JOIN users u ON u.id = p.listed_by AND u.deleted_at IS NULL
          WHERE p.id = $1",
    )
    .bind(id)
    .fetch_one(pool)
    .await?;

    Ok(Some(fishers_domain::MarketListing {
        product,
        club_name: row.club_name,
        seller_name: row.seller_name,
        seller_email: row.seller_email,
        seller_phone: row.seller_phone,
    }))
}

/// Who an enquiry about a listing should reach.
///
/// Whoever put it up, and the club's officers when nothing did — everything
/// listed before products had an author, and anything listed by somebody who
/// has since left.
pub async fn enquiry_recipients(pool: &PgPool, id: Uuid) -> Result<Vec<Uuid>, sqlx::Error> {
    let rows: Vec<(Uuid,)> = sqlx::query_as(
        "SELECT p.listed_by FROM products p
          WHERE p.id = $1 AND p.listed_by IS NOT NULL
            AND EXISTS (SELECT 1 FROM users u WHERE u.id = p.listed_by AND u.deleted_at IS NULL)
          UNION
         SELECT m.user_id FROM products p
           JOIN club_members m ON m.club_id = p.club_id
          WHERE p.id = $1 AND m.status = 'active'
            AND m.role IN ('club_admin', 'super_admin')
            AND NOT EXISTS (
                SELECT 1 FROM products p2 JOIN users u ON u.id = p2.listed_by
                 WHERE p2.id = $1 AND u.deleted_at IS NULL
            )",
    )
    .bind(id)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|(id,)| id).collect())
}

/// One publicly listed item, for its own page.
///
/// Separate from `get_product`, which is the club's own view of its shelf:
/// this one is what anybody signed in may see, and it refuses anything the
/// selling club has not put on the market.
pub async fn public_product(pool: &PgPool, id: Uuid) -> Result<Option<Product>, sqlx::Error> {
    sqlx::query_as::<_, Product>(&format!(
        "SELECT {PRODUCT_COLS} FROM products WHERE id = $1 AND listed_publicly AND active"
    ))
    .bind(id)
    .fetch_optional(pool)
    .await
}

/// What is for sale across every club.
///
/// The reason the shop exists at all now: a club with a spare set of pads, or
/// one that makes its own bats, has thirty members and needs a bigger room.
/// Only what a secretary has deliberately listed publicly, and only what is
/// still in stock — a sold bat on the front page is worse than an empty one.
pub async fn marketplace(
    pool: &PgPool,
    condition: Option<fishers_domain::ProductCondition>,
    query: Option<&str>,
    limit: i64,
) -> Result<Vec<Product>, sqlx::Error> {
    sqlx::query_as::<_, Product>(&format!(
        r#"
        SELECT {PRODUCT_COLS} FROM products
         WHERE listed_publicly AND active
           AND (stock IS NULL OR stock > 0)
           AND ($1::product_condition IS NULL OR condition = $1)
           AND ($2::text IS NULL OR name ILIKE $2 OR brand ILIKE $2 OR description ILIKE $2)
         ORDER BY created_at DESC
         LIMIT $3
        "#
    ))
    .bind(condition)
    .bind(query.map(|q| format!("%{q}%")))
    .bind(limit)
    .fetch_all(pool)
    .await
}

pub async fn list_products(pool: &PgPool, club_id: Uuid) -> Result<Vec<Product>, sqlx::Error> {
    sqlx::query_as::<_, Product>(&format!(
        r#"
        SELECT {PRODUCT_COLS}
        FROM products WHERE club_id = $1 AND active = TRUE ORDER BY name
        "#
    ))
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

        // Take the stock in the same statement that reads the price, inside
        // the order's transaction. Reading it first and writing it later is
        // what let the same second-hand bat be sold to everybody who asked:
        // stock was stored and never once checked or decremented.
        //
        // A NULL stock means "on request" — made to order, or a tea urn that
        // does not run out — so it is left alone rather than driven negative.
        let product = sqlx::query_as::<_, Product>(&format!(
            r#"
            UPDATE products
               SET stock = CASE WHEN stock IS NULL THEN NULL ELSE stock - $3 END
             WHERE id = $1 AND club_id = $2 AND active = TRUE
               AND (stock IS NULL OR stock >= $3)
            RETURNING {PRODUCT_COLS}
            "#
        ))
        .bind(item.product_id)
        .bind(req.club_id)
        .bind(item.quantity)
        .fetch_optional(&mut *tx)
        .await?
        // No row means one of three things and the caller cannot tell them
        // apart from here: no such product, it is no longer for sale, or
        // somebody else got the last one first. The route turns this into a
        // sentence.
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
