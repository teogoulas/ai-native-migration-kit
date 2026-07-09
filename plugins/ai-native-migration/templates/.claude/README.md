# `.claude/` template — settings.json annotated

The `settings.json.tmpl` in this directory is intentionally **plain JSON** (no `// comments`, no `"//":"..."` faux-keys) so it passes the deterministic verifier's JSON-validity check (rubric §Part 1 D03) without any post-processing. That means the settings file itself is not the right place to explain each entry. This README is.

## What ships in the baseline

### `denyList`

Fifteen entries covering four classes of destructive-by-default commands. The intent is **"if an agent runs any of these, that's a mistake, not an operation"** — legitimate uses live in named ops runbooks, not agent sessions.

**Git rewrites** — force-pushing and destructive resets erase history that reviewers may need:
- `git push --force`, `git push --force-with-lease`, `git push -f`
- `git reset --hard`
- `git clean -fdx`

**Database DDL** — schema changes go through migrations, not raw statements:
- `DROP TABLE`
- `DROP DATABASE`
- `TRUNCATE`

**Infrastructure destruction** — both container and IaC channels blocked. Overrides go in named ops runbooks:
- `kubectl delete`
- `terraform destroy`
- `docker system prune -a`

**Supply-chain footguns** — piped-to-shell installs are checked into the repo instead, so the fetched content can be reviewed:
- `curl | sh`, `curl | bash`
- `wget | sh`, `wget | bash`

### `hooks.PostToolUse`

A single audit hook that appends one line per tool invocation to `.claude/audit.log`. Format: `<ISO-8601 UTC timestamp> tool=<CLAUDE_TOOL_NAME>`. Cheap, per-session, disk-only.

**Two things to configure in your target repo:**

1. **Add `.claude/audit.log` to `.gitignore`.** The log is session-scoped and rotates via disk; committing it is noise.
2. **Rotate the log periodically** — either `find .claude/audit.log -size +10M -delete` in the onboarding script, or `logrotate` config, or a cron. Ten megabytes of one-line audit entries takes weeks to accumulate; setting a bound early prevents surprises.

## Extending the template

Common additions per project stack — copy into the `hooks` object:

```jsonc
// PreToolUse example — block Edit if a stop-file exists
"PreToolUse": [
  {
    "matcher": "Edit",
    "hooks": [{ "type": "command", "command": "test -f .agent-stop && exit 1 || exit 0" }]
  }
]

// Stop example — run ai-native-verify at end of session and log the outcome
"Stop": [
  {
    "matcher": "*",
    "hooks": [{ "type": "command", "command": "ai-native-verify . >> .claude/audit.log 2>&1 || true" }]
  }
]
```

## The two-layer pattern

`settings.json` is the enforced half. The **advisory** half — what the human wrote in `AGENTS.md`'s Agent Governance section — must agree. Judge A03 in the audit workflow cross-references the two and flags drift.

Whenever you add a rule to `settings.json`, add the matching advisory statement to `AGENTS.md` in the same PR (and vice versa). The AGENTS.md template ships with a Governance section that mirrors this file's baseline.
