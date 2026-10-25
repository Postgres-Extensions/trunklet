# General PostgreSQL Guidance

Guidance in this file is about **PostgreSQL itself** rather than about pgxntool -- it
applies just as much in a project that has never heard of pgxntool. `CLAUDE.md`, next to
this file, covers pgxntool proper.

As with `CLAUDE.md`, an extension project's own CLAUDE.md and instructions take
precedence over anything here.

The human-facing version of this material is `POSTGRES-NOTES.asc`.

## Never Mention `trusted` Without `superuser = false` and the Security Caveat

Whenever you bring up the `trusted` control-file parameter -- in code, a comment, a
document, a commit message, a PR, or a chat reply -- you MUST in the same breath also:

1. Offer `superuser = false` as the alternative, and
2. State that `trusted = true` carries security consequences, pointing at PostgreSQL's
   [Security Considerations for Extensions](https://www.postgresql.org/docs/current/extend-extensions.html#EXTEND-EXTENSIONS-SECURITY)
   rather than reassuring the reader yourself.

The rule is one-directional: mentioning `superuser = false` on its own is fine. It is
specifically `trusted` that must never appear unaccompanied.

**Why**: `trusted = true` is the answer that comes to mind fastest for "how do I let a
non-superuser install this?", so raising it alone reads as a recommendation. It isn't a
free switch -- it runs the install script as the bootstrap superuser on behalf of an
unprivileged caller, which turns any flaw in that script into privilege escalation.
`superuser = false` solves the same problem while granting nothing: the caller simply
needs the privileges the script actually uses. When the extension doesn't require
superuser-only capabilities, that's the better suggestion.

See `POSTGRES-NOTES.asc` for the user-facing explanation of both parameters.

## Metrics and Estimates

Never produce any kind of metrics or estimates unless you have data to back them up. If
you do have data you MUST reference it.
