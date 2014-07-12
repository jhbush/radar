#!/bin/bash

##### HEADER BEGINS ######################################################################
#
# radar.sh
#     Robust multi-Area Distribution Active Routing
#
# Copyright (c) 2014, Joshua Schripsema
# All rights reserved.
#
# Licensed under the BSD-style license found in the LICENSE file in the same directory.
#
# Determines the closest distribution point and writes it back to the JSS for this
# computer. Hopefully, this will also be able to do the same for JAMF Distribution
# Servers (JDS) in the near future.
#
# https://jamfnation.jamfsoftware.com/featureRequest.html?id=2320
#
##### HEADER ENDS ########################################################################

# Set as 'true' to have the output written to system.log
WRITE_TO_SYSTEM_LOG='true'
# Define a tag for logging to system.log
LOGGING_TAG='com.company.radar'

# You can set the API user and password statically, pulling from a file, or by a parameter
# passed via the JSS. Security Note: This service account is able to modify computer
# object information and, if you store the user and password information locally, an
# administrative user will be able to read this information.
# 
# API Privileges Needed
# Casper 8.x API Privileges - Distribution Points (Read), Computers (Read/Update).
# Casper 9.x Privileges - (Note: All found in "JSS Objects")
#     File Share Distribution Points (Read), JDS (Read), Computers (Read/Update).

# Set the API user statically.
JSS_RADAR_API_USER=''

# Set the API user using parameter $4, first variable passed from Casper.
if [ -n "${4}" ]; then
	JSS_RADAR_API_USER="${4}"
fi

# Set the API password statically.
JSS_RADAR_API_PASS=''

# Pull the password information from a file. Best if location only readable by 'root'.
#JSS_RADAR_API_PASS="$(cat "/path/to/file/with/password/radar.api")"

# Set the API password using parameter $5, second variable passed from Casper.
if [ -n "${5}" ]; then
	JSS_RADAR_API_PASS="${5}"
fi

# Both an API username and password must be specified to use RADAR.
if [ -z "${JSS_RADAR_API_USER}" ]; then
	printf '%s\n' 'An API user must be specified in order to use RADAR.'
	exit 1
fi

if [ -z "${JSS_RADAR_API_PASS}" ]; then
	printf '%s\n' 'An API password must be specified in order to use RADAR.'
	exit 1
fi

# Blacklist the following distribution points and/or servers, by ID, never set by client
# machines. This can be useful if you have servers that only exist for backup or
# replication purposes, but client machines never use. Define as many of these as you
# need by uncommenting and duplicating the 'BLACKLIST_DIST_POINT/SERVER_ID+=('1')' lines.
BLACKLIST_DIST_POINT_ID=()
#BLACKLIST_DIST_POINT_ID+=('1')
#BLACKLIST_DIST_POINT_ID+=('2')
BLACKLIST_DIST_SERVER_ID=()
#BLACKLIST_DIST_SERVER_ID+=('1')
#BLACKLIST_DIST_SERVER_ID+=('2')

# Validate that the share port is reachable on your distribution point.
VALIDATE_SHARE_PORT='true'

# Define as 'true' if your JSS is available on the public internet for administration.
JSS_IS_PUBLIC='false'

# Defined as 'true' if you would like to make sure a policy ran recently. Really only
# necessary/desired if some network subnets have defined distribution points, and others
# don't, in order to verify that the IP address stored in the JSS is recent. Can also be
# used to throttle RADAR if running from a LaunchDaemon.
WAIT_FOR_JSS_POLICY='false'

# Define a test server/port for both public internet access and corporate intranet access.
INTERNET_URL="www.google.com"
INTERNET_PORT='80'
CORP_URL='internal.corp.server.com'
CORP_PORT='80'

# Set to 'true' to validate that the distribution point was set. Adds about 0.5s of
# processing time, may also generate unwanted logs if specific network segments are
# set in the JSS and you don't want RADAR to control them.
VALIDATE_SETTING='true'

function Main () {
	local returnCode='0'
	
	# Wait until the JSS is reachable.
	if [ "${JSS_IS_PUBLIC}" == 'true' ]; then
		wait_for_internet
	else
		wait_for_corp
	fi
	
	# Wait for a recent policy if WAIT_FOR_JSS_POLICY is true.
	if [ "${WAIT_FOR_JSS_POLICY}" == 'true' ]; then
		wait_for_policy
	fi
	
	# Get jss server information and validate that the server is reachable.
	jssServer="$(get_jss_server)"
	if [ "${?}" -ne '0' ]; then
		printf '%s.\n' 'Error communicating with JSS'
		return 1
	fi
	
	# The API has differences between the versions. Version check to determine method.
	case "$(/usr/sbin/jamf version | awk -F= '{ print $2 }')" in
		"8."*)
			ipAddressTag='ipAddress'
			jdsAvailable='false'
			computerSearch='macaddress'
			computerValue="$(networksetup -listallhardwareports | awk '/Thunderbolt/ || /USB/ || /Display/ || /Bluetooth/ {getline; getline} 1' | grep -A 1 'en[0-9]' | awk '/Ethernet Address/ { print $3; exit }' | tr ':' '.')"
			
			run_radar_distribution; returnCode="${?}"
			if [ "${returnCode}" -ne '0' ]; then
				printf '%s\n' 'Unknown error.'
				return "${returnCode}"
			fi
			;;
		"9."*)
			ipAddressTag='ip_address'
			jdsAvailable='false'
			computerSearch='serialnumber'
			computerValue="$(ioreg -c IOPlatformExpertDevice -d 2 | awk '/IOPlatformSerialNumber/ { print $NF }' | tr -d '"' | tr '[:lower:]' '[:upper:]')"
			
			run_radar_distribution; returnCode="${?}"
			if [ "${returnCode}" -ne '0' ]; then
				printf '%s\n' 'Unknown error.'
				return "${returnCode}"
			fi
			;;
#		Hopefully JAMF will eventually add in the ability to do this with the JDS via API.
#		The code to do this is already written, but will likely require some modifications
#		depending on how the information is formatted. Please do not just uncomment this
#		code without testing it thoroughly first.
#		https://jamfnation.jamfsoftware.com/featureRequest.html?id=2320
#
#		"9."[5-9])
#			ipAddressTag='ip_address'
#			jdsAvailable='true'
# 			computerSearch='serialnumber'
# 			computerValue="$(ioreg -c IOPlatformExpertDevice -d 2 | awk '/IOPlatformSerialNumber/ { print $NF }' | tr -d '"' | tr '[:lower:]' '[:upper:]')"
#			
#			run_radar_distribution; returnCode="${?}"
#			if [ "${returnCode}" -ne '0' ]; then
#				printf '%s\n' 'Unknown error.'
#				return "${returnCode}"
#			fi
#			;;
		*)
			printf '%s, %s\n' 'Unrecognized version of the jamf binary' "$(/usr/sbin/jamf version | awk -F= '{ print $2 }')"
			return 1
			;;
	esac
}

# This is the ping function which is used to determine the lowest latency ping result.
function radar_ping () {
	local ipAddress="${1}"
	local distType="${2}"
	local distID="${3}"
	local resultFile="${4}"
	local validatePort="${5}"
	local pingResult=''
	local pingExit=''
	
	# Determine if the validation port is reachable.
	if [ -n "${validatePort}" ]; then
		nc -z "${ipAddress}" "${validatePort}" &>/dev/null
		[ "${?}" -ne '0' ] && return 0
	fi
	
	# Ping the given address 5 times.
	pingResult="$(ping -c 5 -q "${ipAddress}")"; pingExit="${?}"
	# On error, exit out. Server probably unreachable so just ignore this server.
	if [ "${pingExit}" -ne '0' ]; then
		return 0
	fi
	
	# Append the average ping result, the type of server and the id to a results file.
	printf '%s %s %s\n' "$(tail -1 <<< "${pingResult}" | awk -F '/' '{ print $5 }')" "${distType}" "${distID}" >> "${resultFile}"
	return 0
}

# The actual radar function.
function run_radar_distribution () {
	# Define the .tmp file.
	tempFile="/tmp/radar${RANDOM}.tmp"
	
	# Find all available distribution points.
	allDistPointsXML="$(get_jss_resource_xml "${jssServer}" 'distributionpoints' "${JSS_RADAR_API_USER}" "${JSS_RADAR_API_PASS}")"
	[ "${?}" -ne '0' ] && return 1
	
	# Make an array of all the id's.
	allDistPointIDs=($(awk -F'<id>|</id>' '/<id>/ { print $2 }' <<< "${allDistPointsXML}"))
	
	# For each distribution point, spin off a radar_ping process.
	processIDs=()
	for i in "${allDistPointIDs[@]}"; do
		# Skip any "blacklisted" servers.
		(is_in_array BLACKLIST_DIST_POINT_ID "${i}") && continue
		
		# Get the distribution point information and parse the ip address.
		thisDistPointXML="$(get_jss_resource_xml "${jssServer}" "distributionpoints/id/${i}" "${JSS_RADAR_API_USER}" "${JSS_RADAR_API_PASS}")"
		[ "${?}" -ne '0' ] && return 1
		# The ip_address tag used to be labelled ipAddress in JSS 8. Use a variable to allow either.
		thisIPAddress="$(get_single_xml_item '/distribution_point' "id=${i}" "${ipAddressTag}" "${thisDistPointXML}")"
		[ "${?}" -ne '0' ] && return 1
		# If validating that the share port is available, determine the validation port.
		if [ "${VALIDATE_SHARE_PORT}" == 'true' ]; then
			thisHttpEnabled="$(get_single_xml_item '/distribution_point' "id=${i}" 'http_downloads_enabled' "${thisDistPointXML}")"
			[ "${?}" -ne '0' ] && return 1
			if [ "${thisHttpEnabled}" == 'true' ]; then
				thisValidatePort="$(get_single_xml_item '/distribution_point' "id=${i}" 'port' "${thisDistPointXML}")"
				[ "${?}" -ne '0' ] && return 1
			else
				thisValidatePort="$(get_single_xml_item '/distribution_point' "id=${i}" 'share_port' "${thisDistPointXML}")"
				[ "${?}" -ne '0' ] && return 1
			fi
		else
			thisValidatePort=''
		fi
		# Spin off a subprocess to handle the ping. Write process ID to array.
		radar_ping "${thisIPAddress}" distribution_point "${i}" "${tempFile}" "${thisValidatePort}" &
		processIDs+=("${!}")
	done
	
	# If jdsAvailable is 'true', also process the distribution servers.
	if [ "${jdsAvailable}" == 'true' ]; then
		# Find all available distribution servers.
		allDistServersXML="$(get_jss_resource_xml "${jssServer}" 'distributionservers' "${JSS_RADAR_API_USER}" "${JSS_RADAR_API_PASS}")"
		[ "${?}" -ne '0' ] && return 1
	
		# Make an array of all the id's.
		allDistServersIDs=($(awk -F'<id>|</id>' '/<id>/ { print $2 }' <<< "${allDistPointsXML}"))
		# For each distribution point, spin off a "ping" process.
		for i in "${allDistServersIDs[@]}"; do
			# Skip any "blacklisted" servers.
			(is_in_array BLACKLIST_DIST_SERVER_ID "${i}") && continue
			
			# Get the distribution server information and parse the ip address.
			thisDistServerXML="$(get_jss_resource_xml "${jssServer}" "distributionservers/id/${i}" "${JSS_RADAR_API_USER}" "${JSS_RADAR_API_PASS}")"
			[ "${?}" -ne '0' ] && return 1
			thisIPAddress="$(get_single_xml_item '/distribution_point' "id=${i}" 'hostname' "${thisDistServerXML}")"
			[ "${?}" -ne '0' ] && return 1
			# If validating that the share port is available, set the validation port.
			if [ "${VALIDATE_SHARE_PORT}" == 'true' ]; then
				thisValidatePort='443'
			else
				thisValidatePort=''
			fi
			# Spin off a subprocess to handle the ping. Store process ID in array.
			radar_ping "${thisIPAddress}" distribution_server "${i}" "${tempFile}" "${thisValidatePort}" &
			processIDs+=("${!}")
		done
	fi
	
	# Validate that there are distribution points or servers available.
	if [ "${#processIDs[@]}" -eq '0' ]; then
		printf '%s\n' 'Not able to obtain any distribution points or distribution servers.'
		return 0
	fi
	
	# Wait for all my tasks to finish. Specifying PID to better handle running RADAR in
	# parallel with other tasks if part of a larger management framework.
	for i in "${processIDs[@]}"; do
		wait "${i}"
	done
	
	# Validate that at least one entry was written to the temp file.
	if [ ! -f "${tempFile}" ]; then
		printf '%s\n' 'No distribution points or distribution servers were reachable.'
		return 0
	fi
	
	# Find the lowest ping time and get the distType and distID.
	distTypeAndID="$(sort -n "${tempFile}" | awk '{ print $2" "$3; exit }')"
	distType="$(awk '{ print $1 }' <<< "${distTypeAndID}")"
	distID="$(awk '{ print $2 }' <<< "${distTypeAndID}")"
	
	# Get all the general information for this computer.
	computerGeneralXML="$(get_jss_resource_xml "${jssServer}" "computers/${computerSearch}/${computerValue}/subset/general" "${JSS_RADAR_API_USER}" "${JSS_RADAR_API_PASS}")"
	[ "${?}" -ne '0' ] && return 1
	# Parse the computer id.
	computerID="$(get_single_xml_item '/computer/general' '1=1' 'id' "${computerGeneralXML}")"
	[ "${?}" -ne '0' ] && return 1
	# Parse the distribution point.
	computerDistPointName="$(get_single_xml_item '/computer/general' "1=1" 'distribution_point' "${computerGeneralXML}")"
	[ "${?}" -ne '0' ] && return 1
	# If available, parse the distribution server.
	if [ "${jdsAvailable}" == 'true' ]; then
		computerDistServerName="$(get_single_xml_item '/computer/general' "1=1" 'distribution_server' "${computerGeneralXML}")"
		[ "${?}" -ne '0' ] && return 1
	fi
	
	# Get the distribution point/server name. Exit out if set correctly.
	if [ "${distType}" == 'distribution_point' ]; then
		distName="$(get_single_xml_item '/distribution_points/distribution_point' "id=${distID}" 'name' "${allDistPointsXML}")"
		[ "${?}" -ne '0' ] && return 1
		if [ "${computerDistPointName}" == "${distName}" ]; then
			rm -f "${tempFile}"
			return 0
		fi
	elif [ "${distType}" == 'distribution_server' ]; then
		distName="$(get_single_xml_item '/distribution_servers/distribution_server' "id=${distID}" 'name' "${allDistServersXML}")"
		[ "${?}" -ne '0' ] && return 1
		if [ "${computerDistServerName}" == "${distName}" ]; then
			rm -f "${tempFile}"
			return 0
		fi
	else
		printf '%s\n' 'Could not determine distribution type.'
		return 1
	fi
	
	# Write an xml file with the appropriate value.
	printf '%s\n%s\n%s\n%s\n%s\n%s' '<?xml version="1.0" encoding="UTF-8" standalone="no"?>' '<computer>' '<general>' "<${distType}>${distName}</${distType}>" '</general>' '</computer>' > "${tempFile}"
	
	# Upload the new setting.
	result="$(curl -s -k -u "${JSS_RADAR_API_USER}:${JSS_RADAR_API_PASS}" -H "Content-Type: application/xml" -X 'PUT' "${jssServer}/JSSResource/computers/id/${computerID}" -T "${tempFile}")"
	
	# Determine if an error occurred.
	resultID="$(xmllint --format - <<< "${result}" 2>/dev/null | awk -F'<id>|</id>' '/<id/ { print $2; exit }')"
	if [ -n "${resultID}" ] && [ "${resultID}" -eq "${computerID}" ]; then
		# No explicit errors thrown. If not validating the setting, exit out here.
		if [ "${VALIDATE_SETTING}" != 'true' ]; then
			printf '%s.\n' "Set ${distType} to ${distName}"
			rm -f "${tempFile}"
			return 0
		fi
		
		# Get all the general information for this computer.
		computerGeneralXML="$(get_jss_resource_xml "${jssServer}" "computers/${computerSearch}/${computerValue}/subset/general" "${JSS_RADAR_API_USER}" "${JSS_RADAR_API_PASS}")"
		# Parse the distribution point.
		computerDistPointName="$(get_single_xml_item '/computer/general' "1=1" "${distType}" "${computerGeneralXML}")"
		
		# Determine if setting successfully set.
		if [ "${distName}" == "${computerDistPointName}" ]; then
			printf '%s.\n' "Successfully set ${distType} to ${distName}"
		else
			printf '%s. %s %s\n' "Could not set ${distType} to ${distName}" 'Please verify that distribution is not being controlled by network segment for IP:' "$(get_single_xml_item '/computer/general' "1=1" "ip_address" "${computerGeneralXML}")"
		fi
		rm -f "${tempFile}"
		return 0
	else
		printf 'Error:%s\n' "$(sed 's|<p[^>]*>|<p> |g' <<< "${result}" | awk -F'<p>|</p>' '/<p>/ { print $2 }' | tr '\n' '.')"
		rm -f "${tempFile}"
		return 1
	fi
}

# Attempt a connection to a public internet server.
function check_internet () {
	nc -z "${INTERNET_URL}" "${INTERNET_PORT}" &>/dev/null
	return "${?}"
}

# Attempt a connection to a private intranet server.
function check_corp () {
	nc -z "${CORP_URL}" "${CORP_PORT}" &>/dev/null
	return "${?}"
}

# Loop until the machine is on the internet
function wait_for_internet () {
	while ! check_internet; do
		sleep 300
	done
}

# Loop until the machine is on the corporate network
function wait_for_corp () {
	while ! check_corp; do
		sleep 300
	done
}

# This function returns the http/https server address for the JSS server.
function get_jss_server () {
	local result returnCode serverName
	# Verify that the binary exists
	if [ ! -f '/usr/sbin/jamf' ]; then
		printf 'Error: %s' "jamf binary could not be found."
		return 2
	fi
	
	# Check if JSS server is available. Note: Does not validate communication.
	result="$(/usr/sbin/jamf checkJSSConnection)"; returnCode="${?}"
	
	# Parse the server name.
	serverName="$(grep -o -m 1 'https\?://[^/]*' <<< "${result}")"
	
	# Echo out the JSS server name.
	printf '%s' "${serverName}"
	
	# Return the same code that checkJSSConnection did
	return "${returnCode}"
}

# This function handles the curl command and formats the xml result.
function get_jss_resource_xml () {
	local jssServer="${1}"
	local resourceLocation="${2}"
	local jssUsername="${3}"
	local jssPassword="${4}"
	
	# Validate that null values were not passed.
	[ -z "${jssServer}" ] && return 1
	# Validate that null values were not passed.
	[ -z "${resourceLocation}" ] && return 1
	# Validate that null values were not passed.
	[ -z "${jssUsername}" ] && return 1
	# Validate that null values were not passed.
	[ -z "${jssPassword}" ] && return 1
	
	# Use curl to grab the requested resource.
	curlResult="$(curl -s -k -u "${jssUsername}:${jssPassword}" -H 'Content-Type: application/xml' -X 'GET' "${jssServer}/JSSResource/${resourceLocation}")"
	# On error, return error code.
	if [ "${?}" -ne '0' ]; then
		printf '%s\n' "Error obtaining resource."
		return 1
	fi
	
	# Format the xml. This also verifies that it is valid xml.
	formatResult="$(xmllint --format - <<< "${curlResult}")"
	# On error, return error code.
	if [ "${?}" -ne '0' ]; then
		printf '%s%s\n' "Invalid XML. Status Error:" "$(sed 's|<p[^>]*>|<p> |g' <<< "${curlResult}" | awk -F'<p>|</p>' '/<p>/ { print $2 }' | tr '\n' '.')"
		return 1
	fi
	
	# Return the xml text.
	printf '%s' "${formatResult}"
	return 0
}

# This function uses xpath to get a single xml item, removing all xml tags.
function get_single_xml_item () {
	local rootPath="${1}"
	local withMatching="${2}"
	local subItem="${3}"
	local xmlText="${4}"
	
	# Parse the xml and grab the specific item being requested.
	xmlResult="$(xpath "${rootPath}[${withMatching}]/${subItem}" <<< "${xmlText}" 2>/dev/null | xmllint --format - 2>/dev/null)"
	# On error, return error code.
	if [ "${?}" -ne '0' ]; then
		return 1
	fi
	
	# Return the requested item without any xml tags.
	printf '%s' "$(awk -F"<${subItem}>|</${subItem}>" "/<${subItem}>/ { print \$2; exit }" <<< "${xmlResult}")"
	return 0
}

# Determine if array with name ($1) contains key ($2)
function is_in_array () {
	if [ -z "${1}" ] || [ -z "${2}" ]; then
		return 2
	fi

	local arr=${1}[@]
	local key="${2}"

	for element in "${!arr}"; do
		[ "${element}" == "${key}" ] && return 0
	done

	return 1
}

# Verify that a policy has been run in the past 30 seconds. This validates that the JSS
# has a recent IP address. Really only necessary/desired if some network subnets have
# defined distribution points and others don't. Can also be used to throttle RADAR.
function wait_for_policy () {
	# The timestamp for "now" minus 30 seconds.
	timeStamp="$(expr "$(date '+%s')" - 30)"
	
	# Determine when the last policy was run.
	lastPolicy="$(last_jamf_policy_timestamp)"
	logTimestamp="$(stat -f "%m" /var/log/jamf.log)"
	
	# Loop until a policy is run.
	while [ "${lastPolicy}" -lt "${timeStamp}" ]; do
		sleep 5
		logTimestampNew="$(stat -f "%m" /var/log/jamf.log)"
		if [ "${logTimestampNew}" -ne "${logTimestamp}" ]; then
			lastPolicy="$(last_jamf_policy_timestamp)"
			logTimestamp="${logTimestampNew}"
		fi
	done
}

# Read the JAMF log and determine when the last policy was run with the JSS reachable.
function last_jamf_policy_timestamp () {
	# Read the JAMF log file line-by-line in reverse. Removing any policy events that couldn't connect.
	while read line; do
		[ -z "$(grep -o 'Checking for policies triggered by' <<< "${line}")" ] && continue
		printf "$(date -jf '%b %d %T' "$(awk '{ print $2" "$3" "$4 }' <<< "${line}")" '+%s')"
		return 0
	done <<< "$(nl /var/log/jamf.log | sort -nr | cut -f 2- | awk '/Could not connect/ {n=2}; n {n--; next}; 1')"
}

# All functions are defined. Kick off RADAR.
if [ "${WRITE_TO_SYSTEM_LOG}" == 'true' ]; then
	loggerOut="$(Main; exit "${?}")"; exitCode="${?}"
	logger -t "${LOGGING_TAG}" "${loggerOut}"
else
	Main; exitCode="${?}"
fi

exit "${exitCode}"