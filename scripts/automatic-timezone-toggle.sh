#!/bin/sh
#
# Author: Gabriel Marcelino
# Public-facing cleanup: 2026-05-05
# Updated: 2026-05-06
# Portfolio note: macOS utility for toggling automatic time zone behavior.

## Variables
uuid=$(/usr/sbin/system_profiler SPHardwareDataType | grep "Hardware UUID" | cut -c22-57)

# Prompting the User the
## Prompting the user to enable or disable automatic time zone
buttonPress=$(/usr/bin/osascript <<EOT
	tell application "System Events"
    activate
    display dialog "Would you like to Enable or Disable automatic time zone?" buttons {"Enable", "Disable"} default button 2
    if button returned of result is "Disable" then
	set buttonName to button returned of result
	else if button returned of result is "Enable" then
	set buttonName to button returned of result 
    end if
    end tell
EOT
)

# If Disable - Reset to manual time zone
if [ "$buttonPress" = "Disable" ]; then
	echo "
    Disabling automatic time zone
    "
## Prompt User for Which time zone
timezone=$(/usr/bin/osascript <<EOF
	tell application "System Events"
    activate
    set theTimeZone to {"PST", "MDT", "MST", "EST", "CST"}
    set TimeZoneChoice to choose from list theTimeZone with prompt "Please choose which time zone to set:" default items {"PST"}
    return TimeZoneChoice
    end tell
EOF
)

## disabling location services
	/usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -int 0
	/usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd."$uuid" LocationServicesEnabled -int 0
	sudo /usr/bin/defaults write /private/var/db/timed/Library/Preferences/com.apple.timed.plist TMAutomaticTimeZoneEnabled -bool false
	sudo /usr/bin/defaults write /private/var/db/timed/Library/Preferences/com.apple.timezone.auto.plist Active -bool false
    # Setting up the time zone
echo "
Time Zone Choice was $timezone
"
    if [ "$timezone" = "PST" ]; then 
    /usr/sbin/systemsetup -settimezone America/Los_Angeles
    elif [ "$timezone" = "MDT" ]; then 
    /usr/sbin/systemsetup -settimezone America/Denver
    elif [ "$timezone" = "MST" ]; then 
    /usr/sbin/systemsetup -settimezone America/Phoenix
    elif [ "$timezone" = "EST" ]; then 
    /usr/sbin/systemsetup -settimezone America/New_York
    elif [ "$timezone" = "CST" ]; then 
    /usr/sbin/systemsetup -settimezone America/Chicago
fi
time=$(/bin/date +%r::%Z)
# Echo Results
echo "####################
Time Zone set to $timezone, the computer time is $time
####################" 
# If Enable - Set to automatic time zone
elif [ "$buttonPress" = "Enable" ]; then
	echo "Enabling automatic time zone"
    /usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd LocationServicesEnabled -int 1
	/usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd."$uuid" LocationServicesEnabled -int 1
	sudo /usr/bin/defaults write /private/var/db/timed/Library/Preferences/com.apple.timed.plist TMAutomaticTimeZoneEnabled -bool true
	sudo /usr/bin/defaults write /private/var/db/timed/Library/Preferences/com.apple.timezone.auto.plist Active -bool true
fi
#/sbin/shutdown -r now
/usr/bin/killall locationd
