#!/bin/zsh
#
# Author: Gabriel Marcelino
# Public-facing cleanup: 2026-05-05
# Updated: 2026-05-06
# Portfolio note: changes the current console user's local account picture.

CURRENT_USER=$(/usr/bin/stat -f "%Su" /dev/console)
userPicture="/Applications/Self Service.app/Contents/Resources/AppIcon.icns"

# Check if the Picture exists
echo "Checking for:" $userPicture ". . ."
#
if [ -f "$userPicture" ]; then
# If exists then do this

	echo "found: $userPicture"
	echo "Changeing user icon to: $userPicture"
	sudo -u $CURRENT_USER dscl . delete /Users/$CURRENT_USER jpegphoto
	sudo -u $CURRENT_USER dscl . delete /Users/$CURRENT_USER Picture
	dscl . create /Users/$CURRENT_USER Picture "$userPicture"
else
# If does NOT exist then this this
	echo "
	Did NOT find: $userPicture"
fi
# print out the current use picture
echo " $CURRENT_USER Current user picture is:"
echo "$(dscl . -read /Users/$CURRENT_USER Picture | tail -1 | sed 's/^[ \t]*//')"
echo "$CURRENT_USER Picture Changed"
exit 0
