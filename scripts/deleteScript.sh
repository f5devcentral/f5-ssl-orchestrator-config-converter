#!/bin/bash

# Copyright 2024 F5 Networks, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Initialize variables
declare -A  CMIP=''
declare -A  MGSUMMARY=''
declare -A  CM_TOKEN=''
declare -A curl_result=''
declare -A max_try=2
declare -A total_try=0

# Declare an associative array
declare -A inspectionServices_uuid_map
declare -A serviceChains_uuid_map
declare -A policies_uuid_map
declare -A cm_delete_url_map=(
	["IS"]="/api/sslo/v1/inspection-services"
	["SC"]="/api/sslo/v1/service-chains"
	["POLICY"]="/api/sslo/v1/ssl-orchestrator-policies"
)
declare -A cm_post_name_map=(
	["IS"]="Inspection-Service"
	["SC"]="Service-Chain"
	["POLICY"]="Policy"
)

# Define font color variables
declare -A RED='\033[0;31m'
declare -A GREEN='\033[0;32m'
declare -A NC='\033[0m' # No Color

# Function to print script usage
print_usage() {
	printf "\nUsage: ./deleteMigrationScript.sh -cm_ip <IPAddress> -mg_summary <path to file>\n\n"
}

#Function to generate the token
generate_token() {
	# Get CM Auth access_token
	encoded_auth=$(echo -n "$USERID:$PASSWORD" | base64)
	CM_TOKEN_URI="$(curl -sk --location 'https://'${CMIP}'/api/login' --header 'Content-Type: application/json' --header 'Authorization: Basic "$encoded_auth"' --data "{\"username\": \"$USERID\", \"password\": \"$PASSWORD\"}")"
	response_code=$(echo "$CM_TOKEN_URI" | jq -r '.status')
	if [ -n "$response_code" ] && [ "$response_code" != "null" ]; then
		if [ "$response_code" -eq 401 ]; then
			message=$(echo "$CM_TOKEN_URI" | jq -r '.message')
			echo 
			echo -e "${RED}Script aborted, $message.${NC}"
			echo 
			echo "#########################################################################################"
			exit 1
		fi
	else 
		if [ -n "$CM_TOKEN_URI" ]; then
			CM_TOKEN=$(echo "$CM_TOKEN_URI" | jq -r '.access_token')
		fi
	fi
}

# Parsing command line arguments
while [[ "$#" -gt 0 ]]; do
	case "$1" in
		-cm_ip)
			CMIP="$2"
			shift 2
			;;
		-mg_summary)
			MGSUMMARY="$2"
			shift 2
			;;
		*)
			print_usage
			exit 1
			;;
	esac
done

# Checking for mandatory flags
if [ -z "$CMIP" ] || [ -z "$MGSUMMARY" ]; then
	print_usage
	exit 1
fi
echo
echo -n -e "${userchoice}Enter CM instance's user name: ${NC}"
read -s USERID
echo
echo -n -e "${userchoice}Enter CM instance's password: ${NC}"
read -s PASSWORD
echo
echo
echo "#########################################################################################"

# Step 2: Read input from file
mg_summary=$(cat "$MGSUMMARY")

#call generate token function  before posting payloads
generate_token

# Post curl command
delete_curl() {
	local which_url="$1"
	local UUID="$2"
	local name="$3"
	curl_result=""
    URL="https://${CMIP}${cm_delete_url_map[$which_url]}/$UUID"
	# Perform the POST request using curl and capture the output
    curl_result=$(curl -sk -X DELETE "$URL" --header "Content-Type: application/json" --header "Authorization: Bearer ${CM_TOKEN}")
}

print_curl_result() {
	local sequence="$1"
	local name="$2"
	local UUID="$3"
	local message="$4"
	local font_color="$5"
	echo -e "${fontcolor}$object_name $sequence:"
	echo -e "Name: $name"
	echo -e "UUID: $UUID"
	echo -e "Curl-Response: $message${NC}"
	echo 
	echo "#########################################################################################"
	echo 
}
delete_from_cm() {
    # Output the result
    local which_url="$1"
	local name="$2"
	local UUID="$3"
	local sequence="$4"
	local fontcolor=''
	local object_name="${cm_post_name_map[$which_url]}"
	delete_curl "$which_url" "$UUID"
	((total_try++))
	response_code=$(echo "$curl_result" | jq -r '.status')
	message=$(echo "$curl_result" | jq -r '.message')
	fontcolor="${RED}"
		if [  -n "$response_code" ] && [ "$response_code" != "null" ]; then
			if [ "$response_code" -eq 200 ] || [ "$response_code" -eq 202 ]; then
				fontcolor="$GREEN"
				print_curl_result "$sequence" "$name" "$UUID" "$message" "$fontcolor"
			elif [ "$response_code" -eq 401 ]; then
				print_curl_result "$sequence" "$name" "$UUID" "$message" "$fontcolor"
				if [ "$total_try" -lt "$max_try" ]; then
					echo -e "${fontcolor}Generating token again..."
					generate_token
					((total_try++))
					delete_from_cm "$which_url" "$name" "$UUID" "$sequence"
				else
					echo -e "${fontcolor}Script Aborted, Token expired, Max try limit 2 reached, $message.${NC}"
					echo
					echo "#########################################################################################"
					exit 1
				fi
			else
				print_curl_result "$sequence" "$name" "$UUID" "$message" "$fontcolor"
			fi
		else
			print_curl_result "$sequence" "$name" "$UUID" "$message" "$fontcolor"
		fi
	
} 

rollback_migration() {
	local objectType="$1"
	local object=''
	# Delete Policy from migration_summary.json 
	if [[ $objectType == "POLICY" ]]; then
    # Your code for the case when objectType is "POLICY"
		object=$(echo "$mg_summary" | jq '.migratedObjects.policies')
	elif [[ $objectType == "SC" ]]; then
		object=$(echo "$mg_summary" | jq '.migratedObjects.serviceChains')
	elif [[ $objectType == "IS" ]]; then
		object=$(echo "$mg_summary" | jq '.migratedObjects.inspectionServices')
	fi

	obj_length=$(echo "$object" | jq 'length')
	if [ "$obj_length" -gt 0 ]; then
		# Iterate over the InspectionServices array by index
		for ((i = 0; i < obj_length; i++)); do
			total_try=0
			# Extract the object at index i
			obj=$(echo "$object" | jq --argjson i "$i" 'to_entries | .[$i | tonumber] | "\(.key) \(.value)"')
			obj_key=$(echo "$obj" | cut -d' ' -f1)
			obj_value=$(echo "$obj" | cut -d' ' -f2 | sed 's/"$//')
			if [ -n "$obj_key" ] && [ -n "$obj_value" ]; then
				delete_from_cm  $objectType "$obj_key" "$obj_value" "$i"
			fi
		done
	else
    echo -e "${RED}No ${cm_post_name_map[$objectType]} UUID's found to rollback in provided data.${NC}"
fi
} 

# Prompt the user for confirmation
# Perform the rollback of policies
echo 
echo
read -p "Are you sure you want to rollback all migrated policies? (yes/no): " p_choice
echo
echo
# Check if the user's choice is "yes"
if [ "$p_choice" == "yes" ]; then
	# Perform the deletion
	# Example: delete a file named "example.txt"
	rollback_migration "POLICY"
else
	echo
	echo -e "${RED}Migrated policies's rollback cancelled by user.${NC}"
	echo
	echo "#########################################################################################"
fi

# Perform the rollback of policies
echo
read -p "Do you want to rollback all migrated service chains? (yes/no): " sc_choice
echo
# Check if the user's choice is "yes"
if [ "$sc_choice" == "yes" ]; then
	# Perform the deletion
	# Example: delete a file named "example.txt"
	rollback_migration "SC"
else
	echo
	echo -e "${RED}Migrated service chians's rollback cancelled by user.${NC}"
	echo
	echo "#########################################################################################"

fi

# Perform the rollback of policies
echo
read -p "Do you want to rollback all migrated inspection services? (yes/no): " is_choice
echo
# Check if the user's choice is "yes"
if [ "$is_choice" == "yes" ]; then
	# Perform the deletion
	# Example: delete a file named "example.txt"
	rollback_migration "IS"
else
	echo
	echo -e "${RED}Migrated inspection services's rollback cancelled by user.${NC}"
	echo
	echo "#########################################################################################"

fi

echo
echo "End of script Run!!!!!"
echo
echo "#########################################################################################"
