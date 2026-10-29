# Reproduction guide

## View the report

Download `powerbi/HESA_Workforce_Intelligence.pbix` and open it in Power BI Desktop. The file contains imported model data. Screenshots provide a static preview without Power BI. Refresh requires your own SQL Server source and connection settings.

## Rebuild the SQL source

1. Download the HESA Table 6 CSV linked in the README. Retain its source metadata separately. The project snapshot has 38 metadata rows before the nine-column header; inspect newer downloads rather than assuming the same layout.
2. Remove the metadata preamble, preserve all data cells and rename the header using `data_dictionary.md`. Save the prepared file as `hesa_table6_import.csv`.
3. In SSMS, create `HESA_Workforce` if absent. You may run only the opening database-creation batch of the SQL script first.
4. Import the prepared CSV as `dbo.hesa_table6_raw`. Use nullable text fields: `nvarchar(max)` for provider_name, region and occupation_category; `nvarchar(50)` for the other six fields. Preserve blanks for missing values. Verify the nine column names and inspect the import for truncation or conversion failures.
5. After the raw table exists, run `sql/01_hesa_data_preparation_and_validation.sql` in SSMS. It creates or alters six views and returns validation result sets. The script does not import the CSV, delete source rows or recreate an existing database.

The script is organised into SQL Server batches using GO. Existing raw data are a prerequisite. The distributed revision has been statically checked for view batch boundaries and duplicate definitions; it has not been executed against a SQL Server instance in the packaging environment.

## Refresh Power BI

Update the SQL Server data source to your server and the `HESA_Workforce` database, supply your own credentials, and refresh. The model uses Import mode. Confirm the source views exist before refreshing.

Power Query processing:

- Keep `vw_hesa_staff_composition` and `vw_hesa_published_totals` as unfiltered staging queries with load disabled.
- Reference the composition staging query to create `hesa_staff_coverage`. Add `has_fte = if [fte] = null then 0 else 1`, group by academic_year and staff_group, count rows as provider_count and sum has_fte as providers_with_fte. Divide the latter by the former for completeness_pct.
- Reference each staging query separately and inner-merge on ukprn with `vw_hesa_selected_providers`. Remove the nested merge column to create the two selected-provider facts. Do not filter the original staging query to five providers, because that would also restrict coverage.
- Keep academic_year and ukprn as text, FTE as fixed decimal, and counts as whole numbers.

The year dimension is the distinct academic_year list from the coverage summary. Its start-year column supports chronological sorting. See the data dictionary for relationships and KPI definitions.

## Expected checks for the project snapshot

| Check | Expected result |
|---|---|
| Imported rows / academic years | 238,113 / 11 |
| Raw missing UKPRN / raw missing FTE | 8,613 / 27,912 |
| Duplicate provider-year-staff-group keys after filtering | 0 |
| Unmapped retained staff groups | 0 |
| Selected-provider dimension | 5 unique UKPRNs |
| Comparison facts | 110 composition rows; 55 published-total rows |
| Coverage summary | 22 rows |
| Bath 2024/25 academic / non-academic / published total | 1,380 / 2,050 / 3,430 |
| Bath annual change / full-period growth | 2.39% / 26.10% |
| 2024/25 non-academic coverage | 228 in scope; 123 with FTE; 105 missing; 53.9% |

Test the scope slicer: no selection shows five providers; Local three shows Bath, Bristol and UWE Bristol. Bath KPI cards remain fixed. The coverage page retains its full-provider scope.

Later source releases may change these expected figures. Review the reporting definitions and snapshot before treating a mismatch as an implementation defect. Refresh and interactive behaviour require verification in Power BI Desktop; archive inspection alone is not a refresh test.
