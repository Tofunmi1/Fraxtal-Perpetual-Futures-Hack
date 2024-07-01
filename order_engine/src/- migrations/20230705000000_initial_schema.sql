CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    ddx_balance DECIMAL NOT NULL,
    usd_balance DECIMAL NOT NULL,
    trader_address VARCHAR(255) NOT NULL UNIQUE
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    hash VARCHAR(255) NOT NULL UNIQUE,
    amount DECIMAL NOT NULL,
    nonce INTEGER NOT NULL,
    price DECIMAL NOT NULL,
    side VARCHAR(4) NOT NULL,
    trader_address VARCHAR(255) NOT NULL,
    FOREIGN KEY (trader_address) REFERENCES accounts(trader_address)
);