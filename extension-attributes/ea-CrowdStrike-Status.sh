#!/bin/bash

# Path to falconctl
FALCONCTL="/Applications/Falcon.app/Contents/Resources/falconctl"

if [[ -x "$FALCONCTL" ]]; then
    STATUS_OUTPUT=$("$FALCONCTL" stats 2>/dev/null)

    # Check if sensor is running
    if echo "$STATUS_OUTPUT" | grep -q "Sensor operational: true"; then
        echo "<result>Running</result>"
    else
        echo "<result>Installed but Not Running</result>"
    fi
else
    echo "<result>Not Installed</result>"
fi