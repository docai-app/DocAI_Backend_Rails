# AI English Global Administrator

`teacher@docai.net` is the explicitly configured AI English global administrator.
Email comparison is normalized with `strip.downcase`; no domain-wide or role-wide
fallback is permitted.

## Access scope

The account can use the existing teacher and student-facing screens to manage an
assignment from any school or academic year by its UUID. It can:

- view assignment details, submissions, statistics, and individual gradings;
- edit and delete assignments;
- assign and unassign students using the assignment's own school academic year;
- release Essay and Comprehension scores;
- manage assignment sharing using the assignment school's eligible current teachers;
- edit grading data and save or restore teacher reviews;
- send assignment reminders and generate supported sample essays.

Student and teacher selection is always scoped from the target assignment. The
frontend sends `essay_assignment_id` when requesting distribution options, and the
backend resolves the school from `essay_assignments.school_academic_year_id`. For
legacy rows without that field, an existing assignment distribution may provide the
historical school context. If neither source exists, assignment and sharing changes
fail closed instead of falling back to the administrator account's own school.

This access does not change `essay_assignments.general_user_id`. The original owner
remains visible in API responses and UI labels, while capability fields (`can_edit`,
`can_delete`, `can_share`, `can_assign_to_students`, `can_duplicate`, and
`can_release_scores`) describe the administrator's effective permissions.

## Direct URLs

No academic-year query parameter is required:

```text
/essay/assignment/:assignment_id
/essay/assignment/:assignment_id/edit
/essay/assignment/:assignment_id/assign
/essay/grading/:essay_grading_id
```

The frontend keeps list and assignment-detail navigation state in the browser
session, so these resource URLs do not need academic-year, source or parent-ID
query parameters. Previously shared long URLs remain compatible.

## Regression coverage

`test/integration/aienglish_global_read_admin_access_test.rb` verifies cross-school
and historical access, all high-impact mutations, capability flags, existing owner,
student and shared-teacher access, continued 403 responses for unrelated teachers,
and fail-closed handling of unscoped legacy assignments.
