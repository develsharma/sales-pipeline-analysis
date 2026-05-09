# Sales Pipeline Performance Analysis

A end-to-end SQL analytics project analysing sales performance across agents, teams, products, and accounts using a CRM sales pipeline dataset.

---

## Project Overview

This project simulates a real-world business analytics workflow starting from raw data exploration, progressing through multi-table joins, and delivering actionable insights across five analytical dimensions. Every query was written to answer a specific business question.

**Tools Used:** PostgreSQL, pgAdmin 4  
**Dataset Period:** October 2016 – December 2017  
**Total Records:** 8,800 sales opportunities across 4 related tables

---

## Dataset

| Table | Rows | Description |
|---|---|---|
| sales_pipeline | 8,800 | Core deals table opportunities, stages, close values |
| sales_teams | 35 | Agent to manager to region mapping |
| accounts | 85 | Company details: sector, size, location |
| products | 7 | Product catalogue with series and list prices |

**Data Quality Issues Identified and Handled:**
- `GTXPro` in sales_pipeline does not match `GTX Pro` in the products table normalised using CASE before joining, preventing silent exclusion of 1,480 deals
- 1,425 deals had no account recorded (NULL) excluded from account-level analysis and documented
- 5 agents exist in sales_teams with no pipeline activity excluded from performance analysis using join direction

---

## Section 1 — Pipeline Health Check

**Business Question:** What is the overall state of the sales pipeline?

**Approach:** Explored deal distribution across stages, calculated overall win rate against completed deals only (Won + Lost), summarised revenue metrics, and measured average deal cycle time.

**Key Findings:**
- Overall win rate is 63% across completed deals
- Average deal cycle from engagement to close is approximately 52 days
- 4,238 deals won generating total revenue of approximately $10M
- 1,589 deals still active in Engaging stage representing pipeline in progress

---

## Section 2 — Agent Performance Analysis

**Business Question:** Who are the top, mid, and low performing agents and how do they rank on revenue, deal volume, and conversion efficiency?

**Approach:** Built a two-CTE structure first aggregating raw counts per agent, then deriving win rate, revenue rank, win rank, and performance tier using PERCENT_RANK() to create relative rather than fixed threshold tiering.

**SQL Techniques:** CTEs, filtered aggregation, RANK(), PERCENT_RANK(), CASE, NULLIF, COALESCE

**Key Findings:**
- Performance tier based on relative conversion rate within the team top 25%, middle 50%, bottom 25%
- Clear separation between high-revenue agents and high-conversion agents the two do not always overlap
- Agents with highest conversion rates do not always generate the most revenue, revealing two distinct selling profiles across the team

---

## Section 3 — Regional and Team Analysis

**Business Question:** Which regions and managers are performing best, and who are the standout agents within each region?

**Join:** sales_pipeline - sales_teams on sales_agent

**Approach:** Three separate queries at three different grains regional summary, manager summary, and agent-within-region ranking. Grain separation was required because each region has two managers, making a single query impossible without corrupting aggregations.

**SQL Techniques:** JOIN, GROUP BY at multiple grains, PARTITION BY for within-region ranking, RANK(), NTILE()

**Key Findings:**

*Regional Level:*
- West leads on both revenue ($3.57M) and win rate (63.94%) despite fewer completed deals than Central quality over quantity approach
- Central is the most active region with 2,604 completed deals but the lowest win rate and average deal value
- East has the highest average deal value ($1,663) but lowest total revenue — strong closers who are under-prospecting

*Manager Level:*
- Managers with lower deal volumes consistently show higher win rates across all three regions a structural pattern not individual behaviour
- Cara Losch achieves the highest win rate among all managers; Melvin Marxen drives highest volume but lower conversion efficiency
- Neither approach is wrong the right balance depends on company growth strategy

*Agent Level:*
- The volume vs efficiency trade-off repeats at agent level confirming it is a team-wide characteristic
- Two distinct profiles identified: selective closers (Versie Hillebrand, Wilburn Farren, Rosalina Dieter) and volume hunters (Darcel Schlecht, Donn Cantrell, Markita Hansen)
- **Key insight for coaching:** agents in the same performance tier require different interventions selective closers need more qualified opportunities, volume hunters need conversion coaching. A one-size programme would miss this entirely

---

## Section 4 — Product Performance Analysis

**Business Question:** Which products and series generate the most revenue? Which have the best win rates? Are agents specialising in certain products?

**Join:** sales_pipeline - products on product name  
**Data Quality Fix:** GTXPro normalised to GTX Pro via CASE in join condition before aggregation

**Approach:** Three queries at three grains product level, series level, and agent-product matrix. Anti-join verification run before analysis to confirm join integrity.

**SQL Techniques:** CASE in JOIN condition, three-CTE structure, PARTITION BY sales_agent for within-agent product ranking, anti-join for data quality verification

**Key Findings:**

*Product Level:*
- MG Special (list price $55) has the highest win rate (64.84%) but generates the least revenue — easy to sell, low value
- GTK 500 (list price $26,768) has the lowest win rate and fewest deals hardest to close but highest value per deal
- Mid-range GTX series products ($4,000–$5,500) offer the best balance of win rate and deal value the most efficient revenue generators

*Series Level:*
- GTX series dominates on both revenue and win rate driven by having the most products (4 of 7) and widest price range
- No trade-off at series level unlike product level GTX wins on every dimension

*Agent Specialisation:*
- Nearly 50% of agents rely on GTX Pro as their primary revenue product
- **Business risk:** heavy concentration in one product makes the team vulnerable a pricing change or competitive threat to GTX Pro directly impacts half the sales force
- Recommendation: cross-train agents on GTX Plus Pro (similar series, higher list price) to build resilience and increase average deal value

---

## Section 5 — Account Analysis

**Business Question:** Which sectors generate the most revenue? Who are the top accounts? Do larger companies buy bigger deals?

**Join:** sales_pipeline - accounts on account name  
**Data Quality Note:** 1,425 deals excluded due to NULL account values. All 85 named accounts in sales_pipeline matched successfully to the accounts reference table — no genuine mismatches found.

**Approach:** Three queries at three grains sector summary, top account ranking, and company size bucket analysis using employee count as size proxy.

**SQL Techniques:** INNER JOIN, COUNT(DISTINCT), SUM() OVER () for grand totals, CASE for size bucketing, wrapper subquery for top N filtering

**Key Findings:**

*Sector Level:*
- Retail leads on total revenue through volume 17 of 85 accounts are retail, the most of any sector
- Marketing leads on win rate despite mid-level revenue — fewer accounts but higher conversion efficiency
- Finance has the lowest win rate but ranks 5th on revenue — deals are hard to close but high value when won, suggesting a different sales approach is needed for finance accounts

*Top Accounts:*
- Kan-Code (software) is the single highest revenue account software sector dominates individual account rankings despite retail leading at sector level
- 9 of top 10 accounts are US-based international accounts appear underpenetrated
- No clear retail presence in top 10 despite sector dominance confirms retail revenue is driven by volume of small accounts not large individual relationships

*Company Size vs Deal Value:*
- Average deal value increases modestly from Small to Enterprise range of approximately $200 to $2,500
- Total revenue and account count both increase with company size
- Gap between small and enterprise deal values is narrower than expected given budget differences suggests pricing strategy is not fully capitalising on enterprise account capacity

---

## Key SQL Concepts Demonstrated

- Multi-table JOINs (INNER JOIN, LEFT JOIN) with data quality verification
- Common Table Expressions (CTEs) for multi-layer calculations
- Filtered aggregation using FILTER (WHERE) 
- Window functions: RANK(), DENSE_RANK(), PERCENT_RANK(), NTILE(), PARTITION BY
- Data quality handling: NULLIF, COALESCE, anti-join verification, CASE-based normalisation
- Grain management separate queries for separate levels of aggregation
- Business metric derivation: conversion rate, win rate, performance tiering, deal cycle time

---

## Data Source

Dataset sourced from Maven Analytics Sales Pipeline practice dataset. Used for portfolio and learning purposes only.
