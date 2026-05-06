#!/bin/zsh
# Author: Gabriel Marcelino
# Public-facing cleanup: 2026-05-05
# Updated: 2026-05-06
# Portfolio note: generalized monthly app maintenance workflow using Jamf,
# Installomator, user deferrals, and a swiftDialog progress UI.

: <<'ABOUT_THIS_SCRIPT'
-----------------------------------------------------------------------
monthly app maintenance... we send a notification, 
jamf helper or some other method > We list the apps we want to update, 
that may or may not need to restart > users can defer or run > 
run a script that runs through all the policies to update, apps not running just update silently, 
apps running will prompt them to close and restart. depending if the app is in Installomator, 
it can handle the prompt per app, others we just handle
if the user defers the initial prompt, just update the apps that are not running silently

Working with This to make a script using Installomator and Jamf with the following:

On Installomator:

Adobe Creative Cloud DC
Amazon Workspace
Google Chrome 
Microsoft Office 2019/365 (All Separate)
VS Code
Mozilla Firefox 
RingCentral Softphone
Slack
VLC
zoom.us
TextExpander
talkdeskcallbar

On Installomator but not on this script yet:
boxdrive
googledrive
installomator
lastpass
macadminspython
sublimetext
viscosity

Not on Installomator:

Adobe Acrobat Professional DC (using Adobe binary for update)
Adobe Suite (using Adobe binary for update)
Carbon Black Cloud - installCBD
JAMF Connect
Palo Alto Networks GlobalProtect VPN 
Qualys Cloud Agent
Cisco OpenDNS Umbrella Roaming Client - Auto Update
-----------------------------------------------------------------------
ABOUT_THIS_SCRIPT
############################################
# Variables
############################################
JAMF_BINARY="/usr/local/bin/jamf"
AdobeRUM="/usr/local/bin/RemoteUpdateManager"
versionKey="CFBundleShortVersionString"
DialogBinary="/usr/local/bin/dialog"
InstallomatorApp="/usr/local/Installomator/Installomator.sh"
SELF_SERVICE_ICON="/Applications/Self Service.app/Contents/Resources/AppIcon.icns"
LOGO="$SELF_SERVICE_ICON"
WorkingDir="/usr/local/exampleorg/MonthlyUpdates"
Log_File="/var/log/MonthlyUpdate_Defer.log"
countFile="${WorkingDir}/resources/MonthlyUpdate count.txt"
loggedInUser=$( ls -l /dev/console | awk '{print $3}' )
userID=$( id -u $loggedInUser )
Deferral_Policy="MonthlyUpdateDeferral"
Deferral_PLIST="/Library/LaunchAgents/com.exampleorg.monthlyupdatedeferral.plist"
IFS=,
############################################
# Functions
############################################
sendToLog () {
	echo "$(date +"%Y-%b-%d %T") : $1" | tee -a "$Log_File"
}

getJSONValue() {
	# $1: JSON string OR file path to parse (tested to work with up to 1GB string and 2GB file).
	# $2: JSON key path to look up (using dot or bracket notation).
	printf '%s' "$1" | /usr/bin/osascript -l 'JavaScript' \
		-e "let json = $.NSString.alloc.initWithDataEncoding($.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile$(/usr/bin/uname -r | /usr/bin/awk -F '.' '($1 > 18) { print "AndReturnError(ObjC.wrap())" }'), $.NSUTF8StringEncoding)" \
		-e 'if ($.NSFileManager.defaultManager.fileExistsAtPath(json)) json = $.NSString.stringWithContentsOfFileEncodingError(json, $.NSUTF8StringEncoding, ObjC.wrap())' \
		-e "const value = JSON.parse(json.js)$([ -n "${2%%[.[]*}" ] && echo '.')$2" \
		-e 'if (typeof value === "object") { JSON.stringify(value, null, 4) } else { value }'
}

xpath() {
	# the xpath tool changes in Big Sur and now requires the `-e` option
	if [[ $(sw_vers -buildVersion) > "20A" ]]; then
		/usr/bin/xpath -e $@
		# alternative: switch to xmllint (which is not perl)
		#xmllint --xpath $@ -
	else
		/usr/bin/xpath $@
	fi
}

## Getting App Version ##

getAppVersion() {
    # modified by: Søren Theilgaard (@theilgaard) and Isaac Ordonez
    appPathArray=( ${(0)applist} )

        if [[ ${#appPathArray} -gt 0 ]]; then
            filteredAppPaths=( ${(M)appPathArray:#${targetDir}*} )
                if [[ ${#filteredAppPaths} -eq 1 ]]; then
            installedAppPath=$filteredAppPaths[1]
            #appversion=$(mdls -name kMDItemVersion -raw $installedAppPath )
            appversion=$(defaults read $installedAppPath/Contents/Info.plist $versionKey) #Not dependant on Spotlight indexing
            echo "Found app at $installedAppPath, version $appversion, on versionKey $versionKey"
            updateDetected="YES"
                else
                echo "could not determine location of $name"
            fi
        else
            echo "could not find $name"
        fi
}

## Checking if apps exist ##

Install_App_List() {

    ##### Adobe CC #####
    name="Creative Cloud"
    applist="/Applications/Utilities/Adobe Creative Cloud/ACC/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--Adobe Cloud Exists--"
        echo "Checking latest Version"
            if [[ "$(arch)" == "arm64" ]]; then
            downloadURL=$(curl -fs "https://helpx.adobe.com/download-install/kb/creative-cloud-desktop-app-download.html" | grep -o 'https.*macarm64.*dmg' | head -1 | cut -d '"' -f1)
        else
            downloadURL=$(curl -fs "https://helpx.adobe.com/download-install/kb/creative-cloud-desktop-app-download.html" | grep -o 'https.*osx10.*dmg' | head -1 | cut -d '"' -f1)
        fi        
    	appNewVersion=$(echo $downloadURL | grep -o '[^x]*$' | cut -d '.' -f 1 | sed 's/_/\./g')
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then   
            	    echo "$name Needs to be updated"   
        			appsdisplay+=$(echo "$name,")
        			## Installomator variable ##
        			install_apps+=$(echo "adobecreativeclouddesktop ")
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
    	else
        echo "--No $name--"
    fi

    ##### Amazon Workspaces #####
    name="Workspaces"
    applist="/Applications/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--Amazon $name Exists--"
        echo "Checking latest Version"
        appNewVersion=$(curl -fs https://d2td7dqidlhjx7.cloudfront.net/prod/iad/osx/WorkSpacesAppCast_macOS_20171023.xml | grep -o "Version*.*<" | head -1 | cut -d " " -f2 | cut -d "<" -f1)
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then   
            	    echo "$name Needs to be updated"   
        			appsdisplay+=$(echo "Amazon $name,")
        			## Installomator variable ##
        			install_apps+=$(echo "amazonworkspaces ")
        	    else
        	        echo "Amazon $name is on the latest version $appNewVersion"
        	    fi
    	else
        echo "--No Amazon $name--"
    fi

    ##### Google Chrome #####
    name="Google Chrome"
    applist="/Applications/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--$name Exists--"
        echo "Checking latest Version"
        appNewVersion=$(curl -s https://omahaproxy.appspot.com/history | awk -F',' '/mac_arm64,stable/{print $3; exit}')
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then   
            	    echo "$name Needs to be updated"   
        			appsdisplay+=$(echo "$name,")
        			## Installomator variable ##
        			install_apps+=$(echo "googlechrome ")
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
    	else
        echo "--No $name--"
    fi

    ##### Microsoft Auto Updater #####
    name="Microsoft AutoUpdate"
    applist="/Library/Application Support/Microsoft/MAU2.0/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--$name Exists--"
        echo "Checking latest Version"
        downloadURL="https://go.microsoft.com/fwlink/?linkid=830196"
        appNewVersion=$(curl -fsIL "$downloadURL" | grep -i location: | grep -o "/Microsoft_.*pkg" | cut -d "_" -f 3 | cut -d "." -f 1-2)
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then
                	if [[ "$appversion" > "$appNewVersion" ]]; then
                	  echo "$name is on a higher version then reported: $appversion"
                	  else
            	    	echo "$name Needs to be updated"   
        				appsdisplay+=$(echo "$name,")
        				## Installomator variable ##
        				install_apps+=$(echo "microsoftautoupdate ")
        				fi
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
    	else
        echo "--No $name--"
    fi

    ##### Microsoft Office Excel #####
    name="Microsoft Excel"
    applist="/Applications/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--$name Exists--"
        echo "Checking latest Version"
        downloadURL="https://go.microsoft.com/fwlink/?linkid=525135"
        appNewVersion=$(curl -fsIL "$downloadURL" | grep -i location: | grep -o "/Microsoft_.*pkg" | cut -d "_" -f 3 | cut -d "." -f 1-2)
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then
                	if [[ "$appversion" > "$appNewVersion" ]]; then
                	  echo "$name is on a higher version then reported: $appversion"
                	  else
            	    	echo "$name Needs to be updated"   
        				appsdisplay+=$(echo "$name,")
        				## Installomator variable ##
        				install_apps+=$(echo "microsoftexcel ")
        				fi
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
    	else
        echo "--No $name--"
    fi

    ##### Microsoft Office PowerPoint #####
    name="Microsoft PowerPoint"
    applist="/Applications/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--$name Exists--"
        echo "Checking latest Version"
        downloadURL="https://go.microsoft.com/fwlink/?linkid=525136"
        appNewVersion=$(curl -fsIL "$downloadURL" | grep -i location: | grep -o "/Microsoft_.*pkg" | cut -d "_" -f 3 | cut -d "." -f 1-2)
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then
                	if [[ "$appversion" > "$appNewVersion" ]]; then
                	  echo "$name is on a higher version then reported: $appversion"
                	  else
            	    	echo "$name Needs to be updated"   
        				appsdisplay+=$(echo "$name,")
        				## Installomator variable ##
        				install_apps+=$(echo "microsoftpowerpoint ")
        				fi
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
    	else
        echo "--No $name--"
    fi


    ##### Microsoft Office Word #####
   name="Microsoft Word"
    applist="/Applications/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--$name Exists--"
        echo "Checking latest Version"
        downloadURL="https://go.microsoft.com/fwlink/?linkid=525134"
        appNewVersion=$(curl -fsIL "$downloadURL" | grep -i location: | grep -o "/Microsoft_.*pkg" | cut -d "_" -f 3 | cut -d "." -f 1-2)
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then
                	if [[ "$appversion" > "$appNewVersion" ]]; then
                	  echo "$name is on a higher version then reported: $appversion"
                	  else
            	    	echo "$name Needs to be updated"   
        				appsdisplay+=$(echo "$name,")
        				## Installomator variable ##
        				install_apps+=$(echo "microsoftword ")
        				fi
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
    	else
        echo "--No $name--"
    fi

    ##### Microsoft VS Code #####

    name="Visual Studio Code"
    applist="/Applications/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--$name Exists--"
        echo "Checking latest Version"
        downloadURL="https://go.microsoft.com/fwlink/?LinkID=2156837"
        appNewVersion=$(curl -fsL "https://code.visualstudio.com/Updates" | grep "/darwin" | grep -oiE ".com/([^>]+)([^<]+)/darwin" | cut -d "/" -f 2 | sed $'s/[^[:print:]	]//g' | head -1 )
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then
                	if [[ "$appversion" > "$appNewVersion" ]]; then
                	  echo "$name is on a higher version then reported: $appversion"
                	  else
            	    	echo "$name Needs to be updated"   
        				appsdisplay+=$(echo "$name,")
        				## Installomator variable ##
        				install_apps+=$(echo "visualstudiocode ")
        				fi
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
    	else
        echo "--No $name--"
    fi

    ##### Mozilla FireFox #####
    name="Firefox"
    applist="/Applications/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--Firefox Exists--"
        echo "Checking latest Version"
        firefoxVersions=$(curl -fs "https://product-details.mozilla.org/1.0/firefox_versions.json")
        appNewVersion=$(getJSONValue "$firefoxVersions" "LATEST_FIREFOX_VERSION")
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then   
            	    echo "$name Needs to be updated"   
        			appsdisplay+=$(echo "$name,")
        			## Installomator variable ##
        			install_apps+=$(echo "firefox ")
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
    	else
        echo "--No $name--"
    fi

    ##### RingCentral Softphone #####
    name="RingCentral for Mac"
    applist="/Applications/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--$name Exists--"
        echo "Checking latest Version"
        downloadURL="https://downloads.ringcentral.com/sp/RingCentralForMac"
        appNewVersion=$(curl -fsIL "$downloadURL" | grep -i location: | grep -o "/RingCentral-Phone.*dmg" | cut -d "-" -f 3 | cut -d "." -f 1-3)
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then   
            	    echo "$name Needs to be updated"   
        			appsdisplay+=$(echo "$name,")
        			## Installomator variable ##
        			install_apps+=$(echo "ringcentralphone ")
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
    	else
        echo "--No $name--"
    fi

    ##### Slack #####
    name="Slack"
    applist="/Applications/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--$name Exists--"
        echo "Checking latest Version"
        downloadURL="https://slack.com/ssb/download-osx-universal"
    	appNewVersion=$( curl -fsIL "${downloadURL}" | grep -i "^location" | cut -d "/" -f6 )
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then   
            	    echo "$name Needs to be updated"   
        			appsdisplay+=$(echo "$name,")
        			## Installomator variable ##
        			install_apps+=$(echo "slack ")
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
    	else
        echo "--No $name--"
    fi

    ##### VLC #####
    name="VLC"
    applist="/Applications/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--$name Exists--"
        echo "Checking latest Version"
        if [[ $(arch) == "arm64" ]]; then
        downloadURL=$(curl -fs http://update.videolan.org/vlc/sparkle/vlc-arm64.xml | xpath '//rss/channel/item[last()]/enclosure/@url' 2>/dev/null | cut -d '"' -f 2 )
        #appNewVersion=$(curl -fs http://update.videolan.org/vlc/sparkle/vlc-arm64.xml | xpath '//rss/channel/item[last()]/enclosure/@sparkle:version' 2>/dev/null | cut -d '"' -f 2 )
    elif [[ $(arch) == "i386" ]]; then
        downloadURL=$(curl -fs http://update.videolan.org/vlc/sparkle/vlc-intel64.xml | xpath '//rss/channel/item[last()]/enclosure/@url' 2>/dev/null | cut -d '"' -f 2 )
        #appNewVersion=$(curl -fs http://update.videolan.org/vlc/sparkle/vlc-intel64.xml | xpath '//rss/channel/item[last()]/enclosure/@sparkle:version' 2>/dev/null | cut -d '"' -f 2 )
    fi
    	appNewVersion=$(echo ${downloadURL} | sed -E 's/.*\/vlc-([0-9.]*).*\.dmg/\1/' )
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then   
            	    echo "$name Needs to be updated"   
        			appsdisplay+=$(echo "$name,")
        			## Installomator variable ##
        			install_apps+=$(echo "vlc ")
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
    	else
        echo "--No $name--"
    fi
    ##### TextExpander #####
    name="TextExpander"
    applist="/Applications/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--$name Exists--"
        echo "Checking latest Version"
        downloadURL="https://cgi.textexpander.com/cgi-bin/redirect.pl?cmd=download&platform=osx"
    	appNewVersion="$( curl -fsIL "https://cgi.textexpander.com/cgi-bin/redirect.pl?cmd=download&platform=osx" | grep -i "^location" | awk '{print $2}' | tail -1 | cut -d "_" -f2 | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p' )"
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then   
            	    echo "$name Needs to be updated"   
        			appsdisplay+=$(echo "$name,")
        			## Installomator variable ##
        			install_apps+=$(echo "TextExpander ")
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
        else
        echo "--No $name--"
    fi

    ##### talkdeskcallbar #####
    name="Callbar"
    applist="/Applications/$name.app"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--$name Exists--"
        echo "Checking latest Version"
        talkdeskcallbarVersions=$(curl -fsL "https://downloadcallbar.talkdesk.com/release_metadata.json")
        appNewVersion=$(getJSONValue "$talkdeskcallbarVersions" "version")
        downloadURL=https://downloadcallbar.talkdesk.com/Callbar-${appNewVersion}.dmg
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then   
            	    echo "$name Needs to be updated"   
        			appsdisplay+=$(echo "$name,")
        			## Installomator variable ##
        			install_apps+=$(echo "talkdeskcallbar ")
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
        else
        echo "--No $name--"
    fi
    ##### zoom.us #####
    name="zoom.us"
    applist="/Applications/$name.app"
    versionKey="CFBundleVersion"
    echo "App File Path: $applist"
    if [ -d "$applist" ]; then
        echo "--$name Exists--"
        echo "Checking latest Version"
        downloadURL="https://zoom.us/client/latest/ZoomInstallerIT.pkg"
    	appNewVersion="$(curl -fsIL ${downloadURL} | grep -i ^location | cut -d "/" -f5)"
        echo "$name Latest Version: $appNewVersion"
            ## Getting Current Version ##
                getAppVersion
                echo "Mac has $name version $appversion "
                if [[ $appversion != $appNewVersion ]]; then   
            	    echo "$name Needs to be updated"   
        			appsdisplay+=$(echo "$name,")
        			## Installomator variable ##
        			install_apps+=$(echo "zoom ")
        	    else
        	        echo "$name is on the latest version $appNewVersion"
        	    fi
    	versionKey="CFBundleShortVersionString"
        else
        echo "--No $name--"
    fi
}

#Policy_App_List(){
        ##### Adobe DC #####
    # if [ -d '/Applications/Adobe Acrobat DC/Adobe Acrobat.app' ]; then
    #     echo "--Adobe Acrobat DC Exists--"
    #     appsdisplay+=$(echo "$appsdisplay
    #     Adobe Acrobat DC")
    #     #$AdobeRUM --action=instal --productVersions=APRO 
    #     ## Installomator variable ##
    #     CMD_Run_apps=$(echo "$CMD_Run_apps
    #     $AdobeRUM --action=instal --productVersions=APRO")
    # else
    #     echo "--No Adobe Acrobat DC--"
    # fi
    #         ##### Carbon Black #####
    # if [ -d! '/Applications/Adobe Acrobat DC/Adobe Acrobat.app' ]; then
    #     echo "--Adobe Acrobat DC Exists--"
    #     #appsdisplay+=$(echo "$appsdisplay
    #     #Adobe Acrobat DC")
    #     #$AdobeRUM --action=instal --productVersions=APRO 
    #     ## Installomator variable ##
    #     CMD_Run_apps=$(echo "$CMD_Run_apps
    #     $JAMF_BIN --action=instal --productVersions=APRO")
    # else
    #     echo "--No Adobe Acrobat DC--"
    # fi


#}

PromptUser() {
    "$DialogBinary" \
        --title "Monthly Update Required" \
        --message "The following installed apps need updates:\n\n$DialogDisplayApps\n\nTo update, close all listed apps and press Update. Otherwise, click Defer to choose another time." \
        --icon "$SELF_SERVICE_ICON" \
        --button1text "Update" \
        --button2text "Defer" \
        --ontop

    echo "$?"
}

Checking_Tools() {
    ## Check if Installomator exist
    if [ -f "$InstallomatorApp" ]; then
    echo "*************************
    Installomator found continue
    *****************************"
    else 
    echo "Installomator not found will install from Jamf"
    $JAMF_BINARY policy -event Installomator
    echo "Checking if Installomator is installed correctly"
        if [ -f "$InstallomatorApp" ]; then
            echo "*************************
            Installomator found continue
            *****************************"
        else 
            echo "ERROR: Installomator is not installed"
            exit 1
        fi
    fi
        ## Check if swiftDialog exists
    if [ -f "$DialogBinary" ]; then
    echo "*************************
    swiftDialog installed
    *****************************"
    else 
    echo "swiftDialog not found will install from Jamf"
    $JAMF_BINARY policy -event swiftDialog
    echo "Checking if swiftDialog is installed correctly"
        if [ -f "$DialogBinary" ]; then
            echo "*************************
            swiftDialog found continue
            *****************************"
        else 
            echo "ERROR: swiftDialog is not installed"
            exit 1
        fi
    fi
        ## Verify Working directory exists
    if ! [ -d "${WorkingDir}" ]; then
        echo "Monthly Update directory doesn't exist yet. Creating Resources directory..."
        mkdir -p "${WorkingDir}"
    fi
    ## Verify Resources directory exists
    if ! [ -d "${WorkingDir}/resources" ]; then
        echo "JAMF Resources directory doesn't exist yet. Creating Resources directory..."
        mkdir -p "${WorkingDir}/resources"
    fi
    ## Verify Logs directory exists
    if ! [ -d "${WorkingDir}/logs" ]; then
        echo "JAMF Logs directory doesn't exist yet. Creating Logs directory..."
        mkdir -p "${WorkingDir}/logs"
    fi
}

Deferral_Logic() {
    ## Get User input on time ##
    timechoose=$("$DialogBinary" \
        --title "Choose A Time" \
        --message "Choose when you would like to be prompted again:" \
        --icon "$SELF_SERVICE_ICON" \
        --selecttitle "Remind me in" \
        --selectvalues "30 Minutes,1 Hour,4 Hours,1 Day" \
        --button1text "OK" \
        --button2text "Cancel" \
        --ontop)
    selectedTime=$(echo "$timechoose" | awk -F ' : ' '/SelectedOption/{print $2; exit}')
    ## Time choice will give the correct time
    if [ "$selectedTime" = "30 Minutes" ]; then
    echo "Client chose 30 Mins"
    ## convert to secs
    time="1800"
    echo "time will be $time secs"
    elif [ "$selectedTime" = "1 Hour" ]; then
    echo "Client chose 1 hour"
    ## convert to secs
    time="3600"
    echo "time will be $time secs"
    elif [ "$selectedTime" = "4 Hours" ]; then
    echo "Client chose 4 hour"
    ## convert to secs
    time="14400"
    echo "time will be $time secs"
    elif [ "$selectedTime" = "1 Day" ]; then
    echo "Client chose 1 Day"
    ## convert to secs
    time="86400"
    echo "time will be $time secs"
    else
    echo "error Client either exited or closed will put default 30 mins"
     time="1800"
    echo "time will be $time secs"
    fi

    ## Creating Launch Daemon PLIST ##
    /bin/cat > $Deferral_PLIST <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.exampleorg.monthlyupdatedeferral</string>
        <key>ProgramArguments</key>
        <array>
            <string>$JAMF_BINARY</string>
            <string>policy</string>
            <string>-event</string>
            <string>$Deferral_Policy</string>
        </array>
        <key>StandardErrorPath</key>
        <string>/var/log/MonthlyUpdate_Defer_err.log</string>
        <key>StandardOutPath</key>
        <string>/var/log/MonthlyUpdate_Defer.log</string>
        <key>StartInterval</key>
        <integer>$time</integer>
    </dict>
    </plist>
EOF
    ## load plist
    /bin/launchctl bootstrap system $Deferral_PLIST


}

############################################
# Logic
############################################
## Checking if all the Tools are in place to start
Checking_Tools

Install_App_List

    DialogDisplayApps=$(
    for displayapps in $(echo $appsdisplay)
    do
    echo "$displayapps"
    done
    )
 list=$(for apps in $(echo $DialogDisplayApps)
    do
    echo "$apps"
    done | wc -l | sed -e 's/^[ \t]*//')
    echo "this has $list"
        if [ ${list} = '0' ]; then
        echo "No Updates needed will exit"
        exit 0
        else 
        echo "Found $list Updates needed will continue \n ***********************************************"
        fi
    percentage=$((100 / $list))
    percentageAdding="0"


IFS=' '
    echo "
    The Following will run in installomator:
    "
    
    for Installomator in $(echo $install_apps)
    do
    echo "$Installomator"
    done

## Prompt User ##

## if 0 update if 2 they canceled


Choice=$(PromptUser)

if [ $Choice = "0" ]; then
    echo "User wants to update"
    DialogCommandFile="/private/tmp/monthly_update_dialog.log"
    rm -f "$DialogCommandFile"
    touch "$DialogCommandFile"
    ## Initial indeterminate to start installation
    "$DialogBinary" --title "Installing Please Wait" --message "The following apps are updating:\n\n$DialogDisplayApps" --icon "$SELF_SERVICE_ICON" --progress --commandfile "$DialogCommandFile" --button1text "Done" --ontop &
    DialogPID=$!
    echo "$DialogPID"
        for Installomator in $(echo $install_apps)
            do
            echo "***Installing: $Installomator***"
            echo "progress: $percentageAdding" >> "$DialogCommandFile"
            echo "progresstext: ${Installomator} installing - ${percentageAdding}% complete" >> "$DialogCommandFile"
            ## Using Echo for Testing ##
            #echo "$InstallomatorApp $Installomator"
            #sleep 5
            Installomator=$(echo $Installomator | sed 's/ //g')
            $InstallomatorApp $Installomator BLOCKING_PROCESS_ACTION=prompt_user_then_kill LOGO="$LOGO"
            percentageAdding=$(($percentage + $percentageAdding))
            echo "Finished installing"
            echo "progress: $percentageAdding" >> "$DialogCommandFile"
            echo "progresstext: ${Installomator} finished - ${percentageAdding}% complete" >> "$DialogCommandFile"
            sleep 3
        done
        echo "progress: 100" >> "$DialogCommandFile"
        echo "progresstext: Done - 100% complete" >> "$DialogCommandFile"
        echo "quit:" >> "$DialogCommandFile"
        wait "$DialogPID"
        rm -f "$DialogCommandFile"
        if [[ -e "$countFile" ]]; then
			rm "$countFile"
		fi
        ## Writing Plist to remove Defer ##
        /usr/bin/defaults write "${WorkingDir}/com.exampleorg.deferMonthlyupdates" deferMonthlyupdates -bool false;
		sendToLog "Performing a JAMF Inventory Update and exiting..."
        ## Remove Plist if exist ##
        if [ -f $Deferral_PLIST ]; then
            echo "Defer Plist exist will unload and remove it"
            /bin/launchctl bootout system $Deferral_PLIST
            /bin/rm -rf $Deferral_PLIST
            
        fi
        $JAMF_BINARY recon
elif [ $Choice = "2" ]; then
    echo "User hit cancel"
    #User either ugly closed the prompt, or choose to delay.
    Deferral_Logic
        $JAMF_BINARY recon
		exit 0
else
    echo "ERROR: Sending log to Jamf"

fi
exit 0
