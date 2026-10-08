#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
STATE_DIR="$PROJECT_DIR/.git/bas-git-backup"
LOG_FILE="$STATE_DIR/github-backup.log"
LOCK_DIR="$STATE_DIR/backup.lock"

mkdir -p "$STATE_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "Another backup operation is already running; skipping this cycle."
  exit 0
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

cd "$PROJECT_DIR" || {
  log "ERROR: Cannot access project directory: $PROJECT_DIR"
  exit 1
}

BRANCH="$(git branch --show-current 2>/dev/null || true)"
if [[ -z "$BRANCH" ]]; then
  log "ERROR: Repository is in detached HEAD state. Backup skipped."
  exit 1
fi

REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
case "$REMOTE_URL" in
  https://github.com/*/*|https://github.com/*/*.git) ;;
  *)
    log "ERROR: origin is not a GitHub HTTPS URL. Backup skipped."
    exit 1
    ;;
esac

log "=========================================="
log "CAP Project - Automatic Git Backup"
log "Branch: $BRANCH"
log "=========================================="

STATUS="$(git status --porcelain --untracked-files=all 2>/dev/null || true)"
if [[ -n "$STATUS" ]]; then
  log "Working-tree changes detected. Staging all non-ignored changes..."
  if ! git add -A; then
    log "ERROR: git add failed. Resolve repository errors/conflicts and retry."
    exit 1
  fi

  if ! git diff --cached --quiet; then
    COMMIT_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
    log "Creating commit..."
    if ! git commit -m "chore: automatic BAS backup $COMMIT_TIME"; then
      log "ERROR: git commit failed. Check git status and commit identity."
      exit 1
    fi
  else
    log "No commit-worthy changes remained after staging (likely ignored files only)."
  fi
fi

# Always check for local commits that still need pushing. This is important:
# if a previous push failed after a successful commit, the next cycle must retry.
AHEAD=0
if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  read -r _BEHIND AHEAD < <(git rev-list --left-right --count "origin/$BRANCH...$BRANCH" 2>/dev/null || printf '0 0\n')
else
  AHEAD=1
fi

if [[ "${AHEAD:-0}" -gt 0 ]]; then
  log "Local commits waiting to be pushed: $AHEAD"
  log "Pushing to GitHub..."
  if git push origin "$BRANCH"; then
    log "SUCCESS: Changes pushed to GitHub."
  else
    log "ERROR: git push failed. The local commit(s) are retained and the scheduler will retry on the next cycle."
    exit 1
  fi
else
  log "No changes to commit or push."
fi
