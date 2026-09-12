# Pending task reconciliation and bounded recovery — 2026-09-12

## Delivery status and scope

Backend implementation plus a small frontend grading-review notice. Final delivery details and acceptance gates are in the [engineer handoff](2026-09-12-reliability-release-handoff-zh.md). No production deployment/migration, production rerun, real email or paid provider call was performed. Admin UI, WeChat repository and unfinished Listening work are excluded.

This is **not** “rerun every pending submission after two hours.” Two hours makes a tracked task eligible for observation. A dedicated worker checks every five minutes, observing the exact generation slot ID and fencing token in Sidekiq busy work, all queues, scheduled jobs and retry jobs. Two complete absent observations at least one minute apart are required before recovery (normally two five-minute ticks). Backlog and provider latency can delay these checks; this is not a two-hour completion SLA.

The scanner covers `EssayGenerationRun` slots for Essay, Speaking Essay, Speaking Conversation, Sentence Builder and Talk Lab Speaking, including Essay's independent supplementary slot. Comprehension, Sentence Puzzle and Speaking Pronunciation do not use this asynchronous coordinator; Listening is deliberately excluded. Do not describe this as universal retry coverage for every assignment/provider.

Only slots created at/after the explicit activation timestamp are scanned. Historical pending without a slot is **not adopted or rerun**. A legacy running slot lacking the new provider journal cannot be guessed safe: it requires review. Operators must audit old pending separately.

## State decisions

| Observation after eligibility | Action |
|---|---|
| Exact job in busy, queued, scheduled or retry set | Keep it; reset missing observation. Never delete, move or reprioritize it. |
| Redis unavailable / incomplete snapshot / over 20,000 visited jobs | No recovery decision; reset missing observation. Never interpret an observation failure as an empty queue. |
| Queued/retry-wait delivery absent twice | Rotate token under grading lock and re-enqueue using normal `EssayGenerationJob` dispatch. Old deliveries cannot claim. |
| Journaled execution absent twice, no unresolved provider call | Resume remaining checkpoints within the bounded budget. |
| Original Dify workflow result is terminal | Reuse its output through the ordinary validator/persistence code; do not POST that stage again. Invalid/failed results follow the existing bounded failure path. |
| Original Dify workflow still running/pending/paused | Wait; no repeat POST. |
| Missing run ID, changed app key, inaccessible lookup, untracked/opaque operation | Mark generation `unknown` + `requires_attention`; keep the main status compatible and show a review notice. Do not claim the original call failed. |

The main database status can remain `pending` for an uncertain outcome, but `generation.state=unknown` and `generation.requires_attention=true` distinguish it from ordinary processing. The web grading detail displays “This grading needs review. Please contact your teacher.” No JSON/provider/queue jargon, no automatic frontend POST, and no new unsafe Retry control. Existing operation reports already flag unknown slots; the current Admin list is not redesigned and may still use only the legacy pending badge.

## Provider boundary and concurrency

`EssayGenerationRecoveryState` journals the stage before an outbound provider call and captures workflow-run IDs/terminal events as they arrive. App credentials are not copied into the journal: only their SHA-256 digest is stored so a later lookup cannot use a silently changed app key. Terminal outputs can contain normal grading content; this journal is internal database data and is **never returned in public generation metadata**. Normal database access/backups and student-data protections apply.

Supported GET recovery stages are grading, general context and supplementary workflow. Revised-essay completion, audio analysis and final Speaking Essay scoring are conservatively marked opaque: a lost in-flight response requires review rather than blind paid replay. A saved successful checkpoint for any stage is reusable.

Provider GET is outside DB transactions; the reconciler rechecks token, state and unchanged provider context under the grading-row lock before acting. Claim, provider start, output persistence and recovery share the fence. Old workers cannot overwrite results or clear/add current grading errors. A worker that completes while lookup is in flight wins; the reconciler discards its stale observation.

Sidekiq iteration is inherently racy ([official API guidance](https://github.com/sidekiq/sidekiq/wiki/API)); two observations alone are not the concurrency guarantee. Database fencing and the durable provider boundary are essential. No Redis destructive/control API is used.

## Budgets and ordering

- Existing confirmed failures: initial attempt + at most two retries (three attempts total); delays remain 30 seconds then two minutes.
- Recovery does **not reset** `attempts` or `completed_stages`. A reclaimed unfinished execution consumes the next attempt when claimed.
- Reusing a captured terminal response or finalizing already saved checkpoints continues the original attempt, including attempt three. A cached failed result cannot create attempt four.
- Delivery-loss recovery itself is capped at two replacements per cycle, even when queue deliveries disappear before claim. Exhausted unfinished work becomes failed/stopped; an already-known result that cannot safely be resumed within that recovery budget becomes review-needed instead of falsely reporting provider failure.
- A complete successful stage is not regenerated. Existing student-answer guards still prohibit overwriting saved supplementary responses. Main and supplementary slots remain independent.
- The independent scanner queue is `generation_recovery`; it does not consume grading-worker slots. Recovered grading jobs enter the existing normal queue. No priority/front insertion, queue removal or promise of strict global FIFO across multiple worker queues is added.
- Scan work is capped at 100 candidates and approximately 120 seconds between candidates; a currently running GET can extend the tick by its connect/read timeout (10/15 seconds). Oldest checked slots are considered first. Queue inspection itself is bounded by job count.

## Email and existing report boundaries

Reuse `EssayGenerationNotificationJob` and `AdminNotificationMailer.assignment_stopped_notification`, with the existing recipient/SMTP configuration. Review-needed notifications say “Assignment Needs Review”, not falsely “stopped”. A separate attention claim prevents duplicate review notifications; final confirmed failure retains its own notification claim. No extra email provider or recipient was added.

These are **at-most-once transport attempts, not guaranteed inbox delivery**. The final audit added `essay_generation_notifications` to record preparing/build_failed/delivering/sent/unknown outcomes. Rendering failures can safely retry; ambiguous SMTP is not automatically resent. Reports surface uncertain or stale notifications and terminal tasks with no notification delivery. Report event timezone, stale supplementary detection and fresh requeue age were also corrected; see the consolidated handoff for the final evidence and remaining production gates.

## Deployment prerequisites (not performed)

1. Review the scoped frontend/backend diff and preserve unrelated uncommitted reporting/Listening changes. Back up DB.
2. Apply `20260911143000`, `20260912001000`, `20260912030000` and `20260912040000` **before starting this combined backend version**. Journal and notification columns are needed even when scanning/reporting schedules are disabled. Follow the consolidated migration checklist, including timezone review if an earlier reporting draft already collected events.
3. Drain old workers safely and switch compatible Rails web/grading workers together. Do not kill a live provider call or mix old writers that lack the journal/fence.
4. In the dedicated recovery process only, set `AI_ENGLISH_RECOVERY_WORKER=true`, `AI_ENGLISH_RECOVERY_ENABLED=true`, and `AI_ENGLISH_RECOVERY_ENABLED_AT` to the actual activation time in ISO 8601 with explicit offset, e.g. an operator-selected Macau `+08:00` timestamp. Do not backdate it to include unaudited legacy work.
5. Start `bundle exec sidekiq -e production -C config/sidekiq_generation_recovery.yml` using the existing production DB/Redis/service environment. Concurrency is one. Keep grading workers listening to their existing queue and do not also register this schedule there.
6. Check registration of `ai_english_generation_recovery`, startup scan and subsequent five-minute ticks. Confirm new submitted tasks persist `recovery_version=1` after claim and the journal captures the workflow ID.
7. In an isolated environment verify known-lost delivery, live queue, worker disappearance before/after provider start, recovered valid/invalid output and actual SMTP receipt. Production must have working provider GET permissions; local fixtures do not prove them.
8. Deploy the small frontend notice/GET refresh and verify authorized teacher/student access. Unknown may resolve by a later read-only provider lookup; the detail refreshes it without creating a new generation.

Disabling `AI_ENGLISH_RECOVERY_ENABLED` stops future scan actions (including already queued ticks). Stop the dedicated worker when rolling back. Keep added columns and saved responses for audit; do not drop tables/answers or kill active provider calls as a rollback shortcut. The reporting worker and its activation settings are independent.

## Verification evidence

- Isolated Rails/PostgreSQL suite: 145 tests / 1,056 assertions, zero failures/errors/skips, including existing generation, concurrency, validation, summaries, Comprehension and reporting regressions. Subsequent final check results are recorded in the handoff response if they change.
- New tests: `test/integration/essay_generation_reconciler_test.rb` and `test/services/essay_generation_queue_snapshot_test.rb`. Provider/SMTP/queue delivery in regression tests are controlled substitutes; DB locks and persistence are real.
- Actual dedicated Sidekiq 7.3 worker + dedicated loopback Redis + isolated test DB: startup scan completed; Macau 11:20 five-minute scheduler tick actually enqueued and completed on 2026-09-12. Activation cutoff was intentionally in the future, so no records were recovered and no grading/notification jobs ran. Worker and Redis are stopped after verification.
- Tests caught and fixed Rails non-local-return transaction rollback and schema-qualified enum filtering (`category IN (NULL)`). Scanner test now exercises its actual query, not only a manually invoked reconciler.
- Frontend generation-state/component tests, TypeScript and targeted ESLint are checked separately. Desktop/mobile/embedded browser fixtures do not imply production or physical WeChat acceptance.
- Whole-project premium static UI audit still has unrelated existing findings; this feature does not claim a whole-product UI certification.

Run the new Rails tests using the project's explicit isolated test setup (`RAILS_ENV=test`, `LISTENING_RAILS_ISOLATED_TEST=1`, Ruby 3.1, loopback test DB), never production configuration. This isolation flag name does not include Listening in this feature's release scope.
