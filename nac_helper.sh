#!/bin/bash
resource_group="$1"
destination_storage_acc_name="$2"
resource_list_json=""
cosmosdb_account_name=""
database_name="Nasuni"
container_name="Metrics"
scontainer_object_count=0
cosmosdb_count=0

stop_nac_process() {
    pgrep -f 'nac_manager' > nac_manager_pids.tmp
    while read -r pid; do
        echo "INFO ::: Killing process with PID: $pid"
        kill "$pid"
    done < nac_manager_pids.tmp
    rm nac_manager_pids.tmp
    echo "ERROR ::: aborting nac process"
    exit 1
}

get_storage_account_object_count(){
	NEXTMARKER=""
	destination_storage_conn_str=$(az storage account show-connection-string --name ${destination_storage_acc_name} | jq -r '.connectionString')
	scontainer_object_count=0

    echo "INFO ::: Checking count of objects in cosmosdb"
	while [ "$NEXTMARKER" != "null" ]; do
		if [ -n "$NEXTMARKER" ]; then

			FILES=$(az storage blob list -c destcontainer --marker $NEXTMARKER --show-next-marker --account-name $destination_storage_acc_name --connection-string "$destination_storage_conn_str" --output json)
		else

			FILES=$(az storage blob list -c destcontainer --show-next-marker --account-name $destination_storage_acc_name --connection-string "$destination_storage_conn_str" --output json)
		fi

		current_blob_count=$(echo "$FILES" | jq length)
		scontainer_object_count=$((scontainer_object_count + current_blob_count))
		NEXTMARKER=$(echo $FILES | jq -r '.[-1].nextMarker')
	done
	scontainer_object_count=$((scontainer_object_count - 1))
	echo "INFO ::: Count of objects in destination storage container: $scontainer_object_count"
	
}

get_resource_list () {
    resource_list_json=""
    max_attempts=3
    current_attempt=1

    while [ -z "$resource_list_json" ] && [ "$current_attempt" -le "$max_attempts" ]; do
        sleep 60
        resource_list_json=$(az resource list --resource-group "$resource_group" 2> /dev/null)
        echo "INFO ::: Retrieving resource list (Attempt $current_attempt)"
        
        if [ -z "$resource_list_json" ]; then      
            current_attempt=$((current_attempt+1))
        fi
    done

    if [ -z "$resource_list_json" ]; then
        echo "ERROR ::: Failed to retrieve resource list after $max_attempts attempts. Exiting script."
        stop_nac_process
        exit 1
    else
        echo "INFO ::: Successfully retrieved resource list"
    fi
}

check_storage_account_existence() {
    storage_account_name="$1"

    if az storage account show --name "$storage_account_name" --query "name" --output tsv 2>/dev/null; then
        echo "INFO ::: Storage account '$storage_account_name' exists."
    else
        echo "ERROR ::: Storage account '$storage_account_name' not found. Exiting script."
        stop_nac_process
        exit 1        
    fi
}

get_cosmosdb_document_count() {
    echo "INFO ::: Trying to retrieve count of objects in cosmos db"
    result=$(az cosmosdb sql container show --account-name "$cosmosdb_account_name" --resource-group "$resource_group" --database-name "$database_name" --name "$container_name" 2> /dev/null)
    cosmosdb_count=$(echo "$result" | jq -r '.resource.statistics[].documentCount' | awk '{s+=$1} END {print s}')
    echo "INFO ::: Count of objects in cosmosdb: $scontainer_object_count"

}


get_cosmosdb_state() {
    while true; do
    state=$(az cosmosdb show --name "$cosmosdb_account_name" --resource-group "$resource_group" --query "provisioningState" | tr -d '"')
    echo "INFO ::: CosmosDB's state is : $state"

        if [ -n "$state" ]; then
            case "$state" in
            "Succeeded")
                echo "INFO ::: Cosmos DB provisioning state is Succeeded."
                break
                ;;
            "Creating" | "Updating")
                echo "INFO ::: Cosmos DB provisioning state is $state. Waiting for 1 minute to re-check"
                sleep 60
                ;;
            *)
                echo "WARNING ::: Cosmos DB provisioning state is $state. Exiting nac_helper script..."
                exit 1
                ;;
            esac
        fi
    done
}

check_storage_account_existence "$destination_storage_acc_name"
get_resource_list

current_minute=1
while [ -z "$cosmosdb_account_name" ]; do

    cosmosdb_account_name=$(echo "$resource_list_json" | jq -r '.[] | select(.type == "Microsoft.DocumentDb/databaseAccounts") | .name')
    echo "INFO ::: Cosmos DB Account Name: $cosmosdb_account_name"

    if [ -n "$cosmosdb_account_name" ]; then
        echo "INFO ::: Cosmos DB has been created."
        break
    else
        echo "INFO ::: Check $current_minute: Cosmos DB has not been created yet."
        sleep 60
        current_minute=$((current_minute + 1))
        get_resource_list
        fi
done

sleep 600

get_cosmosdb_state
get_storage_account_object_count
get_cosmosdb_document_count

if [ -z "$scontainer_object_count" ]; then
        echo "ERROR ::: No data found in destination storage account."
        stop_nac_process
    fi


if [ "$cosmosdb_count" -lt 1 ]; then
        echo "ERROR ::: Document count in cosmosdb is less than 1. Exiting the script."
        stop_nac_process
else
    counter=0
    max_checks=5
    previous_container_count=0
    previous_db_count=0


    while [ "$counter" -lt "$max_checks" ]; do
        sleep 100
        get_cosmosdb_state

        get_storage_account_object_count
        get_cosmosdb_document_count
        new_db_count="$cosmosdb_count"
        new_container_count="$scontainer_object_count"

        if [ "$new_container_count" -eq "$previous_container_count" ]; then
            if [ "$new_db_count" -eq "$previous_db_count" ]; then

                echo "ERROR ::: Subsequent Count of objects in cosmosdb and destination container are same. Exiting the nac_manager script."
                stop_nac_process
                exit 1
            fi
        fi

        echo "INFO ::: Document Count in $database_name/$container_name: $cosmosdb_count"
        echo "INFO ::: Document Count in $destination_storage_acc_name/destcontainer:$scontainer_object_count"
        
        counter=$((counter+1))
        previous_db_count="$new_db_count"
        previous_container_count="$new_container_count"

    done

    echo "INFO ::: Exiting the nac_helper script."
fi
