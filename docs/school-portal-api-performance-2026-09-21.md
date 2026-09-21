# School portal API read performance — 2026-09-21

## Scope and status

Local backend development changes, on top of the uncommitted school teacher/deletion changes. No push or deployment, no schema/index changes, no production data access. Checked out HEAD remains 9a482cb. Fetch found four newer origin/development commits through 086eea6; they touch separate admin supplementary-monitor work and documentation. Preserve/reconcile those commits before eventual authorized delivery; no force push or branch reset.

## Changes

- Assignment list counts submissions with a grouped SQL query for only the displayed assignment IDs. It no longer eagerly joins/loads all student answers to obtain a count. The creator remains preloaded. List payload fields, audit logging, paging and supported UI sort modes are retained; ordering is limited to supported columns/directions.
- Assignment detail/submission pages no longer preload the assignment's entire grading history before applying their limits. Detail keeps ten recent submissions and counts by status; total comes from the same status counts. Detail includes parent assignment associations to avoid per-row category lookups.
- Snapshot counts displayed assignments' submissions in SQL and reads only the thirty recent grading records it returns. Student/teacher summary reads select only fields used in their response. All other response data, including audit logs, remains compatible.
- School teacher ownership is a database subquery, rather than materializing every teacher ID in Ruby. Creator filtering is an intersection with the existing school scope.
- Delegated student reads apply school, active year, active enrollment and exact granted year/class pairs directly to their enrollment join. The redundant enrollment-ID subquery is removed. Class choices in the same year use IN; different years remain separate OR branches. The catalogue uses the same helper. Empty grants still return no records; no cross-year/class Cartesian expansion.
- Authentication, bcrypt/password checking, per-request permission validation, token revocation and audit writes are not bypassed or cached across requests. No permission TTL cache or database migration was added.

## Measurements

Guarded Rails integration-request benchmark in test/performance/school_portal_benchmark.rb, loopback isolated PostgreSQL listening_rails_isolated_test. It creates synthetic rows inside a transaction and rolls back fixtures/audit writes, avoiding grading callbacks or external AI jobs. Each endpoint is warmed once then sampled seven times, with query cache disabled for measurements. Values below are medians in milliseconds, including Rails request processing and local database work, excluding external network/browser loading. Samples are not production service-level guarantees.

Owner dataset: 30 teachers, 400 students, 8 years, 30 assignments and 6,000 grading records (200 per assignment).

| Endpoint | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Assignment list, 20 rows | 592.62 | 16.19 | 97.3% |
| Assignment detail | 37.63 | 19.27 | 48.8% |
| Snapshot | 662.14 | 45.24 | 93.2% |

Separate maximum-grant scenario uses 300 class grants in one active year with 400 students:

| Endpoint | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Delegated student list | 478.82 | 24.05 | 95.0% |
| Authorized class catalogue | 44.59 | 23.61 | 47.0% |

The large-grant comparator explicitly reinstates only the original read predicates inside the benchmark process, never in a server or application configuration. Ordinary owner /me stayed around 6 ms. Ordinary owner students/teachers did not show a dependable gain; their modest timing differences reflect workload/run variation and are not presented as an improvement. Teacher-index query changes were not retained. The benefit depends on school size, number of grants, database/network latency and number of submissions.

Raw synthetic metrics: [performance JSON](performance/school-portal-api-2026-09-21.json). No credentials or real school data are included. Snapshot grading rows loaded fell from 6,030 (all plus recent) to 30; detail grading rows fell from 210 to 10. The assignment-list join previously returned 4,000 rows for a 20-assignment page and now reads 20 assignments without hydrating grading rows.

## Reproduction and verification

Use the documented isolated Rails environment from school-password-delegation.md. Run rails runner test/performance/school_portal_benchmark.rb. Set SCHOOL_BENCH_MANY_GRANTS=1 for the 300-class scenario; add SCHOOL_BENCH_LEGACY_GRANTS=1 only to compare its original predicates. Guardrails require test environment, the isolated flag, loopback DB host and exact isolated database name. All benchmark inserts roll back.

- Integration suites school_portal_read_performance_test.rb, school_password_delegation_test.rb and admin_api_authentication_test.rb: 32 tests, 606 assertions, zero failures/errors. Checks returned counts against deliberately stale counter caches; fixed row-loading bounds; sorting/search/pagination; status totals; school ownership; exact class pairs across different years; revocation and preserved normal teacher login.
- New read-path tests check actual bounded record loading and response semantics, not wall-clock thresholds that would be flaky across machines.
- No frontend product code changed in this additional optimization. The already-built frontend can use the optimized API without a changed response contract.
- Real browser regression against the restarted local API passes: existing-teacher selection, portal login, class isolation, reset, revoke/disable/removal, old teaching session and fresh teaching login after removal. No browser page errors. Earlier OAuth/static-audit limitations remain as documented in school-teacher-portal-access-2026-09-21.md; this task does not claim those unrelated checks now pass.
