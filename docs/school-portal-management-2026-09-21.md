# School portal loading, deletion and class filtering — 2026-09-21

Release tracking: [production release and verification](school-portal-release-2026-09-21.md). Local-only status below records the earlier verification checkpoint.

## Scope and delivery

Frontend: AIEnglish_Admin_Dashboard_Frontend, school; backend: DocAI_Backend_Rails, development. This change adds no migrations, tables or database structure. Current work is local, not pushed or deployed. Production response-time improvement has not been measured.

> Subsequent change: existing teacher selection and linked access removal are described in [teacher portal access](school-teacher-portal-access-2026-09-21.md). Below, non-reusable email and disabled identity behavior apply only to legacy independent accounts.

## Behavior

- Owners can delete their own school's delegated password-manager accounts; owners and foreign-school identities are not valid delete targets. DELETE /api/school_admin/v1/password_managers/:id takes the current revision; /api/school/v1 alias shares the implementation. A stale/missing revision returns 409. Repeating an already-completed delete returns 204 without another audit event.
- Deletion disables access, empties grants, rotates revision/session_version and stores deleted_at under existing GeneralUser.meta.school_password_access. Identity/history remain; the email cannot be registered again. Deleted accounts disappear from lists, cannot be re-enabled by PATCH, cannot log in, and previously issued tokens fail. No student or teaching records are cascade-deleted.
- The confirmation supports cancel, busy state, conflicts and unknown results. Unknown results require reloading the account list, not automatic write retries. Successful deletion refreshes the list; deleting the final row on a later page goes back one page.
- Students uses a labeled native class select for accessible keyboard/mobile platform behavior, keeping the surrounding Tremor visual style. Options come from academic_years?include_classes=true; a teacher sees only authorized active classes. Apply sends class_name_exact. Legacy class_name partial search remains supported for older clients. Changing the year clears the draft selection; list errors do not silently broaden an applied filter.

## Loading changes and boundaries

- Removed the unused OAuth auth() root-layout call, explicitly authorized by the user. School JWT authentication, route verification and Rails permission enforcement remain. The login form can be statically generated.
- Removed the unconsumed LoadingProvider wrapper, whose URL effects scheduled unnecessary state changes. Suspense still covers pages using search parameters.
- Share only concurrent /me promises for the same token, never cache a settled verification. Keep the verified subtree mounted but hidden during navigation checks, preserving SWR cache; identity or grant changes remount it. No security decision relies on cached class data.
- Class catalogues and grant validation each use one batched enrollment query, independent of the number of years/grants. Students only fetches list fields and the selected year's enrollments rather than every historical enrollment.
- API requests have bounded timeouts. Network latency, server capacity and production database scale still affect real loading time; local correctness is not a production latency benchmark.
- SchoolPasswordAccess must be included after Devise modules, so its authentication override actually runs. Previously the portal guard denied disabled users, but Devise's model-level authentication method could override the concern.

## Validation

- Isolated Rails integration: 23 tests, 486 assertions, zero failures/errors. Includes authorization, token revocation, exact class filtering and bounded catalogue query count, plus existing admin authentication coverage.
- Production frontend build succeeds; repository lint warnings remain in unrelated existing components. Static login HTML contains the login form.
- Both local Playwright suites pass against the production Next build and real isolated Rails: original create/edit/revoke/disable/reset flow, plus delete cancel/conflict/503 reconciliation/success, deleted login and old token rejection, teacher class dropdown and exact filtering, mobile overflow and dialog focus. Concurrent route/focus verification makes one /me request; protected content remains hidden until it completes. No browser page errors.
- TypeScript checking and build-integrated lint pass (existing unrelated lint warnings remain). git diff --check passes in both repositories.
- Mobile screenshots at 390 px were inspected for the class picker and delete confirmation. Native select labeling and Tab focus are verified; macOS headless Chromium cannot exercise the OS popup with arrow keys, so option changes use Playwright selectOption. A headed OS-picker check remains outside this run.
- The premium static audit still reports the same 17 pre-existing findings (7 select-ownership detections, 8 button checks, 2 noValidate detections); it is not a clean audit pass. The class select's explicit native ownership is recorded in UX-CONTRACT.md. No new findings were added.

Local browser tests require loopback Next on 3001 and isolated Rails on 4117, seeded using the existing school delegation fixture. Build with NEXT_PUBLIC_API_BASE_URL=http://127.0.0.1:4117; public environment variables are embedded at build time. Run tests/school-password-delegation.browser.cjs and tests/school-portal-management.browser.cjs using the available Playwright runtime. All accounts/data are synthetic.

Frontend and backend should be released together after reviewing the target environment. An older backend cannot supply dropdown options or deletion. Vercel deployment integrations must be checked before any future GitHub push; no deployment was performed for this change.
