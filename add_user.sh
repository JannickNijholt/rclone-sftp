#!/bin/bash

LOGFILE="/var/log/user_creation.log"
exec 3>&1 1>>"${LOGFILE}" 2>&1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >&3
}

log "Script started."

# Function to prompt for non-empty input
prompt_non_empty() {
    local prompt_message=$1
    local input_var
    while true; do
        echo -n "$prompt_message" >&3
        read input_var
        if [[ -n "$input_var" ]]; then
            echo "$input_var"
            return
        else
            echo "Input cannot be empty. Please try again." >&3
        fi
    done
}

# Function to prompt for a password and confirm it
prompt_password() {
    local password
    local password_confirm
    while true; do
        echo -n "Enter the password: " >&3
        read -s password
        echo >&3
        echo -n "Re-enter the password: " >&3
        read -s password_confirm
        echo >&3
        if [[ "$password" == "$password_confirm" && -n "$password" ]]; then
            echo "$password"
            return
        else
            echo "Passwords do not match or are empty. Please try again." >&3
        fi
    done
}

# Prompt for username
username=$(prompt_non_empty "Enter the new username: ")
log "Entered username: $username"

# Check if user already exists
if id "$username" &>/dev/null; then
    log "User $username already exists."
    echo "User $username already exists. Exiting." >&3
    exit 1
fi

# Create the user
log "Creating user $username."
useradd -m -G users "$username"
if [ $? -ne 0 ]; then
    log "Failed to create user $username."
    echo "Failed to create user $username. Exiting." >&3
    exit 1
fi

# Prompt for and set the password
password=$(prompt_password)
echo "$username:$password" | chpasswd
if [ $? -ne 0 ]; then
    log "Failed to set password for user $username."
    echo "Failed to set password for user $username. Exiting." >&3
    exit 1
fi
log "Password set for user $username."

# Set permissions for the home directory
log "Setting permissions for /home/$username."
chown root:root /home/"$username"
chmod 755 /home/"$username"
mkdir -p /home/"$username"/remote_backups
chown "$username":users /home/"$username"/remote_backups
chmod 700 /home/"$username"/remote_backups

# Prompt for creating a backup folder
echo -n "Do you want to create a backup folder in your Rclone mount? (Y/n) " >&3
read create_backup
if [[ "$create_backup" =~ ^[Yy]$ ]]; then
    backup_location=$(prompt_non_empty "Enter the location for the backup folder: ")
    # Remove trailing slash if present
    backup_location=${backup_location%/}
    log "Creating backup folder at $backup_location/$username."
    mkdir -p "$backup_location/$username"
    mount --bind "$backup_location/$username" /home/"$username"/remote_backups
    echo "$backup_location/$username /home/$username/remote_backups none bind 0 0" >> /etc/fstab
fi

# Update SSH configuration
log "Updating SSH configuration."
sshd_config="/etc/ssh/sshd_config"
if ! grep -q "Match Group users" "$sshd_config"; then
    echo "Match Group users
    ChrootDirectory /home/%u
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no" >> "$sshd_config"
    log "Added Match Group users configuration."
fi

echo "Match User $username
    ChrootDirectory /home/$username
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no" >> "$sshd_config"
log "Added Match User $username configuration."

# Restart SSH service
log "Restarting SSH service."
systemctl restart ssh
if [ $? -ne 0 ]; then
    log "Failed to restart SSH service."
    echo "Failed to restart SSH service. Exiting." >&3
    exit 1
fi

log "Script completed successfully."
echo "User $username created and configured successfully." >&3
