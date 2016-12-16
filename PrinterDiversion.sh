#!/bin/bash
#set -x
clear
printf '\e[8;60;100t'
printf '\e[3;0;0t'

#################################################################################
#										#
#	Specsavers Printer Diversion Script v0.9				#
#										#
#################################################################################
#										#
#										#
#	Author: Doug Goodale							#
# 										#
#	Description:								#
#	This script is used to change the ip address and driver for a		#
#	printer	defined within the CUPS Print Server on each store 		#
#	client.									#
# 										#
#	It first gathers a list of the available printers in store, then	#
#	checks for any existing diversions. It then prompts the user to		#
#	either remove a diversion or add one.					#
# 										#
#	It then makes the necessary changes to the IP and printer driver 	#
#	settings to the relevant printer.					#
#										#
#										#
#################################################################################

#Include the general functions for logging and getting active clients.
. /export/home/support/.library/general.functions
#Include the cupsConfig functions for finding printer model.
. /export/home/support/.library/cupsConfig.functions

#List of the possible addresses for printers in store. Expand where necessary
printersList="100 101 102 103 104 180 181 182 183 184"
#List of clients to exclude from diversion: 
# .2 - HICAPS box running .40 & .11 VMs 
# .45 - Sister store box, printers set for different IP
exclusionList="2 45"
#Logfile location
diversionLog="/var/log/specsavers/printerdiversion.log"
if -f   #does touch just change the date modified
touch $diversionLog
#Cups printer config file location
printerConfig="/etc/cups/printers.conf"

########################## Script Functions ####################################

function printerDetails(){
	#!..
	#Function Name: 	printerDetails
	#Function Description: 	Function for determining printer details from an IP
	#Function Parameters: 	$1: 	IP of the printer
	#			$2-5:	(optional)Desired details, if none will return all details
	#Function Output: 	A list of the requested details, in the same order as the arguments
	#..!

	local printerIp=$1	
	local dumpFile="/tmp/printerInfo.dump"
 
	if [ -z "$printerIp" ]
	then
		echo "Call to printerDetails() requires an IP address"
		return 1 #added return code
	else
		validateIP $printerIp
		if [ $? -eq 0 ]
		then
			echo  "IP address is invalid"
			return 1 #added return code
		else
			wget -t1 -T10 -q $printerIp/main.asp -O $dumpFile   <is always main.asp
			local printerModel=$(findPrinter $dumpFile)
			local printerDriver=""
			local printerName=""
			local printerNumber=$(echo $printerIp | cut -d "." -f4)
			local printerNumberShort="$(($printerNumber - 100))"
			case $printerModel in
				"3510DN")
					printerDriver="sog_ricoh_sp3410dn_t1.ppd"
					printerName="lanier_3510_"$printerNumberShort
					;;
				"3410DN")
					printerDriver="sog_ricoh_sp3410dn_t1.ppd"
					printerName="lanier_3410_"$printerNumberShort
					;;
				"252DN")
					printerDriver="sog_ricoh_spc232sf_t1.ppd"
					printerName="lanier_c252_"$printerNumberShort
					;;
				"242DN")
					printerDriver="sog_ricoh_spc232sf_t1.ppd"
					printerName="lanier_c242_"$printerNumberShort
					;;
				*)
					echo "Unrecognised printer model." #Added default case
					return 1
					;;
			esac
			if [ -z "$2" ]
			then
				echo $printerNumber" "$printerModel" "$printerName" "$printerDriver
			else
				for arg in "$@"
				do
					if [ $arg == $1 ]
					then 
						continue
					else
						echo ${!arg}
					fi
				done
			fi
		fi
	fi
}

function isCupsConf(){
	#!..
	#Function Name:		isCupsConf
	#Function Description:	Reads a client's printers.conf file and returns true or false whether a printer has been configured in CUPS for that client. Finds printer by name not IP.
	#Function Input:	$1:	IP Address of the client
	#			$2:	IP address of the printer
	#Function Output:	Exit code 1 if printer is in clients CUPS, Exit code 0 if not
	#..!

	if [ $(validateIP $1) ]||[ $(validateIP $2) ]
	then
		echo "One or both of the IP addresses provided is missing or invalid" #which one?
		return 1
	else
		local checks=$(rsh $1 "grep $(printerDetails $2 printerName) $printerConfig || echo 1") #good variable name...
		if [ -n "$checks" ]
		then
			return 0
		else
			return 1
		fi 
	fi
}
	
function getConfirm(){

	read confirmed
	while [[ "$confirmed" != n && "$confirmed" != Y ]] #handle upper or lower and decommission this brahhh
	do
		echo "Please select either \"Y\" or \"n\""
		read confirmed
	done
}

function getSelect(){

	read selection
	until [[ "$selection" =~ ^[0-9]+$ ]]&&(( "$selection" >= 1 ))&&(( "$selection" <= "$i" ))
	do
		echo "Please select between 1 and "$i 
		read selection
	done
}

function divertPrinter(){
	#!..
	#Function Name: 	divertPrinter
	#Function Description: 	Diverts the selected printer on all active store clients.
	#Function Parameters:	$1: IP address of the printer being diverted from.
	#			$2: IP address of the printer being diverted to.
	#Function Output: 	Logs to file referenced by $diversionLog

	if [ -z "$1" ]||[ -z "$2" ]
	then
		echo "Insufficient arguments to divertPrinters function"
	else
		local divertFrom=$1
		local divertTo=$2
		local printerName=$(printerDetails $divertFrom printerName)
		local activeClients=$(clientsUp)
		for client in ${exclusionList}
		do
			client=$firstOcts.$client
			activeClients=${activeClients/$client/}
		done
		local failedClients=""

		for ip in ${activeClients};
		do
			local clientNumber=$(echo $ip | cut -d "." -f4)
			validateIP $ip
			if [ $? -eq 1 ];
			then
				log "|-------------------------------------------------------|" $diversionLog
				log "| INFO | Diverting Printer \""$printerName"\" on Client "$clientNumber $diversionLog
				rshCheck $ip
				if [ $? -eq 1 ];
				then
					log "| INFO | Ports open on client." $diversionLog
					log "| INFO | Backing up current CUPS setup..." $diversionLog
					return=$(rsh $ip "cp $printerConfig /etc/cups/printers.conf.diversion || echo 1")
					if [ -n "$return" ]
					then
						log "| ERROR | Error backing up current setup." $diversionLog
						log "| ERROR | Diversion on client "$clientNumber" failed." $diversionLog
						failedClients+=$clientNumber" "
						continue
					else
						log "| INFO | Backup successful!" $diversionLog
					fi

					#update PPD files on the client
					log "| INFO | Updating PPD files to the latest version..." $diversionLog
					return=$(rsh $ip "cd /usr/share/cups/model/ ; wget -t2 -T10 -qN 10.80.0.63/wgetfiles/files/ppd/ppds-full.zip ; unzip -qqo ppds-full.zip || echo 1") #retuyrning what huh?
					if [ -n "$return" ]
					then
						log "| ERROR | Updating PPD files failed." $diversionLog
					else
						log "| INFO | PPD files updated successfully!" $diversionLog
					fi

					#check if printer is configured in CUPS
					isCupsConf $ip $divertFrom
					if [ $? -eq 0 ]
					then
						log "| INFO | Printer is configured in CUPS..." $diversionLog
					else
						log "| WARN | Printer is not configured on this client." $diversionLog
						continue
					fi

					#set ip and driver of divertFrom
					log "| INFO | Changing settings in CUPS..." $diversionLog
					return=$(rsh $ip "/usr/sbin/lpadmin -p "$printerName" -P /usr/share/cups/model/"$(printerDetails $divertFrom printerDriver)" -v socket://"$divertTo":9100 || echo 1")
					if [ -n "$return" ]
					then
						log "| ERROR | Changing printer settings failed." $diversionLog
						log "| ERROR | Diversion on client "$clientNumber" failed." $diversionLog
						failedClients+=$clientNumber" "
						continue
					else
						log "| INFO | Printer diverted successfully!" $diversionLog
					fi		

					#restart CUPS server
					#################################### clear existing jobs first - cupsenable 
					return=$(rsh $ip "/sbin/service cups restart || echo 1")
					if [ $? -ne 0 ]
					then
						log "| ERROR | Problem restarting CUPS server." $diversionLog
					else
						log "| INFO | CUPS service restarted successfully!" $diversionLog
					fi
					sleep 3	
				else
				log "| ERROR | Unable to SSH to client: Ports not open." $diversionLog #rsh specific and what ports
				fi
			else
				log "| ERROR | Unable to connect to client: "$ip" is invalid address." $diversionLog
			fi
		done

		#Log any failed clients
		if [ -n "$failedClients" ]
		then
			log "|-------------------------------------------------------|" $diversionLog
			log "| WARN | Diversion failed on the following clients..." $diversionLog
			for client in ${failedClients}
			do
				log "	 Client "$client $diversionLog
			done
			log "|-------------------------------------------------------|" $diversionLog
		else
			log "|-------------------------------------------------------|" $diversionLog
			log "| INFO | All clients successfully diverted." $diversionLog
			log "|-------------------------------------------------------|" $diversionLog
		fi
	fi
}

###################################################################################################

log "| START | Running Printer Diversion Script..." $diversionLog

#Populate a list of the active printers available on the store network
log "| INFO | Gathering list of available printers..." $diversionLog
count=0
firstOcts=$(hostname -i | cut -f1-3 -d".")
for ip in ${printersList};
do
	printerIp=$firstOcts"."$ip
	ping -c3 -W2 $printerIp > /dev/null
	
	
	# If ping does not receive any reply packets at all it will exit with code 1. If a packet count and deadline are both specified, and fewer than count packets  are  received  by  the
#       time  the deadline has arrived, it will also exit with code 1.  On other error it exits with code 2. Otherwise it exits with code 0. This makes it possible to use the exit code to
 #      see if a host is alive or not.

	
	
	if [ $? -eq 0 ]
	then
		log "		"$printerIp"...[ACTIVE]" $diversionLog
		printerModel=$(printerDetails $printerIp printerModel)
		if [ -n "$printerModel" ];
		then
			printerName=$(printerDetails $printerIp printerName)
			log "		Printer Name:	"$printerName $diversionLog
			log "		Printer Model: 	"$printerModel $diversionLog
			activePrinters=$activePrinters$printerIp" "
			count=$((count+1))
		else
			log "Could not access printer status page" $diversionLog
			log "wget failed with exit status "$? $diversionLog - $? wtf
		fi
	else
		log "		"$printerIp"...[INACTIVE]" $diversionLog	
	fi
done

#Check enough printers were found. 
if (($count <= 1 ))
then

#tell me how many.. maybe which ones etc...
log "| ERROR | Less than 2 printers detected. Some printers may be offline or disconnected. Please divert through the clients' CUPS web interface." $diversionLog
exit    exit code?
fi

#Check if there are existing diversions
log "| INFO | Capturing state of printers..." $diversionLog
diversions=""
for printer in ${activePrinters}
do
	printerName=$(printerDetails $printer printerName)
	activeClients=$(clientsUp)  #range?
	for client in ${exclusionList}
	do
		client=$firstOcts.$client
		activeClients=${activeClients/$client/}
	done
	echo "Printer: \""$printerName\"
	for client in ${activeClients}
	do
		#If the printer is configured on this client...
		returnnumber=$(isCupsConf $client $printer)
		if [[ $returnnumber -eq 0 ]]
		then
			#...and if there is an IP address 
			return=$(rsh $client "grep -m3 -A2 $printerName $printerConfig || echo 1") #nice name
			if [[ -n "$return" ]]
			then
				#Check if it has the right IP or is diverted
				ip=$(echo $return | grep -Eo "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}")
				if [[ "$ip" == "$printer" ]]
				then
					echo "		Client "$(echo $client | cut -d"." -f4)" not diverted."
				else
					echo "		Client "$(echo $client | cut -d"." -f4)" to "$ip
					diversion=$printer","$ip
					return=$(echo $diversions | grep -o $diversion)

					#Check if the diversion is on the list already
					if [[ -n "$return" ]]
					then
						continue
					else
						#If not then add to the list
						diversions=$diversions$diversion" "
					fi
				fi
			else
				echo "Couldn't get printer IP"
			fi
		elif I am a 1...
			continue
		else
			fell over
		fi
	done
done
if [[ -z "$diversions" ]]
then
	log "| INFO | No existing diversions detected." $diversionLog
fi

while [[ -n "$diversions" ]]
do
	log "| INFO | One or more existing diversions in place." $diversionLog
	echo "Please select an option?"
	i=0
	for diversion in ${diversions};
	do
		i=$((i+1))
		divertFrom=$(echo $diversion | cut -d "," -f1) 
		divertTo=$(echo $diversion | cut -d "," -f2) 		
		echo $i")UNDO		"$divertFrom" diverted to "$divertTo
	done
	i=$((i+1))
	echo $i")REMOVE ALL DIVERSIONS/RESTORE DEFAULT SETTINGS (Will run CupsSetup.sh)"
	i=$((i+1))
	echo $i")ADD NEW DIVERSION"
	getSelect

	if [[ $selection -eq $i ]]
	then
		break
	elif [[ $selection -eq $((i-1)) ]]
	then
		wget -N 10.80.0.63/wgetfiles/files/SetupCups.sh  #where is it saving the file to. - specify brah
		sh SetupCups.sh #absolute path plz...
		exit
	else
		diversion=$(echo $diversions | cut -d" " -f$selection) 
		divertFrom=$(echo $diversion | cut -d "," -f1) 
		divertTo=$(echo $diversion | cut -d "," -f2)
		diversions=${diversions/$diversion /}
		divertPrinter $divertFrom $divertFrom
	fi
done	

#Select printer to divert. Enclosed in a loop in case the user selects the wrong printer/s by mistake
confirmed=n #confirm what?
while [[ "$confirmed" == n ]]
do
	echo "Please select the printer you wish to divert? (1 - "$count")"
	i=0
	for printer in ${activePrinters};
	do
		i=$((i+1))
		echo $i")		"$printer" - "\"$(printerDetails $printer printerName)\"
	done

	getSelect

	divertFrom=$(echo $activePrinters | cut -d " " -f$selection)
	remainingPrinters=$(echo $activePrinters | cut -d " " -f$selection --complement)

	#Select printer to divert to.

	echo "Please select the printer you wish to divert to?"
	i=0
	for printer in ${remainingPrinters};
	do
		i=$((i+1))
		echo $i")		"$printer" - "\"$(printerDetails $printer printerName)\"
	done

	getSelect

	divertTo=$(echo $remainingPrinters | cut -d " " -f$selection)
	echo "Confirm that you wish to divert printer @ "$divertFrom" to printer @ "$divertTo"? (Y/n)"
	getConfirm
done

#Change IP and driver for the selected printer in CUPS on each client
log "| INFO | Beginning CUPS diversion process..." $diversionLog

divertPrinter $divertFrom $divertTo 

