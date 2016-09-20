#!/bin/bash

###
#
#            Name:  reissue_filevault_recovery_key.sh
#     Description:  This script is intended to run on Macs which no longer have
#                   a valid recovery key in the JSS. It prompts users to enter
#                   their Mac password, and uses this password to generate a
#                   new FileVault key and escrow with the JSS. The "redirect
#                   FileVault keys to JSS" configuration profile must already
#                   be deployed in order for this script to work correctly.
#          Author:  Elliot Jordan <elliot@lindegroup.com>
#         Created:  2015-01-05
#   Last Modified:  2016-09-13
#         Version:  1.6
#
###


################################## VARIABLES ##################################

# Your company's logo, in PNG format. (For use in jamfHelper messages.)
# Use standard UNIX path format:  /path/to/file.png
LOGO_PNG="/Library/Application Support/PretendCo/logo@512px.png"

# Your company's logo, in ICNS format. (For use in AppleScript messages.)
# Use standard UNIX path format:  /path/to/file.icns
LOGO_ICNS="/private/tmp/PretendCo.icns"

# The title of the message that will be displayed to the user.
# Not too long, or it'll get clipped.
PROMPT_TITLE="FileVault key repair"

# The body of the message that will be displayed before prompting the user for
# their password. All message strings below can be multiple lines.
PROMPT_MESSAGE="Your Mac's FileVault encryption key needs to be regenerated in order for PretendCo IT to be able to recover data from your hard drive in case of emergency.

Click the Next button below, then enter your Mac's password when prompted."

# The body of the message that will be displayed after 5 incorrect passwords.
FORGOT_PW_MESSAGE="You made five incorrect password attempts.

Please contact the Help Desk at 555-1212 for help with your Mac password."

# The body of the message that will be displayed after successful completion.
SUCCESS_MESSAGE="Thank you! Your FileVault key has been regenerated."


###############################################################################
######################### DO NOT EDIT BELOW THIS LINE #########################
###############################################################################


######################## VALIDATION AND ERROR CHECKING ########################

# Suppress errors for the duration of this script. (This prevents Casper from
# marking a policy as "failed" if the words "fail" or "error" inadvertently
# appear in the script output.)
exec 2>/dev/null

BAIL=false

# Make sure the custom logo has been received successfully
if [[ ! -f "$LOGO_ICNS" ]]; then
    echo "[ERROR] Custom icon not present: $LOGO_ICNS"
    BAIL=true
fi
# Convert POSIX path of logo icon to Mac path for AppleScript
LOGO_ICNS="$(osascript -e 'tell application "System Events" to return POSIX file "'"$LOGO_ICNS"'" as text')"

# Bail out if jamfHelper doesn't exist.
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
if [[ ! -x "$jamfHelper" ]]; then
    echo "[ERROR] jamfHelper not found."
    BAIL=true
fi

# Most of the code below is based on the JAMF reissueKey.sh script:
# https://github.com/JAMFSupport/FileVault2_Scripts/blob/master/reissueKey.sh

# Check the OS version.
OS_MAJOR=$(sw_vers -productVersion | awk -F . '{print $1}')
OS_MINOR=$(sw_vers -productVersion | awk -F . '{print $2}')
if [[ "$OS_MAJOR" -ne 10 || "$OS_MINOR" -lt 9 ]]; then
    echo "[ERROR] OS version not 10.9+ or OS version unrecognized."
    sw_vers -productVersion
    BAIL=true
fi

# Check to see if the encryption process is complete
FV_STATUS="$(fdesetup status)"
if grep -q "Encryption in progress" <<< "$FV_STATUS"; then
    echo "[ERROR] The encryption process is still in progress."
    echo "$FV_STATUS"
    BAIL=true
elif grep -q "FileVault is Off" <<< "$FV_STATUS"; then
    echo "[ERROR] Encryption is not active."
    echo "$FV_STATUS"
    BAIL=true
elif ! grep -q "FileVault is On" <<< "$FV_STATUS"; then
    echo "[ERROR] Unable to determine encryption status."
    echo "$FV_STATUS"
    BAIL=true
fi

# Get the logged in user's name
CURRENT_USER="$(stat -f%Su /dev/console)"

# This first user check sees if the logged in account is already authorized with FileVault 2
FV_USERS="$(fdesetup list)"
if ! egrep -q "^${CURRENT_USER}," <<< "$FV_USERS"; then
    echo "[ERROR] $CURRENT_USER is not on the list of FileVault enabled users:"
    echo "$FV_USERS"
    BAIL=true
fi

# If any error occurred above, bail out.
if [[ "$BAIL" == "true" ]]; then
    exit 1
fi

################################ MAIN PROCESS #################################

# Get information necessary to display messages in the current user's context.
USER_ID=$(id -u "$CURRENT_USER")
if [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -le 9 ]]; then
    L_ID=$(pgrep -x -u "$USER_ID" loginwindow)
    L_METHOD="bsexec"
elif [[ "$OS_MAJOR" -eq 10 && "$OS_MINOR" -gt 9 ]]; then
    L_ID=USER_ID
    L_METHOD="asuser"
fi

# Display a branded prompt explaining the password prompt.
echo "Alerting user $CURRENT_USER about incoming password prompt..."
launchctl "$L_METHOD" "$L_ID" "$jamfHelper" -windowType "utility" -icon "$LOGO_PNG" -title "$PROMPT_TITLE" -description "$PROMPT_MESSAGE" -button1 "Next" -defaultButton 1 -startlaunchd &>/dev/null

# Get the logged in user's password via a prompt.
echo "Prompting $CURRENT_USER for their Mac password..."
USER_PASS="$(launchctl "$L_METHOD" "$L_ID" osascript -e 'display dialog "Please enter the password you use to log in to your Mac:" default answer "" with title "'"${PROMPT_TITLE//\"/\\\"}"'" giving up after 86400 with text buttons {"OK"} default button 1 with hidden answer with icon file "'"${LOGO_ICNS//\"/\\\"}"'"' -e 'return text returned of result')"

# Thanks to James Barclay (@futureimperfect) for this password validation loop.
TRY=1
until dscl /Search -authonly "$CURRENT_USER" "$USER_PASS" &>/dev/null; do
    (( TRY++ ))
    echo "Prompting $CURRENT_USER for their Mac password (attempt $TRY)..."
    USER_PASS="$(launchctl "$L_METHOD" "$L_ID" osascript -e 'display dialog "Sorry, that password was incorrect. Please try again:" default answer "" with title "'"${PROMPT_TITLE//\"/\\\"}"'" giving up after 86400 with text buttons {"OK"} default button 1 with hidden answer with icon file "'"${LOGO_ICNS//\"/\\\"}"'"' -e 'return text returned of result')"
    if (( TRY >= 5 )); then
        echo "[ERROR] Password prompt unsuccessful after 5 attempts. Displaying \"forgot password\" message..."
        launchctl "$L_METHOD" "$L_ID" "$jamfHelper" -windowType "utility" -icon "$LOGO_PNG" -title "$PROMPT_TITLE" -description "$FORGOT_PW_MESSAGE" -button1 'OK' -defaultButton 1 -timeout 30 -startlaunchd &>/dev/null &
        exit 1
    fi
done
echo "Successfully prompted for Mac password."

# If needed, unload FDERecoveryAgent and remember to reload later.
FDERA=false
if launchctl list | grep -q "com.apple.security.FDERecoveryAgent"; then
    FDERA=true
    echo "Unloading FDERecoveryAgent..."
    launchctl unload /System/Library/LaunchDaemons/com.apple.security.FDERecoveryAgent.plist
fi

# Translate XML reserved characters to XML friendly representations.
# Thanks @AggroBoy! - https://gist.github.com/AggroBoy/1242257
USER_PASS_XML=$(echo "$USER_PASS" | sed -e 's~&~\&amp;~g' -e 's~<~\&lt;~g' -e 's~>~\&gt;~g' -e 's~\"~\&quot;~g' -e "s~\'~\&apos;~g" )

echo "Issuing new recovery key..."
FDESETUP_OUTPUT="$(fdesetup changerecovery -norecoverykey -verbose -personal -inputplist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Username</key>
    <string>$CURRENT_USER</string>
    <key>Password</key>
    <string>$USER_PASS_XML</string>
</dict>
</plist>
EOF
)"

# Test success conditions.
FDESETUP_RESULT=$?
grep -q "Escrowing recovery key..." <<< "$FDESETUP_OUTPUT"
ESCROW_STATUS=$?
if [[ $FDESETUP_RESULT -ne 0 ]]; then
    echo "[WARNING] fdesetup exited with return code: $FDESETUP_RESULT."
    echo "$FDESETUP_OUTPUT"
elif [[ $ESCROW_STATUS -ne 0 ]]; then
    echo "[WARNING] FileVault key was generated, but escrow did not occur."
    echo "$FDESETUP_OUTPUT"
else
    echo "Displaying \"success\" message..."
    launchctl "$L_METHOD" "$L_ID" "$jamfHelper" -windowType "utility" -icon "$LOGO_PNG" -title "$PROMPT_TITLE" -description "$SUCCESS_MESSAGE" -button1 'OK' -defaultButton 1 -timeout 30 -startlaunchd &>/dev/null &
fi

# Reload FDERecoveryAgent, if it was unloaded earlier.
if [[ "$FDERA" == "true" ]]; then
    # Only if it wasn't automatically reloaded by `fdesetup`.
    if ! launchctl list | grep -q "com.apple.security.FDERecoveryAgent"; then
        echo "Loading FDERecoveryAgent..."
        launchctl load /System/Library/LaunchDaemons/com.apple.security.FDERecoveryAgent.plist
    fi
fi

exit $FDESETUP_RESULT
