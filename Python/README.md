# Python — Hypothesis Testing & Fraud Prediction Model

This folder contains the Python analysis for the **Fraud Transaction Detection** project, picking up where the SQL exploratory work left off — validating fraud signals statistically, engineering features, and building a fraud prediction model.

File: [`Credit_card_fraud_prediction.ipynb`](./Credit_card_fraud_prediction.ipynb)

---

## 🎯 What This Notebook Does

1. Loads the cleaned dataset (from the Athena/S3 pipeline) into pandas
2. Runs formal hypothesis tests to validate which signals actually predict fraud
3. Engineers features and prepares data for modeling
4. Trains and compares three approaches to handling severe class imbalance
5. Tunes the classification threshold for a usable precision/recall tradeoff
6. Evaluates the final model with a confusion matrix, ROC curve, and feature importance

---

## 📦 Libraries Used

```python
pandas, numpy, matplotlib, seaborn
scipy.stats            # t-test, chi-square test
scikit-learn            # LogisticRegression, metrics, preprocessing
imbalanced-learn        # SMOTE, RandomUnderSampler
```

---

## 🧪 1. Hypothesis Testing

Before trusting any feature, each candidate signal was tested statistically rather than assumed to matter.

| # | Hypothesis | Test | Result |
|---|---|---|---|
| 1 | Transaction amount differs between fraud and non-fraud | Independent t-test | **t = 291.33, p ≈ 0.0** → Reject H₀. Amount is a significant signal. |
| 2 | Merchant category is related to fraud | Chi-square test | **χ² = 8,329.14, p ≈ 0.0** → Reject H₀. Category is a significant signal. |
| 3 | The 10PM–3AM "danger window" is related to fraud | Chi-square test | **χ² = 20,191.66, p ≈ 0.0** → Reject H₀. Time window is a significant signal. |
| 4 | Cardholder–merchant distance differs between fraud and non-fraud | Independent t-test | **t = 0.49, p = 0.62** → Fail to reject H₀. **No significant difference.** |

**Why this matters:** Test #4 is the important negative result — despite being an intuitive fraud indicator ("fraud happens far from home"), distance showed no statistical relationship to fraud in this dataset. It was excluded from the final model based on this evidence rather than gut feel, keeping the feature set lean and justified.

---

## 🧹 2. Feature Preparation

- Dropped identity/PII columns not useful for prediction (name, street, job, card number, etc.)
- One-hot encoded `category` (merchant category) and `gender`
- Engineered features: `hour` (extracted from transaction timestamp), `is_danger_window` (binary flag for 10PM–3AM), `distance_miles` (Haversine distance between cardholder and merchant)
- Final feature matrix: **19 features**, target: `is_fraud`

**Train/test split:**
```python
Train shape: (1,481,915, 19)   Test shape: (370,479, 19)
Train fraud rate: 0.521%       Test fraud rate: 0.521%
```
Split is stratified so both sets preserve the same (very low) fraud rate — critical for imbalanced classification.

**Feature scaling:** `StandardScaler` fit on the training set only, then applied to both train and test — this avoids data leakage from test-set statistics into training.

---

## ⚖️ 3. Handling Class Imbalance — Three Approaches Compared

With fraud at just ~0.5% of transactions, a naive model would just predict "not fraud" every time and still be 99.5% "accurate" while catching zero fraud. Three standard imbalance-handling techniques were trained and compared on identical test data:

### Approach A — Class-Weighted Logistic Regression
```python
LogisticRegression(class_weight='balanced')
```
```
ROC-AUC: 0.9553
Precision: 0.03 | Recall: 0.93 | F1: 0.07   (at default threshold 0.5)
```

### Approach B — SMOTE (Synthetic Oversampling)
```python
SMOTE(random_state=42)
# Original training shape: (1,481,915, 19) → After SMOTE: (2,948,388, 19)
```
```
ROC-AUC: 0.9554
Precision: 0.03 | Recall: 0.93 | F1: 0.07   (at default threshold 0.5)
```

### Approach C — Random Undersampling
```python
RandomUnderSampler(random_state=42)
# Original training shape: (1,481,915, 19) → After undersampling: (15,442, 19)
```
```
ROC-AUC: 0.9561
Precision: 0.03 | Recall: 0.93 | F1: 0.07   (at default threshold 0.5)
```

### Comparison & Decision

| Method | ROC-AUC | Training data impact |
|---|---|---|
| Class-weighted | 0.9553 | No change to training data |
| SMOTE | 0.9554 | ~2x training set size (synthetic rows) |
| Undersampling | 0.9561 | ~99% reduction in majority-class rows |

> **Conclusion:** All three methods perform within **less than 1 percentage point** of each other across precision, recall, and ROC-AUC — both at the default threshold and after tuning. This indicates the underlying fraud signal (driven by amount, time-of-day, and category) is strong enough that resampling strategy barely matters.
>
> **Class-weighting was selected as the final approach** — it achieves equivalent performance to SMOTE and undersampling with **zero synthetic data generation and zero data loss**, making it the most computationally efficient and simplest choice with no accuracy tradeoff.

---

## 🎚️ 4. Threshold Tuning

The default 0.5 probability threshold favors recall heavily but produces unusably low precision. A precision-recall curve was generated to find a better operating point:

```python
precision, recall, thresholds = precision_recall_curve(Y_test, Y_pred_weighted_prob)
```

| Threshold | Precision | Recall |
|---|---|---|
| 0.3 | 0.027 | 0.961 |
| 0.5 | 0.034 | 0.932 |
| 0.6 | 0.041 | 0.842 |
| **0.7 ✅ chosen** | **0.066** | **0.746** |
| 0.9 | 0.298 | 0.646 |
| 0.95 | 0.337 | 0.493 |
| 0.99 | 0.361 | 0.354 |

**Threshold = 0.7** was chosen as the operating point: it roughly **doubles precision** over the default threshold while still catching **75% of all fraud cases** — a reasonable balance for a fraud-review workflow where every flagged transaction has a manual-review cost.

---

## ✅ 5. Final Model Evaluation (Class-Weighted, Threshold = 0.7)

**Classification report:**

| Metric | Value |
|---|---|
| Precision | 0.07 |
| Recall | 0.75 |
| F1-score | 0.12 |
| Accuracy | 0.94 |
| **ROC-AUC** | **0.955** |

**Confusion matrix:**

| | Predicted Legit | Predicted Fraud |
|---|---|---|
| **Actual Legit** | 348,120 (TN) | 20,429 (FP) |
| **Actual Fraud** | 490 (FN) | 1,440 (TP) |

**ROC curve:**
```python
fpr, tpr, thresholds = roc_curve(Y_test, Y_pred_weighted_prob)
auc_score = roc_auc_score(Y_test, Y_pred_weighted_prob)  # 0.955
```
Plotted against a random-guess baseline (diagonal, AUC = 0.5) to visually confirm the model's discriminative power.

> **Interpreting the low precision:** With a 0.5% fraud rate, even a strong classifier will generate many false positives relative to true fraud cases in absolute terms. The **ROC-AUC of 0.955** is the more reliable indicator here — it shows the model separates fraud from non-fraud very well across all thresholds, and the 0.7 threshold was deliberately chosen to trade some recall for a meaningfully better precision than the default.

---

## 🔑 6. Feature Importance (Odds Ratios)

Logistic regression coefficients were converted to odds ratios for interpretability:

```python
coef_df['Odds_Ratio'] = np.exp(coef_df['Coefficient'])
```

| Feature | Odds Ratio | Interpretation |
|---|---|---|
| `amt` (transaction amount) | **5.07x** | Strongest predictor — higher amounts sharply raise fraud odds |
| `is_danger_window` | **3.22x** | Confirms the 10PM–3AM SQL/hypothesis-testing finding |
| `category_gas_transport` | 2.85x | High-risk category |
| `category_grocery_pos` | 2.08x | High-risk category |
| `category_grocery_net` | 1.76x | High-risk category |
| `hour` | 1.44x | General time-of-day effect (beyond the danger window flag) |
| `distance_miles` | 0.99x | Negligible effect — confirms hypothesis test #4 finding |
| `category_shopping_net` | 0.63x | Lower relative risk once amount/time are accounted for |

**Note:** `category_shopping_net` has a *negative* coefficient here despite showing the highest raw fraud rate in the SQL analysis — this is because logistic regression coefficients represent the effect of a feature **holding all others constant**. Shopping-net transactions tend to have specific amount/time patterns already captured by other features, so its independent marginal effect differs from its raw/unconditional fraud rate. This is a good example of why both univariate SQL exploration and multivariate modeling are useful — they answer different questions.

---

## ➡️ Where This Feeds Next

The final model's metrics, confusion matrix values, and ROC curve data were exported and used to build the **Model Performance** page of the Power BI dashboard. See the main [project README](../README.md) for the full pipeline and dashboard screenshots.
