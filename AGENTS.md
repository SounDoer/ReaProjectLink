# AGENTS.md — ReaProjectLink

ReaProjectLink is a local, NAS-based delivery and dependency manager for REAPER
projects.

This file records only general development conventions that cannot be inferred
from the code. Keep product decisions in `docs/decisions.md`.

## Language

- Code, identifiers, comments, tests, schemas, branches, and commits are English.
- Conversation and status updates default to Chinese.
- Keep technical names, API names, commands, and error messages in their original
  form.

## Development workflow

- Read `docs/decisions.md` before changing a workflow or data model.
- Do not turn an open question into a decision without user confirmation.
- Keep documentation consistent with confirmed changes.
- Do not invent commands or project structure before they exist.
- Add runtime dependencies only after asking the user.
- Run the relevant checks before reporting implementation work complete.

## Git workflow

- Stay on the current branch unless the user asks otherwise.
- Do not create branches, commit, or push silently.
- Commits follow Conventional Commits with a concise scope, for example:
  `docs(design): record publish workflow`.

## Safety

- Preserve unrelated user changes in a dirty worktree.
- Avoid destructive filesystem and Git operations.
- Confirm exact targets before deleting generated files or history.
- Prefer recoverable and atomic file updates where practical.
