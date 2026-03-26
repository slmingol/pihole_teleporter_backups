#!/bin/bash

set -eu
# Prevent xtrace from echoing secrets
set +x

PATH="$PATH:/usr/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/sbin:/bin"

# Configuration
PIHOLE_HOST="localhost"
PIHOLE_PASSWORD="${PIHOLE_PASSWORD:-}"
PIHOLE_SECRET_FILE="${PIHOLE_SECRET_FILE:-$HOME/.config/pihole_backup.env}"
BACKUP_DIR="/home/pi/pihole_teleporter_backups"
BACKUP_FILE="$BACKUP_DIR/pihole_teleporter_$(date +%Y%m%d_%H%M%S).zip"

PFSENSE_HOST="root@pfsense-rtr1"
PFSENSE_MOUNT="/mnt/usb_backup"
PFSENSE_FS_TYPE="msdosfs"

GHOST_FILES_HOST="slm@ghost-files"
GHOST_FILES_PATH="/volume2/data/backups"

# Verbosity: set VERBOSE=1 or pass --verbose to enable detailed output
VERBOSE="${VERBOSE:-0}"
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
  esac
done

# Logging function
log() {
  printf "[%s] %s\n" "$(date +'%H:%M:%S')" "$*"
}

log_verbose() {
  [ "$VERBOSE" = "1" ] && printf "  > %s\n" "$*" || true
}

# Load secret if not in environment
if [ -z "$PIHOLE_PASSWORD" ] && [ -f "$PIHOLE_SECRET_FILE" ]; then
  # shellcheck disable=SC1090
  . "$PIHOLE_SECRET_FILE"
fi

PIHOLE_PASSWORD="${PIHOLE_PASSWORD:-}"
if [ -z "$PIHOLE_PASSWORD" ]; then
  log "ERROR: PIHOLE_PASSWORD is not set."
  log "Set it in env or in $PIHOLE_SECRET_FILE as: PIHOLE_PASSWORD='your_password'"
  exit 1
fi

mkdir -p "$BACKUP_DIR"

# ============================================================================
# Function: Download Pi-hole teleporter backup
# ============================================================================
backup_pihole() {
  local auth_json=""
  local base_url=""
  local sid=""

  log "STEP 1/4: Backing up Pi-hole..."

  for url in "http://$PIHOLE_HOST" "https://$PIHOLE_HOST"; do
    log_verbose "Trying auth at $url/api/auth ..."
    auth_json=$(printf '{"password":"%s"}' "$PIHOLE_PASSWORD" | curl -sS -k -m 15 -X POST "$url/api/auth" -H "Content-Type: application/json" --data-binary @- 2>/dev/null || true)
    sid=$(printf '%s' "$auth_json" | sed -n 's/.*"sid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [ -n "$sid" ]; then
      base_url="$url"
      break
    fi
  done

  if [ -z "$sid" ]; then
    log "ERROR: Failed to authenticate to Pi-hole API."
    [ "$VERBOSE" = "1" ] && printf "Last response: %s\n" "${auth_json:-<empty>}" || true
    log "Tip: verify PIHOLE_PASSWORD and that Pi-hole API is reachable on http/https localhost."
    return 1
  fi

  log_verbose "Authenticated against $base_url"

  log_verbose "Downloading backup..."
  curl -sS -k -f -o "$BACKUP_FILE" -H "X-FTL-SID: $sid" "$base_url/api/teleporter"

  log_verbose "Logging out..."
  curl -sS -k -X DELETE "$base_url/api/auth" -H "X-FTL-SID: $sid" > /dev/null || true

  sudo chown pi:pi "$BACKUP_FILE"

  log_verbose "Cleaning up backups older than 10 days..."
  find "$BACKUP_DIR" -maxdepth 1 -type f -mtime +10 -name "*.zip" -delete

  log "✓ Backup complete: $(basename "$BACKUP_FILE")"
}

# ============================================================================
# Function: Ensure pfSense backup mount is writable (repair if needed)
# ============================================================================
ensure_pfsense_rw_or_fail() {
  local host="${1:-$PFSENSE_HOST}"
  local mountpoint="${2:-$PFSENSE_MOUNT}"
  local fstype="${3:-$PFSENSE_FS_TYPE}"

  log "STEP 2/4: Checking pfSense backup mount..."

  ssh -o BatchMode=yes "$host" "MNT='$mountpoint' FSTYPE='$fstype' VERBOSE='$VERBOSE' sh -s" <<'EOSH'
set -eu

LINE=$(mount | awk -v m="$MNT" '$3=="on" && $4==m {print; exit}')
if [ -z "$LINE" ]; then
  echo "ERROR: mountpoint $MNT not found" >&2
  exit 2
fi

DEV=$(printf '%s\n' "$LINE" | awk '{print $1}')

if printf '%s\n' "$LINE" | grep -q 'read-only'; then
  [ "$VERBOSE" = "1" ] && echo "  > Read-only detected, repairing $DEV ..." || echo "  > Repairing mount..."
  umount "$MNT"
  fsck_msdosfs -fy "$DEV" > /dev/null 2>&1
  mount -t "$FSTYPE" -o rw "$DEV" "$MNT"
fi

PROBE="$MNT/.rw_probe_$$"
touch "$PROBE"
rm -f "$PROBE"

mount | awk -v m="$MNT" '$3=="on" && $4==m {print; exit}' | grep -q 'read-only' && {
  echo "ERROR: still read-only after remount" >&2
  exit 3
}

echo "OK"
EOSH
  log "✓ Mount is writable"
}

# ============================================================================
# Function: Sync backups to all destinations
# ============================================================================
sync_backups() {
  local subdir_name
  local rsync_opts="-a --no-o --no-g --delete"
  
  if [ "$VERBOSE" = "1" ]; then
    rsync_opts="$rsync_opts -vv --progress --stats"
  else
    rsync_opts="$rsync_opts -q"
  fi

  subdir_name=$(hostname | sed 's/-//g')

  log "STEP 3/4: Syncing to pfSense backup..."
  rsync $rsync_opts -e 'ssh -i ~/.ssh/id_rsa' \
    "$BACKUP_DIR/" \
    "$PFSENSE_HOST:$PFSENSE_MOUNT/$subdir_name/."
  log "✓ pfSense sync complete"

  log "STEP 4/4: Syncing to ghost-files backup..."
  rsync $rsync_opts -e 'ssh -i ~/.ssh/id_rsa' \
    "$BACKUP_DIR/" \
    "$GHOST_FILES_HOST:$GHOST_FILES_PATH/$subdir_name/."
  log "✓ ghost-files sync complete"
}

# ============================================================================
# Main
# ============================================================================
main() {
  log "Starting Pi-hole backup and sync (verbose=$VERBOSE)"

  if ! backup_pihole; then
    log "ERROR: Pi-hole backup failed"
    return 1
  fi

  if ! ensure_pfsense_rw_or_fail; then
    log "ERROR: pfSense mount check failed, skipping syncs"
    return 1
  fi

  if ! sync_backups; then
    log "ERROR: Sync failed"
    return 1
  fi

  log "✓ All done"
}

main "$@"
