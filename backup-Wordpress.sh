#!/bin/bash

# TODO
    # Display the archive name at the end
    # Display the log location at start AND at end
    # Check if we can avoid sudo - passphrase in user's .config dir
    # Keyshortcuts for 
        # easily list the archives
        # Mount an archive
        # Health check
    # Put the temp DB backup file in some other location

# TODO - Accept the following mandatory parameters
    # --project-name | -pname
    # --wp-source-dir | -wp_src
    # --backup-dir
        ## Will be created if it does not exists
# And the following optional parameters
    # --storage-quota | -quota


# TODO - Check on other OSes
    # Ubuntu 16, 18, 18.08
    # Debian 8, 9, 10

# So root - no good
[[ "$(id -u)" != "0" ]] && {
    echo -e "ERROR: You must be root to run this script.\nPlease login as root and execute the script again."
    exit 1
}

SCRIPT_NAME=wp_borg_backup
SCRIPT_VERSION=0.1


project_name="$1"
wp_src_dir="$2"
backup_dst_dir="$3"

storage_quota="5G" #if user provided - update this

# Create the backup directory if it does not exist
mkdir -pv "${backup_dst_dir}"/{bkp_log,DB,WP} > /dev/null
bkp_log_dir="${backup_dst_dir}/bkp_log"
bkp_final_dir="${backup_dst_dir}/WP"
bkp_DB_dir="${backup_dst_dir}/DB"
TS=$(date '+%d_%m_%Y-%H_%M_%S')

LOGFILE="${bkp_log_dir}"/"$SCRIPT_NAME"_v"$SCRIPT_VERSION"_"$TS".log
touch "${LOGFILE}"


# Install "borgbackup" if NOT installed
if ! (type borg > /dev/null 2>&1); then
    apt-get install -y borgbackup >> "$LOGFILE" 2>&1
fi

#If borg is running the same backup - quit
if  (pidof -x borg > /dev/null) && $(pgrep -ac "$wp_src_dir") -gt 0 ; then
    echo "${wp_src_dir} is being backed up from another process" | tee -a "$LOGFILE"
    echo "This process will now exit" | tee -a "$LOGFILE"
    exit 11
fi

# Install wp-cli if not installed
if ! (type wp > /dev/null 2>&1); then
    echo -e "wp-cli not found on system. \nInstalling wp-cli" >> "$LOGFILE" 2>&1
    wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -O /usr/local/bin/wp >> "$LOGFILE" 2>&1
    chmod +x /usr/local/bin/wp >> "$LOGFILE" 2>&1
fi

# Backup WP database
directory_owner=$(ls -ld "${wp_src_dir}" | awk '{print $3}')
sudo -u "${directory_owner}" wp db --quiet export "${wp_src_dir}"/"$TS"_database.sql --add-drop-table --path="${wp_src_dir}"

if mv "${wp_src_dir}"/"${TS}"_database.sql "${bkp_DB_dir}"/"${TS}"_database.sql >> "$LOGFILE" 2>&1; then
    echo "DB backed up successfully" | tee -a "$LOGFILE"
else 
    echo "ERROR: DB Backup Failed. Check log for more details." | tee -a "$LOGFILE"
fi

# Try reading the passphrase from the BORG_PASSCOMMAND exported variable
if [[ -n "$BORG_PASSCOMMAND" ]]; then
    borg_passphrase="$BORG_PASSCOMMAND"
# Else - try finding it from our designated password file
elif [[ -f /root/.config/borg/."$project_name" && -s /root/.config/borg/."$project_name" ]]; then
    borg_passphrase=$(cat /root/.config/borg/."$project_name")
fi

# If no passphrase found and repo EXISTS at the destination - Exit
if [[ ( -z "$borg_passphrase" ) && ( -f "$backup_dst_dir"/config || -f "$bkp_final_dir"/config ) ]]; then
    echo "Could not find a passphrase" | tee -a "$LOGFILE"
    echo -e "Either do a (EXPORT BORG_PASSCOMMAND=[your-passphrase] \n\t\t OR \nAdd the passphrase to /root/.config/borg/.${project_name} file." | tee -a "$LOGFILE"
    exit 12
fi

# Auto generate passphrase if no repo exists
if [[ ( ! -f "$backup_dst_dir"/config ) && ( ! -f "$bkp_final_dir"/config ) ]]; then
    borg_passphrase=$(< /dev/urandom tr -cd 'a-zA-Z0-9@&_' | head -c 20) # 20-character

    mkdir "$backup_dst_dir"/WP >> "$LOGFILE" 2>&1

    export BORG_NEW_PASSPHRASE="$borg_passphrase"

    # Backup any recidual passphrase keys
    if [[ -f /root/.config/borg/."$project_name" ]]; then
        mv /root/.config/borg/."$project_name" /root/.config/borg/."$project_name"_old_"${TS}"
    fi

    # chmod 400 the passphrase file
    touch /root/.config/borg/."$project_name" >> "$LOGFILE" 2>&1 && chmod 440 /root/.config/borg/."$project_name" >> "$LOGFILE" 2>&1 && {
        # Display the passphrase on screen
        echo "############### BACKUP PASSPHRASE ###############" | tee -a "$LOGFILE"
        echo "$borg_passphrase" | tee /root/.config/borg/."$project_name" | tee -a "$LOGFILE"
        echo "############### BACKUP PASSPHRASE ###############" | tee -a "$LOGFILE"
        echo "You CANNOT access your backup without the above passphrase" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
    }

    # Initalize the repo
    if (borg init -v --encryption=repokey-blake2 --storage-quota "$storage_quota" "$bkp_final_dir" >> "$LOGFILE" 2>&1); then
        echo "Repository initialized successfully" | tee -a "$LOGFILE"
    else
        echo "ERROR: Backup initialization failed. Check the logfile for more details." | tee -a "$LOGFILE"
    fi
fi

# This is required again - if passphrase was generated in the above step
export BORG_PASSPHRASE="$borg_passphrase"

# Do the actual backup
# We run it on a lower priority so it does not disturb others
if  ionice -c 2 -n 7 borg create                                \
        --verbose                                               \
        --filter AMEsd                                          \
        --list                                                  \
        --json                                                  \
        --stats                                                 \
        --show-rc                                               \
        --compression zstd                                      \
        --exclude-caches                                        \
        "$bkp_final_dir"::{hostname}_"$project_name"_"$TS"      \
        "$wp_src_dir"                                           \
        "${bkp_DB_dir}"                                         \
        >> "$LOGFILE" 2>&1; then
    echo "Backup Completed Successfully" | tee -a "$LOGFILE"
else
    echo "ERROR: Backup failed. Check the logfile for more details" | tee -a "$LOGFILE"
fi