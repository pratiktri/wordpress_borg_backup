#!/usr/bin/env bash

# TODO
    # Keyshortcuts for 
        # easily list the archives
        # Mount an archive
        # Health check

    # Best Practice 
        # A usage()
        # Comment at top of the file explaining what it does
        # Enable Bash Strict mode

# TODO - Check on other OSes
    # Ubuntu 16, 18, 18.08
    # Debian 8, 9, 10

# No root - no good
[[ "$(id --user)" != "0" ]] && {
    echo -e "ERROR: You must be root to run this script.\nUse sudo and execute the script again."
    exit 1
}

# No apt - no good
! (type apt-get > /dev/null 2>&1) && {
    echo -e "ERROR: This script works only on Debian and Debian-derivatives that use 'apt'"
    exit 2
}

usage() {
    cat <<USAGE
    Usage:
    sudo bash $0 --project-name <name> --wp-source-dir <path> --backup-dir <path> [--storage-quota <size>] [--passphrase-dir <path>]"
    -u,     --username              Username for your server (If omitted script will choose an username for you)
    -r,     --resetrootpwd          Reset current root password
    -hide,  --hide-credentials      Credentials will hidden from screen and can ONLY be found in the logfile
                                    eg: tail -n 20 logfile
    -d,     --defaultsourcelist     Updates /etc/apt/sources.list to download software from debian.org
    -ou,    --only-user             Only creates the user and its SSH authorizations
                                    NOTE: -r, -d would be ignored

    export BORG_PASSPHRASE=<your-passphrase>
    Example: bash ./$SCRIPT_NAME.sh --username myuseraccount --resetrootpwd

USAGE
    exit 0
}


main(){
    local SCRIPT_VERSION, SCRIPT_NAME
    readonly SCRIPT_VERSION=0.9, SCRIPT_NAME=wp_borg_backup

    ################################# Parse Script Arguments #################################

    local passphrase_dir, project_name, wp_src_dir, backup_dst_dir, storage_quota, passphrase_dir

    # By default, keep the passphrase file in the user's (the user that called this script) home directory
    # cause I don't want to pollute root user's home
    passphrase_dir="/home/${SUDO_USER}/.config/borg" 

    while [[ "${#}" -gt 0 ]]; do
        case $1 in
            --project-name | -pname)
                project_name="$2"
                readonly project_name

                shift
                shift
                ;;
            --wp-source-dir | -wp_src)
                wp_src_dir="$2"
                readonly wp_src_dir

                if [[ ! -d "${wp_src_dir}" ]]; then
                    echo "Directory ${wp_src_dir} does NOT exist. Please provide a valid source directory." 2>STDERR
                    exit 3
                fi
                shift
                shift
                ;;
            --backup-dir)
                backup_dst_dir="$2"
                readonly backup_dst_dir
                
                if [[ ! -d "${backup_dst_dir}" ]]; then
                    echo "Directory ${backup_dst_dir} does NOT exist. Please provide a valid backup directory." 2>STDERR
                    exit 4
                fi
                shift
                shift
                ;;
            --storage-quota | -quota)
                storage_quota="$2"
                shift
                shift
                ;;
            --passphrase-dir | -passdir)
                passphrase_dir="$2"
                readonly passphrase_dir

                if [[ ! -d "${passphrase_dir}" ]]; then
                    echo "Directory ${passphrase_dir} does NOT exist. Please provide a valid directory." 2>STDERR
                    exit 5
                fi
                shift
                shift
                ;;
            -h|--help)
                echo
                #TODO - implement the "usage" function
                usage
                echo
                exit 0
                ;;
            *)
                echo "Unknown parameter encounted : $1 - this will be ignored"
                ;;
        esac
    done

    # Check if mandatory items were provided or not
    if [[ -z "${project_name}" ]]; then
        echo "ERROR: Script requires a project name (--project-name | -pname) parameter" 2>STDERR
        usage
        exit 6
    fi

    if [[ -z "${wp_src_dir}" ]]; then
        echo "ERROR: Script requires a source directory (--wp-source-dir | -wp_src) parameter" 2>STDERR
        usage
        exit 7
    fi

    if [[ -z "${backup_dst_dir}" ]]; then
        echo "ERROR: Script requires a backup directory (--backup-dir) parameter" 2>STDERR
        usage
        exit 8
    fi

    # if blank - do something
    if [[ -n "${storage_quota}" ]]; then
        storage_quota="--storage-quota ${storage_quota}"
    fi
    readonly storage_quota

    ################################# Parse Script Arguments #################################




    ######################################### Set up  #########################################
    local bkp_log_dir, bkp_final_dir, bkp_DB_dir, TS, LOGFILE

    # Create the backup directory structure
    mkdir -pv "${backup_dst_dir}"/{bkp_log,DB,WP} > /dev/null
    readonly bkp_log_dir="${backup_dst_dir}/bkp_log"
    readonly bkp_final_dir="${backup_dst_dir}/WP"
    readonly bkp_DB_dir="${backup_dst_dir}/DB"
    readonly TS="$(date '+%d_%m_%Y-%H_%M_%S')"
    readonly LOGFILE="${bkp_log_dir}"/"${SCRIPT_NAME}"_v"${SCRIPT_VERSION}"_"${TS}".log
    touch "${LOGFILE}"
    echo "You can find the log at ${LOGFILE}"

    ######################################### Set up  #########################################




    ################################### Prepare the System ###################################

    # Install "borgbackup" if NOT installed
    if ! (type borg > /dev/null 2>&1); then
        if apt-get install --yes borgbackup >> "${LOGFILE}" 2>&1; then
            echo "borgbackup installed successfully" | tee -a "${LOGFILE}"
        else
            echo "ERROR: installing borgbackup. Check the log for more details" 2>STDERR | tee -a "${LOGFILE}"
            exit 11
        fi
    fi

    #If borg is currently running AND it is backing up the same website - quit
    if  (pidof -x borg > /dev/null) && $(pgrep --list-full --count "${wp_src_dir}") -gt 0 ; then
        echo "${wp_src_dir} is being backed up from another process"  2>STDERR | tee -a "${LOGFILE}"
        echo "This process will now exit"  2>STDERR | tee -a "${LOGFILE}"
        exit 11
    fi

    # Download and Install wp-cli if not installed
    if ! (type wp > /dev/null 2>&1); then
        echo -e "wp-cli not found on system. \nInstalling wp-cli" >> "${LOGFILE}" 2>&1
        wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -O /usr/local/bin/wp >> "${LOGFILE}" 2>&1
        if chmod +x /usr/local/bin/wp >> "${LOGFILE}" 2>&1; then
            echo "Successfully Installed wp-cli" | tee -a "${LOGFILE}"
        else
            wp_cli_installed="$?"
            echo "ERROR: Could not install wp-cli. Program will continue to backup the site data..." 2>STDERR | tee -a "${LOGFILE}"
        fi
    fi

    ################################### Prepare the System ###################################




    ################################### Wordpress DB Backup ###################################

    # Backup WP database only if wp-cli is installed
    if [[ -z "${wp_cli_installed}" || "${wp_cli_installed}" == 0 ]]; then
        local directory_owner

        # For Seurity -> Instead of using "su" to backup DB -> use the owner of the wordpress directory
        readonly directory_owner=$(stat --format='%U' "${wp_src_dir}")
        sudo -u "${directory_owner}" wp db --quiet export "/tmp/${TS}_database.sql" --add-drop-table --path="${wp_src_dir}"

        if mv "/tmp/${TS}"_database.sql "${bkp_DB_dir}/${TS}_database.sql" >> "${LOGFILE}" 2>&1; then
            echo "DB backed up successfully" | tee -a "${LOGFILE}"
        else 
            echo "ERROR: DB Backup Failed. Check log for more details." 2>STDERR | tee -a "${LOGFILE}"
            echo "Script will continue with Wordpress backup" 2>STDERR | tee -a "${LOGFILE}"
        fi
    fi

    ################################### Wordpress DB Backup ###################################




    ################################## Wordpress Site Backup ##################################
    local borg_passphrase

    # Try reading the passphrase from the BORG_PASSCOMMAND exported variable
    if [[ -n "${BORG_PASSCOMMAND}" ]]; then
        borg_passphrase="${BORG_PASSCOMMAND}"
    # Else - try finding it from our designated password file
    elif [[ -f "${passphrase_dir}/.${project_name}" && 
            -s "${passphrase_dir}/.${project_name}" ]]; then
        borg_passphrase=$(cat "${passphrase_dir}"/."${project_name}")
    fi

    # If no passphrase found and repo EXISTS at the destination - Exit
    if [[ ( -z "${borg_passphrase}" ) && 
        ( -f "${backup_dst_dir}"/config || 
                -f "${bkp_final_dir}"/config ) ]]; then
        echo "ERROR: Could not find a passphrase" 2>STDERR | tee -a "${LOGFILE}"
        echo -e "Either do a (EXPORT BORG_PASSCOMMAND=[your-passphrase] \n\t\t OR \nAdd the passphrase to ${passphrase_dir}/.${project_name} file." 2>STDERR | tee -a "${LOGFILE}"
        exit 12
    fi

    # Auto generate passphrase if no repo exists
    if [[ ( ! -f "${backup_dst_dir}"/config ) && 
        ( ! -f "${bkp_final_dir}"/config ) ]]; then
        borg_passphrase=$(< /dev/urandom tr -cd 'a-zA-Z0-9@&_' | head -c 20) # 20-character
        readonly borg_passphrase

        mkdir "${backup_dst_dir}"/WP >> "${LOGFILE}" 2>&1

        export BORG_NEW_PASSPHRASE="${borg_passphrase}"

        # Backup any recidual passphrase keys
        if [[ -f "${passphrase_dir}/.${project_name}" ]]; then
            mv "${passphrase_dir}/.${project_name}" "${passphrase_dir}/.${project_name}_old_${TS}"
        fi

        # chmod 400 the passphrase file
        mkdir -p "${passphrase_dir}" >> "${LOGFILE}" 2>&1 && 
            touch "${passphrase_dir}/.${project_name}" >> "${LOGFILE}" 2>&1 && 
                chmod 440 "${passphrase_dir}/.${project_name}" >> "${LOGFILE}" 2>&1 && {
                    # Display the passphrase on screen
                    echo -e "\n############### BACKUP PASSPHRASE ###############" | tee -a "${LOGFILE}"
                    echo "${borg_passphrase}" | 
                        tee "${passphrase_dir}/.${project_name}" | tee -a "${LOGFILE}"
                    echo "############### BACKUP PASSPHRASE ###############" | tee -a "${LOGFILE}"
                    echo -e "You CANNOT access your backup without the above passphrase\n" | tee -a "${LOGFILE}"
        }

        # Initalize the repo
        if (borg init --verbose \
                    --encryption=repokey-blake2 \
                    --storage-quota \
                    "${storage_quota}" \
                    "${bkp_final_dir}" >> "${LOGFILE}" 2>&1); then
            echo "Repository initialized successfully" | tee -a "${LOGFILE}"
        else
            echo "ERROR: Backup initialization failed. Check the logfile for more details." 2>STDERR | tee -a "${LOGFILE}"
        fi
    fi

    # This is required again - if passphrase was generated in the above step
    export BORG_PASSPHRASE="${borg_passphrase}"

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
            "${bkp_final_dir}"::{hostname}_"$project_name"_"$TS"    \
            "${wp_src_dir}"                                         \
            "${bkp_DB_dir}"                                         \
            >> "${LOGFILE}" 2>&1; then
        echo "Backup Completed Successfully" | tee -a "${LOGFILE}"
    else
        echo "ERROR: Backup failed. Check the logfile for more details" 2>STDERR | tee -a "${LOGFILE}"
    fi

    echo "You can find the log at ${LOGFILE}"

    ################################## Wordpress Site Backup ##################################
}

main "$@"