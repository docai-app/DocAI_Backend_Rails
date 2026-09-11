# Grading and supplementary-exercise reliability — 2026-09-11

## Scope and delivery status

Local implementation for the Rails essay-generation pipeline and Comprehension score denominator. No production migration, historical record correction, paid Dify rerun, email delivery, deployment, or GitHub push was performed. Admin and WeChat repositories are unchanged. This is not a claim that every unrelated Dify integration now uses this coordinator.

## Validation before publication

- `ComprehensionScoreCalculator` counts enabled question blanks before looking at student answers. Empty, missing and malformed answers earn zero without reducing full score. Extra answer IDs do not increase the denominator. The existing model calculation uses this service.
- `EssayFeedbackValidator` checks parsed grading output, finite scores within positive full scores, criterion scores and explanations, sentence/error structure, meaningful general context and revised text. Empty errors are valid. Existing fenced-JSON compatibility remains.
- This is structural validation, not pedagogical quality assessment. It does not prove that every custom rubric returned every expected criterion; future rubric-specific contracts need representative fixtures.
- `SupplementPracticeValidator` uses the actual parser and scorer. Correct-answer and empty-answer probes must both have the same question-count denominator; the former earns full score and the latter zero. Required fields, option uniqueness, valid MC answers, question IDs and duplicate topic/type sections are checked. Invalid output is not published as ready.
- Existing saved student answers block exercise replacement, including draft answers. Corrupt exercises with saved answers require a separately reviewed repair, not deletion or automatic regeneration.

## Durable task state

Migration `20260911143000_create_essay_generation_runs` introduces a unique slot for `(essay_grading_id, kind)`, with kinds `grading` and `supplement`. It records state, fencing token, attempt count, completed stages, timing, manual-retry audit count and notification claim time.

States: `queued`, `running`, `checking`, `retry_wait`, `ready`, `failed`, `unknown`, `cancelled`.

1. A confirmed failure retries after 30 seconds, then after 2 minutes.
2. Each cycle executes at most three attempts: initial execution plus two retries.
3. Successful stages are checkpointed and skipped on retries within the cycle. Managed Dify clients do not add nested POST retries.
4. Main grading stays pending while retrying; only terminal failure marks it stopped.
5. Successful main grading is graded and creates an independent supplementary slot in the same transaction. Supplement failure never changes the main result to stopped.
6. Manual exercise retry is permitted after confirmed failure, or a queued/retry-wait slot is overdue by two hours. A one-minute terminal-failure cooldown applies. There is no lifetime manual-retry cap.
7. Running/checking/unknown tasks cannot be restarted merely because time has elapsed. Unknown is not confirmed failure.

The existing `EssayGradingJob` is a compatibility wrapper. Duplicate legacy queue deliveries do not reset the attempt budget. Create/submit callbacks use one after-save-commit entry point. Admin draft cancellation invalidates tokens; resubmission gets a new cycle.

## Concurrency and preservation

Creation, worker claim, output persistence and answer writes serialize on the grading row. Tokens reject outdated jobs, including queued deliveries after manual recovery. Provider calls run outside database transactions. Four-way concurrent request/claim tests and repeated stale-queue-versus-worker races verify a single winner.

Answer-save and submit endpoints reject writes while an exercise replacement is active. A new generation cannot replace an exercise once any answer record exists. Explicit main reruns cannot run alongside an active supplementary task.

## Uncertain provider results

`DifyWorkflowRecovery` makes a read-only lookup when a captured workflow-run ID is available. It accepts only an identity-matched terminal result; otherwise the slot becomes unknown. It never issues another paid generation POST to discover whether the first POST succeeded.

The lookup follows the official [Dify workflow API implementation](https://github.com/langgenius/dify/blob/main/api/controllers/service_api/app/workflow.py). Missing IDs, unavailable lookup, running/paused status and transport failures remain unknown. There is no new polling scheduler. A killed worker or unresolved unknown task requires operator verification; this version does not automatically recover every infrastructure outage.

## Existing email notification reused

`AdminNotificationMailer.assignment_stopped_notification` and its existing recipient configuration are reused. No new recipient, email integration or parallel mailer was introduced. Optional generation context adds attempt count and stage group and distinguishes exercise failure from main grading failure. Student essay text is not included.

`EssayGenerationNotificationJob` is a deduplication gate: only the current failed token can claim notification, once. Intermediate retries do not email. The claim is stored before sending, giving at-most-once send attempts—not guaranteed delivery. SMTP failure/crash after claiming requires operator review; automatic resend could violate the no-duplicate requirement. Redis enqueue failure is logged and leaves durable state; queue infrastructure still needs operational monitoring.

## Frontend API contract

- `GET /api/v1/essay_gradings/:id/supplement_practice` includes generation metadata: `state`, `can_retry`, attempts and timing. Active/unknown results are not presented as a completed exercise.
- Invalid legacy content can still return HTTP 422; the frontend must read its generation metadata. Existing legacy-response compatibility is retained.
- `POST /api/v1/essay_gradings/:id/supplement_practice/retry` returns 202 when accepted, 409 if no longer eligible, and normal 401/403 authorization failures. The submission owner or existing global-admin policy is required. `can_retry` alone is not authorization.
- Main grading detail includes `generation` and `supplement_generation`. Existing fields are retained for older clients.
- Network failure must not be converted to permission to regenerate. Query status again instead of repeating POST automatically.

## Local verification

Final combined Rails run after the follow-up fixes: **101 tests, 871 assertions, zero failures/errors/skips**. Coverage includes actual controller authorization, save/submit guards, callbacks, bounded retries, successful-stage preservation, independent supplement failure, final notification deduplication, obsolete tokens, concurrent claim/retry races, malformed content, denominator persistence, existing summary and JSON compatibility.

Test files:

- `test/integration/essay_generation_reliability_test.rb`
- `test/integration/essay_generation_concurrency_test.rb`
- `test/integration/essay_generation_recovery_edges_test.rb`
- `test/services/comprehension_score_calculator_test.rb`
- `test/services/essay_feedback_validator_test.rb`
- `test/services/dify_workflow_recovery_test.rb`
- `test/integration/supplement_practice_json_compatibility_test.rb`
- `test/integration/assignment_grading_summary_test.rb`

Use Ruby 3.1.0, `RAILS_ENV=test`, `LISTENING_RAILS_ISOLATED_TEST=1`, `BUNDLE_WITHOUT=development`, `RUBYOPT=-rlogger`, and test-only JWT/Azure placeholders. Run `bundle exec rails test` with the files above. The isolated database guard must remain enabled. Migration and schema dump were run only against the explicitly isolated local test database. Provider, mail and queue delivery were stubbed in tests; concurrency tests use real database locks.

## Deployment and acceptance checklist (not performed)

### Follow-up review fixes

Three gaps found after the original 89-test run are now covered by 12 permanent edge tests:

- Failed first-time supplement generation with no output (or an empty text wrapper) retains generation metadata on HTTP 422. Cooldown, unknown legacy output, GET-to-POST recovery and duplicate clicks are covered. The existing frontend 422 handler can show Retry without product UI changes.
- Managed Sentence Builder summary uses the same `EssayGradingMetrics` contract as list/detail and persists under the current token while still pending. It does not call the old calculator's graded-only path. The database score must be written as `record[:score]`: the legacy `score=` accessor writes Comprehension JSON instead. Tests cover true zero, positive score, fenced output, invalid output and actual worker completion before the webhook.
- Explicit admin reruns request a new cycle or raise `EssayGenerationRun::Unavailable`. Single main/supplement endpoints return HTTP 409 with success false when blocked; bulk results mark that item unsuccessful. Internal duplicate/callback requests retain their idempotent return behavior. Queued, running, checking, retry-wait and unknown states are tested. This changes Rails admin API responses, not the Admin frontend repository.

The attempt budget, delays, queue ordering, saved-answer protection and existing mailer behavior are unchanged by these follow-up fixes. Live production acceptance remains outstanding.

1. Review and back up the database; apply the additive migration before enabling the new Rails code.
2. Drain/stop old workers before switching: old processes do not honor new fencing tokens. Restart web and Sidekiq together with the coordinated version. Do not run mixed old/new writers.
3. Verify Redis scheduled-job delivery and existing SMTP configuration. No new scheduler is required.
4. Deploy compatible frontend handling, then test a controlled successful case, confirmed failure through three attempts, failed-exercise retry, and two simultaneous retry requests.
5. Verify one actual final notification, correct existing recipient, and no essay body. Test an uncertain result without a duplicate generation POST.
6. Audit existing Comprehension records before any correction. This change fixes future calculation but does not silently rewrite historical marks or rerun production submissions.
7. Verify actual production Dify outputs for each supported rubric. Local synthetic regression and browser fixtures are not production acceptance.

Rollback requires stopping new workers before reverting code; leave the additive table in place for audit rather than dropping it. Do not permit old workers to overwrite results while new runs are active. Historical marks and answer records should not be rewritten as part of rollback.
