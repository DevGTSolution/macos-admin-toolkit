#!/bin/sh
#
# Author: Gabriel Marcelino
# Public-facing cleanup: 2026-05-05
# Updated: 2026-05-06
# Portfolio note: generalized Jamf deferral workflow for application updates.

######### Defined Arguments #########
# $4 ===> [OPTIONAL] Default is 0 for limited deferrals. 1=Limited deferrals, with time limit set in $5, 0=unlimited deferrals
# $5 ===> [REQUIRED Only if $4 is 0, meaning you want to set limited deferrals] How many hours before there are no more deferrals?
# $6 ===> [OPTIONAL] Default is 15 minutes. How many minutes in blocks of 15 do you want between each prompt? 15, 30, 45, 60, etc
# $7 ===> [OPTIONAL] URL of .png used for user messaging. Setting the $6 argument clobbers the default image. Apple Software Update icon will be used if no URL is specified
# $8 ===> [REQUIRED] Title of Application being updated. Has to be exact .app name
# $9 ===> [REQUIRED] Jamf trigger for starting the policy
#
######### End Defined Arguements #########

######### Set variables for the script ############

######### Set WorkingDir to $5 #########
if [ -z "$4" ]; then
	# $4 is null
	isLimited=0
else
	# Unlimited recurring prompts
	isLimited="$4"
fi

# How many hours do you want this to run?
# The default is 1, meaning that after 1 hour, or 4 checkins, the user will have no deferrals and the policy will execute.
# Checkins happen every 15 minutes, or 4 times per hour
# Total hours before no more deferrals = $5 (Number of hours) * 4 (Number of checkins)
if [ -z "$5" ]; then
	# $5 is null
	totalHours=1 #default number of intervals
else
	totalHours=$5 #default number of intervals
fi
totalCheckins=`expr $totalHours \* 4`
echo "\$totalCheckins=" $totalCheckins

# How many minutes in increments of 15 do you want between each prompt?
# The default is 15 minutes, meaning that the policy will prompt the user every checkin
# Chekins happen every 15 minutes, or 4 times per hour
# Prompts will happen every (( $5 / 15 ))
if [ -z "$6" ]; then
	# $5 is null
	minBetweenPrompts=15 #default number of intervals
else
	minBetweenPrompts=$6 #default number of intervals
fi
intervalDefault=`expr $minBetweenPrompts / 15`
echo "\$intervalDefault="$intervalDefault

######### Set icon source to $7 #########

## Example: https://files.example.com/icon.png
## Example: /Applications/Self Service.app/Contents/Resources/AppIcon.icns
# Jamf Self Service icon will be used if no icon source is specified
if [ -z "$7" ]; then
	# $7 is null
	iconSource="/Applications/Self Service.app/Contents/Resources/AppIcon.icns"
else
	iconSource="$7"
fi
######### Done setting $iconSource #########

######### Set swTitle to $8 #########
titleAndVersion="$8"
##Example: zoom.us Firefox, Google Chrome, exact name of .app, case-sensitive

swTitle=`echo $titleAndVersion | awk -F',' '{print $1}'`


######### Done setting $swTitle #########

######### Set updateVersion #########
updateVersion=`echo $titleAndVersion | awk -F',' '{print $2}'`

######## Set promptUser to $9 #########
promptUser="$9"


######### Set trigger to $10 #########

##Example: sginstall
trigger="${10}"
echo "JAMF Policy trigger: $trigger"
######### Done setting $trigger #########


######### Set delimitValue to $11 #########
##Example: -, (,  
delimitValue="${11}"
######### Done setting $delimitValue #########

##Example: capsulecorp or Capsule Corp
# Path if $10 is not specified: /usr/local/jamfworkingdir/resources/
#if [ -z "$10" ]; then
	WorkingDir="exampleorg"
#else
#	WorkingDir="${10}"
#fi


## Path to Log file. Map your own Log Path.  Do not use /tmp as it is emptied on boot.
LogPath="/usr/local/${WorkingDir}/logs"

## Set log file and console to recieve output of commands
Log_File="$LogPath/${swTitle} Defer.log"

##below are settings for the title and heading of the JamfHelper prompts seen by the user logged in
title="${swTitle} update required"

# Heading of the notification
heading="$swTitle update required"

# path of file used to count intervals
countFile="/usr/local/${WorkingDir}/resources/${swTitle} count.txt"

######### End set variables for the script ############

######### Create settings for logging and create log file #########

## Verify Resources directory exists
if ! [ -d "/usr/local/${WorkingDir}/resources" ]; then
	echo "JAMF Resources directory doesn't exist yet. Creating Resources directory..."
	mkdir -p "/usr/local/${WorkingDir}/resources"
fi
## Verify Logs directory exists
if ! [ -d "/usr/local/${WorkingDir}/logs" ]; then
	echo "JAMF Logs directory doesn't exist yet. Creating Logs directory..."
	mkdir -p "/usr/local/${WorkingDir}/logs"
fi
## Verify Icons directory exists
if ! [ -d "/usr/local/${WorkingDir}/icons" ]; then
	echo "JAMF Icon directory doesn't exist yet. Creating Icon directory..."
	mkdir -p "/usr/local/${WorkingDir}/icons"
fi

# Hide org directory in Shared directory
chflags hidden "/usr/local/${WorkingDir}"


responseToPrompt ()
{
	if [[ -z $prompt ]];then
		#User ugly closed the prompt.
		sendToLog "User ugly closed the prompt."
		exit 0
	elif [[ $prompt = 0 ]]; then
		##User elected to start updates or the timer ran out after 15 minutes.  Kicking off Apple update script
		sendToLog "User chose to update ${swTitle}..."
		sendToLog "Starting Update Script via Jamf trigger"
		jamf policy -trigger $trigger
		sendToLog "*************************************************"
		sendToLog "Policy $trigger ended. Continuing Maintenance-Deferral script"
		sendToLog "*************************************************"
		if [[ -e "$countFile" ]]; then
			rm "$countFile"
		fi
		sendToLog "Performing a JAMF Inventory Update and exiting..."
        jamf recon
		exit 0
	elif [[ $prompt = 2 || $prompt = 239 ]]; then
		#User either ugly closed the prompt, or choose to delay.
		sendToLog "User either ugly closed the prompt, or chose to defer."
		interval=$(( $interval - 1 ))
		echo $interval > "$countFile"
		exit 0
	else
		##Something unexpected happened.  I don't really know how the user got here, but for fear of breaking things or abruptly rebooting computers we will set a flag for the mac in Jamf saying something went wrong.
		sendToLog "*************************************************"
		sendToLog "Something went wrong, the prompt equalled $prompt"
		sendToLog "*************************************************"
		##Insert API work here at a later data to update JSS that the script is failing.
		exit 1
	fi
}

sendToLog ()
{
	echo "$(date +"%Y-%b-%d %T") : $1" | tee -a "$Log_File"
}

## begin log file
sendToLog "Script Started"

######### End Create settings for logging and create log file #########

# Get current $swTitle version
if [[ $swTitle == *"Google Chrome"* ]]; then
	currentVersion=`ps -eo args -r | grep "/Applications/${swTitle}.app"`
	# Get version number from line 1
	currentVersion=`echo "$currentVersion" | awk -F"/" 'NR==1{print $8}'`

	while [[ $currentVersion == "" ]]; do
		currentVersion=`ps -eo args -r | grep "/Applications/${swTitle}.app"`
		currentVersion=`echo "$currentVersion" | awk -F"/" 'NR==1{print $8}'`
		sleep 1
	done 
else
	currentVersion=`mdls "/Applications/${swTitle}.app" -name kMDItemVersion | awk -F'"' '{print $2}'`
fi

if ! [[ -z $delimitValue ]]; then
	if [[ "$currentVersion" == *"$delimitValue"* ]]; then
		currentVersion=`echo "$currentVersion" | awk -F"$delimitValue" '{print $1}'`
	fi
fi

deferralWorkflow () {
	iconPath="/usr/local/${WorkingDir}/icons/${swTitle}.png"
	echo "Preparing icon for messaging..."
	if [[ "$iconSource" == http* ]]; then
		curl -L "$iconSource" -o "$iconPath"
	elif [[ -f "$iconSource" ]]; then
		cp "$iconSource" "$iconPath"
	else
		echo "Icon source not found: $iconSource"
	fi


	# set $processname to lowercase of $swTitle
	processname=`echo "$swTitle" | tr '[:upper:]' '[:lower:]'`

	if pgrep "$swTitle" || pgrep $swTitle || pgrep "${processname}" || pgrep ${processname} ; then

		######### Start the hardwork ############

		if [[ $promptUser = "Yes" ]]; then

			##Determine how many 15 minute intervals to delay prompt
			remainIntervals=`cat "$countFile"`

			##Check that remainIntervals isn't null (aka pulled back an empty value), if so set it to $intervalDefault
			#Check if $remainIntervals is $null

			if [[ $isLimited = 1 ]]; then
				if [[ -z "$remainIntervals" ]]; then
					interval="$totalCheckins"
				else
					interval="$remainIntervals"
				fi
			else
				if [[ -z "$remainIntervals" ]]; then
					interval="$intervalDefault"
				elif [[ "remainIntervals" -lt 0 ]]; then
					interval="$intervalDefault"
					remainIntervals=$interval
				else
					interval="$remainIntervals"
				fi
			fi

			if [ -z "$remainIntervals" ]; then
				sendToLog "$swTitle is running. This is the first time the user has seen the update prompt. Asking if they would like to update now or to delay..."
				description=`echo "If Update now is selected, any open ${swTitle} windows will be closed and the update may take up to 5 minutes. If you would like to defer for $minBetweenPrompts minutes, please select Defer."`
				button1="Update now"
				button2=`echo "Defer ($minBetweenPrompts)"`
				##prompt the user
				prompt=`"/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType hud -title "$title" -heading "$heading" -alignHeading justified -description "$description" -alignDescription left -icon "/usr/local/${WorkingDir}/icons/${swTitle}.png" -button1 "$button1" -button2 "$button2" -timeout 3600 -countdown -lockHUD -defaultButton 1 -cancelButton 2`
				sendToLog "prompt equaled $prompt. 0=Start Updates 1=failed to prompt 2=User chose defer 239=exited Null=user force quit jamfHelper"
				# Instructions for reponse to prompt here
				responseToPrompt
			else
				# User has seen the prompt before
				######### There is a limited amount of deferrals before the user will be forced to update ############
				if [[ $isLimited = 1 ]]; then
					if [[ $remainIntervals = 1 ]]; then
						#User does not get a prompt during this step
						remainIntervals=$(( $remainIntervals - 2 ))
						echo $remainIntervals > "$countFile"
					elif [[ $remainIntervals -lt 0 ]]; then
						#User has no more deferrals
						sendToLog "$swTitle is running. The user has no more deferrals remaining. The user will  have 5 minutes before the JAMF policy $trigger will execute..."
						description=`echo "You have no deferrals remaining. \n\nYou have 5 minutes remaining before ${swTitle} is forced to closed and update. Please save all of your work. \n\n$swTitle will close, update, and reopen after updating."`
						button1="Update now"
						##prompt the user
						prompt=`"/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType hud -title "$title" -heading "$heading" -alignHeading justified -description "$description" -alignDescription left -icon "/usr/local/${WorkingDir}/icons/${swTitle}.png" -button1 "$button1" -timeout 300 -countdown -lockHUD -defaultButton 1`
						sendToLog "prompt equaled $prompt. 0=Start Updates 1=failed to prompt 2=User chose defer 239=exited Null=user force quit jamfHelper"
						# Instructions for reponse to prompt here
						responseToPrompt
					elif [[ `expr $remainIntervals % $intervalDefault` -eq 0 ]]; then
						# Calculating how many times the user will see the prompt before their mac will be forced to execute the JAMF policy specifed in $9
						sendToLog "Calculating how many times the user will see the prompt before their mac will be forced to execute the JAMF policy $9"
						deferRemaining=`expr $remainIntervals / $intervalDefault`
						sendToLog "$swTitle is running. The user has $deferRemaining remaining deferrals before they will be forced to execute the JAMF policy ${trigger}. Asking if they would like to update now or to delay..."
						description=`echo "You have $deferRemaining deferral(s) remaining until you will be forced to update. \n\nIf Update now is selected, $swTitle will close, update, and reopen after updating. If you would like to defer for $minBetweenPrompts minutes, please select Defer."`
						button1="Update now"
						button2=`echo "Defer ($minBetweenPrompts)"`
						##prompt the user
						prompt=`"/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType hud -title "$title" -heading "$heading" -alignHeading justified -description "$description" -alignDescription left -icon "/usr/local/${WorkingDir}/icons/${swTitle}.png" -button1 "$button1" -button2 "$button2" -timeout 900 -countdown -lockHUD -defaultButton 1 -cancelButton 2`
						sendToLog "User selected $prompt."
						sendToLog "0=Start Updates 1=failed to prompt 2=User chose defer 239=exited Null=user force quit jamfHelper"
						# Instructions for reponse to prompt here
						responseToPrompt
					else
						remainIntervals=$(( $remainIntervals - 1 ))
						echo $remainIntervals > "$countFile"
					fi
				######### There is an unlimited amount of deferrals. The prompt will not go away until the computer is out of policy scope ############
				else
					if [[ $remainIntervals -le 0 ]]; then
						sendToLog "$swTitle is running. Asking if they would like to update now or to delay..."
						description=`echo "If Update now is selected, any open ${swTitle} windows will be closed and the update may take up to 5 minutes. If you would like to defer for $minBetweenPrompts minutes, please select Defer."`
						button1="Update now"
						button2=`echo "Defer ($minBetweenPrompts)"`
						##prompt the user
						prompt=`"/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType hud -title "$title" -heading "$heading" -alignHeading justified -description "$description" -alignDescription left -icon "/usr/local/${WorkingDir}/icons/${swTitle}.png" -button1 "$button1" -button2 "$button2" -timeout 900 -countdown -lockHUD -defaultButton 1 -cancelButton 2`
						sendToLog "prompt equaled $prompt. 0=Start Updates 1=failed to prompt 2=User chose defer 239=exited Null=user force quit jamfHelper"
						# Instructions for reponse to prompt here
						responseToPrompt
					else
						remainIntervals=$(( $remainIntervals - 1 ))
						echo $remainIntervals > "$countFile"
					fi
				fi
			fi
		else
			sendToLog "${swTitle} is running. Not prompting. No action taken"
		fi
	else
    	if [[ -e "$countFile" ]]; then
			rm "$countFile"
		fi
		sendToLog "${swTitle} is not running, updating now..."
		jamf policy -trigger $trigger
		sendToLog "Performing a JAMF Inventory Update and exiting..."
		jamf recon

	fi
}


# Remove periods from $currentVersion
installedversionMajor=$( echo "$currentVersion" | /usr/bin/awk -F. '{print $1}' )
installedversionMinor=$( echo "$currentVersion" | /usr/bin/awk -F. '{print $2}' )
installedversionPatch=$( echo "$currentVersion" | /usr/bin/awk -F. '{print $3}' )

# Remove periods from $updateVersion
updateversionMajor=$( echo "$updateVersion" | /usr/bin/awk -F. '{print $1}' )
updateversionMinor=$( echo "$updateVersion" | /usr/bin/awk -F. '{print $2}' )
updateversionPatch=$( echo "$updateVersion" | /usr/bin/awk -F. '{print $3}' )


if [[ $installedversionMajor -ge $updateversionMajor ]]; then
	echo "Installed major version is greater than or equal to the latest version of ${swTitle}"
	echo "Checking ${swTitle} minor version..."
	if [[ $installedversionMinor -ge $updateversionMinor ]]; then
		echo "Installed minor version is greater than or equal to the latest version of ${swTitle}"
		echo "Checking ${swTitle} patch version..."
		if [[ $installedversionPatch -ge $updateversionPatch ]]; then
			echo "Installed patch version is greater than or equal to the latest version of ${swTitle}"
			sendToLog "${swTitle} $currentVersion is already up to date. No action taken."
			if [[ -e "$countFile" ]]; then
				rm "$countFile"
			fi
		else
			sendToLog "Installed patch version is less than the latest version of ${swTitle}. Beginning Deferral workflow..."
			deferralWorkflow
		fi
	else
		sendToLog "Installed minor version is less than the latest version of ${swTitle}. Beginning Deferral workflow..."
		deferralWorkflow
	fi
else
	sendToLog "Installed major version is less than the latest version of ${swTitle}. Beginning Deferral workflow..."
	deferralWorkflow
fi
exit 0
