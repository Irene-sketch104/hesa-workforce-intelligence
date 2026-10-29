# Data dictionary and schema mapping

## Source-to-SQL mapping

All raw fields are imported as nullable `nvarchar`. `ukprn` remains text even though its values contain digits.

| HESA CSV header | Raw SQL field | Meaning |
|---|---|---|
| UKPRN | ukprn | Provider identifier |
| HE provider | provider_name | Published provider name |
| Country of HE provider | country | Country or aggregate label |
| Region of HE provider | region | Region or aggregate label |
| Academic marker | academic_marker | Academic, Non-academic or All |
| Atypical marker | atypical_marker | Staff atypical-status marker |
| Academic year | academic_year | Academic year label, e.g. 2024/25 |
| Activity standard occupational classification | occupation_category | Occupation detail or published total category |
| Number | fte_raw | Source FTE value retained as text |

The typed view derives `fte` as `decimal(12,2)`, `fte_status` as Missing / Invalid numeric / Valid, and flags `has_geography_all` and `is_occupation_total`. Missing source values remain NULL; they are not converted to zero.

## SQL views

| View | Grain / purpose |
|---|---|
| vw_hesa_table6_typed | One row per imported source row, with typed FTE and quality flags |
| vw_hesa_provider_year_fte | One row per UKPRN, academic year and retained staff group |
| vw_hesa_staff_composition | Academic and Non-academic only |
| vw_hesa_published_totals | One published total per UKPRN and academic year |
| vw_hesa_selected_providers | Five providers with 2024/25 names and geography |
| vw_hesa_local_providers | Bath, Bristol and UWE Bristol for SQL reference/export |

Selection requires non-null UKPRN, country and region other than All, `atypical_marker = 'Non-atypical'`, and the appropriate combination of occupation total and academic marker. These filters remove overlapping aggregate representations; they do not use arbitrary row deduplication.

## Power BI tables

| Table | Grain | Rows in this snapshot | Logical unique key |
|---|---|---:|---|
| vw_hesa_selected_providers | Provider | 5 | ukprn |
| DimAcademicYear | Academic year | 11 | academic_year |
| hesa_selected_staff_composition | Provider × year × staff group | 110 | ukprn + academic_year + staff_group |
| hesa_selected_published_totals | Provider × year | 55 | ukprn + academic_year |
| hesa_staff_coverage | Year × staff group | 22 | academic_year + staff_group |

These are logical keys and Power BI relationships, not SQL primary/foreign-key constraints on views. The two unfiltered source queries have load disabled but continue to feed reference queries.

## Analysis fields

| Field | Meaning / treatment |
|---|---|
| staff_group | Academic (excluding atypical) or Non-academic in the composition fact |
| fte | Category FTE; numeric zero is a valid observed value |
| total_fte_excluding_academic_atypical | Published overall FTE, excluding academic atypical |
| provider_short_name | Bath, Bristol, UWE Bristol, Exeter or Bournemouth |
| comparison_role | Focus institution for Bath; Regional comparator for others |
| is_local_comparator | 1 for Bath/Bristol/UWE Bristol; 0 for Exeter/Bournemouth |
| comparison_scope | DAX label: Local three or Other regional comparators |
| academic_year_start | Numeric first four characters of the year label; used for sorting |
| provider_count | Retained provider rows for one year and staff group |
| providers_with_fte | Count of non-null numeric FTE values in that group |
| completeness_pct | Power Query ratio providers_with_fte / provider_count; formatted as percentage |

In the SQL validation output, `completeness_pct` is expressed on a 0–100 scale. In Power Query it is a 0–1 ratio formatted as a percentage. Do not multiply the latter by 100 again.

## Relationships

All five relationships are active and single-direction, from the unique dimension key (1) to fact rows (*).

| Dimension field | Fact field |
|---|---|
| vw_hesa_selected_providers.ukprn | hesa_selected_staff_composition.ukprn |
| vw_hesa_selected_providers.ukprn | hesa_selected_published_totals.ukprn |
| DimAcademicYear.academic_year | hesa_selected_staff_composition.academic_year |
| DimAcademicYear.academic_year | hesa_selected_published_totals.academic_year |
| DimAcademicYear.academic_year | hesa_staff_coverage.academic_year |

## Measure definitions

| Measure | Definition |
|---|---|
| Published Total FTE | Sum of published totals within the current context |
| Staff Group FTE | Sum of category FTE within the current context |
| Bath FTE 2024/25 | Published total fixed to Bath and 2024/25 |
| Bath YoY Change % | (Bath 2024/25 total − Bath 2023/24 total) / Bath 2023/24 total |
| Bath FTE Growth % | (Bath 2024/25 total − Bath 2014/15 total) / Bath 2014/15 total |
| FTE Completeness % | SUM(providers_with_fte) / SUM(provider_count) |
| Non-academic Providers 2024/25 | Fixed-period, fixed-group provider_count |
| Non-academic Providers With FTE 2024/25 | Fixed-period, fixed-group providers_with_fte |
| Non-academic Providers Missing FTE 2024/25 | Difference between the preceding two counts |

FTE totals should be interpreted for a single year or per point on a time-series axis, not summed across years as a workforce size. Provider counts must not be summed across years or staff groups and interpreted as distinct institutions. Coverage visuals therefore present year/group rows and omit the table grand total.
