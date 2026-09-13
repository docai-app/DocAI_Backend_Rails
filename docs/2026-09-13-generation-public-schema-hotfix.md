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

The first production canary exposed a second configuration mismatch: the installed
`public.capture_essay_operation()` function used unqualified `INSERT INTO
essay_operation_events`, although the repository migration specifies public-qualified
INSERTs. Public foreign keys were correct; the function selected a tenant event
table and its foreign key rejected the public grading ID. The transaction rolled
back, with no provider call. Restore the existing release trigger definition using
`operations_reports:install_triggers`; do not change/drop foreign keys. Readiness now
checks the bound trigger function and its public-qualified INSERT targets, not just
the existence of two trigger names. A regression test reproduces and detects the
incorrect installed function, restores it and verifies a tenant-context claim.

The real canary also exposed excessive stream-journal round trips: Dify had
completed, but workers were still processing repeated workflow_run_id token/node
events inside `observe_provider!`. Thread dumps showed that call path; PostgreSQL
reported no blocked backends. Duplicate, nonterminal identities now skip the lock
and queries once journalled. First/changed IDs and every terminal event still use
the original DB/token fence. A 100-event regression asserts zero duplicate-event
SQL, while changed IDs and obsolete terminal writes remain rejected.

For the two already-running streams, an operator may perform a terminal-result
handoff only after GET of the exact original Dify run confirms completion, the app
key digest still matches, and token/provider context are unchanged under the grading
lock. Privately back up the returned result, then use the existing fenced recovery
with that terminal result. The obsolete reader exits through StaleExecution; wait
for busy=0 before restarting. The successor reuses the result without another POST
or increased provider attempt. This is incident-specific handoff, not a change to
automatic recovery's requirement for absence observations.

Production's Dify GET response additionally encoded `outputs` as a JSON string,
unlike SSE's object. Recovery now decodes object-shaped outputs from GET responses
and already-cached terminal events. Missing, malformed, null or array output is not
invented/replaced and still fails the same feedback validator. Cached recovery tests
use the real string-encoded shape and assert no new HTTP request; this compatibility
change does not relax scoring/grammar validation or retry budgets.

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
- With the installed-trigger regression and uncached readiness verification:
  153 tests, 1,133 assertions, zero failures/errors/skips (seed 9132026).
- With stream identity deduplication and a fenced, no-new-POST terminal handoff:
  155 tests, 1,145 assertions, zero failures/errors/skips (seed 13092028).
- Final suite including actual GET-path object/string output compatibility:
  158 tests, 1,199 assertions, zero failures/errors/skips (seed 13092030).

During runtime acceptance, four handed-off records encountered the then-unhandled
string output format and completed grading on automatic attempt 2. The handoff
itself reused results, but those later automatic retries did make another grading
request. Do not describe this incident as having made zero duplicate provider calls.
The output compatibility fix prevents this specific false failure on future recovery.
Already successful retry results are retained, not replaced by older cached output.

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
   Run `OperationsStatusReport.verify_capture!` using the updated check. If the
   installed trigger is unqualified, back up its definition and restore the existing
   release definition with `RAILS_ENV=production bundle exec rake
   operations_reports:install_triggers`, then recheck. This is trigger DDL, not a
   data migration; it does not replay old events, change scores or send mail.
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
