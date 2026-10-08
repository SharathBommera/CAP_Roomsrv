#!/usr/bin/env bash
set -u

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATE_DIR="$PROJECT_DIR/.git/bas-git-backup"
LOG_FILE="$STATE_DIR/github-backup.log"
LOCK_DIR="$STATE_DIR/backup.lock"

mkdir -p "$STATE_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "Backup already running for this project; skipped."
  exit 0
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

cd "$PROJECT_DIR" || { log "ERROR: project directory unavailable."; exit 1; }

BRANCH="$(git branch --show-current 2>/dev/null || true)"
if [[ -z "$BRANCH" ]]; then
  log "SKIP: detached HEAD."
  exit 0
fi

REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
case "$REMOTE_URL" in
  https://github.com/*/*|https://github.com/*/*.git) ;;
  *) log "SKIP: origin is not GitHub HTTPS."; exit 0 ;;
esac

# Never interfere with an in-progress manual Git operation.
if [[ -f "$PROJECT_DIR/.git/index.lock" || -f "$PROJECT_DIR/.git/MERGE_HEAD" || -f "$PROJECT_DIR/.git/CHERRY_PICK_HEAD" || -f "$PROJECT_DIR/.git/REVERT_HEAD" || -d "$PROJECT_DIR/.git/rebase-merge" || -d "$PROJECT_DIR/.git/rebase-apply" ]]; then
  log "SKIP: another Git operation is in progress. Will retry next cycle."
  exit 0
fi

CONFLICTS="$(git diff --name-only --diff-filter=U 2>/dev/null || true)"
if [[ -n "$CONFLICTS" ]]; then
  log "SKIP: unresolved merge conflicts exist."
  exit 0
fi

export GIT_TERMINAL_PROMPT=0

log "=========================================="
log "CAP Project - Automatic Git Backup"
log "Branch: $BRANCH"
log "=========================================="

# Refresh remote-tracking information without changing working files.
if ! git fetch origin --quiet; then
  log "SKIP: git fetch failed. Local work is retained; retrying next cycle."
  exit 1
fi

STATUS_BEFORE="$(git status --porcelain --untracked-files=all 2>/dev/null || true)"
if [[ -n "$STATUS_BEFORE" ]]; then
  # Give a save in progress a moment to settle, then re-check.
  sleep 2
  STATUS_AFTER="$(git status --porcelain --untracked-files=all 2>/dev/null || true)"
  if [[ "$STATUS_BEFORE" != "$STATUS_AFTER" ]]; then
    log "SKIP: working tree changed during backup check; retrying next cycle."
    exit 0
  fi

  log "Working-tree changes detected. Staging all non-ignored changes..."
  if ! git add -A; then
    log "ERROR: git add failed; retrying next cycle."
    exit 1
  fi

  if ! git diff --cached --quiet; then
    COMMIT_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
    log "Creating automatic backup commit..."
    if ! git commit -m "chore: automatic BAS backup $COMMIT_TIME"; then
      log "ERROR: git commit failed; no push attempted."
      exit 1
    fi
  else
    log "No commit-worthy changes after staging."
  fi
fi

read -r BEHIND AHEAD < <(git rev-list --left-right --count "origin/$BRANCH...$BRANCH" 2>/dev/null || printf '0 0\n')
BEHIND="${BEHIND:-0}"
AHEAD="${AHEAD:-0}"

if (( BEHIND > 0 )); then
  log "SKIP: GitHub has $BEHIND commit(s) not in the local branch. Automatic push is paused to avoid an implicit merge/rebase."
  exit 0
fi

if (( AHEAD > 0 )); then
  log "Local commits waiting to be pushed: $AHEAD"
  log "Pushing to GitHub..."
  if git push origin "$BRANCH"; then
    log "SUCCESS: changes pushed to GitHub."
  else
    log "ERROR: git push failed. Local commits retained; next cycle will retry."
    exit 1
  fi
else
  log "No changes to commit or push."
fi
