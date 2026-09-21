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

Prepared and verified locally. Push and server deployment results will be recorded after actual completion. Historical “local/unpushed” statements in the feature documents describe their original verification checkpoint.
