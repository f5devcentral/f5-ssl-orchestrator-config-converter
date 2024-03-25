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
declare -A  OUTPUTFILE=''
declare -A  CM_TOKEN=''
declare -A curl_result=''
declare -A max_try=2
declare -A total_try=0
declare -A deployable_is=0
declare -A deployable_sc=0
declare -A deployable_policies=0
declare -A 	irules_map
# Declare an associative array
declare -A inspectionServices_uuid_map
declare -A serviceChains_uuid_map
declare -A policies_uuid_map
declare -A cm_post_url_map=(
	["IS"]="/api/v1/spaces/default/security/inspection-services"
	["SC"]="/api/sslo/v1/service-chains"
	["POLICY"]="/api/sslo/v1//ssl-orchestrator-policies"
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
	echo "\nUsage: ./postToCMScript.sh -cm_ip <IPAddress> -scc_output <path to file>\n\n"
}

#Function to generate the token
generate_token() {
	# Get CM Auth access_token
	encoded_auth=$(echo -n "$USERID:$PASSWORD" | base64)
	CM_TOKEN_URI="$(curl -sk --location 'https://'${CMIP}'/api/login' --header 'Content-Type: application/json' --header 'Authorization: Basic "$encoded_auth"' --data "{\"username\": \"$USERID\", \"password\": \"$PASSWORD\"}")"
	response_code=$(echo "$CM_TOKEN_URI" | jq -r '.status')
	#echo "$CM_TOKEN_URI"
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
		-scc_output)
			OUTPUTFILE="$2"
			shift 2
			;;
		*)
			print_usage
			exit 1
			;;
	esac
done

# Checking for mandatory flags
if [ -z "$CMIP" ] || [ -z "$OUTPUTFILE" ]; then
	print_usage
	exit 1
fi

echo -n "Enter CM instance's user name: "
read -s USERID
echo
echo -n "Enter CM instance's password: "
read -s PASSWORD
echo

# 
# Step 2: Read input from file
sccOutput=$(cat "$OUTPUTFILE")
#echo "$sccOutput"

#call generate token function  before posting payloads
generate_token

# Post curl command
post_is_curl() {
	local which_url="$1"
	local payload="$2"
    curl_result=""
	URL="https://${CMIP}${cm_post_url_map[$which_url]}"
	# Perform the POST request using curl and capture the output
    curl_result=$(curl -sk --location "$URL" --header "Content-Type: application/json" --header "Authorization: Bearer ${CM_TOKEN}" --data "$payload")
}
print_curl_result(){
	local sequence="$1"
	local name="$2"
	local UUID="$3"
	local message="$4"
	local font_color="$5"
	echo -e "$fontcolor$object_name $sequence:"
	echo -e "Name: $name"
	echo -e "UUID: $UUID"
	echo -e "Curl-Response: $message${NC}"
	echo 
	echo "#########################################################################################"
	echo 
}
post_to_cm() {
    # Output the result
    local which_url="$1"
	local name="$2"
	local payload="$3"
	local sequence="$4"
	local fontcolor=''
	local object_name="${cm_post_name_map[$which_url]}"
	post_is_curl "$which_url" "$payload"
	((total_try++))
	UUID=$(echo "$curl_result" | jq -r '.id')
	response_code=$(echo "$curl_result" | jq -r '.status')
	message=$(echo "$curl_result" | jq -r '.message')
	fontcolor="$RED"
		if [ "$UUID" != null ]; then
			if [[ "$which_url" == "IS" ]]; then
				inspectionServices_uuid_map[$name]=$UUID
			elif [[ "$which_url" == "SC" ]]; then
				serviceChains_uuid_map[$name]=$UUID
			else
				policies_uuid_map[$name]=$UUID
			fi
			fontcolor="$GREEN"
			print_curl_result "$sequence" "$name" "$UUID" "$message" "$fontcolor"
		elif [ -n "$response_code" ] && [ "$response_code" -eq 401 ]; then
			echo $total_try
			print_curl_result "$sequence" "$name" "$UUID" "$message" "$fontcolor"
			if [ "$total_try" -lt "$max_try" ]; then
				echo -e "${fontcolor}Generating token again..."
				generate_token
				((total_try++))
				post_to_cm "$which_url" "$name" "$payload" "$sequence"
			else
				echo -e "${fontcolor}Script Aborted, Token expired, Max try limit 2 reached, $message."
				echo
				exit 1
			fi
		else
			print_curl_result "$sequence" "$name" "$UUID" "$message" "$fontcolor"
		fi	
} 

echo 
echo "#########################################################################################"
echo
echo "Getting iRule list to update the UUID and data into the inspection services..."
echo 
#get iRules
get_cm_irules() {
	# Extract the name and id of irules using jq

	URL="https://${CMIP}/api/v1/spaces/default/irules"

	# Perform the curl request and store the result in a variable
	curl_result=$(curl -sk --location "$URL" --header "Content-Type: application/json" --header "Authorization: Bearer ${CM_TOKEN}")

	# # Extract the irules array length
	echo "$curl_result" | jq -c '.["_embedded"].irules[] | {name: .name, id: .versions[0].id, staged: .versions[0].staged, version: .versions[0].version}' | while IFS= read -r line; do
		name=$(echo "$line" | jq -r '.name')
		id=$(echo "$line" | jq -r '.id')
		stage=$(echo "$line" | jq -r '.staged')
		version=$(echo "$line" | jq -r '.version')

		json_object=$(jq -n --arg id "$id" --arg stage "$stage" --arg version "$version" --arg name "$name" '{"created_by": $id, "staged": $stage, "version": $version, "name": $name}')
		irules_map["$name"]=$json_object
	done
}

# Call the iRule map function
get_cm_irules
echo 
echo "iRules are fetched from the CM."
echo
echo "#########################################################################################"
echo
echo "Posting Inspection Services..."
echo
echo
# Post inspection services from the SCC output
is_length=$(echo "$sccOutput" | jq '.sslo.inspectionServices | length')

# Iterate over the InspectionServices array by index
for ((i = 0; i < is_length; i++)); do
    total_try=0
    # Extract the object at index i
    obj=$(jq -r --argjson i "$i" '.sslo.inspectionServices[$i]' <<< "$sccOutput")
    # Access attributes of the object
    status=$(jq -r '.status' <<< "$obj")
    # Print or process attributes as needed
    if [ "$status" = "deployable" ] || [ "$status" = "partially_deployable" ]; then
        irules_array=()
        name=$(jq -r '.name' <<< "$obj")
        ((deployable_is++))
        payload=$(jq -r '.payload' <<< "$obj")
        service_type=$(jq -r '.type' <<< "$payload")
        # iRules UUID replacement
        if [[ "$service_type" == "http-transparent" ]] || [[ "$service_type" == "l3" ]]; then
            ir_length=$(jq '.to.irules | length' <<< "$payload")
            # Iterate over the array by index
            for ((j = 0; j < ir_length; j++)); do
                # Extract the value at index j from the "associated_is" array
                value=$(jq -r --argjson j "$j" '.to.irules[$j]' <<< "$payload")
                # Check if the value exists in the irules_map and is not null
                if [[ -n "${irules_map[$value]}" ]]; then
                    # Replace the value with its corresponding ID from the irules_map
                    irules_array+=("${irules_map[$value]}")
                fi
            done
            # Start building the JSON array object
            json="["
            # Iterate over each element in irules_array
            for ((q = 0; q < ${#irules_array[@]}; q++)); do
                # Add value to JSON array
                json+="${irules_array[q]}"
                # Add comma if it's not the last element
                if ((q != ${#irules_array[@]} - 1)); then
                    json+=", "
                fi
            done
            # Close the JSON array object
            json+="]"
            payload=$(jq --argjson irules_json "$json" '.to.irules = $irules_json' <<< "$payload")
        fi
        # Prepare curl command and post to API
        post_to_cm "IS" "$name" "$payload" "$i"
		unset irules_array
    fi
done

echo "Posting Service chains..."
echo

#Service Chain
# Get the length of the array from SCC output 
sc_length=$(echo "$sccOutput" | jq '.sslo.serviceChains | length')

# Iterate over the array by index
for ((i = 0; i < sc_length; i++)); do
	total_try=0
    # Extract the object at index i
    obj=$(echo "$sccOutput" | jq -r --argjson i "$i" '.sslo.serviceChains[$i]')
    
    # Access attributes of the object
    status=$(echo "$obj" | jq -r '.status')

    # Print or process attributes as needed
    if [ "$status" = "deployable" ]; then
		name=$(echo "$obj" | jq -r '.name')
		((deployable_sc++))
		payload=$(echo "$obj" | jq -r '.payload')
		is_length=$(echo "$payload" | jq '.inspection_services | length')
		# Iterate over the array by index
		for ((j = 0; j < is_length; j++)); do
			# Extract the value at index i from the "associated_is" array
			value=$(echo "$payload" | jq -r --argjson j "$j" '.inspection_services[$j]')

			# Check if the value exists in the id_map and is not null
			if [[ -n "${inspectionServices_uuid_map[$value]}" ]]; then
				# Replace the value with its corresponding ID from the id_map
				payload=$(echo "$payload" | jq --argjson j "$j" --arg id "${inspectionServices_uuid_map[$value]}" '.inspection_services[$j] = $id')
			fi
		done
		# Step 4: Prepare curl command and post to API
		post_to_cm "SC" "$name" "$payload" "$j"
	fi
done

echo "Posting policies..."
echo

#Policies
# Get the length of the array from SCC Output
p_length=$(echo "$sccOutput" | jq '.sslo.policies | length')

# Iterate over the array by index
for ((i = 0; i < p_length; i++)); do
	total_try=0
    # Extract the object at index i
    obj=$(echo "$sccOutput" | jq -r --argjson i "$i" '.sslo.policies[$i]')
    
    # Access attributes of the object
    status=$(echo "$obj" | jq -r '.status')
	
    # Print or process attributes as needed
    
	if [ "$status" = "deployable" ]; then
		((deployable_policies++))
		name=$(echo "$obj" | jq -r '.name')
		payload=$(echo "$obj" | jq -r '.payload')
		if [ "$(echo "$obj" | jq '.associatedObjects | has("serviceChains")')" = true ] && [ "$(echo "$obj" | jq '.associatedObjects.serviceChains')" != "null" ]; then
			r_length=$(echo "$payload" | jq '.trafficRuleSets[0].rules | length')
			for ((r = 0; r < r_length; r++)); do
				# Iterate over each action in the current rule
				for ((j = 0; j < $(echo "$payload" | jq ".trafficRuleSets[0].rules[$r].actions | length"); j++)); do
					# Get the serviceChain value from the current action
					actionType=$(echo "$payload" | jq -r ".trafficRuleSets[0].rules[$r].actions[$j].actionType")
					
					if [ "$actionType" = "SERVICE_CHAIN" ]; then
						serviceChain=$(echo "$payload" | jq -r ".trafficRuleSets[0].rules[$r].actions[$j].serviceChain")
						# Check if the serviceChain exists in the id_map and replace it with the corresponding ID
						if [ -n "${serviceChains_uuid_map[$serviceChain]}" ]; then
							payload=$(echo "$payload" | jq ".trafficRuleSets[0].rules[$r].actions[$j].serviceChain = \"${serviceChains_uuid_map[$serviceChain]}\"")
						fi
					fi
				done
			done
		fi
		# Step 4: Prepare curl command and post to API
		post_to_cm "POLICY" "$name" "$payload" "$i"
	fi
done

echo
echo -e "\033[7mNumber of 'deployable' configuration details in $OUTPUTFILE\033[0m"
echo
echo "Inspection services: $deployable_is"
echo "Services chians: $deployable_sc"
echo "Policies: $deployable_policies"
echo
echo
echo -e "\033[7mNumber of 'created' configuration details on $CMIP\033[0m"
echo
is_count=0
for value in "${inspectionServices_uuid_map[@]}"; do
    if [ -n "$value" ]; then
        ((is_count++))
    fi
done


echo "Inspection Services: $is_count"

sc_count=0
for value in "${serviceChains_uuid_map[@]}"; do
    if [ -n "$value" ]; then
        ((sc_count++))
    fi
done

echo "Service chains: $sc_count"

policy_count=0
for value in "${policies_uuid_map[@]}"; do
    if [ -n "$value" ]; then
        ((policy_count++))
    fi
done

echo "Polices: $policy_count"
echo

echo "#########################################################################################"
echo
echo "Saving migratedobjects name with UUID into the file migrationSummary.json...."
echo

# Function to convert map to JSON
map_to_json() {
    declare -n map=$1
    local json="{"
    for key in "${!map[@]}"; do
        json+="\"$key\":\"${map[$key]}\","
    done
    json="${json%,}" # Remove the trailing comma
    json+="}"
    echo "$json"
}

# Convert each map to JSON
policies_json=$(map_to_json policies_uuid_map)
serviceChains_json=$(map_to_json serviceChains_uuid_map)
inspectionServices_json=$(map_to_json inspectionServices_uuid_map)

# Combine JSON objects into a single JSON
combined_json="{\"inspectionServices\":$inspectionServices_json,\"serviceChains\":$serviceChains_json,\"policies\":$policies_json}"

# Update the existing JSON structure
complete_summary='{"migratedObjects":'$combined_json'}'

# Save JSON to a file
file_path="$PWD/migrationSummary.json"
echo "$complete_summary" | jq '.' > $file_path

echo
echo "migrationSummary.json is saved in the current directory!!!"
echo
echo
echo "Post to provided CM instance is complete. Please verify the post details in printed logs."
echo
echo "#########################################################################################"
