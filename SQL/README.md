# SQL — Data Warehousing, Cleaning & Exploratory Analysis

This folder contains the SQL work for the **Fraud Transaction Detection** project, run on **AWS Athena** (Presto SQL engine) against raw transaction data stored in **AWS S3**.

File: [`Fraud_detection.sql`](./Fraud_detection.sql)

---

## 🎯 What This SQL Does

1. Creates an external Athena table pointing at raw CSV data in S3
2. Profiles the data for quality issues (duplicates, nulls, invalid values)
3. Builds a cleaned, Parquet-backed table with an engineered `age` feature
4. Runs exploratory SQL queries to surface fraud patterns before any modeling begins

---

## 🏗️ 1. Database & Table Setup

```sql
CREATE DATABASE fraud_prediction_project;
```

An **external table** is created over raw CSV files in S3 using the `OpenCSVSerde` SerDe, so Athena can query the data directly without loading it into a database:

```sql
CREATE EXTERNAL TABLE fraud_prediction_project.transactions (
    idx BIGINT, trans_date_trans_time STRING, cc_num BIGINT,
    merchant STRING, category STRING, amt DOUBLE,
    first STRING, last STRING, gender STRING,
    street STRING, city STRING, state STRING, zip STRING,
    lat DOUBLE, long DOUBLE, city_pop BIGINT, job STRING, dob STRING,
    trans_num STRING, unix_time BIGINT,
    merch_lat DOUBLE, merch_long DOUBLE,
    is_fraud INT, source STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"')
LOCATION 's3://anmol-fraud-detection-project/'
TBLPROPERTIES ('skip.header.line.count'='1');
```

---

## 🔍 2. Data Profiling — Quality Checks

Before any analysis, the raw data was validated for common issues:

| Check | Query Logic | Result |
|---|---|---|
| Duplicate transactions | `GROUP BY trans_num HAVING COUNT(*) > 1` | ✅ Zero duplicates |
| Nulls in key columns | `SUM(CASE WHEN col IS NULL THEN 1 ELSE 0 END)` across 9 critical fields | ✅ Zero nulls |
| Invalid transaction amounts | `MIN(amt)`, `MAX(amt)`, count of `amt < 0` | ✅ All amounts valid (no negatives) |
| Invalid coordinates (cardholder & merchant) | Range checks: lat ∈ [-90,90], long ∈ [-180,180] | ✅ All coordinates valid |
| Date-of-birth range sanity check | `MIN(dob)`, `MAX(dob)` | ✅ Reasonable range |

This dataset came in clean — no rows needed to be dropped or imputed.

---

## 🧱 3. Cleaned Table with Feature Engineering

A new table, `transactions_cleaned`, is materialized in **Parquet format with Snappy compression** (for faster downstream querying), adding a derived `age` column computed from date of birth:

```sql
CREATE TABLE fraud_prediction_project.transactions_cleaned
WITH (
    format = 'PARQUET',
    external_location = 's3://anmol-fraud-detection-project/cleaned-data/',
    write_compression = 'SNAPPY'
) AS
SELECT *, DATE_DIFF('year', DATE(dob), CURRENT_DATE) AS age
FROM fraud_prediction_project.transactions;
```

All exploratory analysis below runs against this cleaned table.

---

## 📊 4. Exploratory SQL Analysis & Findings

### Fraud rate by merchant category
Identifies which spending categories carry the highest fraud risk.

> **Finding:** `shopping_net` (1.59%), `misc_net` (1.30%), and `grocery_pos` (1.26%) have fraud rates **2–3x higher** than the overall average of 0.58%.

### Fraud rate by hour of day
```sql
SELECT Hour(date_parse(trans_date_trans_time, '%Y-%m-%d %H:%i:%s')) AS Hour_of_day, ...
```
> **Finding:** Fraud is heavily concentrated between **10 PM and 3 AM**, peaking at 10–11 PM (2.60%–2.54%). This window shows a **10–24x higher fraud rate** than all other hours combined.

### Fraud rate by day of week × hour of day
Cross-tabs hour-of-day findings against day of week to check if the pattern is a fluke or consistent.

> **Finding:** The 10 PM–3 AM danger window holds **across every day of the week** — of the top hour/day combinations, 14 of the top 14 and 42 of the top 42 fall inside this window. This is a structural pattern, not noise.

### Average transaction amount: fraud vs. legitimate
```sql
SELECT is_fraud, COUNT(*) AS transaction_count, ROUND(AVG(amt),2) AS avg_amount
FROM transactions_cleaned GROUP BY is_fraud
```
> **Finding:** Fraudulent transactions average **$530.66**, roughly **8x higher** than legitimate transactions — despite occurring **~190x less frequently**.

### Cardholder–merchant distance: fraud vs. legitimate
Uses the Haversine formula (via `ACOS`/`RADIANS`) to compute distance in miles between cardholder and merchant location.

> **Finding:** No meaningful difference in distance between fraud and legitimate transactions. Unlike time-of-day and amount, **distance is not a useful standalone fraud predictor** in this dataset.

### Monthly fraud trend
Aggregates fraud rate by year/month to check for seasonality.

> **Finding:** Fraud rate declined from an early-2019 peak and stabilized. **December consistently shows the lowest fraud rate**, despite having the highest transaction volume.

### Fraud rate by age group
Buckets cardholders into age ranges (18–25, 26–35, ..., 65+) and computes fraud rate per bucket.

> **Finding:** Fraud rate is **meaningfully higher among older cardholders (56+)**, showing a mild but consistent age-based risk pattern.

---

## ➡️ Why This Matters

These SQL-driven findings directly shaped the feature engineering and hypothesis testing done later in Python:
- **Amount**, **hour-of-day / danger window**, and **merchant category** were carried forward as model features because they showed strong, statistically distinguishable patterns here.
- **Cardholder-merchant distance** was tested but ultimately excluded from the final feature set, since this SQL analysis (later confirmed by a formal t-test in Python) showed no meaningful signal.

See the main [project README](../README.md) for how these findings connect to the hypothesis testing, ML modeling, and Power BI dashboard stages.
