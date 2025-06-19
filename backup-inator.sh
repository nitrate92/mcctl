#!/bin/bash

active_instance=$(systemctl list-units --type=service --state=running,active | grep -o "minecraft-.*\.service")
active_instance_dir=$(systemctl show -p WorkingDirectory --value "${active_instance}")
active_instance_name=$(systemctl show -p Description --value "${active_instance}")

# Start the 2005 Honda CRV
if [[ $active_instance && $active_instance_dir && $active_instance_name ]]; then
    echo "Behold, the Minecraft backup-inator!"
    # Do we have a backup directory?
    if [[ ! -e "${active_instance_dir}/backups" ]]; then
        mkdir "${active_instance_dir}/backups"
    fi

    # Back up everything except the backups folder itself to avoid backup-ception
    tar --exclude='backups' -cvf "${active_instance_dir}"/backups/"${active_instance_name}"_"$(date +%m-%d-%y)".tar.gz "${active_instance_dir}"
    # Remove backups older than 10 days
    find "${active_instance_dir}"/backups -mtime +10 -type f -delete
else
    echo "Either a Minecraft service is not running/is missing a required unit attribute, or something went seriously wrong."
fi