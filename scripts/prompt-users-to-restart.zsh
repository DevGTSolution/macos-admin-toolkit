#!/bin/zsh
#
# Author: Gabriel Marcelino
# Public-facing cleanup: 2026-05-05
# Updated: 2026-05-06
# Portfolio note: user restart prompt for managed macOS devices based on uptime.

# https://community.jamf.com/t5/jamf-pro/scheduling-rebooting-of-machines/m-p/223221
###################
### Adam T.
### April 16, 2020
### This is a JamfHelper Script which will be used to notify user if they have not restarted the computer in 7 days
### This script will give the user options how to proceed (now, 1 min, 5 min, 30 min 1 hr, 2 hrs as an example)
### This is needed as staff members tend not to restart their computers often
### This script is called from another script that checks uptime
##################
### Using Jamf Helper is cool
#################



#Message type variables below
JamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
DRY_RUN="${4:-${DRY_RUN:-true}}"
SELF_SERVICE_ICON="/Applications/Self Service.app/Contents/Resources/AppIcon.icns"
lastReboot=$(date -jf "%s" "$(sysctl kern.boottime | awk -F'[= |,]' '{print $6}')" +'%m%d%Y')
log="/var/log/Mac-Uptime.log"
timestamp=$(date +%F\ %T)

runRestart() {
    case "$DRY_RUN" in
        false|False|FALSE|0|no|No|NO)
            /sbin/shutdown -r now
            ;;
        *)
            echo "[DRY_RUN] Would run: /sbin/shutdown -r now"
            ;;
    esac
}

if [ $(date -v-"30"d +'%m%d%Y') -ge $lastReboot ]; then
    #Utility window gives a white background
    window="utility"
    title="Please Restart your computer!"
    heading="Please restart your computer"
    description="Your computer has not been restarted in more then 21 days. A more frequent restart is recommended.

    Doing so optimizes the performance of your computer as well as allows us to deploy security updates or new applications to you automatically.

    Please restart now."

    icon="$SELF_SERVICE_ICON"



    selection=$("$JamfHelper" -windowType "$window" -title "$title" -heading "$heading" -description "$description" -icon "$icon" -button2 "Restart"  -showDelayOptions "0, 60, 300, 3600, 7200, 14400" )

    buttonClicked="${selection:$i-1}"
    timeChosen="${selection%?}"

    ## Convert seconds to minutes for restart command
    timeMinutes=$((timeChosen/60))

    ## Echoes for troubleshooting purposes
    echo "$timestamp" : "Button clicked was: $buttonClicked" | tee -a $log
    echo "$timestamp" : "Time chosen was: $timeChosen" | tee -a $log
    echo "$timestamp" : "Time in minutes: $timeMinutes" | tee -a  $log

    if [[ "$buttonClicked" == "2" ]] && [[ ! -z "$timeChosen" ]]; then
        echo "Restart button was clicked. Initiating restart in $timeMinutes minutes"
        restartselection=$("$JamfHelper" -timeout "$timeChosen" -countdown -button1 "Restart Now" -heading "Restarting..." -title "Restarting Timer" -windowType utility -description "Will restart the computer when timer finishes. If you want to restart earlier, hit Restart Now.")
        if [ "$restartselection" = "0" ]; then 
        echo "$timestamp" : "Client chose to restart before time was up" | tee -a  $log
        runRestart
        else
        runRestart
        fi
    elif [[ "$buttonClicked" == "2" ]] && [[ -z "$timeChosen" ]]; then
        echo "$timestamp" : "Restart button was clicked. Initiating immediate restart" | tee -a  $log
    runRestart
        exit 0
    fi
elif [ $(date -v-"7"d +'%m%d%Y') -ge $lastReboot ]; then

    #Utility window gives a white background
    window="utility"
    title="Please Restart your computer!"
    heading="Please restart your computer"
    description="Your computer has not been restarted in at least seven days. A more frequent restart is recommended.

    Doing so optimizes the performance of your computer as well as allows us to deploy security updates or new applications to you automatically.

    Please restart now."

    icon="$SELF_SERVICE_ICON"



    selection=$("$JamfHelper" -windowType "$window" -title "$title" -heading "$heading" -description "$description" -icon "$icon" -button2 "Restart"  -showDelayOptions "0, 60, 300, 3600, 7200, 14400" -button1 "Cancel" -cancelButton 1)

    buttonClicked="${selection:$i-1}"
    timeChosen="${selection%?}"

    ## Convert seconds to minutes for restart command
    timeMinutes=$((timeChosen/60))

    ## Echoes for troubleshooting purposes
    echo "$timestamp" : "Button clicked was: $buttonClicked" | tee -a $log
    echo "$timestamp" : "Time chosen was: $timeChosen" | tee -a $log
    echo "$timestamp" : "Time in minutes: $timeMinutes" | tee -a  $log

    if [[ "$buttonClicked" == "2" ]] && [[ ! -z "$timeChosen" ]]; then
        echo "Restart button was clicked. Initiating restart in $timeMinutes minutes"
        restartselection=$("$JamfHelper" -timeout "$timeChosen" -countdown -button1 "Restart Now" -heading "Restarting..." -title "Restarting Timer" -windowType utility -description "Will restart the computer when timer finishes. If you want to restart earlier, hit Restart Now." -button2 "Cancel")
        if [ "$restartselection" = "0" ]; then 
        echo "$timestamp" : "Client chose to restart before time was up" | tee -a  $log
        runRestart
        elif [ "$restartselection" = "2" ]; then
        echo "$timestamp" : "Cancel button clicked. Exiting..." | tee -a  $log
        fi
    elif [[ "$buttonClicked" == "2" ]] && [[ -z "$timeChosen" ]]; then
        echo "$timestamp" : "Restart button was clicked. Initiating immediate restart" | tee -a  $log
        runRestart
        elif [ "$buttonClicked" = "1" ]; then
        echo "$timestamp" : "Cancel button clicked. Exiting..." | tee -a  $log
        exit 0
    fi
    
fi

exit
