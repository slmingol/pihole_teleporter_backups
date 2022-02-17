# backup last 10 days worth of teleports to remote server

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

#26 22 * * * /home/pi/pihole_teleporter_backups/backup_last_10days_teleporters.sh >> /tmp/cron.log 2>&1
00 22 * * * /home/pi/pihole_teleporter_backups/backup_last_10days_teleporters.sh
```

### Contents of script
```
$ more /home/pi/pihole_teleporter_backups/backup_last_10days_teleporters.sh
#!/bin/bash

PATH="$PATH:/usr/sbin:/usr/local/bin/"

pushd /home/pi/pihole_teleporter_backups > /dev/null 2>&1
pihole -a -t
sudo chown pi.pi *.gz
find "/home/pi/pihole_teleporter_backups/" -maxdepth 1 -type f -mtime +10 -mtime -31 -name "*.gz" -ls -delete
rsync -avz --no-o --no-g -e 'ssh -i ~/.ssh/id_rsa' --delete \
	/home/pi/pihole_teleporter_backups/ \
	root@pfsense-rtr1:/mnt/usb_backup/pihole/. \

# https://askubuntu.com/questions/476041/how-do-i-make-rsync-delete-files-that-have-been-deleted-from-the-source-folder
```
