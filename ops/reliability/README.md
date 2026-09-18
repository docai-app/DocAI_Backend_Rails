# Dedicated production reliability processes

This is an opt-in operator tool, not an automatic deploy hook. Requires explicit
approval for the target production host. No migration, database repair, source
checkout, image build/pull, historical rerun, or main-worker restart is performed.

## Preconditions

1. Approved GitHub SHA, no tracked changes; existing migrations and report capture
   verified read-only. Database backup/restore and application release already reviewed.
2. Main container is the expected production Sidekiq, one source bind mount, one
   existing application network. Enough memory for two dedicated 1.5 GiB-capped
   processes (normally much less). Existing Redis and main queues must be kept.
3. Review SMTP and one explicit recipient. Runtime directory must be operator-owned,
   mode 700, outside Git; its env and manifest files are 600 and never committed.

From the approved checkout (replace placeholders, never copy a historical cutoff):

```sh
python3 ops/reliability/worker_runtime.py reports --repo "$PWD" --sha APPROVED_SHA --runtime-dir PRIVATE_DIRECTORY --recipient APPROVED_EMAIL
python3 ops/reliability/worker_runtime.py recovery --repo "$PWD" --sha APPROVED_SHA --runtime-dir PRIVATE_DIRECTORY --recipient APPROVED_EMAIL
```

Both commands default to dry run. Add `--apply` only after readiness review. The
actual server Macau time is captured on each apply; no activation-date override is
accepted. Never delete the runtime files to restart with a new cutoff. Creation
refuses an existing container or env file; diagnose any partial failure first.

The existing immutable image, environment and source mount are reused. New role
flags are scoped to each container, concurrency 1, original dedicated queue YAML,
restart always, bounded logs, no published ports. No role flags are put in shared
`.env`; source `.env` supplies the same DB/SMTP as the existing application.

Names: `aienglish-operations-reports`, `aienglish-generation-recovery`. Existing main
worker is untouched. Manifest includes exact release and launch arguments but no
secret values. Image and source checkout must remain compatible on future deploys.
**Future source updates must also safely drain these new workers**, not just the main
worker: a report may be delivering mail, and recovery may be querying a provider.

## Sidekiq Web credentials (independent of Admin API token)

```sh
python3 ops/reliability/sidekiq_credentials.py --repo "$PWD" --sha APPROVED_SHA --runtime-dir PRIVATE_DIRECTORY
```

Add `--apply` after review. Generates a random 256-bit password on the server,
preserves other `.env` settings and a private backup, refuses existing Sidekiq keys,
and prints no secret. The credentials are in
`PRIVATE_DIRECTORY/sidekiq-credentials.private.json`, accessible to the server
operator. Deliver via the team's password manager, not Git/chat. A scoped Rails web
restart is necessary for dotenv loading; do not restart Redis/main worker to do so.
Verify anonymous and wrong credentials 401, valid credentials 200, plus an existing
Admin proxy read. This does not rotate `ADMIN_TOKEN` or Admin login credentials and
does not add network allowlisting/rate limiting.

## Acceptance and stop/rollback

- Run `operations_reports:check` inside the report worker: read-only, not proof of
  SMTP delivery. Run `aienglish:recovery_status` in the recovery worker.
- Confirm only intended queues, concurrency=1, activation times, startup tick and
  at least two cron ticks. A registered schedule alone is not sufficient.
- Automatic report periods are Macau 00–12, 12–18, 18–24. No cutoff before activation
  is sent. Do not backdate to force a test email; let the next scheduled report run.
- Report `sent` means SMTP acceptance, not inbox receipt. Ask recipient to confirm.
- New submission/provider GET acceptance is separate. Do not kill production jobs
  or clear queues to manufacture loss. Historical pending is not adopted.
- To stop one feature, TSTP only that named dedicated container, wait until its
  Sidekiq process is quiet and busy=0, then `docker stop --timeout 180 NAME`.
  Do not force stop in-flight mail/provider calls. A manually stopped container
  with `restart=always` may restart after Docker restarts: for durable disablement
  also use `docker update --restart=no NAME`. Preserve runtime env, cutoff, queues,
  delivery records and student answers. Restarting later reuses the same container
  and activation, then restore `--restart=always` after approval.
- Do not remove Redis, run compose down/prune, remove a delivery claim, or restore
  a database snapshot as a routine rollback. Queue jobs can remain after stopping
  a dedicated consumer; this is not cancellation of a running action.

Tests (no Docker, production DB or SMTP access):

```sh
python3 -m unittest discover -s ops/reliability -p 'test_*.py' -v
```
