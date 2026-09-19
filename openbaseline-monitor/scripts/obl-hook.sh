#!/bin/sh
# The monitor plugin's only entry point: find the obl binary and hand it the
# hook event.
#
# The hooks used to call a bare `obl`, which assumed someone had already
# installed the CLI from a terminal. Going through a script the plugin ships
# means the plugin can look in more than one place, and later fetch the binary
# itself, without the hook manifest changing again.
#
# ZERO BYTES ON STDOUT. On SessionStart, whatever a hook writes to stdout is
# added to the model's context, so one stray line here lands inside the user's
# conversation. Diagnostics go to the log file below; nothing else may print.
set -eu

home="${HOME:-}"
log_dir="${OBL_STATE_DIR:-${XDG_STATE_HOME:-$home/.local/state}/openbaseline}"
log="$log_dir/plugin.log"

note() {
  mkdir -p "$log_dir" >/dev/null 2>&1 || return 0
  printf '%s obl-hook: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" >>"$log" 2>/dev/null || true
}

# Resolution order: an explicit override, then the PATH, then the two places
# obl installs itself. `command -v` is wrapped because it answers non-zero
# when nothing is found, and under `set -e` that would exit non-zero: a hook
# that exits non-zero puts a warning into the user's Claude session.
bin=""
if [ -n "${OBL_BIN:-}" ] && [ -x "${OBL_BIN:-}" ]; then
  bin="$OBL_BIN"
fi
if [ -z "$bin" ]; then
  on_path=$(command -v obl 2>/dev/null || true)
  if [ -n "$on_path" ] && [ -x "$on_path" ]; then
    bin="$on_path"
  fi
fi
if [ -z "$bin" ]; then
  for candidate in \
    "$home/.local/bin/obl" \
    "${CLAUDE_PLUGIN_DATA:-$home/.claude/plugins/data/openbaseline-monitor}/bin/obl"; do
    if [ -x "$candidate" ]; then
      bin="$candidate"
      break
    fi
  done
fi

# No binary is not a failure. A machine that has never installed obl must not
# error on every session start; it reports nothing, quietly, and a later step
# teaches this script to fetch the binary into CLAUDE_PLUGIN_DATA.
if [ -z "$bin" ]; then
  note "no obl binary found on PATH or in the plugin data directory"
  exit 0
fi

# exec, so argv (`claude hook`) reaches obl and the hook event JSON on stdin
# is forwarded untouched. The subcommand lives in hooks.json, never here.
exec "$bin" "$@"
