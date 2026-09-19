# openbaseline Claude Code plugins

The plugin marketplace for [openbaseline](https://openbaseline.io).

```
/plugin marketplace add openbaseline/claude-plugins
/plugin install openbaseline-monitor@openbaseline
```

## openbaseline-monitor

Two jobs, and the second one is not a report: it reports Claude Code **session
activity** to your openbaseline team, and it keeps the machine on the team's
**tool baseline**.

Installing the plugin is the whole installation. It fetches the obl CLI into
its own data directory, opens a browser so you can approve the machine and pick
a team, and takes it from there. Nothing to install first, and no terminal.

### What leaves the machine

Metadata only: the session id, the working directory, the model name, the
message count, whether the session is still active, token counts, and how often
the session ran out of Claude quota. **No message content, no tool inputs or
outputs, no prompts, and no session title**, since titles are derived from
conversation content.

### ❌ It also installs software

Keeping the machine on the baseline means writing one mise config fragment and
running `mise install` for the tools your team declares, unattended, on a
schedule. **Anyone who can edit your team's tool list can cause software to be
installed on every member's machine, and mise backends run install scripts.**
It is on by default and there is no prompt.

`OBL_NO_APPLY=1` turns that part off. `OBL_NO_REPORT=1` turns off everything
the plugin does and leaves the machine quiet. It never writes your own mise
`config.toml` and never edits `~/.claude/`: a pin you write yourself wins over
the team baseline, and deleting one fragment takes the machine off it.

Windows has no terminal-free path yet, because Claude Code has no interpreter
for a `.sh` hook there.

See [`openbaseline-monitor/README.md`](openbaseline-monitor/README.md) for the
full list of what is reported, every switch, and where the logs are.

## Source

This repository is the published artifact, including this file. The source of
truth lives in the openbaseline monorepo under `claude-plugin/`, beside the
`obl claude hook` and `obl claude apply` commands the hooks invoke, because the
two have to move together.

MIT licensed.
