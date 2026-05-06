#!/bin/sh
#
# Author: Gabriel Marcelino
# Public-facing cleanup: 2026-05-05
# Updated: 2026-05-06
# Portfolio note: generalized installer workflow for downloading and installing
# .zip, .pkg, and .dmg payloads on managed macOS devices.

####################################################################################################
#
# DESCRIPTION
#
# Automatically download DMGs, PKGs, ZIPs from the Internet and install
#
####################################################################################################

####################################################################################################
# Beginning of Variables section
# 
# $4 ===> URL to download .zip, .pkg, or .dmg ONLY
# $5 ===> Exact name of the .app you are installing/upgrading, ie, you will use Google Chrome vs just chrome
# $6 ===> For .pkg installations ONLY. URL to download .plist file
# $7 ===> For .pkg installations ONLY. Exact name of the .plist
#
####################################################################################################

# Sets variable for a unique temporary directory to extract DMGs
temp="/Users/Shared/temp"

# Set $downloadURL to $4
downloadURL="$4"

# OPTIONAL: .app to close during installation
theApp="$5"

# OPTIONAL: URL to config files needed for .pkg installations
configURL="$6"

# MANDATORY: If $6 is not null
configName="$7"

# 

if [ -z "$8" ]; then
    forcequit="no"
else
    forcequit="$8"
fi

# OPTIONAL: 

####################################################################################################
# End of Variables section
####################################################################################################

####################################################################################################
# Beginning of Functions section
####################################################################################################
function pkgInstall {
    pkgtoinstall=$( find "$temp" -name '*.pkg' )
    echo "Found: $pkgtoinstall"
    echo "********************************************************"
    echo "* Installing ${pkgtoinstall}"
    echo "********************************************************"
    installer -allowUntrusted -verboseR -pkg "$pkgtoinstall" -target /
    sleep 10
    # Delete temporary directory 
    rm -rf "$temp"
}

function dmgMount {
    if [[ -d "${temp}/mount" ]]; then
        #unmount/remove $temp/mount
        echo "********************************************************"
        echo "${temp}/mount is still exists!"
        echo "********************************************************"
        isDetached=`hdiutil detach "${temp}/mount" -verbose`
        echo "********************************************************"
        echo "$isDetached"
        echo "********************************************************"
        rm -rf "${temp}/mount"
    fi

    #Create temporary directory
    mkdir -p "${temp}/mount"
    
    dmgtoinstall=$( find $temp -name '*.dmg' )
    echo "Found: $dmgtoinstall"
    echo "********************************************************"
    echo "* Extracting ${dmgtoinstall} to ${temp}/mount"
    echo "********************************************************"
    
    # Auto-accept any licensing pop-ups that mounting the DMG might make
    yes | hdiutil attach -noverify -nobrowse -mountpoint ${temp}/mount "$dmgtoinstall"
}

function dmgDetach {
    #unmount/remove $temp/mount
    echo "Detaching ${temp}/mount"
    isDetached=`hdiutil detach "${temp}/mount" -verbose`
    echo "********************************************************"
    echo "Attempting to eject the .dmg"
    echo "$isDetached"
    echo "********************************************************"
    if [[ "$isDetached" != *"ejected."* ]]; then
        echo "********************************************************"
        echo "${temp}/mount was not able to eject!"
        echo "********************************************************"
    else
        echo "********************************************************"
        echo "${temp}/mount ejected successfully!"
        echo "********************************************************"
        # Delete temporary directory
        echo "********************************************************"
        echo "Removing $temp"
        echo "********************************************************"
        rm -rf "$temp"
    fi
}

function appInstall {
    apptoinstall=$( find $temp -name '*.app' -maxdepth 2 )
    echo "Found: $apptoinstall"
    # Creating an array if more than one .app in the .zip or .dmg
    #read -a nameArray <<<"$apptoinstall"
    # There may be .app files inside of the first .app. creating array to select only the top level .app
    #apptoinstall=`echo ${nameArray[0]}`
    echo ".app to copy: $apptoinstall"

    if [[ "$downloadURL" == *".zip" ]]; then
        appName=$( /bin/echo "$apptoinstall" | /usr/bin/awk -F/ '{print $5}' )
    else
        appName=$( /bin/echo "$apptoinstall" | /usr/bin/awk -F/ '{print $6}' )
    fi
    echo "\$appName: $appName"
    if ! [[ -z "$appName" ]]; then
        if [[ -d "/Applications/${appName}" ]]; then
            echo "********************************************************"
            echo "$appName already exists in /Applications"
            echo "Removing $appName from /Applications"
            echo "********************************************************"
            rm -rf "/Applications/${appName}"
        fi
        echo "********************************************************"
        echo "* Copying ${apptoinstall} to /Applications"
        echo "********************************************************"
        #Copies contents of disk image to /Applications
        yes | cp -R "$apptoinstall" /Applications
        sleep 10
        # Delete temporary directory
        if [[ "$downloadURL" == *".pkg" ]] || [[ "$downloadURL" == *".zip" ]] ; then
            rm -rf "$temp"
        fi
        
    else
        echo "\$appName is null. No action taken!"
    fi
    
}

function handleZip {
    echo "********************************************************"
    echo "* Unzipping zip file"
    echo "********************************************************"
    # Unzip
    unzip "${temp}/1.zip" -d "${temp}/"
    # Removing __MACOSX directory
    if [[ -d "${temp}/__MACOSX" ]]; then
        rm -rf "${temp}/__MACOSX"
    fi
    sleep 10
}

function closeApp {
    echo "Closing $theApp"
    if [ "$forcequit" = "Yes" ]; then
        killall "$theApp" 
    else
        osascript <<EOT
        quit application "$theApp"
EOT
    fi
}

function openApp {
    echo "Opening $theApp"
    sleep 10
    osascript <<EOT
    tell application "$theApp"
    activate
    end tell
EOT
}

####################################################################################################
# End of Functions section
####################################################################################################

####################################################################################################
# Begin work
####################################################################################################

#Create temporary directory
sudo mkdir -p "$temp"

#Scans $downloadURL for file extension
if [[ "$downloadURL" == *".zip" ]]; then
    echo "********************************************************"
    echo "* Downloading zip file"
    echo "********************************************************"
    echo ""
    #Download $downloadURL, moves it to $temp and name it 1.zip
    curl -L "$downloadURL" -o "${temp}/1.zip"
    handleZip
    # Check what type of file is in the .zip
    echo "Checking what type of file is in the .zip..."
    echo ""
    whatsInTheBox=$( ls "${temp}" )
    if [[ "$whatsInTheBox" == *".app"* ]]; then
        echo "********************************************************"
        echo "* Checking what type of file is in the .zip..."
        echo "********************************************************"
        echo ""
        echo "There is a .app in the .zip"
        if [ -z "$5" ]; then
            echo "No app was specified for installation. Will not attempt to close and open $theApp for installation process..."
            appInstall
        else    
            # set $processname to lowercase of $theApp
            processname=`echo "$theApp" | tr '[:upper:]' '[:lower:]'`

            if pgrep "$theApp" || pgrep "${processname}" ; then
                echo "$theApp was specified for installation. Will attempt to close and open $theApp for installation process..."
                # Attempt to close the .app specified in $5
                closeApp
                appInstall
                openApp
            else
                appInstall
            fi
        fi
    elif [[ "$whatsInTheBox" == *".pkg"* ]]; then
        echo "There is a .pkg in the .zip"
        if [ -z "$5" ]; then
            echo "No app was specified for installation. Will not attempt to close and open $theApp for installation process..."
            if [ -z "$6" ]; then
                echo "No URL was specified for a config file. The pkg installation will not use a config file."
            else
                if [ -z "$7" ]; then
                    echo "No name was specified for a config file. no config file will be used with the pkg installation"
                else
                    echo "A config file was specified. Downloading config file and saving to ${temp}/${configName}"
                    curl -L "$configURL" -o "${temp}/${configName}"
                fi
            fi
            pkgInstall
        else
            processname=`echo "$theApp" | tr '[:upper:]' '[:lower:]'`

            if pgrep "$theApp" || pgrep "${processname}" ; then
                echo "$theApp was specified for installation. Will attempt to close and open $theApp for installation process..."
                # Attempt to close the .app specified in $5
                closeApp
                if [ -z "$6" ]; then
                    echo "No URL was specified for a config file. The pkg installation will not use a config file."
                else
                    if [ -z "$7" ]; then
                        echo "No name was specified for a config file. no config file will be used with the pkg installation"
                    else
                        echo "A config file was specified. Downloading config file and saving to ${temp}/${configName}"
                        curl -L "$configURL" -o "${temp}/${configName}"
                    fi
                fi
                pkgInstall
                openApp
            else
                if [ -z "$6" ]; then
                    echo "No URL was specified for a config file. The pkg installation will not use a config file."
                else
                    if [ -z "$7" ]; then
                        echo "No name was specified for a config file. no config file will be used with the pkg installation"
                    else
                        echo "A config file was specified. Downloading config file and saving to ${temp}/${configName}"
                        curl -L "$configURL" -o "${temp}/${configName}"
                    fi
                fi
                pkgInstall
            fi
        fi
    #If .pkg isn't found, do this
    elif [[ "$whatsInTheBox" == *".dmg"* ]]; then
        echo "There is a .dmg in the .zip"
        dmgMount
        if [ -z "$5" ]; then
            echo "No app was specified for installation. Will not attempt to close and open $theApp for installation process..."
            appInstall
        else    
            # set $processname to lowercase of $theApp
            processname=`echo "$theApp" | tr '[:upper:]' '[:lower:]'`

            if pgrep "$theApp" || pgrep "${processname}" ; then
                echo "$theApp was specified for installation. Will attempt to close and open $theApp for installation process..."
                # Attempt to close the .app specified in $5
                closeApp
                appInstall
                openApp
            else
                appInstall
            fi
        fi
        dmgDetach
    else
        echo "Please check the contents of $temp. No .app, .pkg, or .dmg found in $temp"
    fi 
elif [[ "$downloadURL" == *".pkg" ]]; then
    echo "********************************************************"
    echo "* Downloading pkg file"
    echo "********************************************************"
    echo ""
    #Download $downloadURL, moves it to $temp and name it 1.pkg
    curl -L "$downloadURL" -o "${temp}/1.pkg"
    if [ -z "$5" ]; then
        echo "No app was specified for installation. Will not attempt to close and open $theApp for installation process..."
        if [ -z "$6" ]; then
            echo "No URL was specified for a config file. The pkg installation will not use a config file."
        else
            if [ -z "$7" ]; then
                echo "No name was specified for a config file. no config file will be used with the pkg installation"
            else
                echo "A config file was specified. Downloading config file and saving to ${temp}/${configName}"
                curl -L "$configURL" -o "${temp}/${configName}"
            fi
        fi
        pkgInstall
    else
        processname=`echo "$theApp" | tr '[:upper:]' '[:lower:]'`
        echo $processname
        if pgrep "$theApp" || pgrep "${processname}" ; then
            echo "$theApp was specified for installation. Will attempt to close and open $theApp for installation process..."
            # Attempt to close the .app specified in $5
            closeApp
            if [ -z "$6" ]; then
                echo "No URL was specified for a config file. The pkg installation will not use a config file."
            else
                if [ -z "$7" ]; then
                    echo "No name was specified for a config file. no config file will be used with the pkg installation"
                else
                    echo "A config file was specified. Downloading config file and saving to ${temp}/${configName}"
                    curl -L "$configURL" -o "${temp}/${configName}"
                fi
            fi
            pkgInstall
            openApp
        else
            if [ -z "$6" ]; then
                echo "No URL was specified for a config file. The pkg installation will not use a config file."
            else
                if [ -z "$7" ]; then
                    echo "No name was specified for a config file. no config file will be used with the pkg installation"
                else
                    echo "A config file was specified. Downloading config file and saving to ${temp}/${configName}"
                    curl -L "$configURL" -o "${temp}/${configName}"
                fi
            fi
            pkgInstall
        fi
    fi     
#If .pkg isn't found, do this
elif [[ "$downloadURL" == *".dmg" ]]; then
    echo "********************************************************"
    echo "* Downloading dmg file"
    echo "********************************************************"
    echo ""
    #Download $downloadURL, moves it to $temp and name it 1.dmg
    curl -L "$downloadURL" -o "${temp}/1.dmg"
    dmgMount
    whatsInTheBox=$( ls "${temp}/mount" )
    if [[ "$whatsInTheBox" == *".app"* ]]; then
        echo "********************************************************"
        echo "* Checking what type of file is in the .dmg..."
        echo "********************************************************"
        echo ""
        echo "There is a .app in the .dmg"
        if [ -z "$5" ]; then
            echo "No app was specified for installation. Will not attempt to close and open $theApp for installation process..."
            appInstall
        else    
            # set $processname to lowercase of $theApp
            processname=`echo "$theApp" | tr '[:upper:]' '[:lower:]'`

            if pgrep "$theApp" || pgrep "${processname}" ; then
                echo "$theApp was specified for installation. Will attempt to close and open $theApp for installation process..."
                # Attempt to close the .app specified in $5
                closeApp
                appInstall
                openApp
            else
                appInstall
            fi
        fi
    elif [[ "$whatsInTheBox" == *".pkg"* ]]; then
        echo "There is a .pkg in the .zip"
        if [ -z "$5" ]; then
            echo "No app was specified for installation. Will not attempt to close and open $theApp for installation process..."
            if [ -z "$6" ]; then
                echo "No URL was specified for a config file. The pkg installation will not use a config file."
            else
                if [ -z "$7" ]; then
                    echo "No name was specified for a config file. no config file will be used with the pkg installation"
                else
                    echo "A config file was specified. Downloading config file and saving to ${temp}/${configName}"
                    curl -L "$configURL" -o "${temp}/${configName}"
                fi
            fi
            pkgInstall
        else
            processname=`echo "$theApp" | tr '[:upper:]' '[:lower:]'`

            if pgrep "$theApp" || pgrep "${processname}" ; then
                echo "$theApp was specified for installation. Will attempt to close and open $theApp for installation process..."
                # Attempt to close the .app specified in $5
                closeApp
                if [ -z "$6" ]; then
                    echo "No URL was specified for a config file. The pkg installation will not use a config file."
                else
                    if [ -z "$7" ]; then
                        echo "No name was specified for a config file. no config file will be used with the pkg installation"
                    else
                        echo "A config file was specified. Downloading config file and saving to ${temp}/${configName}"
                        curl -L "$configURL" -o "${temp}/${configName}"
                    fi
                fi
                pkgInstall
                openApp
            else
                if [ -z "$6" ]; then
                    echo "No URL was specified for a config file. The pkg installation will not use a config file."
                else
                    if [ -z "$7" ]; then
                        echo "No name was specified for a config file. no config file will be used with the pkg installation"
                    else
                        echo "A config file was specified. Downloading config file and saving to ${temp}/${configName}"
                        curl -L "$configURL" -o "${temp}/${configName}"
                    fi
                fi
                pkgInstall
            fi
        fi
    fi
    dmgDetach
else
    echo "Unknown file. Please check URL and try again."
fi
