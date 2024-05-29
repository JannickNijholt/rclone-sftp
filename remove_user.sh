#!/bin/bash

LOGFILE="/var/log/user_removal.log"
exec 3>&1 1>>"${LOGFILE}" 2>&1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >&3
}

log "Script started."

# Get list of users in the "users" group
user_list=($(getent group users | awk -F: '{print $4}' | tr ',' ' '))

if [ ${#user_list[@]} -eq 0 ]; then
    echo "No users found in the 'users' group." >&3
    log "No users found in the 'users' group."
    exit 1
fi

# Display list of users
echo "Select a user to remove:" >&3
for i in "${!user_list[@]}"; do
    echo "[$((i + 1))] ${user_list[$i]}" >&3
done

# Prompt for user selection
while true; do
    echo -n "Enter the number of the user to remove: " >&3
    read user_number
    if [[ "$user_number" =~ ^[0-9]+$ ]] && [ "$user_number" -ge 1 ] && [ "$user_number" -le "${#user_list[@]}" ]; then
        selected_user=${user_list[$((user_number - 1))]}
        break
    else
        echo "Invalid selection. Please enter a number between 1 and ${#user_list[@]}." >&3
    fi
done

log "Selected user: $selected_user"

# Remove backup folder and unmount
backup_folder=$(grep "/home/$selected_user/remote_backups" /etc/fstab | awk '{print $1}')
if [ -n "$backup_folder" ]; then
    log "Removing and unmounting backup folder: $backup_folder"
    umount /home/"$selected_user"/remote_backups
    if [ $? -ne 0 ]; then
        log "Failed to unmount /home/$selected_user/remote_backups."
        echo "Failed to unmount /home/$selected_user/remote_backups. Exiting." >&3
        exit 1
    fi
    sed -i "\|$backup_folder /home/$selected_user/remote_backups|d" /etc/fstab
    rm -rf "$backup_folder"
    log "Backup folder $backup_folder removed."
fi

# Terminate user's processes
log "Terminating processes for user: $selected_user"
pkill -u "$selected_user"
if [ $? -ne 0 ]; then
    log "No processes found for user $selected_user or failed to terminate processes."
fi

# Change ownership of the home directory back to the user
log "Changing ownership of /home/$selected_user back to $selected_user"
chown -R "$selected_user":"$selected_user" /home/"$selected_user"
if [ $? -ne 0 ]; then
    log "Failed to change ownership of /home/$selected_user."
    echo "Failed to change ownership of /home/$selected_user. Exiting." >&3
    exit 1
fi

# Remove the user
log "Removing user: $selected_user"
userdel -r "$selected_user" 2>&1 | tee -a >(log)
if [ $? -ne 0 ]; then
    log "Failed to remove user $selected_user."
    echo "Failed to remove user $selected_user. Exiting." >&3
    exit 1
fi
log "User $selected_user removed."

# Remove specific SSH configuration for the user
log "Removing SSH configuration for user: $selected_user"
sshd_config="/etc/ssh/sshd_config"
sed -i "\|Match User $selected_user|,/^$/d" "$sshd_config"
if [ $? -ne 0 ]; then
    log "Failed to remove SSH configuration for user $selected_user."
    echo "Failed to remove SSH configuration for user $selected_user. Exiting." >&3
    exit 1
fi
log "SSH configuration for user $selected_user removed."

# Check if "Match Group users" should be removed
if ! grep -q "^Match User" "$sshd_config"; then
    log "Removing 'Match Group users' configuration."
    sed -i "\|Match Group users|,/^$/d" "$sshd_config"
    if [ $? -ne 0 ]; then
        log "Failed to remove 'Match Group users' configuration."
        echo "Failed to remove 'Match Group users' configuration. Exiting." >&3
        exit 1
    fi
    log "'Match Group users' configuration removed."
fi

# Restart SSH service
log "Restarting SSH service."
systemctl restart ssh 2>&1 | tee -a >(log)
if [ $? -ne 0 ]; then
    log "Failed to restart SSH service."
    echo "Failed to restart SSH service. Exiting." >&3
    exit 1
fi

log "Script completed successfully."
echo "User $selected_user removed and cleaned up successfully." >&3
