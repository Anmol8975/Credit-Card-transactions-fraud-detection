# Fraud Transaction Detection

End-to-end fraud detection project: cleaned and analyzed 1.85M+ transactions in SQL, uncovered fraud patterns by time, category, and age via hypothesis testing, built a logistic regression model (ROC-AUC 0.96), and visualized insights in an interactive two-page Power BI dashboard.

---

## 📌 Project Overview

Credit card fraud is rare but costly — fraudulent transactions in this dataset make up just **0.52%** of all transactions, yet averaged **8x higher value** than legitimate ones. This project builds a full pipeline to detect fraud patterns and predict fraudulent transactions, from raw data in the cloud to a decision-ready dashboard.

**Pipeline:**

```
AWS S3 (raw data) → AWS Athena (SQL profiling + EDA) → Python (hypothesis testing + ML modeling) → Power BI (dashboard)
```

---

## 🗂️ Dataset

- **Source:** [Fraud Detection Dataset — Kaggle](https://www.kaggle.com/datasets/kartik2112/fraud-detection)
- **Size:** 1,852,394 transactions
- **Fraud rate:** 0.52%
- **Storage:** Raw CSV data stored in AWS S3, queried via AWS Athena (Presto SQL engine) using an external table
- **Fields:** transaction time, amount, merchant, category, cardholder demographics (age, gender, location), merchant location, and fraud label (`is_fraud`)

---

## ☁️ Step 1: AWS S3 + Athena — Data Warehousing & Profiling

Raw transaction data was stored in an S3 bucket and queried directly using **AWS Athena** with an external Hive-style table definition (SerDe: OpenCSVSerde).

```sql
CREATE EXTERNAL TABLE fraud_prediction_project.transactions (
    idx BIGINT, trans_date_trans_time STRING, cc_num BIGINT,
    merchant STRING, category STRING, amt DOUBLE,
    gender STRING, city STRING, state STRING, lat DOUBLE, long DOUBLE,
    dob STRING, is_fraud INT, ...
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
LOCATION 's3://anmol-fraud-detection-project/'
TBLPROPERTIES ('skip.header.line.count'='1');
```

### Data Quality Checks (via Athena SQL)

| Check | Result |
|---|---|
| Duplicate transactions | ✅ Zero duplicates |
| Null/missing values (key columns) | ✅ Zero nulls |
| Invalid transaction amounts (< 0) | ✅ None found |
| Invalid lat/long (cardholder & merchant) | ✅ All coordinates valid |

A cleaned table (`transactions_cleaned`) was materialized in **Parquet format with Snappy compression** for query performance, with a derived `age` column computed from date of birth.

### Key SQL-Driven Findings

**Fraud rate by category** — Online/digital categories carry the highest risk:
| Category | Fraud Rate |
|---|---|
| Shopping (Net) | 1.59% |
| Misc (Net) | 1.30% |
| Grocery (Pos) | 1.26% |
| Overall average | 0.58% |

**Fraud rate by hour** — A sharp "danger window" emerged:
> Fraud peaks between **10 PM–3 AM**, with the highest rates at 10–11 PM (2.60%–2.54%). This window shows **10–24x higher fraud rates** than all other hours combined — and the pattern holds consistently across every day of the week.

**Fraud rate by age group** — Older cardholders (56+) show meaningfully higher fraud exposure than younger groups.

**Average transaction amount** — Fraudulent transactions average **$530.66** vs. legitimate transactions' average, roughly **8x higher** — despite fraud transaction *count* being ~190x smaller than legitimate transaction count.

**Cardholder–merchant distance** — Tested but **not predictive**: no meaningful difference in distance between fraud and legitimate transactions.

**Monthly trend** — Fraud rate declined from an early-2019 peak and stabilized; December consistently shows the lowest fraud rate despite the highest transaction volume.

---

## 🐍 Step 2: Python — Hypothesis Testing

Statistical tests were run in Python (`scipy.stats`) to validate which signals were genuinely predictive of fraud before feeding them into a model.

| Hypothesis | Test | Result |
|---|---|---|
| Transaction amount differs for fraud vs. non-fraud | Independent t-test | **t = 291.33, p ≈ 0.0** → Reject H₀: significant difference |
| Merchant category relates to fraud | Chi-square test | **χ² = 8,329.14, p ≈ 0.0** → Reject H₀: significant relationship |
| "Danger window" (10PM–3AM) relates to fraud | Chi-square test | **χ² = 20,191.66, p ≈ 0.0** → Reject H₀: significant relationship |
| Cardholder–merchant distance differs for fraud | Independent t-test | **t = 0.49, p = 0.62** → Fail to reject H₀: no significant difference |

**Takeaway:** Transaction amount, merchant category, and time-of-day are all statistically validated fraud signals. Geographic distance between cardholder and merchant is not — it was excluded as a weak predictor based on this evidence, not intuition.

---

## 🤖 Step 3: Machine Learning — Fraud Prediction Model

### Approach

A **Logistic Regression** model was trained to predict `is_fraud`, using engineered features including transaction amount, hour of day, danger-window flag, cardholder-merchant distance, one-hot encoded merchant category, and gender.

- **Train/test split:** 80/20 (1,481,915 train / 370,479 test), stratified to preserve the 0.52% fraud rate in both sets.
- **Features scaled** with `StandardScaler` (fit on train only, to prevent data leakage).

### Handling Class Imbalance — Three Approaches Compared

Because fraud is rare (~0.5% of transactions), three imbalance-handling strategies were tested and compared:

| Method | ROC-AUC | Precision @0.7 | Recall @0.7 |
|---|---|---|---|
| Class-weighted Logistic Regression | 0.9553 | 0.066 | 0.746 |
| SMOTE (synthetic oversampling) | 0.9554 | 0.066 | 0.746 |
| Random undersampling | 0.9561 | 0.064 | 0.745 |

**Conclusion:** All three methods converged to statistically indistinguishable performance (<1 percentage point difference across precision, recall, and ROC-AUC). Given equivalent results, **class-weighting was selected as the final approach** — it requires no synthetic data generation (unlike SMOTE's ~2x training set expansion) and no data loss (unlike undersampling's ~99% reduction in majority-class training data), making it the most computationally efficient choice with zero performance tradeoff.

### Threshold Tuning

The default 0.5 classification threshold maximizes recall but produces very low precision. A precision-recall tradeoff analysis was run across multiple thresholds:

| Threshold | Precision | Recall |
|---|---|---|
| 0.3 | 0.027 | 0.961 |
| 0.5 | 0.034 | 0.932 |
| 0.6 | 0.041 | 0.842 |
| **0.7 (chosen)** | **0.066** | **0.746** |
| 0.9 | 0.298 | 0.646 |
| 0.95 | 0.337 | 0.493 |
| 0.99 | 0.361 | 0.354 |

**Threshold = 0.7** was selected as the operating point — it nearly doubles precision versus the default threshold while still catching 75% of fraud cases, a reasonable tradeoff for a real-world fraud review workflow where false positives carry a manual review cost.

### Final Model Performance (Threshold = 0.7)

| Metric | Value |
|---|---|
| Precision | 0.07 |
| Recall | 0.75 |
| F1-score | 0.12 |
| Accuracy | 0.94 |
| **ROC-AUC** | **0.96** |

**Confusion Matrix (Threshold = 0.7):**

| | Predicted Legit | Predicted Fraud |
|---|---|---|
| **Actual Legit** | 348,120 (TN) | 20,429 (FP) |
| **Actual Fraud** | 490 (FN) | 1,440 (TP) |

> ROC-AUC of 0.96 indicates strong overall discriminative ability. Precision remains low at any usable recall level — an expected outcome for extreme class imbalance (0.5% fraud rate) with a linear model, and a realistic reflection of the precision-recall tradeoff fraud teams navigate in practice.

### Feature Importance (Odds Ratios)

The strongest predictors of fraud, ranked by odds ratio:

| Feature | Odds Ratio | Interpretation |
|---|---|---|
| Transaction amount | 5.07x | Higher amounts sharply increase fraud odds |
| Danger window (10PM–3AM) | 3.22x | Confirms the time-based pattern found in SQL/EDA |
| Gas transport category | 2.85x | High-risk category |
| Grocery (pos) category | 2.08x | High-risk category |
| Cardholder-merchant distance | 0.99x | Negligible effect — confirms hypothesis test finding |

---

## 📊 Step 4: Power BI Dashboard

A two-page interactive dashboard was built to make both the exploratory findings and the model's performance accessible to non-technical stakeholders.

### Page 1 — Fraud Risk Patterns
- KPI cards: Fraud Rate, Total Transactions, Fraud Transaction Count, Total Fraud Amount
- Fraud Rate by Age Group
- Average Fraud Amount vs. Average Legit Amount
- Fraud Rate by Category
- Total Transactions & Fraud Rate by Hour (dual-axis combo chart)
- Slicers: Category, Gender

### Page 2 — Model Performance
- KPI cards: Precision, Recall, F1-score, ROC-AUC
- Confusion Matrix (color-coded by correct vs. incorrect predictions)
- Threshold comparison table (0.5 / 0.7 / 0.9)
- ROC Curve with random-guess baseline reference line

*(See `/dashboard` folder for the `.pbix` file and screenshots.)*

---

## 🛠️ Tools & Technologies

| Category | Tools |
|---|---|
| Cloud Storage | AWS S3 |
| Query Engine | AWS Athena (Presto SQL) |
| Data Format | Parquet (Snappy compression) |
| Language | Python (pandas, numpy, scipy, scikit-learn, imbalanced-learn) |
| Statistical Testing | t-test, chi-square test (scipy.stats) |
| Modeling | Logistic Regression (class-weighted, SMOTE, undersampling) |
| Visualization | Power BI |

---

## 📁 Repository Structure

```
fraud-transaction-detection/
├── README.md
├── sql/
│   └── Fraud_detection.sql
├── notebook/
│   └── Credit_card_fraud_prediction.ipynb
├── dashboard/
│   ├── Fraud_Detection.pbix
└── images/
    ├── page1_fraud_risk_patterns.png
    └── page2_model_performance.png
```

---

## 🔑 Key Takeaways

- Fraud is heavily concentrated in a **10PM–3AM time window**, online shopping/grocery categories, and among older cardholders — all statistically validated, not assumed.
- Cardholder-to-merchant distance is **not** a useful fraud signal in this dataset, despite being an intuitive one.
- A simple, well-tuned Logistic Regression with class weighting matches the performance of more complex resampling techniques (SMOTE, undersampling) — simplicity won without sacrificing accuracy.
- Precision-recall threshold tuning is essential for imbalanced fraud problems: the "best" model depends on the acceptable tradeoff between catching fraud (recall) and false alarms (precision) for the business context.

---

## 👤 Author

**Name:** Anmol Verma

**Email:** manojaashp.anm@gmail.com

