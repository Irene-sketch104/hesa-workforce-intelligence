-- Run after importing hesa_table6_import.csv into dbo.hesa_table6_raw.
-- For first-time setup, create the database, import the CSV, then run this script.
IF DB_ID(N'HESA_Workforce') IS NULL
    EXEC(N'CREATE DATABASE HESA_Workforce');
GO

USE HESA_Workforce;
GO

SELECT
    COUNT(*) AS total_rows,

    SUM(CASE
        WHEN NULLIF(LTRIM(RTRIM(ukprn)), '') IS NULL
        THEN 1 ELSE 0
    END) AS missing_ukprn_rows,

    SUM(CASE
        WHEN NULLIF(LTRIM(RTRIM(fte_raw)), '') IS NULL
        THEN 1 ELSE 0
    END) AS missing_fte_rows,

    COUNT(DISTINCT academic_year) AS academic_year_count

FROM dbo.hesa_table6_raw;

-- Distinguish detail-level records from aggregate-level totals

USE HESA_Workforce;
GO

GO

CREATE OR ALTER VIEW dbo.vw_hesa_table6_typed
AS
SELECT
    NULLIF(LTRIM(RTRIM(ukprn)), '') AS ukprn,
    provider_name,
    country,
    region,
    academic_marker,
    atypical_marker,
    academic_year,
    occupation_category,
    fte_raw,

    -- Convert blank values to NULL before numeric conversion
    TRY_CONVERT(
        decimal(12, 2),
        NULLIF(LTRIM(RTRIM(fte_raw)), '')
    ) AS fte,

    -- Distinguish missing, invalid numeric and valid values
    CASE
        WHEN NULLIF(LTRIM(RTRIM(fte_raw)), '') IS NULL
            THEN 'Missing'
        WHEN TRY_CONVERT(
            decimal(12, 2),
            NULLIF(LTRIM(RTRIM(fte_raw)), '')
        ) IS NULL
            THEN 'Invalid numeric'
        ELSE 'Valid'
    END AS fte_status,

    -- Flag aggregate geographic representations
    CASE
        WHEN country = 'All' OR region = 'All'
            THEN 1
        ELSE 0
    END AS has_geography_all,

    -- Flag occupation total rows
    CASE
        WHEN occupation_category LIKE 'Total%'
            THEN 1
        ELSE 0
    END AS is_occupation_total

FROM dbo.hesa_table6_raw;
GO

-- Group occupation categories into three standardised staff groups

GO

CREATE OR ALTER VIEW dbo.vw_hesa_provider_year_fte
AS
SELECT
    ukprn,
    provider_name,
    country,
    region,
    academic_year,

    CASE occupation_category
        WHEN 'Total academic staff (excluding atypical)'
            THEN 'Academic'
        WHEN 'Total non-academic staff'
            THEN 'Non-academic'
        WHEN 'Total (excluding academic atypical)'
            THEN 'Total excluding academic atypical'
    END AS staff_group,
    fte,
    fte_status

FROM dbo.vw_hesa_table6_typed

-- Retain identified providers and one geographic representation
WHERE ukprn IS NOT NULL
    AND country <> 'All'
    AND region <> 'All'

-- Exclude academic atypical staff
    AND atypical_marker = 'Non-atypical'

-- Keep only the three published totals with matching markers
    AND (
        (
            occupation_category =
                'Total academic staff (excluding atypical)'
            AND academic_marker = 'Academic'
        )
        OR (
            occupation_category = 'Total non-academic staff'
            AND academic_marker = 'Non-academic'
        )
        OR (
            occupation_category =
                'Total (excluding academic atypical)'
            AND academic_marker = 'All'
        )
    );
GO
-- Spot-check staff group mapping and FTE values for the University of Bath (2024/25)
SELECT
    provider_name,
    academic_year,
    staff_group,
    fte,
    fte_status
FROM dbo.vw_hesa_provider_year_fte
WHERE ukprn = '10007850'
    AND academic_year = '2024/25'
ORDER BY staff_group;


---- Inspect the saved view definition
--SELECT OBJECT_DEFINITION(
--    OBJECT_ID('dbo.vw_hesa_provider_year_fte')
--) AS view_definition;

-- Check for duplicate provider-year-staff-group combinations
SELECT
    ukprn,
    academic_year,
    staff_group,
    COUNT(*) AS row_count
FROM dbo.vw_hesa_provider_year_fte
GROUP BY
    ukprn,
    academic_year,
    staff_group
HAVING COUNT(*) > 1;

-- Check for unmapped staff groups
SELECT
    COUNT(*) AS unmapped_rows
FROM dbo.vw_hesa_provider_year_fte
WHERE staff_group IS NULL;

-- Keep mutually exclusive staff categories for composition analysis
GO

CREATE OR ALTER VIEW dbo.vw_hesa_staff_composition
AS
SELECT
    ukprn,
    provider_name,
    country,
    region,
    academic_year,
    staff_group,
    fte,
    fte_status
FROM dbo.vw_hesa_provider_year_fte
WHERE staff_group IN ('Academic', 'Non-academic');
GO

-- Keep published totals excluding academic atypical staff
GO

CREATE OR ALTER VIEW dbo.vw_hesa_published_totals
AS
SELECT
    ukprn,
    provider_name,
    country,
    region,
    academic_year,
    fte AS total_fte_excluding_academic_atypical,
    fte_status
FROM dbo.vw_hesa_provider_year_fte
WHERE staff_group = 'Total excluding academic atypical';
GO

-- Verify the composition view
SELECT *
FROM dbo.vw_hesa_staff_composition
WHERE ukprn = '10007850'
    AND academic_year = '2024/25';

-- Verify the published totals view
SELECT *
FROM dbo.vw_hesa_published_totals
WHERE ukprn = '10007850'
    AND academic_year = '2024/25';

-- Assess FTE completeness by academic year and staff group
SELECT
    academic_year,
    staff_group,
    COUNT(*) AS provider_count,
    COUNT(fte) AS providers_with_fte,

    SUM(CASE
        WHEN fte_status = 'Missing' THEN 1
        ELSE 0
    END) AS providers_missing_fte,

    SUM(CASE
        WHEN fte_status = 'Invalid numeric' THEN 1
        ELSE 0
    END) AS providers_invalid_fte,

    CAST(
        100.0 * COUNT(fte) / NULLIF(COUNT(*), 0)
        AS decimal(5, 1)
    ) AS completeness_pct

FROM dbo.vw_hesa_staff_composition
GROUP BY
    academic_year,
    staff_group
ORDER BY
    academic_year,
    staff_group;


-- Check Bath's staff composition across all available years
SELECT
    academic_year,
    staff_group,
    fte,
    fte_status
FROM dbo.vw_hesa_staff_composition
WHERE ukprn = '10007850'
ORDER BY
    academic_year,
    staff_group;

-- Check Bath's published totals across all available years
SELECT
    academic_year,
    total_fte_excluding_academic_atypical,
    fte_status
FROM dbo.vw_hesa_published_totals
WHERE ukprn = '10007850'
ORDER BY academic_year;


-- Compare the sum of staff categories with published totals
WITH composition AS (
    SELECT
        ukprn,
        academic_year,
        MAX(CASE
            WHEN staff_group = 'Academic' THEN fte
        END) AS academic_fte,
        MAX(CASE
            WHEN staff_group = 'Non-academic' THEN fte
        END) AS non_academic_fte
    FROM dbo.vw_hesa_staff_composition
    GROUP BY
        ukprn,
        academic_year
)
SELECT
    t.academic_year,
    c.academic_fte,
    c.non_academic_fte,
    c.academic_fte + c.non_academic_fte
        AS combined_category_fte,
    t.total_fte_excluding_academic_atypical
        AS published_total_fte,
    c.academic_fte + c.non_academic_fte
        - t.total_fte_excluding_academic_atypical
        AS difference_fte
FROM dbo.vw_hesa_published_totals AS t
LEFT JOIN composition AS c
    ON t.ukprn = c.ukprn
    AND t.academic_year = c.academic_year
WHERE t.ukprn = '10007850'
ORDER BY t.academic_year;



-- Retrieve the previous academic year's published FTE
WITH annual_trend AS (
    SELECT
        academic_year,
        total_fte_excluding_academic_atypical AS total_fte,
        LAG(total_fte_excluding_academic_atypical) OVER (
            ORDER BY academic_year
        ) AS previous_year_fte
    FROM dbo.vw_hesa_published_totals
    WHERE ukprn = '10007850'
)

-- Calculate annual changes using published totals
SELECT
    academic_year,
    total_fte,
    previous_year_fte,
    total_fte - previous_year_fte AS yoy_change_fte,
    CAST(
        100.0 * (total_fte - previous_year_fte)
        / NULLIF(previous_year_fte, 0)
        AS decimal(10, 2)
    ) AS yoy_change_pct
FROM annual_trend
ORDER BY academic_year;

--COMPARE WITH OTHER SCHOOLS
-- Identify providers with complete composition data for all 11 years
WITH complete_composition AS (
    SELECT
        ukprn
    FROM dbo.vw_hesa_staff_composition
    WHERE academic_year BETWEEN '2014/15' AND '2024/25'
    GROUP BY ukprn
    HAVING COUNT(DISTINCT academic_year) = 11
        AND COUNT(*) = 22
        AND COUNT(fte) = 22
),

-- Identify providers with complete published totals for all 11 years
complete_totals AS (
    SELECT
        ukprn
    FROM dbo.vw_hesa_published_totals
    WHERE academic_year BETWEEN '2014/15' AND '2024/25'
    GROUP BY ukprn
    HAVING COUNT(DISTINCT academic_year) = 11
        AND COUNT(*) = 11
        AND COUNT(total_fte_excluding_academic_atypical) = 11
)

-- List regional comparison candidates using their latest-year details
SELECT
    t.ukprn,
    t.provider_name,
    t.region,
    t.total_fte_excluding_academic_atypical AS total_fte_2024_25
FROM dbo.vw_hesa_published_totals AS t
INNER JOIN complete_composition AS c
    ON t.ukprn = c.ukprn
INNER JOIN complete_totals AS p
    ON t.ukprn = p.ukprn
WHERE t.academic_year = '2024/25'
    AND t.region = 'South West'
ORDER BY
    t.total_fte_excluding_academic_atypical DESC;



-- Define regional comparators and flag the Bath–Bristol subgroup
GO

CREATE OR ALTER VIEW dbo.vw_hesa_selected_providers
AS
SELECT
    ukprn,
    provider_name,
    country,
    region,
    CASE ukprn
        WHEN '10007850' THEN 'Bath'
        WHEN '10007786' THEN 'Bristol'
        WHEN '10007792' THEN 'Exeter'
        WHEN '10007164' THEN 'UWE Bristol'
        WHEN '10000824' THEN 'Bournemouth'
    END AS provider_short_name,
    CASE
        WHEN ukprn = '10007850' THEN 'Focus institution'
        ELSE 'Regional comparator'
    END AS comparison_role,
    CASE
        WHEN ukprn IN ('10007850', '10007786', '10007164')
            THEN 1
        ELSE 0
    END AS is_local_comparator
FROM dbo.vw_hesa_published_totals
WHERE academic_year = '2024/25'
    AND ukprn IN (
        '10007850',
        '10007786',
        '10007792',
        '10007164',
        '10000824'
    );
GO


-- (2) Define the 3 provider Bath–Bristol comparison group
GO

CREATE OR ALTER VIEW dbo.vw_hesa_local_providers
AS
SELECT
    ukprn,
    provider_name,
    country,
    region,
    provider_short_name,
    comparison_role
FROM dbo.vw_hesa_selected_providers
WHERE ukprn IN (
    '10007850', -- University of Bath
    '10007786', -- University of Bristol
    '10007164'  -- University of the West of England, Bristol
);
GO

-- Verify the three selected providers
SELECT *
FROM dbo.vw_hesa_local_providers
ORDER BY provider_short_name;


------------------------------------------------------

-- Verify comparison group membership
SELECT
    provider_short_name,
    is_local_comparator
FROM dbo.vw_hesa_selected_providers
ORDER BY provider_short_name;