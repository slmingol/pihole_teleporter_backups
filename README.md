# Pi-hole Teleporter Backup & Sync

Automatically backup Pi-hole configuration via teleporter API and sync to remote servers with colorful, professional output.

## Quick Start

```bash
# 1. Clone or copy the repo
cd ~/pihole_teleporter_backups

# 2. Configure your Pi-hole password
./setup_password.sh

# 3. Set up SSH keys for remote servers
ssh-keygen -t rsa -b 4096 -N '' <<<$'\n'
ssh-copy-id -i ~/.ssh/id_rsa admin@pfsense-rtr1
ssh-copy-id -i ~/.ssh/id_rsa slm@ghost-files

# 4. Test the script
./pihole_backup_and_sync.sh --verbose

# 5. Add to crontab for daily backups
crontab -e
# Add: 00 22 * * * /home/pi/pihole_teleporter_backups/pihole_backup_and_sync.sh
```

## Features

- 🔐 **Secure Authentication**: Safely stores Pi-hole password in `~/.config`
- 🌐 **Auto Port Detection**: Automatically detects Pi-hole on ports 80, 8080, 443, or 4443
- 🔧 **Auto-Repair**: Automatically repairs read-only USB mounts with fsck
- 🎨 **Colorful Output**: Clean, professional terminal output with colors and Unicode symbols
- 📦 **Multi-Destination Sync**: Backs up to both pfSense USB and remote NAS
- 🧹 **Auto Cleanup**: Retains only last 10 days of backups
- 🔍 **Verbose Mode**: Optional detailed logging for troubleshooting

## Configuration

### Pi-hole Password

#### Quick Setup (Recommended)

Run the helper script to securely configure your password:

```bash
./setup_password.sh
```

#### Manual Setup

Alternatively, create a secret file manually:

```bash
mkdir -p ~/.config
printf "PIHOLE_PASSWORD='your_actual_pihole_password'\n" > ~/.config/pihole_backup.env
chmod 600 ~/.config/pihole_backup.env
```

The script will automatically load the password from this file. You can also set the `PIHOLE_PASSWORD` environment variable.

## Setup

### mkdir
```
$ mkdir -p ~/pihole_teleporter_backups
```

### Create an SSH key
```
$ ssh-keygen -t rsa -b 4096 -N '' <<<$'\n'
```

### Allow it to SSH to remote backup servers w/o interaction

For pfSense backup:
```
$ ssh-copy-id -i ~/.ssh/id_rsa admin@pfsense-rtr1
```

For ghost-files backup:
```
$ ssh-copy-id -i ~/.ssh/id_rsa slm@ghost-files
```

### Add crontab entry for user `pi`

Edit crontab:
```bash
crontab -e
```

Add this line for daily execution at 10 PM:
```
00 22 * * * /home/pi/pihole_teleporter_backups/pihole_backup_and_sync.sh
```

Verify it's saved:
```bash
crontab -l
```

## Usage

### Manual Run

Standard output:
```bash
./pihole_backup_and_sync.sh
```

With verbose logging:
```bash
./pihole_backup_and_sync.sh --verbose
```

### Automated Run

The script runs automatically via cron at 10 PM daily (see crontab entry above).

## How It Works

The script performs the following steps:

1. **Backup Pi-hole**: Authenticates to Pi-hole API (tries ports 80, 8080, 443, 4443) and downloads teleporter backup ZIP
2. **Check Mount**: Verifies pfSense USB backup mount is writable
3. **Auto-Repair**: If mount is read-only, automatically runs `fsck_msdosfs` and remounts
4. **Sync to pfSense**: Rsyncs backups to pfSense USB drive
5. **Sync to NAS**: Rsyncs backups to ghost-files remote backup  
6. **Cleanup**: Removes local backups older than 10 days

## Troubleshooting

### Authentication Failed

If you see "Failed to authenticate to Pi-hole API":

1. Verify your password is correct:
   ```bash
   ./setup_password.sh
   ```

2. Check Pi-hole is running:
   ```bash
   sudo systemctl status pihole-FTL
   ```

3. Test API manually:
   ```bash
   source ~/.config/pihole_backup.env
   curl -X POST http://localhost:8080/api/auth \
     -H "Content-Type: application/json" \
     -d "{\"password\":\"$PIHOLE_PASSWORD\"}"
   ```

### Mount Check Failed

If you see "Mountpoint not found":

1. Check if USB is mounted on pfSense:
   ```bash
   ssh admin@pfsense-rtr1 "mount | grep /mnt"
   ```

2. Update `PFSENSE_MOUNT` in the script if using a different path

### SSH Connection Issues

If rsync fails with SSH errors:

1. Test SSH connection:
   ```bash
   ssh admin@pfsense-rtr1 "echo OK"
   ssh slm@ghost-files "echo OK"
   ```

2. Re-copy SSH keys if needed:
   ```bash
   ssh-copy-id -i ~/.ssh/id_rsa admin@pfsense-rtr1
   ssh-copy-id -i ~/.ssh/id_rsa slm@ghost-files
   ```

## Customization

Edit the script configuration section to customize:

- `PIHOLE_HOST`: Default is `localhost` (script auto-detects port)
- `PFSENSE_HOST`: SSH connection string for pfSense router
- `PFSENSE_MOUNT`: Mount point for USB backup on pfSense
- `GHOST_FILES_HOST`: SSH connection string for NAS
- `GHOST_FILES_PATH`: Backup directory on NAS
- `BACKUP_DIR`: Local backup storage directory
