#!/bin/bash

# Function to log messages 
log_message() {
    local message="$1"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $message" >> $LOG_FILE
}

# Function to generate a random password
generate_password() {
    echo $(openssl rand -base64 12)
}

# check for file name 
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <name-of-text-file>"
    exit 1
fi

USER_FILE="$1"
PASSWORD_FILE="/var/secure/user_passwords.csv"
LOG_FILE="/var/log/user_management.log"

# Check if the user file exists
if [ ! -f "$USER_FILE" ]; then
    echo "Error: File $USER_FILE does not exist."
    exit 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    log_message "ERROR: Script not run as root"
    exit 1
fi

# Create secure directory for passwords
mkdir -p $(dirname "$PASSWORD_FILE")
chmod 700 $(dirname "$PASSWORD_FILE")
chmod +rwx $(dirname "$PASSWORD_FILE")
chmod +rwx $(dirname "$LOG_FILE")

# Initialize or clear password file
> $PASSWORD_FILE
chmod 600 $PASSWORD_FILE

# Read the input file
while IFS=';' read -r username groups; do
    # Ignore whitespace
    username=$(echo "$username" | xargs)
    groups=$(echo "$groups" | xargs)

    # Skip empty lines or comments
    if [[ -z "$username" || "$username" == \#* ]]; then
        continue
    fi

    # Check if user already exists
    if getent passwd "$username" > /dev/null 2>&1; then
        log_message "INFO: User $username already exists, skipping creation"
        continue
    fi

    # Create user's personal group if not exists
    if ! getent group "$username" > /dev/null 2>&1; then
        groupadd "$username"
        log_message "INFO: Group $username created"
    fi

    # Create user with personal group
    useradd -m -g "$username" -s /bin/bash "$username"
    log_message "INFO: User $username created with personal group $username"

    # Set up additional groups
    IFS=',' read -ra ADDR <<< "$groups"
    for group in "${ADDR[@]}"; do
        group=$(echo "$group" | xargs)
        if [[ -n "$group" ]]; then
            if ! getent group "$group" > /dev/null 2>&1; then
                groupadd "$group"
                log_message "INFO: Group $group created"
            fi
            usermod -aG "$group" "$username"
            log_message "INFO: User $username added to group $group"
        fi
    done

    # Generate password
    password=$(generate_password)
    echo "$username:$password" | chpasswd
    log_message "INFO: Password set for user $username"

    # Store password in a secure file
    echo "$username: $password" >> $PASSWORD_FILE

    # Set proper permissions for home directory
    chmod 700 "/home/$username"
    chown "$username:$username" "/home/$username"
    log_message "INFO: Home directory permissions set for user $username"

done < "$USER_FILE"

log_message "INFO: User creation script completed"
echo "User creation completed. Check the log file for details."
