# openbaseline-monitor

A Claude Code plugin that reports session **activity** to your OpenBaseline
team, so the team's Sessions page and the optimizations checks have real
evidence to work from.

## What leaves the machine

Metadata only, on session start, at the end of each turn, and on session end:

- the session's id (Claude Code's own UUID)
- the working directory
- the model name
- how many messages the session holds
- whether the session is active or ended

**Deliberately not reported:** any message content, tool inputs or outputs,
prompts, or the session title (titles are derived from conversation content).
Everything is reported as *you*, to the team you last used with `--team` —
nothing is sent when you are not signed in or no team is remembered.

## Requirements

The [obl CLI](https://openbaseline.io/download) on your PATH, signed in
(`obl auth login`) with a remembered team (any `obl packages install --team
org/team` sets it).

## Install

```
/plugin marketplace add OpenBaseline/claude-plugins
/plugin install openbaseline-monitor@openbaseline
```

The hooks call `obl claude hook`, which exits silently in every failure mode —
a reporting problem must never disturb the session it is reporting on.

If your team renamed the binary (`obl` is rename-friendly), edit
`hooks/hooks.json` to match, or keep an `obl` symlink beside it.
