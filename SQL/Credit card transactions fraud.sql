## create a database
CREATE DATABASE fraud_prediction_project;

## CREATE table 
CREATE EXTERNAL TABLE fraud_prediction_project.transactions (
    idx BIGINT,
    trans_date_trans_time STRING,
    cc_num BIGINT,
    merchant STRING,
    category STRING,
    amt DOUBLE,
    first STRING,
    last STRING,
    gender STRING,
    street STRING,
    city STRING,
    state STRING,
    zip STRING,
    lat DOUBLE,
    long DOUBLE,
    city_pop BIGINT,
    job STRING,
    dob STRING,
    trans_num STRING,
    unix_time BIGINT,
    merch_lat DOUBLE,
    merch_long DOUBLE,
    is_fraud INT,
    source STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
   'separatorChar' = ',',
   'quoteChar' = '"'
)
LOCATION 's3://anmol-fraud-detection-project/'
TBLPROPERTIES ('skip.header.line.count'='1');



## perform data profiling process before moving to EDA
## Check for Duplicates
SELECT trans_num, COUNT(*) AS cnt
FROM transactions
GROUP BY trans_num
HAVING COUNT(*) > 1 
## Dataset has zero Duplicates

## Check for null and missing values across key columns
SELECT
    SUM(CASE WHEN trans_date_trans_time IS NULL THEN 1 ELSE 0 END) AS null_trans_time,
    SUM(CASE WHEN amt IS NULL THEN 1 ELSE 0 END) AS null_amt,
    SUM(CASE WHEN category IS NULL THEN 1 ELSE 0 END) AS null_category,
    SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END) AS null_gender,
    SUM(CASE WHEN dob IS NULL THEN 1 ELSE 0 END) AS null_dob,
    SUM(CASE WHEN merchant IS NULL THEN 1 ELSE 0 END) AS null_merchant,
    SUM(CASE WHEN is_fraud IS NULL THEN 1 ELSE 0 END) AS null_is_fraud,
    SUM(CASE WHEN lat IS NULL THEN 1 ELSE 0 END) AS null_lat,
    SUM(CASE WHEN merch_lat IS NULL THEN 1 ELSE 0 END) AS null_merch_lat,
    COUNT(*) AS total_rows
FROM transactions;
## Dataset has zero null and missing values 

## check for invalid/impossible transaction amt 
SELECT MIN(amt) AS min_amount,
       MAX(amt) AS max_amount,
       SUM(CASE WHEN amt < 0 THEN 1 ELSE 0 END) AS invalid_amount
FROM transactions
## All the transaction amount are legit

## check lat/long validity (merchant & card holder)
SELECT SUM(CASE WHEN lat < -90 or lat > 90 THEN 1 ELSE 0 END) AS invalid_lat,
       SUM(CASE WHEN long < -180 or long > 180 THEN 1 ELSE 0 END) AS invalid_long,
       SUM(CASE WHEN merch_lat < -90 or merch_lat > 90 THEN 1 ELSE 0 END) AS invalid_merc_lat,
       SUM(CASE WHEN merch_long < -180 or merch_long > 180 THEN 1 ELSE 0 END) AS invalid_merc_long
FROM transactions
## Dataset has zero invalid lat/long for (merchant/card holder)

## check for dob range
SELECT MIN(dob) AS earliest_dob,
       MAX(dob) AS latest_dob
FROM transactions

## Create a new table name transactions_cleaned we will add a new 'Age' column in the Dataset.
CREATE TABLE fraud_prediction_project.transactions_cleaned
WITH (
    format = 'PARQUET',
    external_location = 's3://anmol-fraud-detection-project/cleaned-data/',
    write_compression = 'SNAPPY'
) AS
SELECT
    *,
    DATE_DIFF('year', DATE(dob), CURRENT_DATE) AS age
FROM fraud_prediction_project.transactions;

## view new table 
SELECT *
FROM transactions_cleaned
limit 1852394


## do some quick EDA on Dataset
## Which category is the risky and has the highest fraud rate ?? 
WITH table_1 AS (
                  SELECT category AS category,
                  ROUND(AVG(amt),2) AS avg_fraud_amt,
                  SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END) AS fraud_count,
                  COUNT(*) AS total_transactions
                  FROM transactions_cleaned
                  GROUP BY category
)
SELECT category,
       fraud_count,
       avg_fraud_amt,
       CAST(fraud_count AS DOUBLE)/total_transactions * 100 AS fraud_rate
FROM table_1
ORDER BY fraud_rate DESC
/* In this query i calculated the fraud_rate, fraud_count by category Which tells us the which category has the highest fraud_rate
shopping_net has 1.59%, misc_net has 1.30%, grocery_pos has 1.26% which is 2-3x higher than the overall fraud_rate i.e 0.58%. */

## Fraud rate by hour of day??
With hour_ AS ( 
               SELECT Hour(date_parse(trans_date_trans_time, '%Y-%m-%d %H:%i:%s')) AS Hour_of_day,
                      COUNT(*) AS total_transactions,
                      SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END) AS fraud_count
               FROM transactions_cleaned
               GROUP BY HOUR(date_parse(trans_date_trans_time, '%Y-%m-%d %H:%i:%s'))
)
SELECT Hour_of_day,
       fraud_count,
       ROUND(CAST(fraud_count AS DOUBLE)/total_transactions * 100, 3) AS fraud_rate_pct
FROM hour_ 
ORDER BY fraud_rate_pct DESC
/* This query tells us that most of the fraud_transactions are done in FROM 10PM to 3AM the peak is 10-11 PM (2.60%-2.54%) Recpectively and it is still high from 12 - 3AM aound 1.34% and after that is drops down,10PM - 3AM window shows 10-24x higher fraud_rate compare to all other hours comnined.*/

## Fraud rate by day of week and hour of day ??
WITH combo AS (
    SELECT
        DAY_OF_WEEK(date_parse(trans_date_trans_time, '%Y-%m-%d %H:%i:%s')) AS day_num,
        HOUR(date_parse(trans_date_trans_time, '%Y-%m-%d %H:%i:%s')) AS txn_hour,
        SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END) AS fraud_count,
        COUNT(*) AS total_transactions
    FROM transactions_cleaned
    GROUP BY
        DAY_OF_WEEK(date_parse(trans_date_trans_time, '%Y-%m-%d %H:%i:%s')),
        HOUR(date_parse(trans_date_trans_time, '%Y-%m-%d %H:%i:%s'))
)
SELECT
    day_num,
    CASE day_num
       WHEN 1 THEN 'Monday'
       WHEN 2 THEN 'Tuesday'
       WHEN 3 THEN 'Wednesday'
       WHEN 4 THEN 'Thursday'
       WHEN 5 THEN 'Friday'
       WHEN 6 THEN 'Saturday'
       WHEN 7 THEN 'Sunday'
       END AS day_name,
    txn_hour,
    fraud_count,
    total_transactions,
    ROUND(CAST(fraud_count AS DOUBLE) / total_transactions * 100, 3) AS fraud_rate_pct
FROM combo
WHERE total_transactions > 100  -- filter out tiny/noisy buckets
ORDER BY fraud_rate_pct DESC
/* Finding that the 10PM - 3AM danger window is consistent across every day of week. combining hour of day and day of week the 14 highest come from 10AM-11AM and 42 highest coome from 10AM-3AM, this proves that the 10PM-3AM window is not an artifact but a consistent pattern throughout the week.*/



## Average transaction amount: fraud vs. non-fraud?
SELECT is_fraud, 
       COUNT(*) AS transaction_count,
       ROUND(AVG(amt),2) AS avg_amount
FROM transactions_cleaned
GROUP BY is_fraud
/* The avg_amount of fraud transaction is 530.66 which is 8x times more that legit transaction, but the fraud_transaction_count is 190x times smaller compare to legit transaction.*/

## Distance between cardholder and merchant: fraud vs. non-fraud??
WITH distances AS (
    SELECT
        is_fraud,
        3959 * ACOS(
            COS(RADIANS(lat)) * COS(RADIANS(merch_lat)) *
            COS(RADIANS(merch_long) - RADIANS(long)) +
            SIN(RADIANS(lat)) * SIN(RADIANS(merch_lat))
        ) AS distance_miles
    FROM transactions_cleaned
)
SELECT
    is_fraud,
    COUNT(*) AS transaction_count,
    ROUND(AVG(distance_miles), 2) AS avg_distance_miles,
    ROUND(APPROX_PERCENTILE(distance_miles, 0.5), 2) AS median_distance_miles,
    ROUND(MIN(distance_miles), 2) AS min_distance,
    ROUND(MAX(distance_miles), 2) AS max_distance
FROM distances
GROUP BY is_fraud;
/* Finding: Cardholder-to-merchant distance shows no meaningful difference between fraud and legitimate transactions.Unlike time-of-day and transaction amount, distance does not appear to be a useful standalone predictor of fraud in this dataset.*/

## Monthly Fraud Trend??
-- Monthly Fraud Trend??
WITH month_year AS (
    SELECT 
        COUNT(*) AS transaction_count,
        SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END) AS fraud_count,
        YEAR(DATE_PARSE(trans_date_trans_time, '%Y-%m-%d %H:%i:%s')) AS year_num,
        MONTH(DATE_PARSE(trans_date_trans_time, '%Y-%m-%d %H:%i:%s')) AS month_num
    FROM transactions_cleaned
    GROUP BY 
        YEAR(DATE_PARSE(trans_date_trans_time, '%Y-%m-%d %H:%i:%s')),
        MONTH(DATE_PARSE(trans_date_trans_time, '%Y-%m-%d %H:%i:%s'))
)
SELECT 
    year_num,
    month_num,
    fraud_count,
    transaction_count,
    ROUND(CAST(fraud_count AS DOUBLE) / transaction_count * 100, 2) AS fraud_rate
FROM month_year
ORDER BY year_num, month_num;
/* Finding: Fraud rate declined from an early-2019 peak and stabilized, with December consistently showing the lowest fraud rate despite the highest transaction volume.*/

## fraud_rate by age group??
WITH age_buckets AS (
    SELECT
        is_fraud,
        CASE
            WHEN age BETWEEN 18 AND 25 THEN '18-25'
            WHEN age BETWEEN 26 AND 35 THEN '26-35'
            WHEN age BETWEEN 36 AND 45 THEN '36-45'
            WHEN age BETWEEN 46 AND 55 THEN '46-55'
            WHEN age BETWEEN 56 AND 65 THEN '56-65'
            WHEN age > 65 THEN '65+'
            ELSE 'Unknown'
        END AS age_group
    FROM transactions_cleaned
)
SELECT
    age_group,
    SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END) AS fraud_count,
    COUNT(*) AS total_transactions,
    ROUND(CAST(SUM(CASE WHEN is_fraud = 1 THEN 1 ELSE 0 END) AS DOUBLE) / COUNT(*) * 100, 3) AS fraud_rate_pct
FROM age_buckets
GROUP BY age_group
ORDER BY 
    CASE age_group
        WHEN '18-25' THEN 1
        WHEN '26-35' THEN 2
        WHEN '36-45' THEN 3
        WHEN '46-55' THEN 4
        WHEN '56-65' THEN 5
        WHEN '65+' THEN 6
        ELSE 7
    END;
## Finding: Fraud rate is meaningfully higher among older cardholders (56+), showing a mild age-based risk pattern.