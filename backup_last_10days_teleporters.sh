#!/bin/bash

set -x
PATH="$PATH:/usr/sbin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/sbin:/bin"

pushd /home/pi/pihole_teleporter_backups > /dev/null 2>&1
pihole -a -t
sudo chown pi.pi *.gz
find "/home/pi/pihole_teleporter_backups/" -maxdepth 1 -type f -mtime +10 -mtime -31 -name "*.gz" -ls -delete
rsync -avvvz --no-o --no-g -e 'ssh -vvvv -i ~/.ssh/id_rsa' --delete --progress --stats --no-inc-recursive -W --rsync-path=/usr/local/bin/rsync \
	/home/pi/pihole_teleporter_backups/ \
	root@pfsense-rtr1:/mnt/usb_backup/pihole/.

rsync -avz --no-o --no-g -e 'ssh -i ~/.ssh/id_rsa' --delete \
	/home/pi/pihole_teleporter_backups/ \
	slm@watcher:/export/raid1/data/backups/pihole/.

# https://askubuntu.com/questions/476041/how-do-i-make-rsync-delete-files-that-have-been-deleted-from-the-source-folder
