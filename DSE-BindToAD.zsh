#!/bin/zsh

# Editor: Andrew W. Johnson
# Date: 2020.02.13
# Version 2.00
# Organization: Stony Brook University/DoIT
#
# Originally written by the folks at DeployStudio, and modified over the years to 
# work with out DeployStudio. Converted it to ZSH.
#
# We find that there are issues when binding with a profile that are not present when 
# dsconfigad is used to bind.
#
# Using $4 (Jamf parameter) for the OU to bind to.
#
# !! This version of the script has been sanitized !!

IS_BOUND=`/usr/sbin/dsconfigad -show | /usr/bin/egrep "Active Directory Domain"`


if [ -n "${IS_BOUND}" ]; then
	/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: This computer is bound to the AD." >> /var/log/jamf.log
	/bin/echo "This computer is bound to the AD."
	exit 0
else
	/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: This computer is not bound to the AD." 2>&1 >> /var/log/jamf.log
	/bin/echo "This computer is not bound to the AD." 2>&1

	# Disable history characters
	histchars=

	SCRIPT_NAME=$( /usr/bin/basename "${0}" )

	/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: ${SCRIPT_NAME} - v2.00" >> /var/log/jamf.log
	/bin/echo "${SCRIPT_NAME} - v2.00"

	is_ip_address() {
		IP_REGEX="\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"
		IP_CHECK=`/bin/echo ${1} | /usr/bin/egrep ${IP_REGEX}`
		if [ ${#IP_CHECK} -gt 0 ]
		then
			return 0
		else
			return 1
		fi
	}
	AD_DOMAIN=""
	COMPUTER_ID=`/usr/sbin/scutil --get ComputerName | /usr/bin/tr '[:upper:]' '[:lower:]'`
#	COMPUTERS_OU=""
	COMPUTERS_OU="${4}"
	ADMIN_LOGIN=""
	ADMIN_PWD=""

	MOBILE="enable"
	MOBILE_CONFIRM="disable"
	LOCAL_HOME="enable"
	USE_UNC_PATHS="enable"
	UNC_PATHS_PROTOCOL="smb"
	PACKET_SIGN="allow"
	PACKET_ENCRYPT="allow"
	PASSWORD_INTERVAL=0
	AUTH_DOMAIN=""
	ADMIN_GROUPS=""

	UID_MAPPING=""
	GID_MAPPING=""
	GGID_MAPPING=""

	#
	# Wait for network services to be initialized
	#
	/bin/echo "Checking for the default route to be active..."
	ATTEMPTS=0
	MAX_ATTEMPTS=10
	while ! (/usr/sbin/netstat -rn -f inet | /usr/bin/grep -q default)
	do
		if [ ${ATTEMPTS} -le ${MAX_ATTEMPTS} ]
		then
			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Waiting for the default route to be active..." >> /var/log/jamf.log
			/bin/echo "Waiting for the default route to be active..."
			/bin/sleep 6
			ATTEMPTS=`expr ${ATTEMPTS} + 1`
		else
			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Network not configured, AD binding failed (${MAX_ATTEMPTS} attempts), will retry at next boot!" 2>&1 >> /var/log/jamf.log
			/bin/echo "Network not configured, AD binding failed (${MAX_ATTEMPTS} attempts), will retry at next boot!" 2>&1
			exit 1
		fi
	done
	
	#
	# Wait for the related server to be reachable
	# NB: AD service entries must be correctly set in DNS
	#
	SUCCESS=
	is_ip_address "${AD_DOMAIN}"
	if [ ${?} -eq 0 ]
	then
			# The AD_DOMAIN variable contains an IP address, let's try to ping the server
		/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Testing ${AD_DOMAIN} reachability" 2>&1 >> /var/log/jamf.log
		/bin/echo "Testing ${AD_DOMAIN} reachability" 2>&1  
		if /sbin/ping -t 5 -c 1 "${AD_DOMAIN}" | /usr/bin/grep "round-trip"
		then
			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Ping successful!" 2>&1 >> /var/log/jamf.log
			/bin/echo "Ping successful!" 2>&1
			SUCCESS="YES"
		else
			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Ping failed..." 2>&1 >> /var/log/jamf.log
			/bin/echo "Ping failed..." 2>&1
		fi
	else
		ATTEMPTS=0
		MAX_ATTEMPTS=12
		while [ -z "${SUCCESS}" ]
		do
			if [ ${ATTEMPTS} -lt ${MAX_ATTEMPTS} ]
			then
				AD_DOMAIN_IPS=( `/usr/bin/host "${AD_DOMAIN}" | /usr/bin/grep " has address " | /usr/bin/cut -f 4 -d " "` )
				for AD_DOMAIN_IP in ${AD_DOMAIN_IPS[@]}
				do
					/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Testing ${AD_DOMAIN} reachability on address ${AD_DOMAIN_IP}" 2>&1 >> /var/log/jamf.log
					/bin/echo "Testing ${AD_DOMAIN} reachability on address ${AD_DOMAIN_IP}" 2>&1  
					if /sbin/ping -t 5 -c 1 ${AD_DOMAIN_IP} | /usr/bin/grep "round-trip"
					then
						/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Ping successful!" 2>&1 >> /var/log/jamf.log
						/bin/echo "Ping successful!" 2>&1
						SUCCESS="YES"
					else
						/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Ping failed..." 2>&1 >> /var/log/jamf.log
						/bin/echo "Ping failed..." 2>&1
					fi
					if [ "${SUCCESS}" = "YES" ]
					then
						break
					fi
				done
			if [ -z "${SUCCESS}" ]
			then
				/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: An error occurred while trying to get ${AD_DOMAIN} IP addresses, new attempt in 10 seconds..." 2>&1 >> /var/log/jamf.log
				/bin/echo "An error occurred while trying to get ${AD_DOMAIN} IP addresses, new attempt in 10 seconds..." 2>&1
				/bin/sleep 10
				ATTEMPTS=`expr ${ATTEMPTS} + 1`
			fi
			else
				/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Cannot get any IP address for ${AD_DOMAIN} (${MAX_ATTEMPTS} attempts), aborting lookup..." 2>&1 >> /var/log/jamf.log
				/bin/echo "Cannot get any IP address for ${AD_DOMAIN} (${MAX_ATTEMPTS} attempts), aborting lookup..." 2>&1
				break
			fi
		done
	fi
	if [ -z "${SUCCESS}" ]
	then
		/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Cannot reach any IP address of the domain ${AD_DOMAIN}." 2>&1 >> /var/log/jamf.log
		/bin/echo "Cannot reach any IP address of the domain ${AD_DOMAIN}." 2>&1
		/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: AD binding failed, will retry at next boot!" 2>&1 >> /var/log/jamf.log
		/bin/echo "AD binding failed, will retry at next boot!" 2>&1
		exit 1
	fi
	
	#
	# Unbinding computer first
	#
	/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Unbinding computer..." 2>&1 >> /var/log/jamf.log
	/bin/echo "Unbinding computer..." 2>&1
	/usr/sbin/dsconfigad -remove -username "${ADMIN_LOGIN}" -password "${ADMIN_PWD}" 2>&1

	#
	# Try to bind the computer
	#
	ATTEMPTS=0
	MAX_ATTEMPTS=12
	SUCCESS=
	while [ -z "${SUCCESS}" ]
	do
		if [ ${ATTEMPTS} -le ${MAX_ATTEMPTS} ]
		then
			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Binding computer to domain ${AD_DOMAIN}..." 2>&1 >> /var/log/jamf.log
			/bin/echo "Binding computer to domain ${AD_DOMAIN}..." 2>&1
			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: ${AD_DOMAIN}" >> /var/log/jamf.log
			/bin/echo "${AD_DOMAIN}"
			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: ${COMPUTER_ID}" >> /var/log/jamf.log
			/bin/echo "${COMPUTER_ID}"
			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: ${COMPUTERS_OU}" >> /var/log/jamf.log
			/bin/echo "${COMPUTERS_OU}"
			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: ${ADMIN_LOGIN}" >> /var/log/jamf.log
			/bin/echo "${ADMIN_LOGIN}"
#			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: ${ADMIN_PWD}" >> /var/log/jamf.log
#			/bin/echo "${ADMIN_PWD}"

			/usr/sbin/dsconfigad -add "${AD_DOMAIN}" -computer "${COMPUTER_ID}" -ou "${COMPUTERS_OU}" -username "${ADMIN_LOGIN}" -password "${ADMIN_PWD}" -force 2>&1
			IS_BOUND=`/usr/sbin/dsconfigad -show | /usr/bin/grep "Active Directory Domain"`
			if [ -n "${IS_BOUND}" ]
			then
				SUCCESS="YES"
			else
				/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: An error occured while trying to bind this computer to AD, new attempt in 10 seconds..." 2>&1 >> /var/log/jamf.log
				/bin/echo "An error occured while trying to bind this computer to AD, new attempt in 10 seconds..." 2>&1
				/bin/sleep 10
				ATTEMPTS=`expr ${ATTEMPTS} + 1`
			fi
			else
				/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: AD binding failed (${MAX_ATTEMPTS} attempts), will retry at next boot!" 2>&1 >> /var/log/jamf.log
				/bin/echo "AD binding failed (${MAX_ATTEMPTS} attempts), will retry at next boot!" 2>&1
				SUCCESS="NO"
			fi
	done
	
	if [ "${SUCCESS}" = "YES" ]
	then
		#
		# Update AD plugin options
		#
		/bin/echo "Setting AD plugin options..." 2>&1
		/usr/sbin/dsconfigad -mobile ${MOBILE} 2>&1
		/bin/sleep 1
		/usr/sbin/dsconfigad -mobileconfirm ${MOBILE_CONFIRM} 2>&1 
		/bin/sleep 1
		/usr/sbin/dsconfigad -localhome ${LOCAL_HOME} 2>&1
		/bin/sleep 1
		/usr/sbin/dsconfigad -useuncpath ${USE_UNC_PATHS} 2>&1
		/bin/sleep 1
		/usr/sbin/dsconfigad -protocol ${UNC_PATHS_PROTOCOL} 2>&1
		/bin/sleep 1
		/usr/sbin/dsconfigad -packetsign ${PACKET_SIGN} 2>&1
		/bin/sleep 1
		/usr/sbin/dsconfigad -packetencrypt ${PACKET_ENCRYPT} 2>&1
		/bin/sleep 1
		/usr/sbin/dsconfigad -passinterval ${PASSWORD_INTERVAL} 2>&1
		if [ -n "${ADMIN_GROUPS}" ]
		then
			/bin/sleep 1
			/usr/sbin/dsconfigad -groups "${ADMIN_GROUPS}" 2>&1
		fi
		/bin/sleep 1

		if [ -n "${AUTH_DOMAIN}" ] && [ "${AUTH_DOMAIN}" != 'All Domains' ]
		then
			/usr/sbin/dsconfigad -alldomains disable 2>&1
		else
			/usr/sbin/dsconfigad -alldomains enable 2>&1
		fi
		AD_SEARCH_PATH=`/usr/bin/dscl /Search -read / CSPSearchPath | grep "Active Directory" | sed 's/^ *//' | sed 's/ *$//'`
		if [ -n "${AD_SEARCH_PATH}" ]
		then
			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Deleting '${AD_SEARCH_PATH}' from authentication search path..." 2>&1 >> /var/log/jamf.log
			/bin/echo "Deleting '${AD_SEARCH_PATH}' from authentication search path..." 2>&1
			/usr/bin/dscl localhost -delete /Search CSPSearchPath "${AD_SEARCH_PATH}" 2>/dev/null
			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Deleting '${AD_SEARCH_PATH}' from contacts search path..." 2>&1 >> /var/log/jamf.log
			/bin/echo "Deleting '${AD_SEARCH_PATH}' from contacts search path..." 2>&1
			/usr/bin/dscl localhost -delete /Contact CSPSearchPath "${AD_SEARCH_PATH}" 2>/dev/null
		fi
		/usr/bin/dscl localhost -create /Search SearchPolicy CSPSearchPath 2>&1
		/usr/bin/dscl localhost -create /Contact SearchPolicy CSPSearchPath 2>&1
		AD_DOMAIN_NODE=`/usr/bin/dscl localhost -list "/Active Directory" | head -n 1`
		if [ "${AD_DOMAIN_NODE}" = "All Domains" ]
		then
			AD_SEARCH_PATH="/Active Directory/All Domains"
		elif [ -n "${AUTH_DOMAIN}" ] && [ "${AUTH_DOMAIN}" != 'All Domains' ]
		then
			AD_SEARCH_PATH="/Active Directory/${AD_DOMAIN_NODE}/${AUTH_DOMAIN}"
		else
			AD_SEARCH_PATH="/Active Directory/${AD_DOMAIN_NODE}/All Domains"
		fi
		/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Adding '${AD_SEARCH_PATH}' to authentication search path..." 2>&1 >> /var/log/jamf.log
		/bin/echo "Adding '${AD_SEARCH_PATH}' to authentication search path..." 2>&1
		/usr/bin/dscl localhost -append /Search CSPSearchPath "${AD_SEARCH_PATH}"
		/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Adding '${AD_SEARCH_PATH}' to contacts search path..." 2>&1 >> /var/log/jamf.log
		/bin/echo "Adding '${AD_SEARCH_PATH}' to contacts search path..." 2>&1
		/usr/bin/dscl localhost -append /Contact CSPSearchPath "${AD_SEARCH_PATH}"

		if [ -n "${UID_MAPPING}" ]
		then
			/bin/sleep 1
			/usr/sbin/dsconfigad -uid "${UID_MAPPING}" 2>&1
		fi
		if [ -n "${GID_MAPPING}" ]
		then
			/bin/sleep 1
			/usr/sbin/dsconfigad -gid "${GID_MAPPING}" 2>&1
		fi
		if [ -n "${GGID_MAPPING}" ]
		then
			/bin/sleep 1
			/usr/sbin/dsconfigad -ggid "${GGID_MAPPING}" 2>&1
		fi

		GROUP_MEMBERS=`/usr/bin/dscl /Local/Default -read /Groups/com.apple.access_loginwindow GroupMembers 2>/dev/null`
		NESTED_GROUPS=`/usr/bin/dscl /Local/Default -read /Groups/com.apple.access_loginwindow NestedGroups 2>/dev/null`
		if [ -z "${GROUP_MEMBERS}" ] && [ -z "${NESTED_GROUPS}" ]
		then
			/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Enabling network users login..." 2>&1 >> /var/log/jamf.log
			/bin/echo "Enabling network users login..." 2>&1
			/usr/sbin/dseditgroup -o edit -n /Local/Default -a netaccounts -t group com.apple.access_loginwindow 2>/dev/null
		fi

		if [ "${SUCCESS}" = "YES" ]
		then
			if [ -e "/System/Library/CoreServices/ServerVersion.plist" ]
			then
				DEFAULT_REALM=`more /Library/Preferences/edu.mit.Kerberos | grep default_realm | awk '{ print $3 }'`
				if [ -n "${DEFAULT_REALM}" ]
				then
					/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: The binding process looks good, will try to configure Kerberized services on this machine for the default realm ${DEFAULT_REALM}..." 2>&1 >> /var/log/jamf.log
					/bin/echo "The binding process looks good, will try to configure Kerberized services on this machine for the default realm ${DEFAULT_REALM}..." 2>&1
					/usr/sbin/sso_util configure -r "${DEFAULT_REALM}" -a "${ADMIN_LOGIN}" -p "${ADMIN_PWD}" all
				fi
				#
				# Give OD a chance to fully apply new settings
				#
				/bin/echo "$( /bin/date | /usr/bin/awk '{print $1, $2, $3, $4}' ) $( /usr/sbin/scutil --get LocalHostName ) $( /usr/bin/basename ${0} )[$$]: Applying changes..." 2>&1  >> /var/log/jamf.log
				/bin/echo "Applying changes..." 2>&1
				/bin/sleep 10
			fi
			exit 0
		fi
	fi
fi
exit 0
