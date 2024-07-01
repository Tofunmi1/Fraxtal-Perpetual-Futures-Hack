use actix_web::body::BoxBody;
use actix_web::http::header::ContentType;
use actix_web::http::StatusCode;
use actix_web::{delete, get, post, web, App, HttpResponse, HttpServer, Responder, ResponseError};
use serde::{Deserialize, Serialize};
use sqlx::postgres::PgPool;
use sqlx::{Pool, Postgres};

use std::fmt::Display;

use order_book::json::{JsonAccount, JsonOrder};
use order_book::primitive::{Address, Hash};

struct AppState {
    db_pool: Pool<Postgres>,
}

#[derive(Debug, Serialize)]
struct ErrNoAccount {
    address: String,
    err: String,
}

impl ResponseError for ErrNoAccount {
    fn status_code(&self) -> StatusCode {
        StatusCode::NOT_FOUND
    }

    fn error_response(&self) -> HttpResponse<BoxBody> {
        let body = serde_json::to_string(&self).unwrap();
        HttpResponse::NotFound()
            .content_type(ContentType::json())
            .body(body)
    }
}

impl Display for ErrNoAccount {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

#[derive(Debug, Serialize)]
struct ErrNoOrder {
    hash: Hash,
    err: String,
}

impl ResponseError for ErrNoOrder {
    fn status_code(&self) -> StatusCode {
        StatusCode::NOT_FOUND
    }

    fn error_response(&self) -> HttpResponse<BoxBody> {
        let body = serde_json::to_string(&self).unwrap();
        HttpResponse::NotFound()
            .content_type(ContentType::json())
            .body(body)
    }
}

impl Display for ErrNoOrder {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

#[post("/accounts")]
async fn new_account(
    req: web::Json<JsonAccount>,
    data: web::Data<AppState>,
) -> Result<HttpResponse, actix_web::Error> {
    let account = JsonAccount {
        ddxBalance: req.ddxBalance.clone(),
        usdBalance: req.usdBalance.clone(),
        traderAddress: req.traderAddress.clone(),
    };

    sqlx::query!(
        "INSERT INTO accounts (ddx_balance, usd_balance, trader_address) VALUES ($1, $2, $3)",
        account.ddxBalance,
        account.usdBalance,
        account.traderAddress
    )
    .execute(&data.db_pool)
    .await
    .map_err(|e| {
        eprintln!("Failed to execute query: {}", e);
        HttpResponse::InternalServerError().finish()
    })?;

    Ok(HttpResponse::Created()
        .content_type(ContentType::plaintext())
        .insert_header(("X-Hdr", "sample"))
        .body("New account created!"))
}

#[get("/accounts/{traderAddress}")]
#[allow(non_snake_case)]
async fn get_account(
    traderAddress: web::Path<String>,
    data: web::Data<AppState>,
) -> Result<impl Responder, ErrNoAccount> {
    let trader: Address = traderAddress
        .parse::<Address>()
        .expect("Failed to parse trader's address!");

    let account = sqlx::query_as!(
        JsonAccount,
        "SELECT ddx_balance as ddxBalance, usd_balance as usdBalance, trader_address as traderAddress FROM accounts WHERE trader_address = $1",
        trader.to_string()
    )
    .fetch_optional(&data.db_pool)
    .await
    .map_err(|_| ErrNoAccount {
        address: traderAddress.to_string(),
        err: String::from("Database error"),
    })?;

    account.map(web::Json).ok_or(ErrNoAccount {
        address: traderAddress.to_string(),
        err: String::from("Account not found"),
    })
}

#[delete("/accounts/{traderAddress}")]
#[allow(non_snake_case)]
async fn delete_account(
    traderAddress: web::Path<String>,
    data: web::Data<AppState>,
) -> Result<impl Responder, ErrNoAccount> {
    let trader: Address = traderAddress
        .parse::<Address>()
        .expect("Failed to parse trader's address!");

    let deleted_account = sqlx::query_as!(
        JsonAccount,
        "DELETE FROM accounts WHERE trader_address = $1 RETURNING ddx_balance as ddxBalance, usd_balance as usdBalance, trader_address as traderAddress",
        trader.to_string()
    )
    .fetch_optional(&data.db_pool)
    .await
    .map_err(|_| ErrNoAccount {
        address: traderAddress.to_string(),
        err: String::from("Database error"),
    })?;

    deleted_account.map(web::Json).ok_or(ErrNoAccount {
        address: traderAddress.to_string(),
        err: String::from("Account not found"),
    })
}

#[post("/orders")]
async fn new_order(
    req: web::Json<JsonOrder>,
    data: web::Data<AppState>,
) -> Result<impl Responder, ErrNoAccount> {
    // This function will need significant changes to handle order matching logic
    // The following is a placeholder implementation
    let order = req.into_inner();

    let result = sqlx::query!(
        "INSERT INTO orders (amount, nonce, price, side, trader_address) VALUES ($1, $2, $3, $4, $5) RETURNING id",
        order.amount,
        order.nonce,
        order.price,
        order.side,
        order.traderAddress
    )
    .fetch_one(&data.db_pool)
    .await
    .map_err(|_| ErrNoAccount {
        address: order.traderAddress,
        err: String::from("Failed to add order"),
    })?;

    Ok(web::Json(result.id))
}

#[get("/orders/{hash}")]
async fn get_order(
    hash: web::Path<Hash>,
    data: web::Data<AppState>,
) -> Result<impl Responder, ErrNoOrder> {
    let order_hash = hash.clone();

    let order = sqlx::query_as!(
        JsonOrder,
        "SELECT amount, nonce, price, side, trader_address as traderAddress FROM orders WHERE hash = $1",
        order_hash.to_string()
    )
    .fetch_optional(&data.db_pool)
    .await
    .map_err(|_| ErrNoOrder {
        hash: order_hash.clone(),
        err: String::from("Database error"),
    })?;

    order.map(web::Json).ok_or(ErrNoOrder {
        hash: order_hash,
        err: String::from("Order not found"),
    })
}

#[delete("/orders/{hash}")]
async fn cancel_order(
    hash: web::Path<Hash>,
    data: web::Data<AppState>,
) -> Result<impl Responder, ErrNoOrder> {
    let order_hash = hash.clone();

    let deleted_order = sqlx::query_as!(
        JsonOrder,
        "DELETE FROM orders WHERE hash = $1 RETURNING amount, nonce, price, side, trader_address as traderAddress",
        order_hash.to_string()
    )
    .fetch_optional(&data.db_pool)
    .await
    .map_err(|_| ErrNoOrder {
        hash: order_hash.clone(),
        err: String::from("Database error"),
    })?;

    deleted_order.map(web::Json).ok_or(ErrNoOrder {
        hash: order_hash,
        err: String::from("Order not found"),
    })
}

#[get("/book")]
async fn get_book(data: web::Data<AppState>) -> impl Responder {
    // This function will need to be implemented to generate the L2 order book from the database
    // The following is a placeholder implementation
    web::Json("L2 Order Book")
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Set up database connection pool
    let db_pool = PgPoolOptions::new()
        .max_connections(5)
        .connect("postgres://username:password@localhost/database_name")
        .await
        .expect("Failed to create pool");

    // Run migrations
    sqlx::migrate!("./migrations")
        .run(&db_pool)
        .await
        .expect("Failed to migrate the database");

    let app_state = web::Data::new(AppState { db_pool });

    HttpServer::new(move || {
        App::new()
            .app_data(app_state.clone())
            .service(new_account)
            .service(get_account)
            .service(delete_account)
            .service(new_order)
            .service(get_order)
            .service(cancel_order)
            .service(get_book)
    })
    .bind(("127.0.0.1", 4321))?
    .run()
    .await
}
