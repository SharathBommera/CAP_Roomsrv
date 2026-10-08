#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
STATE_DIR="$PROJECT_DIR/.git/bas-git-backup"
LOG_FILE="$STATE_DIR/backup-scheduler.log"
PID_FILE="$STATE_DIR/backup-scheduler.pid"
BACKUP_SCRIPT="$PROJECT_DIR/scripts/github-backup.sh"
INTERVAL_SECONDS="${BACKUP_INTERVAL_SECONDS:-1800}"
TERMINATE=0

mkdir -p "$STATE_DIR"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    log "Scheduler already running with PID $OLD_PID; exiting duplicate instance."
    exit 0
  fi
  rm -f "$PID_FILE"
fi

echo "$$" > "$PID_FILE"

cleanup() {
  rm -f "$PID_FILE"
  log "Scheduler stopped."
}
trap cleanup EXIT
trap 'TERMINATE=1' INT TERM

log "Scheduler started with PID $$; interval $INTERVAL_SECONDS seconds."

while [[ "$TERMINATE" -eq 0 ]]; do
  if "$BACKUP_SCRIPT" >> "$LOG_FILE" 2>&1; then
    :
  else
    log "Backup script returned a non-zero exit code; scheduler will retry later."
  fi

  for ((i=0; i<INTERVAL_SECONDS && TERMINATE==0; i++)); do
    sleep 1
  done
done
