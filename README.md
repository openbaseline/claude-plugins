# OpenBaseline Claude Code plugins

The plugin marketplace for [OpenBaseline](https://openbaseline.io).

```
/plugin marketplace add OpenBaseline/claude-plugins
/plugin install openbaseline-monitor@openbaseline
```

## openbaseline-monitor

Reports Claude Code **session activity** to your OpenBaseline team, so the
team's Sessions page and the Observability dashboard have real evidence to work
from.

What leaves the machine is metadata only — the session id, the working
directory, the model name, the message count, and whether the session is still
active. **No message content, no tool inputs or outputs, no prompts, and no
session title** (titles are derived from conversation content).

The hooks call `obl claude hook`, which exits silently in every failure mode:
not signed in, no team remembered, or the API unreachable are all no-ops. A
reporting problem must never disturb the session it is reporting on.

Requires the [obl CLI](https://openbaseline.io/download), signed in with
`obl auth login`.

See [`openbaseline-monitor/README.md`](openbaseline-monitor/README.md) for details.

## Source

This repository is the published artifact. The source of truth lives in the
OpenBaseline monorepo under `claude-plugin/`, alongside the `obl claude hook`
command the hooks invoke — the two have to stay in step.

MIT licensed.
