# Claude skills

Project-checked-in skills meant to be installed into the
operator's `~/.claude/skills/` directory. Each subdirectory is one
skill (with its own `SKILL.md`).

## Installing

The simplest pattern is symlink-into-place so updates here ride
forward without re-copying:

```bash
mkdir -p ~/.claude/skills
ln -snf "$(pwd)/claude-skills/syrus-debug" ~/.claude/skills/syrus-debug
```

After that, Claude Code reads the skill on demand whenever its
description matches the operator's question.

## Why these are checked into the repo

Skills are tightly coupled to the project's API + behaviors —
when the API changes, the skill needs to change in the same PR.
Keeping them next to the code makes that obvious and reviewable.
