-- SALES PIPELINE PERFORMANCE ANALYSIS
-- Dataset  : sales_pipeline, sales_teams, products, accounts

-- DATA QUALITY NOTES
-- 1. GTXPro in sales_pipeline equals GTX Pro in products table
--    Handled via CASE normalisation before all product joins
-- 2. 1425 deals have NULL account and are excluded from account analysis
-- 3. 5 agents in sales_teams have no pipeline activity
--    Excluded via join direction with sales_pipeline on left


-- SECTION 0 : DATA QUALITY CHECKS
-- Run these before any analysis on a new dataset


-- 0.1 Row counts across all tables
SELECT
	'sales_pipeline' AS table_name,
	COUNT(*) AS row_count
FROM
	sales_pipeline
UNION ALL
SELECT
	'accounts',
	COUNT(*)
FROM
	accounts
UNION ALL
SELECT
	'products',
	COUNT(*)
FROM
	products
UNION ALL
SELECT
	'sales_teams',
	COUNT(*)
FROM
	sales_teams;


-- 0.2 Verify join integrity : sales_pipeline to sales_teams
-- Expected result : 0 unmatched rows
SELECT COUNT(*) AS unmatched_agents
FROM sales_pipeline sp
LEFT JOIN sales_teams st ON sp.sales_agent = st.sales_agent
WHERE st.sales_agent IS NULL;


-- 0.3 Verify join integrity : sales_pipeline to products
-- Expected result : GTXPro appears here as a mismatch
SELECT DISTINCT sp.product AS unmatched_products
FROM sales_pipeline sp
LEFT JOIN products p ON sp.product = p.product
WHERE p.product IS NULL;


-- 0.4 Verify join integrity : sales_pipeline to accounts
-- Checks for real account names missing from accounts table
SELECT COUNT(*) AS genuine_mismatches
FROM sales_pipeline sp
LEFT JOIN accounts a ON sp.account = a.account
WHERE a.account IS NULL
AND sp.account IS NOT NULL;


-- 0.5 Check NULL account values in sales_pipeline
SELECT COUNT(*) AS null_account_deals
FROM sales_pipeline
WHERE account IS NULL;


-- 0.6 Confirm uniqueness of join column in sales_teams
SELECT
    COUNT(sales_agent) AS total_rows,
    COUNT(DISTINCT sales_agent) AS unique_agents
FROM sales_teams;


-- SECTION 1 : PIPELINE HEALTH CHECK
-- Business Question : What is the overall state of our sales pipeline?


-- 1.1 Deal distribution across pipeline stages
SELECT
    deal_stage,
    COUNT(opportunity_id) AS deals,
    ROUND(
        COUNT(opportunity_id) * 100.0
        / SUM(COUNT(opportunity_id)) OVER ()
    , 2) AS pct_of_total
FROM sales_pipeline
GROUP BY deal_stage
ORDER BY deals DESC;


-- 1.2 Overall win rate across completed deals only
-- Won and Lost are completed outcomes
-- Prospecting and Engaging are still active and excluded from denominator
SELECT
    COUNT(opportunity_id) FILTER (WHERE deal_stage = 'Won') AS won_deals,
    COUNT(opportunity_id) FILTER (WHERE deal_stage = 'Lost') AS lost_deals,
    COUNT(opportunity_id) FILTER (WHERE deal_stage IN ('Won','Lost')) AS completed_deals,
    ROUND(
        COUNT(opportunity_id) FILTER (WHERE deal_stage = 'Won') * 100.0
        / NULLIF(
            COUNT(opportunity_id) FILTER (WHERE deal_stage IN ('Won','Lost'))
        , 0)
    , 2) AS overall_win_rate_pct
FROM sales_pipeline;


-- 1.3 Revenue summary from won deals
SELECT
    COUNT(opportunity_id) FILTER (WHERE deal_stage = 'Won')  AS total_won_deals,
    ROUND(SUM(close_value) FILTER (WHERE deal_stage = 'Won'), 2) AS total_revenue,
    ROUND(AVG(close_value) FILTER (WHERE deal_stage = 'Won'), 2) AS avg_deal_value,
    MIN(close_value) FILTER (WHERE deal_stage = 'Won') AS min_deal_value,
    MAX(close_value) FILTER (WHERE deal_stage = 'Won') AS max_deal_value
FROM sales_pipeline;


-- 1.4 Average deal cycle time for won deals only
-- Measures days from engage date to close date
SELECT
    ROUND(AVG(close_date - engage_date), 1) AS avg_days_to_close,
    PERCENTILE_CONT(0.5) WITHIN GROUP
        (ORDER BY close_date - engage_date)  AS median_days_to_close,
    MIN(close_date - engage_date) AS fastest_close_days,
    MAX(close_date - engage_date) AS slowest_close_days
FROM sales_pipeline
WHERE deal_stage = 'Won'
AND close_date IS NOT NULL
AND engage_date IS NOT NULL;


-- SECTION 2 : AGENT PERFORMANCE ANALYSIS
-- Business Question : Who are our top mid and low performers?


-- 2.1 Full agent metrics with rankings and performance tier
-- Performance tier is relative to the team using PERCENT_RANK
-- Top 25 percent of team by conversion = Top Performer
WITH
agent_raw AS (
    SELECT
        sales_agent,
        COALESCE(SUM(close_value) FILTER (WHERE deal_stage = 'Won'), 0) AS revenue,
        COUNT(opportunity_id) FILTER (WHERE deal_stage = 'Won') AS won_opportunity,
        COUNT(opportunity_id) FILTER (WHERE deal_stage = 'Lost') AS lost_opportunity,
        COUNT(opportunity_id) FILTER (WHERE deal_stage IN ('Won','Lost')) AS total_opportunity
    FROM sales_pipeline
    GROUP BY sales_agent
),
agent_metrics AS (
    SELECT
        sales_agent,
        revenue,
        won_opportunity,
        lost_opportunity,
        total_opportunity,
        ROUND(
            (won_opportunity * 100.0 / NULLIF(total_opportunity, 0))::NUMERIC
        , 2) AS conversion_rate,
        RANK() OVER (ORDER BY revenue DESC)          AS revenue_rank,
        RANK() OVER (ORDER BY won_opportunity DESC)  AS win_rank
    FROM agent_raw
),
final AS (
    SELECT
        *,
        NTILE(3) OVER (ORDER BY conversion_rate ASC) AS ntile_bucket,
        ROUND(
            (PERCENT_RANK() OVER (ORDER BY conversion_rate ASC) * 100.0)::NUMERIC
        , 2) AS conversion_percentile
    FROM agent_metrics
)
SELECT
    sales_agent,
    revenue,
    revenue_rank,
    won_opportunity,
    lost_opportunity,
    total_opportunity,
    win_rank,
    conversion_rate,
    conversion_percentile,
    CASE ntile_bucket
        WHEN 3 THEN 'Top Performer'
        WHEN 2 THEN 'Mid Performer'
        WHEN 1 THEN 'Low Performer'
    END AS performance_tier
FROM final
ORDER BY revenue_rank;


-- SECTION 3 : REGIONAL AND TEAM ANALYSIS
-- Business Question : How are regions managers and agents performing?
-- Join : sales_pipeline to sales_teams on sales_agent


-- 3.1 Regional performance summary
-- One row per region, 3 rows total
SELECT
    st.regional_office,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') AS won_deals,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Lost') AS lost_deals,
    COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')) AS completed_deals,
    COALESCE(
        ROUND(SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won'), 2)
    , 0) AS total_revenue,
    ROUND(AVG(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won'), 2) AS avg_deal_value,
    ROUND(
        COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') * 100.0
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0)
    , 2) AS win_rate_pct,
    RANK() OVER (
        ORDER BY SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won') DESC
    ) AS revenue_rank,
    RANK() OVER (
        ORDER BY
            COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0)
        DESC
    ) AS win_rate_rank
FROM sales_pipeline sp
JOIN sales_teams st ON sp.sales_agent = st.sales_agent
GROUP BY st.regional_office
ORDER BY revenue_rank;


-- 3.2 Manager performance summary
-- One row per manager, 6 rows total
-- Used for manager performance reviews
SELECT
    st.manager,
    st.regional_office,
    COUNT(DISTINCT sp.sales_agent) AS agents_managed,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') AS team_won_deals,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Lost') AS team_lost_deals,
    COALESCE(
        ROUND(SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won'), 2)
    , 0) AS team_revenue,
    ROUND(AVG(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won'), 2) AS avg_deal_value,
    ROUND(
        COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') * 100.0
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0)
    , 2) AS team_win_rate_pct,
    RANK() OVER (
        ORDER BY SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won') DESC
    ) AS overall_revenue_rank,
    RANK() OVER (
        PARTITION BY st.regional_office
        ORDER BY SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won') DESC
    ) AS rank_within_region
FROM sales_pipeline sp
JOIN sales_teams st ON sp.sales_agent = st.sales_agent
GROUP BY st.manager, st.regional_office
ORDER BY overall_revenue_rank;


-- 3.3 Agent performance within regions
-- PARTITION BY regional_office resets ranking per region
-- Shows overall rank and within-region rank side by side
WITH agent_raw AS (
    SELECT
        sp.sales_agent,
        st.manager,
        st.regional_office,
        COALESCE(SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won'), 0) AS revenue,
        COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') AS win_number,
        COUNT(*) FILTER (WHERE sp.deal_stage = 'Lost') AS lost_number,
        COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')) AS completed_deals
    FROM sales_pipeline sp
    JOIN sales_teams st ON sp.sales_agent = st.sales_agent
    GROUP BY sp.sales_agent, st.manager, st.regional_office
)
SELECT
    sales_agent,
    manager,
    regional_office,
    revenue,
    completed_deals,
    win_number,
    ROUND(win_number * 100.0 / NULLIF(completed_deals, 0), 2) AS win_rate,
    RANK() OVER (ORDER BY revenue DESC) AS overall_revenue_rank,
    RANK() OVER (
        PARTITION BY regional_office ORDER BY revenue DESC
    ) AS rank_within_region,
    CASE NTILE(3) OVER (
        PARTITION BY regional_office
        ORDER BY win_number * 1.0 / NULLIF(completed_deals, 0) DESC
    )
        WHEN 1 THEN 'Top Performer'
        WHEN 2 THEN 'Mid Performer'
        WHEN 3 THEN 'Low Performer'
    END AS performance_tier
FROM agent_raw
ORDER BY regional_office, rank_within_region;


-- SECTION 4 : PRODUCT PERFORMANCE ANALYSIS
-- Business Question : Which products drive revenue and win rate?
-- Are agents specialising in certain products?
-- Join : sales_pipeline to products on product name
-- Data fix : GTXPro normalised to GTX Pro in pipeline_clean CTE


-- 4.1 Product level summary
-- One row per product, 7 rows total
WITH pipeline_clean AS (
    SELECT
        opportunity_id,
        sales_agent,
        close_value,
        deal_stage,
        CASE WHEN product = 'GTXPro' THEN 'GTX Pro'
             ELSE product
        END AS product
    FROM sales_pipeline
),
product_raw AS (
    SELECT
        pc.product,
        p.series,
        p.sales_price,
        COALESCE(SUM(pc.close_value) FILTER (WHERE pc.deal_stage = 'Won'), 0) AS total_revenue,
        ROUND(AVG(pc.close_value) FILTER (WHERE pc.deal_stage = 'Won'), 2) AS avg_deal_value,
        COUNT(*) FILTER (WHERE pc.deal_stage = 'Won') AS win_number,
        COUNT(*) FILTER (WHERE pc.deal_stage = 'Lost') AS lost_number,
        ROUND(
            COUNT(*) FILTER (WHERE pc.deal_stage = 'Won') * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE pc.deal_stage IN ('Won','Lost')), 0)
        , 2) AS win_rate
    FROM pipeline_clean pc
    JOIN products p ON pc.product = p.product
    GROUP BY pc.product, p.series, p.sales_price
)
SELECT
    product,
    series,
    sales_price AS list_price,
    total_revenue,
    avg_deal_value,
    win_number,
    lost_number,
    win_rate,
    RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank,
    RANK() OVER (ORDER BY win_rate DESC) AS win_rank
FROM product_raw
ORDER BY revenue_rank;


-- 4.2 Product series comparison
-- One row per series, 3 rows total : GTX vs MG vs GTK
WITH pipeline_clean AS (
    SELECT
        close_value,
        deal_stage,
        CASE WHEN product = 'GTXPro' THEN 'GTX Pro'
             ELSE product
        END AS product
    FROM sales_pipeline
)
SELECT
    p.series,
    COUNT(*) FILTER (WHERE pc.deal_stage = 'Won') AS won_deals,
    ROUND(SUM(pc.close_value) FILTER (WHERE pc.deal_stage = 'Won'), 2) AS total_revenue,
    ROUND(AVG(pc.close_value) FILTER (WHERE pc.deal_stage = 'Won'), 2) AS avg_deal_value,
    ROUND(
        COUNT(*) FILTER (WHERE pc.deal_stage = 'Won') * 100.0
        / NULLIF(COUNT(*) FILTER (WHERE pc.deal_stage IN ('Won','Lost')), 0)
    , 2) AS win_rate,
    RANK() OVER (
        ORDER BY SUM(pc.close_value) FILTER (WHERE pc.deal_stage = 'Won') DESC
    ) AS revenue_rank
FROM pipeline_clean pc
JOIN products p ON pc.product = p.product
GROUP BY p.series
ORDER BY revenue_rank;


-- 4.3 Agent x product performance matrix
-- PARTITION BY sales_agent resets rank per agent
-- Use to identify product specialisation patterns
WITH pipeline_clean AS (
    SELECT
        opportunity_id,
        sales_agent,
        close_value,
        deal_stage,
        CASE WHEN product = 'GTXPro' THEN 'GTX Pro'
             ELSE product
        END AS product
    FROM sales_pipeline
),
product_raw AS (
    SELECT
        pc.sales_agent,
        pc.product,
        p.series,
        p.sales_price,
        COALESCE(SUM(pc.close_value) FILTER (WHERE pc.deal_stage = 'Won'), 0) AS total_revenue,
        ROUND(AVG(pc.close_value) FILTER (WHERE pc.deal_stage = 'Won'), 2) AS avg_deal_value,
        COUNT(*) FILTER (WHERE pc.deal_stage = 'Won') AS win_number,
        COUNT(*) FILTER (WHERE pc.deal_stage = 'Lost') AS lost_number,
        ROUND(
            COUNT(*) FILTER (WHERE pc.deal_stage = 'Won') * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE pc.deal_stage IN ('Won','Lost')), 0)
        , 2) AS win_rate
    FROM pipeline_clean pc
    JOIN products p ON pc.product = p.product
    GROUP BY pc.sales_agent, pc.product, p.series, p.sales_price
)
SELECT
    *,
    RANK() OVER (PARTITION BY sales_agent ORDER BY total_revenue DESC) AS revenue_rank_per_agent,
    RANK() OVER (PARTITION BY sales_agent ORDER BY win_rate DESC) AS win_rank_per_agent,
    RANK() OVER (PARTITION BY product ORDER BY win_rate DESC) AS win_rank_per_product
FROM product_raw
ORDER BY sales_agent, revenue_rank_per_agent;


-- 4.4 Product specialisation summary
-- Which product do most agents rely on as their primary revenue source?
WITH pipeline_clean AS (
    SELECT
        opportunity_id,
        sales_agent,
        close_value,
        deal_stage,
        CASE WHEN product = 'GTXPro' THEN 'GTX Pro'
             ELSE product
        END AS product
    FROM sales_pipeline
),
product_raw AS (
    SELECT
        pc.sales_agent,
        pc.product,
        COALESCE(SUM(pc.close_value) FILTER (WHERE pc.deal_stage = 'Won'), 0) AS total_revenue,
        ROUND(
            COUNT(*) FILTER (WHERE pc.deal_stage = 'Won') * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE pc.deal_stage IN ('Won','Lost')), 0)
        , 2) AS win_rate
    FROM pipeline_clean pc
    JOIN products p ON pc.product = p.product
    GROUP BY pc.sales_agent, pc.product
),
ranked AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY sales_agent ORDER BY total_revenue DESC) AS revenue_rank
    FROM product_raw
)
SELECT
    product,
    COUNT(sales_agent)       AS agents_relying_on_this,
    ROUND(AVG(total_revenue), 2) AS avg_revenue,
    ROUND(AVG(win_rate), 2)  AS avg_win_rate
FROM ranked
WHERE revenue_rank = 1
GROUP BY product
ORDER BY agents_relying_on_this DESC;


-- SECTION 5 : ACCOUNT ANALYSIS
-- Business Question : Which sectors and accounts drive revenue?
-- Do larger companies buy bigger deals?
-- Join : sales_pipeline to accounts on account
-- Note : 1425 NULL account deals excluded via INNER JOIN


-- 5.1 Sector level revenue and win rate
-- Includes account count and proportion of total accounts per sector
SELECT
    a.sector,
    COUNT(DISTINCT sp.account) AS accounts_in_sector,
    SUM(COUNT(DISTINCT sp.account)) OVER () AS total_accounts,
    ROUND(
        COUNT(DISTINCT sp.account) * 100.0
        / SUM(COUNT(DISTINCT sp.account)) OVER (), 1) AS pct_of_total_accounts,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') AS won_deals,
    ROUND(SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won'), 2) AS total_revenue,
    ROUND(AVG(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won'), 2) AS avg_deal_value,
    ROUND(
        COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') * 100.0
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0)
    , 2) AS win_rate_pct,
    RANK() OVER (
        ORDER BY SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won') DESC
    ) AS revenue_rank,
    RANK() OVER (
        ORDER BY
            COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0)
        DESC
    ) AS win_rate_rank
FROM sales_pipeline sp
INNER JOIN accounts a ON sp.account = a.account
GROUP BY a.sector
ORDER BY revenue_rank;


-- 5.2 Top 10 accounts by revenue
-- Brings in sector location and employee count for context
SELECT * FROM (
    SELECT
        sp.account,
        a.sector,
        a.office_location,
        a.employees,
        COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')) AS total_deals,
        COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') AS won_deals,
        ROUND(SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won'), 2) AS total_revenue,
        ROUND(AVG(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won'), 2) AS avg_deal_value,
        ROUND(
            COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') * 100.0
            / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0)
        , 2) AS win_rate_pct,
        RANK() OVER (
            ORDER BY SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won') DESC
        ) AS revenue_rank
    FROM sales_pipeline sp
    INNER JOIN accounts a ON sp.account = a.account
    GROUP BY sp.account, a.sector, a.office_location, a.employees
) AS ranked
WHERE revenue_rank <= 10
ORDER BY revenue_rank;


-- 5.3 Company size vs deal value
-- Do larger companies buy bigger deals?
-- Size defined by employee count
-- Assumption documented : no explicit size definition provided by stakeholder
SELECT
    CASE
        WHEN a.employees < 500  THEN '1. Small'
        WHEN a.employees < 2000 THEN '2. Mid'
        WHEN a.employees < 5000 THEN '3. Large'
        ELSE                         '4. Enterprise'
    END AS company_size,
    COUNT(DISTINCT sp.account) AS total_accounts,
    COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') AS won_deals,
    ROUND(AVG(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won'), 2) AS avg_deal_value,
    ROUND(SUM(sp.close_value) FILTER (WHERE sp.deal_stage = 'Won'), 2) AS total_revenue,
    ROUND(
        COUNT(*) FILTER (WHERE sp.deal_stage = 'Won') * 100.0
        / NULLIF(COUNT(*) FILTER (WHERE sp.deal_stage IN ('Won','Lost')), 0)
    , 2) AS win_rate_pct
FROM sales_pipeline sp
INNER JOIN accounts a ON sp.account = a.account
GROUP BY company_size
ORDER BY company_size;
