# /verify — run the deterministic AI-native audit against this repo

Invokes `./skill/scripts/ai-native-verify` against the current repo and
reports the summary. No agentic layer — this is the fast, deterministic-only
path suitable for a pre-push sanity check.

## Usage
```
/verify
```

## What it runs
```
./skill/scripts/ai-native-verify --format=text .
```

## What to do with the output
- **All pass** → nothing to do.
- **Partial verdicts** → the repo has structural presence but a quality
  gap. Read the evidence and remediation hint.
- **Fail verdicts** → the criterion is not satisfied. Templates under
  `skill/templates/` typically fix these; see `docs/DEVELOPMENT.md` for
  the deny-list workflow.
- **N/A verdicts** → the check is not applicable to this repo. If a check
  is systemically n/a for a legitimate reason, document it in
  `docs/plans/dogfood-decisions.md`.

## Related
- Full agentic audit: `/ai-native-migration <this-repo-path>` from any
  Claude Code session (requires the kit to be installed via install.sh).
