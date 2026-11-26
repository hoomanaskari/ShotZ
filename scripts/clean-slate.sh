#!/usr/bin/env bash
# Removes every local ShotZ / ShotZ Dev / "Shotz" trace, for testing a clean install
# from the GitHub download. Derived from docs/UNINSTALL.md (which explains each item).
#
#   scripts/clean-slate.sh                    dry run: shows what exists and what would go
#   scripts/clean-slate.sh --yes              does it
#   scripts/clean-slate.sh --yes --include-review   also removes build/review in the checkout
#
# Never touched: the source checkout and its git history, dist/, sparkle-releases/, the keychain
# (the Sparkle private key lives there), SwiftPM .build folders, files you exported.
#
# User data (Application Support folders with captures, installed apps, build/review) is moved to
# the Trash; build products, caches and temp folders are deleted. Every path is checked before
# anything happens: if one resolves outside the expected places, the script stops without changes.
#
# Testing only: SHOTZ_CLEAN_SANDBOX=1 with HOME, TMPDIR, SHOTZ_CLEAN_APPLICATIONS and
# SHOTZ_CLEAN_REPO pointing into a throwaway folder; system commands (kill, defaults, tccutil,
# lsregister) are then only printed, never run.
set -euo pipefail

YES=0
INCLUDE_REVIEW=0
for arg in "$@"; do
  case "$arg" in
    --yes) YES=1 ;;
    --include-review) INCLUDE_REVIEW=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg (use --yes, --include-review, --help)" >&2; exit 64 ;;
  esac
done

# MARK: Locations

die() { echo "clean-slate: $*" >&2; exit 2; }
resolve_dir() { (cd "$1" 2>/dev/null && pwd -P); }

[[ -n "${HOME:-}" && "$HOME" == /* ]] || die "HOME is not an absolute path"
HOME_R="$(resolve_dir "$HOME")" || die "HOME does not exist"
TMP_R="$(resolve_dir "${TMPDIR:-/tmp}")" || die "TMPDIR does not exist"
APPS="${SHOTZ_CLEAN_APPLICATIONS:-/Applications}"
APPS_R="$(resolve_dir "$APPS")" || die "$APPS does not exist"
SCRIPT_DIR="$(resolve_dir "$(dirname "${BASH_SOURCE[0]}")")"
if [[ -n "${SHOTZ_CLEAN_REPO:-}" ]]; then
  REPO_R="$(resolve_dir "$SHOTZ_CLEAN_REPO")" || die "SHOTZ_CLEAN_REPO does not exist"
else
  # The main checkout, also when this script runs from a worktree.
  common="$(git -C "$SCRIPT_DIR/.." rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -n "$common" ]]; then
    [[ "$common" == /* ]] || common="$SCRIPT_DIR/../$common"
    REPO_R="$(resolve_dir "$common/..")"
  else
    REPO_R="$(resolve_dir "$SCRIPT_DIR/..")"
  fi
fi
[[ -n "$REPO_R" && -f "$REPO_R/Package.swift" ]] || die "cannot find the ShotZ checkout (got '$REPO_R')"

SANDBOX="${SHOTZ_CLEAN_SANDBOX:-0}"
if [[ "$SANDBOX" == 1 ]]; then
  for d in "$HOME_R" "$TMP_R" "$APPS_R" "$REPO_R"; do
    case "$d" in
      /private/tmp/*|/private/var/folders/*) ;;
      *) die "sandbox mode needs HOME, TMPDIR, SHOTZ_CLEAN_APPLICATIONS and SHOTZ_CLEAN_REPO inside a temp folder (got $d)" ;;
    esac
  done
  [[ "$HOME_R" != "$(resolve_dir "/Users/$(id -un)" 2>/dev/null || echo /nonexistent)" ]] || die "sandbox HOME is the real home"
fi

LIB="$HOME_R/Library"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
IDS=(com.pixelforty.shotz com.pixelforty.shotz.dev app.shotz.Shotz app.shotz.Shotz.dev)
DOMAINS=()
for id in "${IDS[@]}"; do DOMAINS+=("$id" "$id.testrun"); done

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
size_of() { du -sh "$1" 2>/dev/null | cut -f1 | tr -d ' '; }

# MARK: Plan
# Parallel arrays (bash 3.2): group, path, mode (trash|delete).

P_GROUP=(); P_PATH=(); P_MODE=(); P_REAL=(); P_INODE=()
REFUSED=0

# Allowed places a removable path may resolve into, each with whether its entries must carry a
# ShotZ name ("named") or may be anything ("any", the contents of build/ folders).
allowed_for() {
  local real="$1"
  local named=("$LIB/Application Support" "$LIB/Caches" "$LIB/Saved Application State" "$LIB/HTTPStorages" \
               "$LIB/Preferences" "$TMP_R" "$APPS_R")
  local p
  for p in "${named[@]}"; do
    if [[ "$real" == "$p/"* ]]; then echo named; return; fi
  done
  if [[ "$real" == "$REPO_R/build/"* ]]; then echo any; return; fi
  if [[ "$real" == "$REPO_R/.claude/worktrees/"*"/build/"* ]]; then echo any; return; fi
  echo none
}

# plan <group> <trash|delete> <path>: adds the path if it exists and passes every check.
plan() {
  local group="$1" mode="$2" path="$3"
  [[ -e "$path" || -L "$path" ]] || return 0
  [[ -n "$path" && "$path" == /* && "$path" != *$'\n'* ]] || { echo "  REFUSED (not absolute): $path"; REFUSED=1; return 0; }
  local parent base real kind
  base="$(basename "$path")"
  parent="$(resolve_dir "$(dirname "$path")")" || { echo "  REFUSED (parent unresolvable): $path"; REFUSED=1; return 0; }
  real="$parent/$base"
  case "$real" in
    */.git|*/.git/*|*/dist|*/dist/*|*/sparkle-releases|*/sparkle-releases/*)
      echo "  REFUSED (protected): $real"; REFUSED=1; return 0 ;;
  esac
  if [[ "$real" == "$REPO_R/"* && "$real" != "$REPO_R/build/"* && "$real" != "$REPO_R/.claude/worktrees/"*"/build/"* ]]; then
    echo "  REFUSED (inside the source checkout): $real"; REFUSED=1; return 0
  fi
  kind="$(allowed_for "$real")"
  if [[ "$kind" == none ]]; then echo "  REFUSED (outside the expected places): $real"; REFUSED=1; return 0; fi
  if [[ "$kind" == named ]]; then
    case "$(lower "$base")" in
      *shotz*|*pixelforty*) ;;
      *) echo "  REFUSED (not a ShotZ name): $real"; REFUSED=1; return 0 ;;
    esac
  fi
  # The same folder under two spellings (Shotz.app / ShotZ.app on a case-insensitive disk) once only.
  local i inode
  inode="$(stat -f '%d:%i' "$path" 2>/dev/null || echo "$real")"
  for ((i = 0; i < ${#P_INODE[@]}; i++)); do [[ "${P_INODE[$i]}" == "$inode" ]] && return 0; done
  P_GROUP+=("$group"); P_PATH+=("$path"); P_MODE+=("$mode"); P_REAL+=("$real"); P_INODE+=("$inode")
}

# Apps in /Applications (both spellings, interrupted install.sh leftovers).
plan "Installed apps" trash "$APPS_R/ShotZ.app"
plan "Installed apps" trash "$APPS_R/Shotz.app"
for p in "$APPS_R"/.ShotZ.app.installing.* "$APPS_R"/.ShotZ.app.previous.* "$APPS_R"/.Shotz.app.previous.*; do
  plan "Installed apps" trash "$p"
done

# Build products: everything in each build/ folder of the checkout and its worktrees.
build_dirs=("$REPO_R/build")
for wt in "$REPO_R"/.claude/worktrees/*/; do
  [[ -d "$wt/build" ]] && build_dirs+=("${wt%/}/build")
done
for b in "${build_dirs[@]}"; do
  [[ -d "$b" ]] || continue
  for p in "$b"/* "$b"/.[!.]*; do
    [[ -e "$p" || -L "$p" ]] || continue
    if [[ "$(basename "$p")" == review && "$b" == "$REPO_R/build" ]]; then
      [[ "$INCLUDE_REVIEW" == 1 ]] && plan "Review sheets (build/review)" trash "$p"
      continue
    fi
    plan "Build products ($b)" delete "$p"
  done
done

# Application Support: current ids (captures!), earlier names, test runs, migration staging.
AS="$LIB/Application Support"
for n in com.pixelforty.shotz com.pixelforty.shotz.dev com.pixelforty.shotz.testrun com.pixelforty.shotz.dev.testrun \
         com.pixelforty.shotz.migrating com.pixelforty.shotz.dev.migrating \
         Shotz "ShotZ Dev" "ShotZ Test Runs" "ShotZ Dev Test Runs" Shotz-Dev; do
  plan "Application Support (captures, documents, history)" trash "$AS/$n"
done

# Caches (incl. Sparkle's), saved state, HTTP storage.
for id in "${IDS[@]}"; do
  plan "Caches, saved state, HTTP storage" delete "$LIB/Caches/$id"
  plan "Caches, saved state, HTTP storage" delete "$LIB/Saved Application State/$id.savedState"
  plan "Caches, saved state, HTTP storage" delete "$LIB/HTTPStorages/$id"
  plan "Caches, saved state, HTTP storage" delete "$LIB/HTTPStorages/$id.binarycookies"
done

# Temp folders.
for n in com.pixelforty.shotz com.pixelforty.shotz.dev com.pixelforty.shotz.testrun com.pixelforty.shotz.dev.testrun \
         Shotz "ShotZ Dev" "ShotZ Test Runs" "ShotZ Dev Test Runs" Shotz-Dev; do
  plan "Temporary folders" delete "$TMP_R/$n"
done
for p in "$TMP_R"/Shotz*Tests-*; do plan "Temporary folders (test leftovers)" delete "$p"; done

# Throw-away preference suites left by `swift test` (removed as files: there can be thousands).
STRAY_PREFS=()
for p in "$LIB/Preferences"/Shotz*Tests-*.plist; do
  [[ -e "$p" ]] || continue
  case "$(basename "$p")" in
    Shotz*Tests-*.plist) STRAY_PREFS+=("$p") ;;
  esac
done

# Defaults domains that exist.
EXISTING_DOMAINS=()
for d in "${DOMAINS[@]}"; do
  if [[ -e "$LIB/Preferences/$d.plist" ]]; then
    EXISTING_DOMAINS+=("$d")
  elif [[ "$SANDBOX" != 1 ]] && defaults read "$d" >/dev/null 2>&1; then
    EXISTING_DOMAINS+=("$d")
  fi
done

# Running instances (matched by resolved executable path).
PIDS=(); PID_PATHS=()
while read -r pid exe; do
  [[ -n "$pid" ]] || continue
  case "$exe" in
    */ShotZ.app/Contents/MacOS/ShotZ|*/Shotz.app/Contents/MacOS/Shotz|*/ShotZ.app/Contents/MacOS/Shotz|\
    */"ShotZ Dev.app"/Contents/MacOS/ShotZ|*/"Shotz Dev.app"/Contents/MacOS/Shotz|*/"ShotZ Dev.app"/Contents/MacOS/Shotz)
      PIDS+=("$pid"); PID_PATHS+=("$exe") ;;
  esac
done < <(ps -axo pid=,comm= 2>/dev/null | sed -E 's/^ *([0-9]+) +/\1 /')

# Launch Services registrations (metadata only; dist/ and sparkle-releases/ copies are left registered).
LS_PATHS=()
if [[ -x "$LSREGISTER" ]]; then
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    # Left registered: release copies in dist/ and sparkle-releases/, and mounted disk images
    # (the downloaded DMG under test lives in /Volumes).
    case "$p" in "$REPO_R/dist/"*|"$REPO_R/sparkle-releases/"*|/Volumes/*) continue ;; esac
    LS_PATHS+=("$p")
  done < <("$LSREGISTER" -dump 2>/dev/null | sed -nE 's/^path: +(.*\/(ShotZ|Shotz)( Dev)?\.app)( \(0x[0-9a-f]+\))?$/\1/p' | sort -u)
fi

# MARK: Report

[[ "$REFUSED" == 0 ]] || die "refusing to continue: a path above resolved outside the expected places. Nothing was changed."

if [[ "$YES" == 1 ]]; then echo "== ShotZ clean slate: REMOVING (--yes)"; else echo "== ShotZ clean slate: DRY RUN (nothing will be changed; re-run with --yes to act)"; fi
[[ "$SANDBOX" == 1 ]] && echo "   sandbox mode: system commands are printed, not run"
echo "   checkout: $REPO_R   home: $HOME_R"
echo

echo "-- Running instances (quit first: SIGTERM, then SIGKILL after 5 s)"
if [[ ${#PIDS[@]} -eq 0 ]]; then echo "   none"; else for ((i = 0; i < ${#PIDS[@]}; i++)); do echo "   pid ${PIDS[$i]}  ${PID_PATHS[$i]}"; done; fi
echo

last=""
for ((i = 0; i < ${#P_PATH[@]}; i++)); do
  if [[ "${P_GROUP[$i]}" != "$last" ]]; then echo "-- ${P_GROUP[$i]}"; last="${P_GROUP[$i]}"; fi
  verb="delete"; [[ "${P_MODE[$i]}" == trash ]] && verb="to Trash"
  extra=""
  if [[ -d "${P_PATH[$i]}/Captures" ]]; then
    n=$(find "${P_PATH[$i]}/Captures" -type f 2>/dev/null | wc -l | tr -d ' ')
    extra="  ($n capture files)"
  fi
  printf '   %-9s %6s  %s%s\n' "$verb" "$(size_of "${P_PATH[$i]}")" "${P_PATH[$i]}" "$extra"
done
[[ ${#P_PATH[@]} -eq 0 ]] && echo "-- Files and folders: none found"
echo

echo "-- Preferences (defaults delete per domain)"
if [[ ${#EXISTING_DOMAINS[@]} -eq 0 ]]; then echo "   no ShotZ domains"; else for d in ${EXISTING_DOMAINS[@]+"${EXISTING_DOMAINS[@]}"}; do echo "   $d"; done; fi
if [[ ${#STRAY_PREFS[@]} -gt 0 ]]; then
  echo "   + ${#STRAY_PREFS[@]} throw-away 'swift test' suites (Shotz*Tests-<UUID>.plist, deleted as files), e.g. $(basename "${STRAY_PREFS[0]}")"
fi
echo

echo "-- Screen Recording permission (one reset per bundle id)"
for id in "${IDS[@]}"; do echo "   tccutil reset ScreenCapture $id"; done
echo

echo "-- Launch Services registrations (lsregister -u)"
if [[ ${#LS_PATHS[@]} -eq 0 ]]; then echo "   none"; else for p in ${LS_PATHS[@]+"${LS_PATHS[@]}"}; do echo "   $p"; done; fi
echo

CAPTURE_WARNING=0
for ((i = 0; i < ${#P_PATH[@]}; i++)); do [[ -d "${P_PATH[$i]}/Captures" ]] && CAPTURE_WARNING=1; done
if [[ "$CAPTURE_WARNING" == 1 ]]; then
  echo "!! WARNING: your ShotZ captures, documents and history above go to the Trash and ShotZ will no"
  echo "!! longer know them. Copy out anything you want to keep before emptying the Trash."
  echo
fi

print_left_in_place() {
  echo "-- Left in place"
  echo "   $REPO_R (source, .git, dist/, sparkle-releases/), SwiftPM .build folders"
  [[ "$INCLUDE_REVIEW" == 1 ]] || echo "   $REPO_R/build/review (pass --include-review to remove it)"
  echo "   the keychain (Sparkle's private key), exported screenshots (e.g. ~/Desktop)"
  echo "   Launch Services entries for dist/, sparkle-releases/ and mounted disk images (/Volumes)"
  echo "   unified log entries (they age out) and crash reports in ~/Library/Logs/DiagnosticReports"
  echo
  echo "-- Manual steps"
  echo "   1. System Settings > General > Login Items & Extensions: remove ShotZ / ShotZ Dev if still listed"
  echo "      (each app's login item can only be unregistered by the app itself or there)."
  echo "   2. System Settings > Privacy & Security > Screen & System Audio Recording: check no ShotZ entry is left."
  echo "   3. Empty the Trash when you are sure."
}

if [[ "$YES" != 1 ]]; then
  print_left_in_place
  echo
  echo "Dry run only. Nothing was changed."
  exit 0
fi

# MARK: Act

run() {   # system commands: printed in sandbox mode
  if [[ "$SANDBOX" == 1 ]]; then echo "   [sandbox] would run: $*"; else "$@"; fi
}

echo "== Quitting running instances"
for ((i = 0; i < ${#PIDS[@]}; i++)); do
  echo "   SIGTERM pid ${PIDS[$i]}"
  run kill -TERM "${PIDS[$i]}" 2>/dev/null || true
done
if [[ ${#PIDS[@]} -gt 0 && "$SANDBOX" != 1 ]]; then
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    alive=0
    for pid in ${PIDS[@]+"${PIDS[@]}"}; do kill -0 "$pid" 2>/dev/null && alive=1; done
    [[ "$alive" == 0 ]] && break
    sleep 0.5
  done
  for pid in ${PIDS[@]+"${PIDS[@]}"}; do
    if kill -0 "$pid" 2>/dev/null; then echo "   SIGKILL pid $pid"; kill -KILL "$pid" 2>/dev/null || true; fi
  done
fi

echo "== Resetting Screen Recording permission"
for id in "${IDS[@]}"; do run tccutil reset ScreenCapture "$id" || echo "   (no entry for $id)"; done

echo "== Removing preferences"
for d in ${EXISTING_DOMAINS[@]+"${EXISTING_DOMAINS[@]}"}; do
  if [[ "$SANDBOX" == 1 ]]; then
    echo "   [sandbox] would run: defaults delete $d"
    rm -f -- "$LIB/Preferences/$d.plist"
  else
    defaults delete "$d" 2>/dev/null || echo "   (could not delete $d)"
  fi
done
for p in ${STRAY_PREFS[@]+"${STRAY_PREFS[@]}"}; do
  case "$p" in "$LIB/Preferences/Shotz"*"Tests-"*.plist) rm -f -- "$p" ;; *) die "unexpected preference path $p" ;; esac
done
[[ ${#STRAY_PREFS[@]} -gt 0 ]] && echo "   removed ${#STRAY_PREFS[@]} test suites"

echo "== Unregistering from Launch Services"
for p in ${LS_PATHS[@]+"${LS_PATHS[@]}"}; do run "$LSREGISTER" -u "$p" 2>/dev/null || true; done

echo "== Removing files and folders"
TRASH="$HOME_R/.Trash"
mkdir -p "$TRASH"
for ((i = 0; i < ${#P_PATH[@]}; i++)); do
  p="${P_PATH[$i]}"
  [[ -n "$p" && "$p" == /* ]] || die "empty path in plan"
  [[ -e "$p" || -L "$p" ]] || continue
  if [[ "${P_MODE[$i]}" == trash ]]; then
    dest="$TRASH/$(basename "$p")"
    [[ -e "$dest" ]] && dest="$dest $(date +%Y-%m-%d\ %H.%M.%S)"
    mv -- "$p" "$dest"
    echo "   to Trash: $p"
  elif [[ -L "$p" ]]; then
    rm -f -- "$p"
    echo "   deleted link: $p"
  else
    rm -rf -- "$p"
    echo "   deleted: $p"
  fi
done
echo
print_left_in_place
echo
echo "Done."
