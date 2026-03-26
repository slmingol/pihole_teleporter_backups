# backup last 10 days worth of teleports to remote server

## Secret Handling (Required Before Commit)

`pihole_backup_and_sync.sh` reads `PIHOLE_PASSWORD` from environment or from a local file:

`~/.config/pihole_backup.env`

File contents should be:

```
PIHOLE_PASSWORD='your_pihole_password_here'
```

Protect it:

```
chmod 600 ~/.config/pihole_backup.env
```

Do not hardcode passwords in scripts.

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

Crontab entry should look like this for 11pm daily
```
$ crontab -l
...
 For more information see the manual pages of crontab(5) and cron(8)
#
# m h  dom mon dow   command

00 22 * * * /home/pi/pihole_teleporter_backups/pihole_backup_and_sync.sh
```

### Run the script

Manual: `/home/pi/pihole_teleporter_backups/pihole_backup_and_sync.sh`

Or automatically via cron at 10 PM daily (see crontab entry above).

The script:
1. Backs up Pi-hole teleporter to `.zip` (v6) via REST API
2. Checks/repairs pfSense mount if read-only (auto-fsck on FAT)
3. Syncs to pfSense USB backup
4. Syncs to ghost-files remote backup
5. Retains last 10 days of backups locally
