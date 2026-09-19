# The Windows twin of obl-bootstrap.sh: fetch the obl binary into the
# plugin's own data directory so installing the plugin is the whole
# installation.
#
# UNVERIFIED, like every other Windows path in this repo. Nothing in the
# hooks manifest calls it yet either: Claude Code has no .sh interpreter on
# native Windows, so obl-hook.sh cannot run there, and a bootstrap that
# installed a binary nothing would ever invoke is worse than no bootstrap.
# This file exists so the two halves land together when a Windows entry point
# is wired up.
#
# ZERO OUTPUT. A hook's stdout on SessionStart becomes part of the model's
# context, so everything worth saying goes to the same plugin.log the POSIX
# script writes.

$ErrorActionPreference = 'Stop'

$stateDir = if ($env:OBL_STATE_DIR) { $env:OBL_STATE_DIR }
            elseif ($env:XDG_STATE_HOME) { Join-Path $env:XDG_STATE_HOME 'openbaseline' }
            else { Join-Path $env:USERPROFILE '.local\state\openbaseline' }
$log = Join-Path $stateDir 'plugin.log'

function Note([string] $message) {
  try {
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Add-Content -Path $log -Value "$stamp obl-bootstrap: $message"
  } catch { }
}

# A machine that is not somebody's workstation gets left alone: hooks inherit
# the full environment and fire in CI and in cloud sessions too.
foreach ($off in @('OBL_NO_BOOTSTRAP', 'CI', 'CLAUDE_CODE_REMOTE')) {
  if ([Environment]::GetEnvironmentVariable($off)) {
    Note "$off is set, not installing anything"
    exit 0
  }
}

$dataDir = if ($env:CLAUDE_PLUGIN_DATA) { $env:CLAUDE_PLUGIN_DATA }
           else { Join-Path $env:USERPROFILE '.claude\plugins\data\openbaseline-monitor' }
$destDir = Join-Path $dataDir 'bin'
$dest = Join-Path $destDir 'obl.exe'

# The same resolution order the hook uses. An obl the user manages is theirs.
if ($env:OBL_BIN -and (Test-Path $env:OBL_BIN)) { Note 'OBL_BIN already points at a binary'; exit 0 }
if (Get-Command 'obl' -ErrorAction SilentlyContinue) { Note 'obl is already on the PATH'; exit 0 }
foreach ($candidate in @((Join-Path $env:LOCALAPPDATA 'Programs\openbaseline\obl.exe'), $dest)) {
  if (Test-Path $candidate) { Note "obl is already installed at $candidate"; exit 0 }
}

if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
  Note "no published build for '$($env:PROCESSOR_ARCHITECTURE)', leaving the machine alone"
  exit 0
}
$asset = 'obl-windows-amd64.exe'

# OBL_CLI_BASE_URL replaces the whole prefix including /cli, the way
# selfupdate.BaseURL() reads it, not install.ps1's apex-shaped OBL_BASE_URL.
$base = if ($env:OBL_CLI_BASE_URL) { $env:OBL_CLI_BASE_URL } else { 'https://openbaseline.io/cli' }

# A failed checksum retried on every session start is a denial of service on
# the CDN and on the user, so a mismatch parks the attempt for a day.
$backoff = Join-Path $stateDir 'bootstrap-backoff'
if (Test-Path $backoff) {
  if ((Get-Item $backoff).LastWriteTimeUtc -gt (Get-Date).ToUniversalTime().AddMinutes(-1440)) {
    Note 'a recent attempt failed verification, not retrying yet'
    exit 0
  }
  Remove-Item -Force $backoff -ErrorAction SilentlyContinue
}

try { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
catch { Note "cannot create $destDir"; exit 0 }

# A directory is the portable atomic test-and-set: two sessions opened
# seconds apart would otherwise both pull the same 10MB.
$lock = Join-Path $destDir '.bootstrap.lock'
$haveLock = $false
try { New-Item -ItemType Directory -Path $lock -ErrorAction Stop | Out-Null; $haveLock = $true } catch { }
if (-not $haveLock) {
  if ((Test-Path $lock) -and (Get-Item $lock).LastWriteTimeUtc -lt (Get-Date).ToUniversalTime().AddMinutes(-10)) {
    Note 'breaking a bootstrap lock left behind by a dead session'
    Remove-Item -Force -Recurse $lock -ErrorAction SilentlyContinue
    try { New-Item -ItemType Directory -Path $lock -ErrorAction Stop | Out-Null; $haveLock = $true } catch { }
  }
}
if (-not $haveLock) { Note 'another session is bootstrapping, standing down'; exit 0 }

# Staged INSIDE the destination directory: a move cannot cross a volume, and
# a "temp then move" that quietly degrades to a copy can tear a binary in
# half. Same rule selfupdate.Replace follows.
$staged = Join-Path $destDir ".obl.download.$PID"
try {
  # latest.json rather than SHA256SUMS: it pins a version as well as a
  # checksum, so the log can say what was installed.
  $manifest = Invoke-RestMethod -Uri "$base/latest.json" -TimeoutSec 20 -UseBasicParsing
  $version = $manifest.version
  $sum = $manifest.sums.$asset

  # Refusing to install unverified bytes is the rule selfupdate.Download
  # holds. Anything that is not 64 hex characters is not a checksum.
  if (-not $version -or -not ($sum -match '^[0-9a-f]{64}$')) {
    Note "no usable checksum for $asset in the manifest, refusing to install"
    exit 0
  }

  Invoke-WebRequest -Uri "$base/$asset" -OutFile $staged -TimeoutSec 300 -UseBasicParsing
  $got = (Get-FileHash -Algorithm SHA256 $staged).Hash.ToLower()
  if ($got -ne $sum) {
    Remove-Item -Force $staged -ErrorAction SilentlyContinue
    New-Item -ItemType File -Force -Path $backoff | Out-Null
    Note "checksum mismatch for $asset (expected $sum, got $got), nothing installed"
    exit 0
  }

  # Mark-of-the-web is what SmartScreen reads; clearing it is the moral twin
  # of the quarantine xattr the POSIX script drops on macOS.
  Unblock-File -Path $staged -ErrorAction SilentlyContinue
  Move-Item -Force $staged $dest
  Note "installed obl $version into $dest"
} catch {
  Note "bootstrap failed: $($_.Exception.Message)"
} finally {
  Remove-Item -Force $staged -ErrorAction SilentlyContinue
  Remove-Item -Force -Recurse $lock -ErrorAction SilentlyContinue
}

exit 0
