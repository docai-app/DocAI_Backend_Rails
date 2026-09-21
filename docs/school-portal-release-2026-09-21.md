# School portal production release — 2026-09-21

## Scope and authorization

The user explicitly changed this release from development to **Backend production**, authorized deployment to `akali@43.228.217.157`, and accepted the existing Vercel automatic deployments when pushing frontend `school`. No manual Vercel deployment is authorized or required. This does not change the default development branch for future tasks.

Frontend is `qq505810824/AIEnglish_Admin_Dashboard_Frontend` / `school`, application commit `f4b72c4`. Total Admin `main`, the student frontend and WeChat are outside this change.

## Exact backend composition

- Fresh production server: branch `production`, HEAD `041a3215ca341e1401089f58d2ba90b5608eb024`.
- GitHub production before synchronization: `9c2f82a`; it is an ancestor of the server HEAD.
- Keep the already deployed report/calendar-health and historical-draft fixes. Apply only school portal commit `94d23e0` from development onto the actual server baseline, producing application commit `4492fc8`.
- Do not merge the unrelated development Admin supplement monitor changes.
- Server-to-candidate diff has no migrations, schema, Gemfile, Dockerfile or compose changes. Existing school tables and GeneralUser.school_id verified present; read-only migration check reports pending=false.
- Server tracked files are clean; preserve its two untracked font files.

## Verification before delivery

- Exact production candidate: 92 tests / 1460 assertions, zero failures/errors/skips. School authorization, API performance, Admin authentication, draft lifecycle/concurrency, audio preparation and Admin override suites use only the isolated local test DB.
- After frontend remote integration: TypeScript and diff checks pass. Real local browser delegation and uncertain-reset/read-refresh regressions pass again. Earlier five browser suites and production build passed; no application code changed during rebase (remote school only added an environment example).
- Prior local benchmark and UI evidence remain in the linked feature documents. They do not establish production latency or real-device accessibility.

## Deployment procedure and rollback

After pushing and verifying the exact production SHA on GitHub:

1. Fetch production on the server, verify HEAD still equals the baseline, inspect the complete diff and abort for migration/dependency/config changes. Verify no pending migration and no tracked modifications.
2. Record container IDs, image IDs, start times, environment SHA256 and Redis identity/start time. Never output environment values or credentials.
3. Quiet all three existing Sidekiq containers with `docker kill --signal=TSTP`: `docai_backend_rails-sidekiq-1`, `aienglish-operations-reports`, `aienglish-generation-recovery`. Wait until all three registry entries have quiet=true and busy=0; do not terminate active grading.
4. Stop only these three workers and `docai_backend_rails-docai-rails-1`; fast-forward the production checkout to the verified SHA using `git merge --ff-only <SHA>`; start the same four containers. Preserve the Redis container, queue state, runtime configuration and enable times. Do not run the old deploy.sh (compose down/up and global image deletion), rebuild images, prune, migrate or start other services.
5. Verify all four processes loaded the new source, pending migrations remain false, workers resume with original queues, Redis/environment digests unchanged, HTTP and school authorization read checks pass, and scheduled worker health/tick completion is healthy.

Application rollback baseline: `041a3215ca341e1401089f58d2ba90b5608eb024`. If needed, use the same quiet/drain and four-container stop/start process, preserve all data/runtime/Redis, and return the source to that exact baseline without deleting untracked files. The baseline lacks the new teacher-linked portal access, so rollback also requires compatible frontend behavior; do not erase grants or teacher identities as rollback. Escalate database concerns to an engineer.

## Delivery state

Completed backend delivery:

- GitHub `production` and server were verified at `ca63f9554fa9ff82dc68fe90ea84e7763b66fb65`; school application code is `4492fc8`. The following verification-record commit changes documentation only.
- All three workers reported quiet=true/busy=0 twice before stopping. Web and all three existing workers restarted at 2026-09-21 19:54:32–33 Asia/Macau. Four container IDs/images and environment digests stayed identical; restart_count=0 and no ERROR/FATAL lines in startup logs.
- Redis container ID/start time stayed identical (2026-09-20T10:34:39Z), with no public 6379 binding. No Redis restart, queue clear, migration, image build/prune, runtime-setting change or unrelated-service restart.
- Read-only production checks used the same `public` tenant as ApiController and an existing active school owner with an in-memory JWT (never output/saved). Both school API aliases /me returned 200. Students, selectable teachers, academic years/classes, assignments and snapshot returned 200. Anonymous school /me (both aliases) and ordinary assignment API returned 401. No real teacher grant or student password was changed to test the deployment.
- Single server-local HTTP samples: /me 1.62–1.67s, students 3.01s, teacher picker 1.86s, academic years 2.09s, assignments 3.73s, snapshot 8.42s. These are limited live samples, not browser load-time guarantees or before/after benchmarks. Production remains slower than isolated local tests; further latency investigation is outstanding.
- After restart, all three workers resumed (quiet=false/busy=0). At 20:00, reports tick completed at 20:00:04 and recovery at 20:00:01 with error_count=0. At 20:00:55, schedule health healthy=true, each role had one worker and no issues; pending migrations remained false.
- Frontend GitHub `school` verified at `8ab33e08343d1b1044eb86a1ee5d607d866cf97c`. All three existing Vercel integrations reported **Deployment was blocked**. New frontend UI is therefore not verified deployed; no manual deployment or integration/account setting changes were made. The school login URL was reachable in Chromium (HTTP 200, two login fields, no page errors), but that does not prove the new commit is live.
- Backend development checkout retains the school feature commit `94d23e0` locally; production delivery followed the user's later branch instruction. It was not wholesale merged into production and the unrelated Admin supplement monitor was excluded.

Historical “local/unpushed” statements in feature documents describe their original verification checkpoint. Local E2E covers permission removal preserving teaching login, but no real-account credential login/reset or complete teacher/student workflow was performed in production. No blanket zero-bug claim is made.
