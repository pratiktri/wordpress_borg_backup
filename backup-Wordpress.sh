#!/bin/sh

# Create DB backup in the given location
    # wp db export downloads/`date +%Y%m%d`_database.sql --add-drop-table --path=/var/www/upakhyana.com/htdocs/
	# - Where to keep the db backups?

# Do Backup of the WP files + logfiles + Db Backup files
	# - Borg - run it on lower priority with "nice"
    # Compression? zlib?
    # Pruning?
    # Max size?
    # Frequency?
    # What needs to be excluded?


# Sync the backup to remote using Rclone
    # How about backup filling up space?
    # What if the server gets hacked - can he delete everything from remote location as well?

# So root - no good
[[ "$(id -u)" != "0" ]] && {
    echo -e "ERROR: You must be root to run this script.\nPlease login as root and execute the script again."
    exit 1
}

SCRIPT_NAME=wp_borg_backup
SCRIPT_VERSION=0.1

wp_src_dir=""
wp_log_dir=""
backup_dst_dir=""
borg_passphrase=""
storage_quota="5G" #if user provided - update this
project_name=""

TS=$(date '+%d_%m_%Y-%H_%M_%S')
LOGFILE=/tmp/"$SCRIPT_NAME"_v"$SCRIPT_VERSION"_"$TS".log

# Install "borgbackup" if NOT installed
if ! type borg 2>> "$LOGFILE" >&2; then
    apt-get install -y borgbackup 2>> "$LOGFILE" >&2
fi

#If borg is running the same backup - quit
if  (pidof -x borg > /dev/null) && $(pgrep -ac "$wp_src_dir") -gt 0 ; then
    echo "${wp_src_dir} is being backed up from another process" | tee -a "$LOGFILE"
    echo "This process will now exit" | tee -a "$LOGFILE"
    exit 11
fi

# Backup the DB
if [[ -d ${backup_dst_dir}/DB ]]; then
    mkdir ${backup_dst_dir}/DB 2>> "$LOGFILE" >&2
fi

# Install wp-cli if not installed
if ! type wp 2>> "$LOGFILE" >&2; then
    echo -e "wp-cli not found on system. \nInstalling wp-cli" 2>> "$LOGFILE" >&2
    wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -O /usr/local/bin/wp 2>> "$LOGFILE" >&2
    chmod +x /usr/local/bin/wp 2>> "$LOGFILE" >&2
fi

# Backup WP database
wp db export ${backup_dst_dir}/DB/"$TS"_database.sql --add-drop-table --path=${wp_src_dir} 2>> "$LOGFILE" >&2

# If no passphrase provided and repo exists at the destination - Exit
if [[ ( -z "$borg_passphrase") && (-f "$backup_dst_dir"/config || -d "$backup_dst_dir"/WP || -d "$backup_dst_dir"/WP/config) ]]; then
    echo -e "You did not provide passphrase for this existing backup.\nProcess will exit now." | tee -a "$LOGFILE"
    exit 12
fi

# Auto generate passphrase if no repo exists
if [[ -z "$borg_passphrase" && ! -f "$backup_dst_dir"/config && ! -d "$backup_dst_dir"/WP && ! -d "$backup_dst_dir"/WP/config ]]; then
    borg_passphrase=$(< /dev/urandom tr -cd 'a-zA-Z0-9~!@#$%^&*()_+-=' | head -c 20) # 20-character

    mkdir "$backup_dst_dir"/WP 2>> "$LOGFILE" >&2

    export BORG_NEW_PASSPHRASE="$borg_passphrase"

    # Initalize the repo
    borg init -v --encryption=repokey-blake2 --storage-quota "$storage_quota" "$backup_dst_dir"/WP 
fi

# Peform the actual backup
export BORG_PASSPHRASE="$borg_passphrase"
borg create \
    "$backup_dst_dir"/WP::{hostname}_"$project_name"_"$TS" \
    "$wp_src_dir"

borg create                                             \
    --verbose                                           \
    --filter AMEsd                                      \
    --list                                              \
    --json                                              \
    --stats                                             \
    --show-rc                                           \
    --compression zstd                                  \