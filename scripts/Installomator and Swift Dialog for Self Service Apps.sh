#!/bin/zsh

export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# -----------------------------------------------------------------------
# Script Name: Installomator and Swift Dialog for Self Service Apps
# Author: GTsolution
#
# Description:
#   Uses Swift Dialog and Installomator to install apps from Self Service.
#
#   If Installomator is not installed locally, this script downloads it from
#   the official Installomator GitHub release branch.
#
# Jamf Parameters:
#   Parameter 4 = Message displayed over the progress bar
#   Parameter 5 = Path or URL to an icon
#   Parameter 6 = Installomator label for the app to install
# -----------------------------------------------------------------------

cat <<'EXIT_CODES'

Exit codes:
98 = Not supported OS
97 = Not being run as Root
96 = Installomator couldn't be installed or found
95 = Swift Dialog couldn't be installed or found
94 = Missing Installomator app label
0  = All went well

EXIT_CODES

############################################
# Variables
############################################

DEBUG="${DEBUG:-0}"

dialog_command_file="/var/tmp/dialog.log"

# Parameter 4: message displayed over the progress bar
message="${4:-Self Service Progress}"

# Parameter 5: path or URL to an icon
icon="${5:-/System/Applications/App Store.app/Contents/Resources/AppIcon.icns}"

# Parameter 6: Installomator label
app="${6:-}"

dialogApp="/Library/Application Support/Dialog/Dialog.app"
InstallomatorApp="/usr/local/Installomator/Installomator.sh"

overlayicon="$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist self_service_app_path 2>/dev/null || echo "")"

############################################
# Functions
############################################

log() {
    echo "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*"
}

dialogUpdate() {
    # $1: dialog command
    local dcommand="$1"

    if [[ -n "$dialog_command_file" ]]; then
        echo "$dcommand" >> "$dialog_command_file"
        log "Dialog: $dcommand"
    fi
}

install_installomator_from_github() {
    local installomator_url="https://raw.githubusercontent.com/Installomator/Installomator/release/Installomator.sh"
    local installomator_dir="/usr/local/Installomator"
    local installomator_path="${installomator_dir}/Installomator.sh"

    log "Installomator not found. Downloading from the official GitHub release branch."

    /bin/mkdir -p "$installomator_dir"

    /usr/bin/curl \
        --fail \
        --location \
        --silent \
        --show-error \
        "$installomator_url" \
        --output "$installomator_path"

    if [[ -f "$installomator_path" ]]; then
        /bin/chmod 755 "$installomator_path"
        log "Installomator downloaded successfully."
    else
        log "ERROR: Installomator download failed."
        exit 96
    fi
}

############################################
# Checking for Tools
############################################

# Check minimum macOS requirement
if [[ "$(/usr/bin/sw_vers -buildVersion)" < "20A" ]]; then
    log "ERROR: This script requires at least macOS 11 Big Sur."
    exit 98
fi

# Check we are running as root
if [[ "$DEBUG" -eq 0 && "$(/usr/bin/id -u)" -ne 0 ]]; then
    log "ERROR: This script should be run as root."
    exit 97
fi

# Check that Parameter 6 was provided
if [[ -z "$app" ]]; then
    log "ERROR: Missing Installomator label. Add the app label to Jamf Parameter 6."
    exit 94
fi

# Clean up old dialog command file if present
if [[ -f "$dialog_command_file" ]]; then
    log "Removing old dialog command file."
    /bin/rm -f "$dialog_command_file"
else
    log "No dialog command file found. Continuing."
fi

# Check if Installomator exists
if [[ -f "$InstallomatorApp" ]]; then
    log "Installomator found. Continuing."
else
    install_installomator_from_github

    log "Checking if Installomator installed correctly."

    if [[ -f "$InstallomatorApp" ]]; then
        log "Installomator found. Continuing."
    else
        log "ERROR: Could not find Installomator."
        exit 96
    fi
fi

# Check if Swift Dialog exists
if [[ -d "$dialogApp" ]]; then
    log "Swift Dialog found. Continuing."
else
    log "Swift Dialog not found."
    log "Installing Swift Dialog with Installomator."

    "$InstallomatorApp" swiftdialog NOTIFY=silent INSTALL="force"

    log "Checking if Swift Dialog installed correctly."

    if [[ -d "$dialogApp" ]]; then
        log "Swift Dialog found. Continuing."
    else
        log "ERROR: Could not find Swift Dialog."
        exit 95
    fi
fi

############################################
# Logic
############################################

log "Installing $app."

# Display first screen
/usr/bin/open -a "$dialogApp" --args \
    --title none \
    --icon "$icon" \
    --overlayicon "$overlayicon" \
    --message "$message" \
    --mini \
    --progress 100 \
    --position bottomright \
    --movable \
    --commandfile "$dialog_command_file"

/bin/sleep 0.1

log "Running Installomator for label: $app."

# Install app using Installomator
"$InstallomatorApp" "$app" DIALOG_CMD_FILE="$dialog_command_file" NOTIFY=silent

############################################
# Cleanup
############################################

log "Cleaning up."

dialogUpdate "progress: complete"
dialogUpdate "progresstext: Done"

/bin/sleep 0.5

dialogUpdate "quit:"

/bin/sleep 0.5

# Dialog may already be closed, so ignore errors.
/usr/bin/killall "Dialog" 2>/dev/null || true

# Clean up dialog command file
/bin/rm -f "$dialog_command_file"

log "Done. Closing up."

exit 0