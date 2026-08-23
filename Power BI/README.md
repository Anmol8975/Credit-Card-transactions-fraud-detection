# Power BI — Fraud Risk Dashboard

This folder contains the Power BI deliverable for the **Fraud Transaction Detection** project — a two-page interactive dashboard that turns the SQL/Python analysis into a decision-ready visual tool.

File: `Fraud_Detection.pbix`

---

## 🎯 Purpose

While the SQL and Python work answer "what patterns exist in fraud data" and "how well can we predict it," this dashboard answers **"how would a fraud analyst or stakeholder actually use this day-to-day?"** — combining exploratory pattern analysis with model transparency in one tool.

---

## 📄 Page 1 — Fraud Risk Patterns

**Purpose:** Give an analyst a fast, filterable view of where and when fraud is concentrated.

| Visual | What it shows |
|---|---|
| KPI cards | Fraud Rate (0.52%), Total Transactions (1.85M), Fraud Transaction count (9.65K), Total Fraud Amount ($5.12M) |
| Fraud Rate by Age Group | Column chart, sorted descending, confirms older cardholders (56–65, 65+) carry the highest fraud rate |
| AVG Fraud Amount vs. AVG Legit Amount | Side-by-side comparison — fraud transactions average ~8x higher value than legitimate ones |
| Fraud Rate by Category | Horizontal bar chart with gradient shading and data labels, ranked by risk |
| Total Transactions & Fraud Rate by Hour | Dual-axis combo chart (bars = volume, line = fraud rate) — visualizes the 10PM–3AM "danger window" found in SQL analysis |

**Slicers:** Select Category, Select Gender

---

## 📄 Page 2 — Model Performance

**Purpose:** Make the machine learning model's behavior transparent and auditable — not just "it works," but *how well*, *where it fails*, and *why this threshold was chosen*.

| Visual | What it shows |
|---|---|
| KPI cards | Precision (0.07), Recall (0.75), F1-score (0.12), ROC-AUC (0.96) — all at the chosen threshold of 0.7 |
| Confusion Matrix | Matrix visual with conditional formatting — correct predictions (diagonal) shaded darker than errors, so accuracy is readable at a glance |
| Threshold Comparison Table | Precision/recall at thresholds 0.5, 0.7, and 0.9, with the chosen threshold (0.7) highlighted |
| ROC Curve | Line chart of true positive rate vs. false positive rate, plotted against a dashed diagonal baseline (random-guess reference) to visually confirm model skill |


---

## 🎨 Design & Theming

- Custom **plum/mauve color theme** (`theme/power_bi_theme.json`) applied via **View → Themes → Browse for themes**, keeping KPI cards, charts, and headers visually consistent across both pages.
- Correct/incorrect prediction cells in the confusion matrix use conditional formatting rather than static colors, so the visual updates automatically if the underlying data changes.
- Page navigation buttons (top of each page) let users switch between "Fraud Risk Patterns" and "Model Performance" without relying on the bottom tab strip — active page is visually distinguished from the inactive one.

---

## 🧩 Data Sources Feeding This Dashboard

| Table | Origin | Used for |
|---|---|---|
| `transactions_cleaned` | AWS Athena (Parquet, from S3) | Page 1 — all fraud pattern visuals |
| `ConfusionMatrix` | Manually entered (`Enter Data`), values from the Python notebook's final model evaluation | Page 2 — confusion matrix |
| `ThresholdComparison` | Manually entered (`Enter Data`), values from the Python notebook's precision-recall curve | Page 2 — threshold table |
| `roc_curve_data` | Exported from Python (`fpr`, `tpr` arrays from `roc_curve()`), imported via Get Data → Text/CSV | Page 2 — ROC curve |

> Note: Model outputs (confusion matrix, threshold table, ROC points) are static exports from the trained model in the notebook, not live-recalculated in Power BI — this dashboard visualizes model results, it doesn't retrain or re-score data.

---

## 🖥️ How to Open

1. Install [Power BI Desktop](https://powerbi.microsoft.com/desktop/) (free, Windows only).
2. Open `Fraud_Detection.pbix`.
3. If prompted about data source credentials/paths (for the Athena/S3-sourced table), you may need to either reconnect to your own data source or use the static exported tables — the `.pbix` includes cached data so visuals will still render even without a live connection.

---

## ➡️ How This Connects

This dashboard is the final stage of the pipeline: **AWS S3 → AWS Athena (SQL) → Python (hypothesis testing + modeling) → Power BI**. See the main [project README](../README.md) for the full end-to-end writeup, and the `sql/` and `notebook/` folders for how each number on these pages was derived.
