#!/bin/sh

###
#
#
#	Author: Zac Bolick
# 	Description: Downloads Big Sur via an update URL which subsiquently installs to applications
# 				 via post script in the package
#				 Checks for machine compatibility, available disk space, and power adapter.
#				 Progress bars created by CocoaDialog
#				 Silent install will be run after download and extraction
# 
# 				 ~~~ USER IS ONLY PROMPTED ONCE ~~~
##

### Set Global Variables ###
# Big Sur 11.4
finalURL="http://swcdn.apple.com/content/downloads/55/59/071-00696-A_4T69TQR1VO/9psvjmwyjlucyg708cqjeaiylrvb0xph94/InstallAssistant.pkg"
pathToInstall="/Applications/Install macOS Big Sur.app/Contents/Resources/startosinstall"
pathToDL="/private/tmp/InstallAssistant.pkg"
osName="Big Sur"
# path to your icon you I will curl it from a URL or you can supply a path if it's already stored on the computer
iconPath="/Library/Application Support/JAMF/Downloads/companyIcon.png"
# I will curl this into iconPath if I don't find something there
iconURL="MUST-BE-INNITIALIZED"

### Create functions ###
## CocoaDialog
## Check for CocoaDialog and install it if not found
## CocoaDialog Binary will be set as variable "CD" for use in the script.
checkCocoaDialog() {
	CD="/Library/Application Support/JAMF/Scripts/cocoaDialog.app/Contents/MacOS/cocoaDialog"
	local tries=1
	while [ ! -e "$CD" ]; do
		if [ "$tries" == 3 ]; then
			echo "Tried to install CocoaDialog 3 times without success. Exiting..."
			exit 1
		else
		    curl -L "https://download1490.mediafire.com/zoxg4y8wsbhg/luk9ef9eico8twh/cocoaDialog_3.pkg" -o "/private/tmp/cocoaDialog_3.pkg"
			installer -pkg "/private/tmp/cocoaDialog_3.pkg" -target /
			sleep 5
			(( tries++ ))
		fi
	done
}
## Check for the icon and install it if not found
checkIcon() {
	if [[ -e "$iconPath" ]]; then
		echo "Icon found moving on..."
		return
	fi

	local tries=1
	while [ ! -e "$iconPath" ]; do
		if [ "$tries" == 3 ]; then
			echo "Could not install icon..."
		else
			curl -L "$iconURL" -o "$iconPath"
			sleep 5
			(( tries++ ))
		fi
	done
}
# Error out and Exit
BAILOUT() {
	echo "ERROR: $1"
	exec 3>&-
	exit 1
}
# Display a custom error message using CocoaDialog
errorMessage() {
	REASON="$1"
	"$CD" msgbox  --title "Install Error" --text "Error" --informative-text "$REASON" --icon-file "$iconPath" --button1 "Close" --timeout 30
}
# Download the file
downloadFile() {
	echo "Starting Download..." 2>&1
	# Download the specified file from the URL
	tries=2
	curl -L "$finalURL" -s -o "$pathToDL" 2>&1
	while [[ "$?" -ne 0 ]]; do
		sleep 2
		if [ "$(cat /tmp/progstat)" = "stopped" ]; then
			exit 1
		fi
		echo "Download Failed, retrying.  This is attempt $tries" 2>&1
		(( tries++ ))
		if [ "$tries" == 11 ]; then
			echo "Download has failed 10 times, exiting" 2>&1
			echo "stopped" > /tmp/progstat
			errorMessage "Download of Big Sur Failed. Please try again or contact Administrator."
			exit 1
		fi
		curl -L "$dlURL" -s -o "$pathToDL" 2>&1
	done
}
# Get the file size of the file being downloaded
getDownloadSize() {
	curl -sI "$finalURL" | grep -i Content-Length | awk '{print $2}' | tr -d '\r'
}
# Calculate download percent
dlPercent() {
	fSize=$(ls -nl "$pathToDL" | awk '{print $5}')
	percent=$(echo "scale=2;($fSize/$dlSize)*100" | bc)
	percent=${percent%.*}
}
# Check for a minumum amount of free space on the system. Min amount of GB as parameter
checkFreeSpace() {
	freeSpace=$(df -H | grep "/$" | awk '{print $4}')
	local minAmount=$1
	byteType=${freeSpace: -1}
	byteNum=${freeSpace%?}
	if [[ "$byteType" = "T" ]]; then
		echo "Free space check passed: $byteNum TB Available"
	elif [[ "$byteType" = "M" ]]; then
		errorMessage "Process can not continue there is only $byteNum megabytes of free space. Please free up at least 35 gigabytes of free space."
		BAILOUT "Not enough free space found. Only $byteNum megabytes available on boot drive."
	elif [[ "$byteType" = "G" ]]; then
		if [ $byteNum -gt $minAmount ]; then
			echo "Free space check passed: $byteNum GB Available"
		else
			errorMessage "Process can not continue. There is only $byteNum gigabytes of free space. Please free up at least 35 gigabytes to proceed."
			BAILOUT "Not enough free space. Only $byteNum gigabytes. Recommend 35 of free space."
		fi
	else
		echo "Checking for free space was not successful. Proceeding but if something goes wrong more disk space may be needed."
	fi
}

############## Start of Script ##############

# First some housekeeping
checkCocoaDialog
checkIcon
dlSize=$(getDownloadSize)
percent=0
tmpDir="/private/tmp/$osName"
if [ ! -d "$tmpDir" ]; then
	mkdir "$tmpDir"
fi

# Check if computer is running on AC Power
if [[ $(pmset -g ps | head -1) =~ "AC Power" ]]; then
  		acPower=1
fi
while [[ $acPower != 1 ]]; do
	powerDialog=$("$CD" msgbox --icon-file "$iconPath" --title "Warning" --text "Computer not plugged in." --informative-text "This computers does not appear to be plugged in. Please plug into AC power before continuing." --button1 "Continue" --button2 "Cancel" --timeout 120)
	if [[ $(pmset -g ps | head -1) =~ "AC Power" ]]; then
  		acPower=1
	fi
	if [ "$powerDialog" = 2 ]; then
		echo "AC Power not detected. User Canceled."
		exit 1
	fi
done

## Check for Compatibility
modID=$(/usr/sbin/sysctl -n hw.model)
modName=$(echo "$modID" | sed 's/[^a-zA-Z]//g')
modVer=$(echo "$modID" | sed 's/[^0-9,]//g' | awk -F, '{print $1}')
if [ "$modName" = "iMac" ] && [ "$modVer" -ge 13 ]; then
	osCompat=true
elif [ "$modName" = "iMacPro" ] && [ "$modVer" -ge 17 ]; then
	osCompat=true
elif [ "$modName" = "MacPro" ] && [ "$modVer" -ge 13 ]; then
	osCompat=true
elif [ "$modName" = "MacMini" ] && [ "$modVer" -ge 14 ]; then
	osCompat=true
elif [ "$modName" = "MacBookPro" ] && [ "$modVer" -ge 13 ]; then
	osCompat=true
elif [ "$modName" = "MacBookAir" ] && [ "$modVer" -ge 13 ]; then
	osCompat=true
elif [ "$modName" = "MacBook" ] && [ "$modVer" -ge 15 ]; then
	osCompat=true
elif [ "$modName" = "VMware" ]; then
	osCompat=true
else
	osCompat=false
fi
if [ "$osCompat" = true ]; then
	echo "System is $osName compatible..."
elif [ "$osCompat" = false ]; then
	echo "System is not compatible with $osName. Exiting..."
	compatDialog=$("$CD" msgbox --icon-file "$iconPath" --title "ERROR" --text "System not Compatible" --informative-text "This system is not compatible with $osName. Please contact Administrator" --button1 "Close" --timeout 120)
	exit 1
fi

# Cleanup stuff
rm -f /tmp/hpipe
mkfifo /tmp/hpipe
progstat="/private/tmp/progstat"
if [ -f "$progstat" ]; then
	rm -f "$progstat"
fi

# Check if installer has already been downloaded
downloaded="no"
if [ -f "$pathToDL" ]; then
	dlPercent
	if [ "$percent" = 100 ]; then
		downloaded="yes"
	elif [ "$percent" != 100 ]; then
		rm -f "$pathToDL"
	fi
fi

# Check if macOS Installer is already available
installed="no"
if [ -e "$pathToInstall" ]; then
	echo "Installer already available..."
	installed="yes"
fi

# Keep machine awake, as if user is active. 
/usr/bin/caffeinate -disu &

# Download macOS if Needed
if [ "$downloaded" = "no" ] && [ "$installed" = "no" ]; then
	checkFreeSpace 35
	downloadDialog=$("$CD" msgbox --icon-file "$iconPath" --title "Download Needed" --text "$osName has not been pre-downloaded." --informative-text "The installer has not been pre-loaded on this system. Downloading may add an additional hour or longer, depending on your internet speed." --button1 "Continue" --button2 "Cancel" --timeout 120)
	if [[ $downloadDialog != 1 ]]; then
		echo "User canceled due to download needed. Exiting..."
		exit 0
	fi
	# Create Progress Bar
	echo "Creating Progress Bar..."
	progress=$("$CD" progressbar --icon-file "$iconPath" --stoppable --percent 0 --title "Downloading..." --text "Downloading macOS $osName" 2>&1 > "$progstat" < /tmp/hpipe) &
	exec 3<> /tmp/hpipe
	echo -n . >&3

	# Track Progress
	while [[ $percent != 100 ]]; do
	if [ "$(cat $progstat)" = "stopped" ]; then
		echo "User canceled download."
		cpros=$(pgrep curl)
		if [ ! -z "$cpros" ]; then
			echo "Stopping download with PID $cpros"
			kill $cpros
		fi
		exit 1
	fi
	if [ -f "$pathToDL" ]; then
		dlPercent
		echo "$percent\n" >&3
	fi
	done &

	downloadFile
	exec 3>&-
fi


if [ "$installed" = "no" ]; then
	echo "Putting macOS Installer in place..."
	rm -f /tmp/hpipe
	mkfifo /tmp/hpipe
	progress=$("$CD" progressbar --icon-file "$iconPath" --indeterminate --title "Preparing..." --text "Preparing to install macOS $osName" < /tmp/hpipe) &
	exec 3<> /tmp/hpipe
	echo -n . >&3
		
	installer -pkg ./InstallAssistant.pkg -target /

	sleep 5
	rm "$pathToDL"
	exec 3>&-
fi

# Install macOS
echo "Ready to install..."
checkFreeSpace 35
rm -f /tmp/hpipe
mkfifo /tmp/hpipe
progress=$("$CD" progressbar --icon-file "$iconPath" --indeterminate --title "Installing..." --text "Installation is starting. This may take up to 30 minutes..." --informative-text "Your computer will reboot to continue installation." < /tmp/hpipe) &
exec 3<> /tmp/hpipe
echo -n . >&3

# This line actually does the installing
"$pathToInstall" --agreetolicense --nointeraction --rebootdelay 10

selfService=$(pgrep "Self Service")


if [ ! -z "$selfService" ]; then
	kill "$selfService"
fi
