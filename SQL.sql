CREATE TABLE IF NOT EXISTS moneywash_playerdata (
    identifier VARCHAR(60) PRIMARY KEY,
    totalWashed INT DEFAULT 0,
    totalTransactions INT DEFAULT 0,
    successfulTransactions INT DEFAULT 0,
    failedTransactions INT DEFAULT 0,
    reputation INT DEFAULT 0,
    lastWash INT DEFAULT 0,
    history LONGTEXT
);

CREATE TABLE IF NOT EXISTS moneywash_daily (
    identifier VARCHAR(60) PRIMARY KEY,
    date VARCHAR(20),
    amount INT DEFAULT 0
);
