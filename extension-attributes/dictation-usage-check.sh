#!/bin/sh
#
# Author: Gabriel Marcelino
# Public-facing cleanup: 2026-05-05
# Updated: 2026-05-06
# Portfolio note: Jamf extension-attribute style check for Dictation usage.

currentUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }')

plistToCheck="/Users/$currentUser/Library/Preferences/com.apple.speech.recognition.AppleSpeechRecognition.prefs.plist"
timesUsed=$(/usr/bin/defaults read "$plistToCheck" DictationIMMessageTracesSinceLastReport)
Checking=$(echo "$?")
if [ "$Checking" = 0 ]; then 
	timesUsed=$(/usr/libexec/PlistBuddy -c "print :DictationIMMessageTracesSinceLastReport" /Users/"$currentUser"/Library/Preferences/com.apple.speech.recognition.AppleSpeechRecognition.prefs.plist)
	result="Yes: $timesUsed"
else
	result="No"
fi

echo $result
