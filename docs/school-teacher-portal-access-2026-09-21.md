# Existing teacher accounts: school portal access

Release tracking: [production release and verification](school-portal-release-2026-09-21.md). Local-only status below records the earlier verification checkpoint.

## Status

2026-09-21: user explicitly authorized reuse of existing teacher email/password and the necessary authentication/authorization changes; user additionally required teaching access to survive portal permission removal. Implemented locally on frontend school and backend development. Not pushed or deployed. No migrations, new tables/columns, or production data changes.

## User flow

Owner opens 新增老師管理權限, searches/paginates the current school's active teachers, selects one and grants exact academic-year/class pairs. No new email, name or password is entered. The teacher uses their existing credentials at the same school portal login URL. Existing independent password-manager accounts remain editable/removable with their old behavior.

Linked teacher rows say 移除權限. Removing or disabling the portal permission preserves the GeneralUser, teaching role, features, email, password, original school_id and teaching records. Teachers can continue using the teaching platform and can log in afresh. Removing access allows the school owner to explicitly grant it again later, with a new portal session version.

## Backend contract

- GET password_managers/teachers is owner-only, under both school API aliases, 20 rows per page, searchable by keyword. It only returns role=teacher identities with active TeacherAssignment in this school's active academic years. Existing undeleted linked grants are excluded; a deleted grant can be assigned again. It does not return password data or tokens.
- POST password_managers with teacher_id and grants grants access on the existing user. It rejects email/nickname/password fields, invalid teacher identities, foreign-school/historical/inactive teachers, and non-owner callers. The row lock prevents duplicate grant writes; existing undeleted permission returns 409, even if disabled or owned by a different school.
- Role and school_id are unchanged. Store school_password_access.school_id, enabled, grants, created_by_id, revision and session_version in the existing GeneralUser.meta. No new GeneralUser or energy record is created. Legacy POST email/nickname/password remains supported for compatibility.
- PATCH linked teacher permission accepts grants/enabled/revision, rejecting credential/profile fields. DELETE logically removes only the linked portal permission; revision checks and audit history remain. Different schools cannot overwrite each other's active grants. This portal has one current school context per teacher; multi-school selection is outside this change.
- Portal authorization checks both current employment and the exact class grants. Leaving/transferring the school or archiving the academic year revokes portal access even when metadata remains. Class access never falls back to full school access.

## Authentication boundary

School portal sign-in marks only the dispatched JWT with school_password_version, using a transient model attribute and force/store:false sign-in. A normal teacher JWT has no portal version. On school routes a linked teacher needs the current version, active permission and current employment. Portal-version JWTs are subject to the restricted action allowlist on all generic API routes as well. A revoked portal JWT cannot become a general teaching JWT by deleting metadata or reauthorizing the teacher.

Normal teaching authentication does not consult linked permission enabled/deleted flags. Only legacy dedicated school_password_manager identities use those flags in active_for_authentication?. The teacher's database role remains teacher; school session and /me responses derive school_password_manager solely for the portal UI and return the school from permission metadata. Do not rewrite the persisted teacher role or primary school_id.

## Verification

- Isolated Rails delegation/admin authentication suites: 26 tests, 561 assertions, zero failures/errors. Covers unchanged credentials/features and user count; real teacher login and assignment-list access after disable/delete; old portal token denial; restricted portal token rejection by teaching API; exact student reset scope; duplicate/foreign-school conflicts; reauthorization; and loss of active employment.
- Real Next production build + isolated Rails browser flow passes: picker pagination/search/selection, original credentials at portal login, grants/reset/revoke/disable, conflict recovery, removal, old teaching login surviving and fresh teaching login after removal. No page errors.
- Separate frontend fixture test covers failed teacher catalogue/retry/no results, required-selection focus, keyboard selection, narrow viewport, create payload excluding credentials, read-only identity edit and linked-removal copy. This is not backend permission evidence.
- Frontend production build and standalone TypeScript checks pass; existing unrelated lint warnings remain. Existing deletion/class-filter/loading browser regression also passes. Mobile picker/removal screenshots were inspected; no horizontal page overflow.
- Extra OAuth compatibility suite: 4 tests / 13 assertions, 2 failures (unauthenticated authorize tests expect 400 but receive login redirect 302). Repeated against a clean temporary archive of backend HEAD 9a482cb, with the same isolated environment: identical two failures. No OAuth code was changed to hide these existing failures.
- Premium static audit retains the same 17 pre-existing findings; it is not a clean static audit pass. The new picker introduces no extra findings. Both repos pass git diff --check.
- All checks above are local. Neither source checkout was pushed or deployed. No tests touched real school data.

The isolated browser seed now creates 24 synthetic teaching users (plus the existing school/owner/students) to exercise pagination. It is guarded by test environment, isolation flag and exact local database name. Reseeding resets only these synthetic fixture identities. Deployment requires the updated backend before the frontend picker; an older backend does not support teachers/teacher_id and must not be described as compatible with the new flow.
