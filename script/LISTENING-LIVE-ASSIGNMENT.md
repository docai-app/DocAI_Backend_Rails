# Listening A2 live integration evidence

2026-09-09, isolated `listening_rails_isolated_test`, branch `bobby-codex-backend`.

`listening_live_assignment.rb` uses real test-account password login and in-process Rails API requests. Creation fetches the published version over HTTP from the local QG server (127.0.0.1:4102); audio uses authenticated Azure Blob reads from private `listening-test`, without an audio mock. No Dify or TTS generation is invoked.

Verified result:
- assignment ID `e0d2aace-c881-4198-8c38-bb18aa6b89e3`, code `7003fe`;
- QG source 46, published version 108, A2, four questions;
- teacher creation and individual distribution to the fictional student succeeded;
- student content omitted question answers/evidence;
- student audio endpoint returned bytes matching the stored SHA-256;
- server answer checking returned graded, 4/4; grading ID `7db282b8-37ea-441e-b968-ef49472fcffa`.

The runner intentionally submits known correct answers as an integration assertion, not as evidence of learner listening comprehension. It uses an existing fictional source, not a newly crawled article. Browser playback/interaction, deployed-server verification, Admin UI publication and live crawler provenance still need verification.

Execution requires Ruby 3.1.0, `RAILS_ENV=test`, `LISTENING_RAILS_ISOLATED_TEST=1`, the exact isolated DB, `DEVISE_JWT_SECRET_KEY`, `QG_LISTENING_INTERNAL_URL`, matching `QG_LISTENING_SERVICE_TOKEN`, `QG_LISTENING_STORAGE_CONTAINER=listening-test`, and server-only Azure storage credentials. Never print credentials. The successful runner used a process-local random JWT secret, not a production secret; normal browser and server processes must use matching persistent test configuration.

The first attempt lacked `DEVISE_JWT_SECRET_KEY`: sign-in could return a token but verification failed with no verification key (401 on creation). Providing an isolated-process secret fixed this without bypassing authentication. A diagnostic direct invocation also failed during Azure initialization when credentials were omitted; no assignment was created by these failed attempts.

The script reuses its named fixture assignment after verifying the selected QG version, checks distribution before creating it, and uses fixed playback/submission idempotency IDs. It does not reset the DB. An existing test submission may affect what this student's browser shows: use a separate explicitly marked student/assignment for a fresh human acceptance test rather than deleting the integration evidence.

## Browser exercise

The existing local assignment Rails server was restarted with real Azure read configuration, QG loopback URL and a fresh process-only test JWT secret (4101, exec session 25959, PID 85925). QG runs on 4102 (session 56889, PID 81894). Production and frontend 3000 were not restarted. Re-login was required after the test JWT secret changed. These process handles must be revalidated before reuse.

On frontend 3001, the fictional student logged in and joined `7003fe`. The upload page rendered four questions. Initial playback against the old server failed; after restart and re-login, the page displayed Playing audio and remaining plays fell from 9 to 8. UI-selected answers C/A/D/B were saved (Draft saved), then submitted through the confirmation dialog. The dashboard showed a new Graded record. Opening its details displayed 4/4 and 100%: grading `cf27ac09-3318-44a5-8b9b-de594dc519c5`.

Remaining result-page defects: navigation appended `role=teacher` despite student session; legacy result rendering displayed no audio URL, plays used 0 and omitted question text/options. Do not treat these as missing generated audio or proof of privilege escalation: authenticated permissions and rendering behavior need investigation. The result page must be adapted to server-owned snapshots without exposing an unrestricted private blob URL. No production deployment or Admin browser publication has occurred.

Result API follow-up: `listening_grading_for_display` now joins saved answer outcomes with safe question wording/type/options from the immutable snapshot for the authorized grading detail response. It does not mutate stored grading, expose answer keys/evidence/transcript/blob URLs, or change unrelated grading payloads. Full integration suite passed 10 tests / 107 assertions. Two existing playback tests previously assumed an empty database (`count`/`first` globally); they now assert against their own assignment/student, preserving live exercise records. This backend change has not yet been loaded into the running test server or rechecked in the browser. Audio review and play-count rendering still need work.

Playback-count follow-up: new final submissions now capture the server playback state's cumulative count for this student/assignment. Drafts omit it, client-supplied counts are ignored, and later edits preserve the saved count even if the student plays again. Historical graded rows with no captured count remain unknown (`nil`), rather than backfilling a later total as though it were the count at submission. Frontend must render these missing historical values as unknown rather than zero. This code still requires server reload and browser verification.

The local 4101 Puma was subsequently hot-restarted via its verified SIGUSR2 handler, preserving process configuration. Browser result recheck confirmed all four question texts/options now render with server score 4/4 and unknown historical plays shown as an em dash.

`--prepare-only` now prepares a separate human acceptance fixture without playing or submitting: assignment `87b97b05-c050-4c54-8534-fe2ac989fdb0`, code `0c6964`, zero submissions. It is distributed to the same test student. Browser opened `/listening/upload/0c6964`: first load displayed the existing recoverable load error; explicit Retry loading succeeded and showed A2, 10 plays remaining, question 1/4 and 0% answered. No playback or answers were performed on this fresh fixture. Initial-load failure still needs diagnosis and is not claimed fixed. The tab is retained for the user's test.
