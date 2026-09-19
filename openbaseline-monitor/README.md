# openbaseline-monitor

A Claude Code plugin that reports session **activity** to your openbaseline
team, so the team's Sessions page and the optimizations checks have real
evidence to work from.

## What leaves the machine

Metadata only, on session start, at the end of each turn, and on session end:

- the session's id (Claude Code's own UUID)
- the working directory
- the model name
- how many messages the session holds
- whether the session is active or ended
- token counts: input, output, cache-read, cache-creation, thinking: summed
  numbers, never the text they were counted from
- how many times the session ran out of Claude quota, and which quota
  (`five_hour` or `weekly`)

**Deliberately not reported:** any message content, tool inputs or outputs,
prompts, or the session title (titles are derived from conversation content).
Nor the usage-limit notice itself: it reads "You've hit your session limit ·
resets 7:50pm (Europe/Oslo)", and the reset time and timezone would say where
you are and when you work. The notice is classified on your machine and only
the count and the scope travel.

Everything is reported as *you*, to the team this machine is connected to:
the one you picked in the browser when you approved it, or the one you last
named with `--team`. Nothing is sent when you are not signed in or no team is
remembered.

`OBL_NO_REPORT=1` turns it off on this machine, along with everything else the
plugin does. See **Turning pieces off** below for the finer switches.

## Install

```
/plugin marketplace add openbaseline/claude-plugins
/plugin install openbaseline-monitor@openbaseline
```

## What happens when you install it

Installing the plugin is the whole installation. Nobody opens a terminal:

1. **The binary arrives in the background.** A second SessionStart hook runs
   asynchronously and fetches obl into the plugin's own data directory, so
   nothing waits on a ~10MB transfer while you start work.
2. **A browser opens so you can approve the machine.** On the first session
   after that, obl mints a sign-in code, prints one line naming the URL and
   the code, and opens the page. You approve there and pick a team. Nothing
   waits for you: the hook asks once per turn whether you have approved yet,
   and gets out of the way.
3. **The team's tool baseline is applied.** Once the machine is connected, a
   third hook brings it onto whatever tools the team declares.
4. **Sessions start reporting**, as described above.

The download is verified against the sha256 published in
`https://openbaseline.io/cli/latest.json`, and nothing is installed if there
is no checksum or it does not match; a failed verification parks the attempt
for a day rather than re-downloading on every session start. obl installs only
into `<plugin data>/bin/obl`, never `~/.local/bin`: a copy of obl you manage
yourself is yours, and if one is already on your PATH the bootstrap does
nothing.

### The honest caveats

- **The first session reports nothing.** The binary arrives while that session
  is already running, and it has no account yet. Reporting starts from the
  next one.
- **obl stops asking.** If nobody approves, the invitation backs off and after
  five unanswered rounds obl stops offering. Run `obl auth login` from a
  terminal to connect the machine after that.
- **`obl configure` is the recovery path.** It says what the machine still
  needs, and it is what to run if the remembered team is wrong: a team that no
  longer resolves means every report 404s in silence.
- **Windows has no zero-terminal path.** Claude Code has no interpreter for a
  `.sh` hook there, so neither the bootstrap nor the reporting hook runs.
  `scripts/obl-bootstrap.ps1` is the PowerShell twin, kept beside its sibling
  so the two land together whenever a Windows entry point is added, and it is
  unverified like every other Windows path in openbaseline. On Windows today,
  install and connect the CLI yourself:

  ```
  irm https://openbaseline.io/install.ps1 | iex
  obl auth login
  ```

### ❌ Applying the baseline installs software on this machine

Step 3 above is not a report. It writes one mise config fragment
(`<mise config dir>/conf.d/openbaseline.toml`) and runs `mise install` for the
tools your team declares, unattended, every six hours. **Anyone who can edit
your team's tool list can cause software to be installed on every member's
machine, and mise backends run install scripts.** It is on by default and
there is no prompt, deliberately. `OBL_NO_APPLY=1` turns it off.

obl never writes your own `config.toml` and never edits `~/.claude/`; a pin you
write yourself wins over the team baseline, and deleting that one fragment
takes the machine off it. What it did is logged to
`~/.local/state/openbaseline/apply.log`.

## Turning pieces off

Every switch is an environment variable, and any non-empty value counts:

| Variable | What stops |
| --- | --- |
| `OBL_NO_REPORT` | Everything: session metadata, the tool inventory, pairing, **and** the baseline install. One variable makes the machine quiet and leaves it alone, with the plugin still installed. |
| `OBL_NO_PAIR` | Only the browser sign-in. An already-connected machine keeps reporting. |
| `OBL_NO_APPLY` | Only the baseline install. |
| `OBL_NO_BOOTSTRAP` | Only fetching the binary. |
| `OBL_NO_BROWSER` | Only opening the tab. The invitation line still names the URL and the code. |

`CI` and `CLAUDE_CODE_REMOTE` skip all of it, and so does a Linux box with no
`DISPLAY` or `WAYLAND_DISPLAY`. Hooks fire in CI, in containers and in cloud
sessions too, and a machine that is not somebody's workstation should not turn
up as a device in a team's list, let alone have software installed on it.

## Requirements

None you have to install. The plugin fetches the [obl
CLI](https://openbaseline.io/download) itself and connects it in a browser.

## How the hook runs

The hooks call `scripts/obl-hook.sh`, a script this plugin ships, and it
forwards everything on to obl: `obl claude hook` for the three reporting
events, `obl claude apply` for the baseline. The subcommand lives in
`hooks/hooks.json` and reaches obl through argv, never in the script. It looks
for the binary in this order:

1. `$OBL_BIN`, if it is set and executable
2. `obl` on your PATH
3. `~/.local/bin/obl`, where the installer puts it
4. `bin/obl` inside the plugin's own data directory

Finding none of those is not an error: the script exits 0 and stays quiet,
because a machine without the CLI must not fail every session start. Nothing
is ever written to stdout either, since a hook's stdout on SessionStart
becomes part of the model's context; anything worth saying goes to
`~/.local/state/openbaseline/plugin.log` (or `$OBL_STATE_DIR`). The bootstrap
writes to the same log, and it is the place to look if the binary never
appears.

Both subcommands exit 0 silently in every failure mode: not signed in, no
team, a malformed event, an unreachable API. A reporting problem must never
disturb the session it is reporting on, and a hook exiting non-zero puts a
warning into it.

If your team renamed the binary (`obl` is rename-friendly), point `OBL_BIN` at
it rather than editing `hooks/hooks.json`, which an update would overwrite.
