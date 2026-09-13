# Pending incident: shared generation tables hidden by tenant schemas

## Confirmed cause

Production at `0948582` stored generation slots in `public.essay_generation_runs`.
The database user's default schema was `docai`, which also contained an empty
table with the same name. The new generation model was not excluded from Apartment
tenancy. The worker's `find_by` returned nil and the job returned normally, without
calling Dify, changing the grading status or triggering failure retries.

At 2026-09-13 21:00 Macau time: 61 generation slots were queued with zero attempts
and no started_at. Today's submissions included 51 pending, 36 older than two hours.
These counts are an incident snapshot, not ongoing monitoring.

## Change and scope

Add `EssayGenerationRun`, `EssayOperationEvent`, `OperationsReportDelivery` and
`EssayGenerationNotification` to Apartment's existing public/excluded model list,
alongside `EssayGrading`. All four must resolve to public in web, worker and tenant
contexts; otherwise reporting/notification claims could also be split by schema.

This is backend-only. No frontend/Admin/WeChat/Listening edits, provider changes,
new migration, account changes, score recalculation or deletion of tenant tables.
Existing migration files are not rewritten by this emergency hotfix. Production's
four required migrations and public tables were verified present. Fresh installation
and the earlier migration failure still require an explicit public-schema migration
procedure; do not assume this model fix changes migration DDL or repairs a missing
public table. Do not blindly rerun `db:migrate:up` (Apartment also migrates tenants).

## Regression proof

`test/integration/essay_generation_schema_test.rb` creates actual shadow tables in
an isolated PostgreSQL schema and switches Apartment to that schema. Before the
fix both tests failed, including the exact worker lookup failure. After the fix:

- The real generation job finds, claims and completes the public slot using a
  controlled provider double; duplicate delivery cannot claim it again.
- The supplement slot remains public; all four tenant shadow tables remain empty.
- Event, report and notification writes/associations remain in public.
- Generation, concurrency, recovery, queue-snapshot and reporting suites: 83 tests,
  491 assertions, zero failures/errors/skips (seed 10211).
- Second pass including assignment summaries, supplementary compatibility and
  global-admin permission regressions: 152 tests, 1,124 assertions, zero failures,
  errors or skips (seed 13092026).

Tests use Ruby 3.1, `RAILS_ENV=test`, `LISTENING_RAILS_ISOLATED_TEST=1`, the explicit
loopback isolated DB and fake providers/Sidekiq/mail. They do not call production.

## Deployment and recovery checklist

1. Fetch the target GitHub branch and confirm a fast-forward from `0948582`.
   Preserve server-only font files and all environment/configuration files.
2. Verify all four public tables and migrations exist; inspect counts in tenant
   copies before any recovery. This hotfix does not move or merge records.
3. Quiet only the affected grading worker; wait until busy=0. Do not kill an active
   provider request. Preserve Redis queues and existing jobs.
4. Retain a private server-side snapshot of affected slots/gradings before recovery.
5. Fast-forward server checkout to the published hotfix and restart the existing
   Rails web and grading worker. No dependency/image rebuild or migration required
   for this configuration-only change in the existing bind-mounted deployment.
6. Verify the running container model table names are public-qualified and that
   a known public slot is visible even with the default `docai` search path.
7. Recover only explicitly audited, never-started affected slots (queued, attempts=0,
   started_at absent, provider_context/completed_stages empty, grading still pending).
   Recheck queue/busy/scheduled/retry absence twice and revalidate under the grading
   lock. Use the existing token-fenced recovery method; never reset attempts or
   mass-rerun unknown/running/completed records. Start with a canary and check real
   provider progress before releasing the remaining incident batch.
8. Check actual persisted scores, generation state and supplementary output. Jobs
   appearing as Sidekiq `done` is not sufficient acceptance.

Recovery/report dedicated workers were not configured at incident inspection.
Deploying this hotfix does not enable those schedules. Configure and separately
accept them using the existing handoff; do not backdate activation to replay old work.

## Rollback

Retain `0948582` as the pre-hotfix code reference, but it reproduces this incident;
do not blindly roll back and resume grading on it. If another regression appears,
quiet/drain the worker, preserve all records/queues, investigate and choose a reviewed
version. Do not drop the public tables, delete jobs, reset scores or overwrite answers.

Deployment results and final commit are to be recorded after runtime acceptance;
the test result above alone does not claim production recovery.
