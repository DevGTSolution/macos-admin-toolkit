#!/bin/bash

# Get all admin group members
groupmember_raw=$(dscl . -read /Groups/admin GroupMembership 2>/dev/null | cut -c 18-)

# Convert the list to an array
IFS=' ' read -r -a members <<< "$groupmember_raw"

# Define excluded users
# Add default admin accounts and Jamf accounts in between
excluded_users=("root" "_mbsetupuser")

# Filter members
filtered_members=()
for user in "${members[@]}"; do
    if [[ ! " ${excluded_users[*]} " =~ " $user " ]]; then
        filtered_members+=("$user")
    fi
done

# Join and output the result
echo "<result>${filtered_members[*]}</result>"