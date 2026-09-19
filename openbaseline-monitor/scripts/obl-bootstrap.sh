#!/bin/sh
# Fetch the obl binary into the plugin's own data directory, so installing the
# plugin is the whole installation and nobody has to open a terminal first.
#
# Run from a SECOND SessionStart hook marked "async": true. Async matters
# twice over: a ~10MB download must not sit in front of someone who just
# opened a session, and Claude Code enforces no timeout on an async hook, so
# every network call below carries its own deadline instead.
#
# ZERO BYTES ON STDOUT AND STDERR. A hook's stdout on SessionStart is added to
# the model's context, so one stray line lands inside the user's conversation.
# Everything worth saying goes to the same plugin.log obl-hook.sh writes.
set -eu

home="${HOME:-}"
log_dir="${OBL_STATE_DIR:-${XDG_STATE_HOME:-$home/.local/state}/openbaseline}"
log="$log_dir/plugin.log"

# One redirection for the whole script, rather than a `2>/dev/null` per
# command: it also catches what curl, mv and the shell itself have to say.
if mkdir -p "$log_dir" 2>/dev/null; then
  exec 2>>"$log"
else
  exec 2>/dev/null
fi

note() {
  printf '%s obl-bootstrap: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" >>"$log" 2>/dev/null || true
}

# Nothing here is worth doing twice, or doing at all in a machine that is not
# somebody's workstation. Hooks inherit the full environment and fire in CI,
# in containers and in cloud sessions, where downloading a binary and
# registering a "workstation" is noise in a team's device list.
if [ -n "${OBL_NO_BOOTSTRAP:-}" ]; then
  note "OBL_NO_BOOTSTRAP is set, not installing anything"
  exit 0
fi
if [ -n "${CI:-}" ]; then
  note "CI is set, this is not a workstation"
  exit 0
fi
if [ -n "${CLAUDE_CODE_REMOTE:-}" ]; then
  note "CLAUDE_CODE_REMOTE is set, this is not a workstation"
  exit 0
fi

# The same resolution order obl-hook.sh uses. If the hook can already find a
# binary, there is nothing to install: an obl the user manages themselves is
# theirs, and a second copy under the plugin would shadow nothing and age.
data_dir="${CLAUDE_PLUGIN_DATA:-$home/.claude/plugins/data/openbaseline-monitor}"
dest_dir="$data_dir/bin"
dest="$dest_dir/obl"

if [ -n "${OBL_BIN:-}" ] && [ -x "${OBL_BIN:-}" ]; then
  note "OBL_BIN already points at a binary"
  exit 0
fi
on_path=$(command -v obl 2>/dev/null || true)
if [ -n "$on_path" ] && [ -x "$on_path" ]; then
  note "obl is already on the PATH"
  exit 0
fi
for candidate in "$home/.local/bin/obl" "$dest"; do
  if [ -x "$candidate" ]; then
    note "obl is already installed at $candidate"
    exit 0
  fi
done

# Asset naming has to track selfupdate.AssetName and build-dist.sh exactly:
# get it wrong and the download is a 404 page that fails the checksum, which
# is safe but useless. Windows is out of scope for a POSIX script; the .ps1
# beside this file is its twin.
os=$(uname -s 2>/dev/null || true)
arch=$(uname -m 2>/dev/null || true)
case "$os" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *)
    note "no published build for '$os', leaving the machine alone"
    exit 0 ;;
esac
case "$arch" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=amd64 ;;
  *)
    note "no published build for '$arch', leaving the machine alone"
    exit 0 ;;
esac
asset="obl-${os}-${arch}"

# OBL_CLI_BASE_URL replaces the whole prefix including /cli, the way
# selfupdate.BaseURL() reads it. It is NOT install.sh's OBL_BASE_URL, which
# names the apex.
base="${OBL_CLI_BASE_URL:-https://openbaseline.io/cli}"
case "$base" in
  https://*) proto="=https" ;;
  # Only an explicit override can be plain http: a local mirror, or this
  # script's own tests. The default can never be redirected down to it.
  http://*) proto="=http,https" ;;
  *)
    note "OBL_CLI_BASE_URL is not an http(s) URL, refusing to fetch from it"
    exit 0 ;;
esac

# A failed checksum retried on every session start is a denial of service
# aimed at the CDN and at the user, so a mismatch parks the attempt for a
# while. The stamp lives in the state dir beside the log, never in the config
# dir: a dotfiles repo carrying it between machines would silence a machine
# that never had the problem.
backoff="$log_dir/bootstrap-backoff"
if [ -e "$backoff" ]; then
  if [ -n "$(find "$backoff" -maxdepth 0 -mmin +1440 2>/dev/null)" ]; then
    rm -f "$backoff" 2>/dev/null || true
  else
    note "a recent attempt failed verification, not retrying yet"
    exit 0
  fi
fi

mkdir -p "$dest_dir" 2>/dev/null || {
  note "cannot create $dest_dir"
  exit 0
}

# mkdir is the portable atomic test-and-set in sh, and two sessions opened
# seconds apart would otherwise both pull the same 10MB.
lock="$dest_dir/.bootstrap.lock"
staged="$dest_dir/.obl.download.$$"
if ! mkdir "$lock" 2>/dev/null; then
  if [ -n "$(find "$lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    note "breaking a bootstrap lock left behind by a dead session"
    rmdir "$lock" 2>/dev/null || true
    mkdir "$lock" 2>/dev/null || {
      note "could not take the bootstrap lock"
      exit 0
    }
  else
    note "another session is bootstrapping, standing down"
    exit 0
  fi
fi
# shellcheck disable=SC2064 -- expand the paths now; neither can change.
# Both staged names, not just the binary: the manifest is deleted as soon as
# it is parsed, but an exit between the fetch and that line would otherwise
# leave one behind per failed session start.
trap "rm -f '$staged' '$staged.json' 2>/dev/null; rmdir '$lock' 2>/dev/null; exit 0" EXIT INT TERM

if command -v curl >/dev/null 2>&1; then
  # Never bare curl: its progress meter goes to stderr, and stderr is the log.
  fetch() { curl -fsSL --proto "$proto" --tlsv1.2 --max-time "$1" -o "$3" "$2"; }
elif command -v wget >/dev/null 2>&1; then
  # One try, so -T is the whole deadline rather than a per-attempt one.
  fetch() { wget -q --tries=1 -T "$1" -O "$3" "$2"; }
else
  note "neither curl nor wget is available"
  exit 0
fi

# latest.json rather than SHA256SUMS: it pins a version as well as a checksum,
# so the log can say what was installed.
manifest="$staged.json"
fetch 20 "$base/latest.json" "$manifest" || {
  note "could not fetch $base/latest.json"
  exit 0
}

version=""
sum=""
if command -v python3 >/dev/null 2>&1; then
  parsed=$(python3 - "$manifest" "$asset" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as fh:
        manifest = json.load(fh)
except Exception:
    raise SystemExit(1)
version = manifest.get("version") or "-"
sums = manifest.get("sums") or {}
sys.stdout.write("%s %s\n" % (version, sums.get(sys.argv[2]) or "-"))
PY
)
  if [ -n "$parsed" ]; then
    version=${parsed%% *}
    sum=${parsed##* }
    # The placeholder json.dumps cannot produce, standing in for "absent" so
    # the two fields stay positional in one line of output.
    if [ "$version" = "-" ]; then version=""; fi
    if [ "$sum" = "-" ]; then sum=""; fi
  fi
fi
if [ -z "$sum" ]; then
  # Same sed idiom publish.sh uses to read a version, so this stays
  # dependency-free. build-dist.sh writes one sum per line, which is what
  # makes a line-oriented reader adequate here.
  version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)
  sum=$(sed -n "s/.*\"$asset\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$manifest" | head -n 1)
fi
rm -f "$manifest" 2>/dev/null || true

# Refusing to install unverified bytes is the same rule selfupdate.Download
# holds. A sum that is not 64 hex characters is not a sum: something served a
# redirect page, or the manifest changed shape, and either way we stop.
case "$sum" in
  *[!0-9a-f]*|"") sum="" ;;
esac
if [ -z "$sum" ] || [ "${#sum}" -ne 64 ]; then
  note "no usable checksum for $asset in the manifest, refusing to install"
  exit 0
fi
if [ -z "$version" ] || [ "$version" = "-" ]; then
  note "the manifest carries no version, refusing to install"
  exit 0
fi

# Download INTO the destination directory. A rename cannot cross a
# filesystem, and a "temp then move" that quietly degrades to a copy can tear
# a binary in half, which is the rule selfupdate.Replace follows too.
fetch 300 "$base/$asset" "$staged" || {
  note "could not download $asset"
  exit 0
}

if command -v shasum >/dev/null 2>&1; then
  got=$(shasum -a 256 "$staged" | cut -d' ' -f1)
elif command -v sha256sum >/dev/null 2>&1; then
  got=$(sha256sum "$staged" | cut -d' ' -f1)
else
  note "no shasum or sha256sum on this machine, refusing to install unverified bytes"
  exit 0
fi

if [ "$got" != "$sum" ]; then
  rm -f "$staged" 2>/dev/null || true
  : >"$backoff" 2>/dev/null || true
  note "checksum mismatch for $asset (expected $sum, got $got), nothing installed"
  exit 0
fi

# Make the staged file runnable BEFORE the rename, so the destination path is
# never briefly a file Gatekeeper or the kernel would refuse.
chmod +x "$staged" 2>/dev/null || {
  note "could not make the download executable"
  exit 0
}
if [ "$os" = darwin ] && command -v xattr >/dev/null 2>&1; then
  xattr -d com.apple.quarantine "$staged" 2>/dev/null || true
fi
mv -f "$staged" "$dest" 2>/dev/null || {
  note "could not install into $dest"
  exit 0
}

note "installed obl $version into $dest"
exit 0
