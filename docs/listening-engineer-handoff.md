# Listening assignment backend handoff (2026-09-10)

Code is prepared on `bobby-codex-backend`; **not deployed**. The owner asked for GitHub delivery and engineer-managed deployment. Do not treat the earlier server-staged package as the latest code.

## Responsibilities and contracts

- QG (`bobbylian-hue/qg-backend-rails`) shares Reading's crawler/articles but produces separate immutable Listening versions, audio, publication and Admin APIs.
- This backend copies a published version into an immutable assignment snapshot. Student responses do not carry trusted answers or scores; the backend checks them against the snapshot.
- Creation requires authorized teacher context and `meta.listening` with `version_id`, `news_feed_id`, `level`; optional `play_limit` (1–20), `allow_pause`, `allow_seek` are validated.
- Distribution uses the existing assignment access system. New content and playback endpoints inherit teacher/distributed-student/historical-submission authorization.
- `GET /api/v1/essay_assignments/:id/listening_content` returns safe question content and playback settings.
- `POST /api/v1/essay_assignments/:id/listening_audio` requires a valid `request_id`, checks limits and Azure bytes, and returns protected WAV bytes, not a public blob URL.
- Submission uses the existing grading endpoints. The Listening-specific `Idempotency-Key` prevents duplicate creates on retries with the same payload. Draft answers omit correctness and answer keys.
- Result detail now includes safe question wording/options and server scores. Old missing play counts stay unknown. Protected result-page audio review and teacher transcript/answer-release UI remain incomplete.

## Release requirements

Every published article must have A2/B2/C2; single A2 is only a local integration fixture. Generation stays manually triggered, with no daily cron added. The owner permits the 30 old QG Listening forms to be hidden from the new catalog while preserving data. Production preflight found no existing Listening assignments/submissions, but verify again before deployment.

Teacher-triggered audio after transcript review is a discussed future change, not implemented. The current QG publication gate still requires verified audio for all three levels. Frontend and total Admin changes live in separate repos and are not included/deployed by this push. The teacher creation UI must be verified against the version contract before public rollout.

## Configuration and migrations

Use server-only environment values or a gitignored, mode-0600 `.listening-runtime.json` in this Rails root:
- `QG_LISTENING_INTERNAL_URL` (HTTPS QG base URL; plain HTTP only allowed for loopback tests)
- `QG_LISTENING_SERVICE_TOKEN` (match QG, at least 32 bytes)
- `QG_LISTENING_STORAGE_CONTAINER` (private)
- `QG_LISTENING_AZURE_STORAGE_NAME`, `QG_LISTENING_AZURE_STORAGE_ACCESS_KEY`

The optional runtime initializer accepts only these names. Existing environment values take precedence; other assignment types' Azure settings are not overwritten. Existing global Azure configuration is still required by the application's original initializer.

Take and verify database/code backups before applying only these additive migrations:
- `20260909120000_create_listening_assignment_snapshots.rb`
- `20260909130000_create_listening_playback_states.rb`

Both models are excluded from Apartment tenant schemas alongside assignments/users. Deploy to the **public schema** with verified search path; do not sweep every tenant or execute unrelated pending migrations automatically. Do not use production schema load/reset. Revert only the reviewed code for rollback, retaining added tables/data until an engineer assesses them.

## Existing Redis blocker (not fixed by Listening)

Before any Listening code or migrations were applied, a request to `/api/v1/general_users/me` returned 500 and Rails logged `Redis::ReadOnlyError`. Read-only inspection found the shared Redis in replica mode with a down external replication link. `requirepass` was empty, protected mode disabled, and port 6379 mapped onto the host. The cause and exposure history are not established; do not claim a proven intrusion.

Engineer actions before deployment: preserve Redis configuration/logs/data and inspect intended topology, ACLs, persistence, firewall and Docker networking. Confirm no legitimate replication depends on the current link. Contain unneeded external access, then plan restoration of the intended writable service without flushing keys/queues. Verify Rails authentication, rate limiting, Sidekiq and existing workloads afterward. No `REPLICAOF`, ACL, firewall, queue deletion or service restart was performed by this handoff.

Separate code-security finding: the existing assignment model already contains provider-key-shaped literals in the baseline commit. They were not added or reproduced in this handoff. Review migration to server secrets and credential rotation as a separate coordinated change; this patch preserves unrelated provider behavior.

## Verification and remaining acceptance

Local full isolated integration suite: **11 tests, 110 assertions, no failures/errors**. Run with `RAILS_ENV=test`, `LISTENING_RAILS_ISOLATED_TEST=1`, exact isolated DB, test JWT secret and valid dummy Azure configuration for the pre-existing initializer; do not point tests at production. See `script/LISTENING-LIVE-ASSIGNMENT.md` for the successful fictional A2 local browser/API exercise, not production acceptance.

Before rollout, jointly validate all three levels on a real article, Admin publish, teacher create/distribute, student playback/draft/submit, trusted scoring, negative authorization and Reading regression. The existing Redis fault must be resolved independently. No Vercel or Mini Program deployment is authorized by this GitHub handoff.
