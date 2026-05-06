#!/bin/zsh
#
# Author: Gabriel Marcelino
# Public-facing cleanup: 2026-05-05
# Updated: 2026-05-06
# Portfolio note: renames a managed macOS device from a configurable prefix
# and the hardware serial number.

serialNumber=`system_profiler SPHardwareDataType | awk '/Serial/ {print $4}'`

preFix=M-
computerName=${preFix}$serialNumber

# sets the hostname as variable computerName
scutil --set HostName $computerName
sleep 1
scutil --set LocalHostName $computerName
sleep 1
scutil --set ComputerName $computerName
sleep 1
HN=`scutil --get HostName`
LHN=`scutil --get LocalHostName`
CN=`scutil --get ComputerName`
defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName "$computerName"
 echo -e "
    ###################################
                 Results
    ###################################
     HostName: $HN
     LocalHostName: $LHN
     ComputerName: $CN
    ###################################
    "
jamf recon

exit 0
