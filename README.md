# Pi-hole Teleporter Backup & Sync

Automatically backup Pi-hole configuration via teleporter API and sync to remote servers.

## Configuration

### Pi-hole Password

Create a secret file to store your Pi-hole admin password:

```bash
mkdir -p ~/.config
printf "PIHOLE_PASSWORD='your_actual_pihole_password'\n" > ~/.config/pihole_backup.env
chmod 600 ~/.config/pihole_backup.env
```

The script will automatically load the password from this file. Alternatively, you can set the `PIHOLE_PASSWORD` environment variable.

## Setup

### mkdir
```
$ mkdir -p ~/pihole_teleporter_backups
```

### Create an SSH key
```
$ ssh-keygen -t rsa -b 4096 -N '' <<<$'\n'
```

### Allow it to SSH to remote backup server w/o interaction
```
$ ssh-copy-id -i ~/.ssh/id_rsa root@pfsense-rtr1
```

### Add crontab entry for user `pi`
```
$ crontab -e
....
```

Crontab entry should look like this for 10 PM daily:
```
$ crontab -l
...
 For more information see the manual pages of crontab(5) and cron(8)
#
# m h  dom mon dow   command

00 22 * * * /home/pi/pihole_teleporter_backups/pihole_backup_and_sync.sh
```

### Run the script

Manual run:
```bash
/home/pi/pihole_teleporter_backups/pihole_backup_and_sync.sh
```

With verbose output:
```bash
/home/pi/pihole_teleporter_backups/pihole_backup_and_sync.sh --verbose
```

Or automatically via cron at 10 PM daily (see crontab entry above).

The script:
1. Backs up Pi-hole teleporter to `.zip` (v6) via REST API
2. Checks/repairs pfSense mount if read-only (auto-fsck on FAT)
3. Syncs to pfSense USB backup
4. Syncs to ghost-files remote backup
5. Retains last 10 days of backups locally
