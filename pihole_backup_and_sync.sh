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

PFSENSE_HOST="admin@pfsense-rtr1"
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

# Colors
COLOR_RESET="\033[0m"
COLOR_CYAN="\033[0;36m"
COLOR_GREEN="\033[0;32m"
COLOR_RED="\033[0;31m"
COLOR_YELLOW="\033[1;33m"
COLOR_DIM="\033[2m"

# Logging function
log() {
  printf "${COLOR_DIM}[%s]${COLOR_RESET} %s\n" "$(date +'%H:%M:%S')" "$*"
}

log_step() {
  printf "\n${COLOR_YELLOW}━━━ %s${COLOR_RESET}\n" "$*"
}

log_success() {
  printf "    ${COLOR_GREEN}✓${COLOR_RESET} %s\n" "$*"
}

log_error() {
  printf "    ${COLOR_RED}✗${COLOR_RESET} %s\n" "$*"
}

log_verbose() {
  [ "$VERBOSE" = "1" ] && printf "      ${COLOR_DIM}• %s${COLOR_RESET}\n" "$*" || true
}

# Load secret if not in environment
if [ -z "$PIHOLE_PASSWORD" ] && [ -f "$PIHOLE_SECRET_FILE" ]; then
  # shellcheck disable=SC1090
  . "$PIHOLE_SECRET_FILE"
fi

PIHOLE_PASSWORD="${PIHOLE_PASSWORD:-}"
if [ -z "$PIHOLE_PASSWORD" ]; then
  printf "\n${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n"
  printf "${COLOR_RED}  ✗ Configuration Error${COLOR_RESET}\n"
  printf "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n\n"
  printf "${COLOR_RED}ERROR:${COLOR_RESET} PIHOLE_PASSWORD is not set.\n\n"
  printf "Set it in one of these ways:\n"
  printf "  1. Run: ./setup_password.sh\n"
  printf "  2. Set in $PIHOLE_SECRET_FILE as: PIHOLE_PASSWORD='your_password'\n"
  printf "  3. Export as env var: export PIHOLE_PASSWORD='your_password'\n\n"
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

  log_step "STEP 1/4: Backing up Pi-hole"

  # Try common Pi-hole ports (http:80, http:8080, https:443, https:4443)
  for url in "http://$PIHOLE_HOST" "http://$PIHOLE_HOST:8080" "https://$PIHOLE_HOST" "https://$PIHOLE_HOST:4443"; do
    log_verbose "Trying auth at $url/api/auth ..."
    auth_json=$(printf '{"password":"%s"}' "$PIHOLE_PASSWORD" | curl -sS -k -m 15 -X POST "$url/api/auth" -H "Content-Type: application/json" --data-binary @- 2>/dev/null || true)
    sid=$(printf '%s' "$auth_json" | sed -n 's/.*"sid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [ -n "$sid" ]; then
      base_url="$url"
      log_verbose "Connected successfully via $url"
      break
    fi
  done

  if [ -z "$sid" ]; then
    printf "\n${COLOR_RED}ERROR:${COLOR_RESET} Failed to authenticate to Pi-hole API.\n"
    if [ "$VERBOSE" = "1" ]; then
      printf "${COLOR_DIM}Last response: %s${COLOR_RESET}\n" "${auth_json:-<empty>}"
    fi
    printf "\n${COLOR_YELLOW}Tip:${COLOR_RESET} Verify PIHOLE_PASSWORD is correct and Pi-hole API is reachable.\n"
    printf "     Check: sudo systemctl status pihole-FTL\n\n"
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

  log_success "Backup saved: $(basename "$BACKUP_FILE")"
}

# ============================================================================
# Function: Ensure pfSense backup mount is writable (repair if needed)
# ============================================================================
ensure_pfsense_rw_or_fail() {
  local host="${1:-$PFSENSE_HOST}"
  local mountpoint="${2:-$PFSENSE_MOUNT}"
  local fstype="${3:-$PFSENSE_FS_TYPE}"

  log_step "STEP 2/4: Checking pfSense backup mount"

  local result
  if ! result=$(ssh -o BatchMode=yes "$host" "MNT='$mountpoint' FSTYPE='$fstype' VERBOSE='$VERBOSE' sh -s" 2>&1 <<'EOSH'
set -eu

LINE=$(mount | awk -v m="$MNT" '$2=="on" && $3==m {print; exit}')
if [ -z "$LINE" ]; then
  echo "Mountpoint $MNT not found"
  exit 2
fi

DEV=$(printf '%s\n' "$LINE" | awk '{print $1}')

# Test if writable first
PROBE="$MNT/.rw_probe_$$"
if ! touch "$PROBE" 2>/dev/null; then
  [ "$VERBOSE" = "1" ] && echo "Read-only detected, repairing $DEV ..." || true
  umount "$MNT"
  fsck_msdosfs -fy "$DEV" > /dev/null 2>&1
  mount -t "$FSTYPE" -o rw "$DEV" "$MNT"
  
  # Test again after repair
  if ! touch "$PROBE" 2>/dev/null; then
    echo "Still read-only after remount"
    exit 3
  fi
fi

rm -f "$PROBE"

echo "OK"
EOSH
); then
    log_error "Mount check failed: $result"
    return 1
  fi

  log_verbose "Mount status: $result"
  log_success "Mount is ready and writable"
}

# ============================================================================
# Function: Sync backups to all destinations
# ============================================================================
sync_backups() {
  local subdir_name
  local rsync_opts="-a --no-o --no-g --delete --modify-window=2"
  
  if [ "$VERBOSE" = "1" ]; then
    rsync_opts="$rsync_opts -vv --progress --stats"
  else
    rsync_opts="$rsync_opts -q"
  fi

  subdir_name=$(hostname | sed 's/-//g')

  log_step "STEP 3/4: Syncing to pfSense backup"
  rsync $rsync_opts -e 'ssh -i ~/.ssh/id_rsa' \
    "$BACKUP_DIR/" \
    "$PFSENSE_HOST:$PFSENSE_MOUNT/$subdir_name/."
  log_success "Synced to pfSense"

  log_step "STEP 4/4: Syncing to ghost-files backup"
  rsync $rsync_opts -e 'ssh -i ~/.ssh/id_rsa' \
    "$BACKUP_DIR/" \
    "$GHOST_FILES_HOST:$GHOST_FILES_PATH/$subdir_name/."
  log_success "Synced to ghost-files"
}

# ============================================================================
# Main
# ============================================================================
main() {
  printf "\n${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n"
  printf "${COLOR_CYAN}  Pi-hole Backup & Sync${COLOR_RESET}\n"
  printf "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n"
  log "Started at $(date +'%Y-%m-%d %H:%M:%S')"

  if ! backup_pihole; then
    printf "\n${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n"
    printf "${COLOR_RED}  ✗ Backup failed${COLOR_RESET}\n"
    printf "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n\n"
    return 1
  fi

  if ! ensure_pfsense_rw_or_fail; then
    printf "\n${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n"
    printf "${COLOR_RED}  ✗ Mount check failed - skipping syncs${COLOR_RESET}\n"
    printf "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n\n"
    return 1
  fi

  if ! sync_backups; then
    printf "\n${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n"
    printf "${COLOR_RED}  ✗ Sync failed${COLOR_RESET}\n"
    printf "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n\n"
    return 1
  fi

  printf "\n${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n"
  printf "${COLOR_GREEN}  ✓ All operations completed successfully${COLOR_RESET}\n"
  printf "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n\n"
}

main "$@"
