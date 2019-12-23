******# Wordpress Backup with Borgbackup

Bash script that simplifies Borg backup for Wordpress websites.

## Purpose
Make backup easy for a server running multiple Wordpress websites. 

_borg_ is amazing backup solution, but if you have multiple websites running on the same server - you might have to create a script each for each of those websites. You would also need to spend sometime manually initializing a new repo for each of those websites, generate a passphrase, copy the passphrase immediately, _export_ the passphrase in a new script.

This script is designed specifically to ease those issues. You provide where your Wordpress is installed and where you want the backup to be stored and a unique name for the website - the script takes care of the rest. It'll create a strong enough passphrase, initialize the repo, then perform the actual backup.

On subsequent executions, it'll read the passphrase file and perform an incremental backup.

## Status

TESTED ON DEBIAN 10.
NEEDS FURTHER TESTING.

## Usage

### Prerequisites
- Any Linux distribution that support "_apt_"
- A user having _sudo_ access to the server

### Examples

```console
$ wget -q https://raw.githubusercontent.com/pratiktri/wordpress_borg_backup
/master/wp_borg_backup.sh -O wp_borg_backup.sh && chmod u+x wp_borg_backup.sh | tee sudo bash ./wp_borg_backup.sh --project-name "example.com" --wp-source-dir "/var/www/example.com" --backup-dir "/home/me/backup/example.com" --storage-quota 15G --passphrase-dir "/home/user/.config/borg"


$ wget -q https://raw.githubusercontent.com/pratiktri/wordpress_borg_backup
/master/wp_borg_backup.sh -O wp_borg_backup.sh && chmod u+x wp_borg_backup.sh | tee sudo bash ./wp_borg_backup.sh -pname "example.com" -wp-src "/var/www/example.com" --backup-dir "/home/me/backup/example.com"
```

### Available Options

Run the script with below option (--help or -h) to see all available options:-

```console
$ sudo ./wp_borg_backup.sh --help

Usage:
    sudo ./wp_borg_backup.sh --project-name <name> --wp-source-dir <path> --backup-dir <path> [--storage-quota <size>] [--passphrase-dir <path>]"
    -pname,         --project-name      A Unique name (usually the website name) for this backup
    -wp_src,        --wp-source-dir     Directory where your WordPress website is stored
    --backup-dir                        Directory where backup files will be stored
    -quota,         --storage-quota     [Optional] Unlimited by default
                                        When supplied backups would never exceed this capacity. 
                                        Older backups will automatically be deleted to make room for new ones.
    -passdir,       --passphrase-dir    [Optional] /home/[user]/.config/borg by default
                                        Backups keys are stored (in plain-text) at this location.
                                        Use "export BORG_PASSPHRASE" as shown in the example below to avoid saving passphrase to file.
    -h,             --help              Display this information

    NOTE:- You MUST specify BORG_PASSPHRASE by export or by a passphrase file

    $ export BORG_PASSPHRASE=<your-passphrase>
    $ sudo ./wp_borg_backup.sh --project-name "example.com" --wp-source-dir "/var/www/example.com" --backup-dir "/home/me/backup/example.com"  --storage-quota 5G --passphrase-dir /root/borg
```

### What does the script do?

- Install _borgbackup_ if not installed
- Install _wp-cli_ if not installed
- Backup the Wordpress database using _wp-cli_ 
- Initialize _borg_ repository if --backup-dir is empty
  - Generates a passphrase
  - Saves the passphrase to /home/[user]/.config/borg directory
  - Secures the passphrase file by "chmod 400"
- Performs the backup

## FAQ
Q - Is the passphrase saved on the server in plain-text

Ans - Yes. 

However, it does restrict access to the file only to _root_ user. If someone has access to your server and can access a file restricted to _root_ - then they would just go to the website folder itself to do any damage. You should sync your backup regularly to other locations for more protection.
      
 If you do not like that, edit the script to add the following line to top of the file.

```
    export BORG_PASSPHRASE=[your-passphrase]
```


### Roadmap

-   [ ] Pretty print console output
-   [ ] Test on 
    -   [ ] Ubuntu 18.08
    -   [ ] Ubuntu 18.04
    -   [ ] Ubuntu 16.04
    -   [ ] Debian 8
    -   [ ] Debian 9

## License

Copyright 2019 Pratik Kumar Tripathy

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
**