#!/bin/bash
resource_group="$1"
destination_storage_acc_name="$2"
resource_list_json=""
cosmosdb_account_name=""
database_name="Nasuni"
container_name="Metrics"
object_needed=0
cosmosdb_count=0

get_storage_account_object_count(){
    destination_account_key=`az storage account keys list --account-name $destination_storage_acc_name | jq -r '.[0].value'`

    object_needed=`az storage blob list --account-name $destination_storage_acc_name --container-name destcontainer --account-key $destination_account_key --query "length([])"`

    echo "Total required objects in cosmosdb: $object_needed"
}

get_resource_list () {
    resource_list_json=""
    while [ -z "$resource_list_json" ]; do
        resource_list_json=$(az resource list --resource-group "$resource_group" 2> /dev/null)
        echo "Retrieving resource list"
    done
    echo "Retrieved resource list"

}

get_cosmosdb_document_count() {
    echo "Trying to retrieve count of objects in cosmos db"
    result=$(az cosmosdb sql container show --account-name "$cosmosdb_account_name" --resource-group "$resource_group" --database-name "$database_name" --name "$container_name" 2> /dev/null)
    cosmosdb_count=$(echo "$result" | jq -r '.resource.statistics[].documentCount' | awk '{s+=$1} END {print s}')
}

stop_nac_process() {
    pgrep -f 'nac_manager' > nac_manager_pids.tmp
    while read -r pid; do
        echo "Killing process with PID: $pid"
        kill "$pid"
    done < nac_manager_pids.tmp
    rm nac_manager_pids.tmp
    echo "aborting nac process"
    exit 1
}


get_resource_list

current_minute=1
while [ -z "$cosmosdb_account_name" ]; do

    cosmosdb_account_name=$(echo "$resource_list_json" | jq -r '.[] | select(.type == "Microsoft.DocumentDb/databaseAccounts") | .name')
    echo "Cosmos DB Account Name: $cosmosdb_account_name"

    if [ -n "$cosmosdb_account_name" ]; then
        echo "Cosmos DB has been created."
        break
    else
        echo "Check $current_minute Cosmos DB has not been created yet."
        sleep 5
        current_minute=$((current_minute + 1))
        get_resource_list
        fi
done

sleep 600

while true; do
  state=$(az cosmosdb show --name "$cosmosdb_account_name" --resource-group "$resource_group" --query "provisioningState" | tr -d '"')
  
echo "state is : $state"

  if [ -n "$state" ]; then

  case "$state" in
  "Succeeded")
    echo "Cosmos DB provisioning state is Succeeded."
    break
    ;;
  "Creating" | "Updating")
    echo "Cosmos DB provisioning state is $state. Waiting for 1 minute to re-check"
    sleep 60
    ;;
  *)
    echo "Cosmos DB provisioning state is $state. Exiting..."
    exit 1
    ;;
esac

  fi
done

get_storage_account_object_count
get_cosmosdb_document_count

if [ -z "$object_needed" ]; then
        echo "No data found in destination storage account."
        stop_nac_process
    fi


if [ "$cosmosdb_count" -lt 1 ]; then
        echo "Document count is less than 1. Exiting the script."
        stop_nac_process
else
    echo "Count of objects is $cosmosdb_count . Waiting for count to reach $object_needed."

    previous_count="$cosmosdb_count"

    while [ "$cosmosdb_count" -lt "$object_needed" ]; do
        sleep 120

        get_cosmosdb_document_count
        new_count=$cosmosdb_count
       
        if [ "$new_count" -eq "$previous_count" ]; then
            echo "Subsequent Count of objects in cosmosdb are same. Exiting the script."
            stop_nac_process
            exit 1
        fi

        echo "Document Count in $database_name/$container_name: $cosmosdb_count"
        previous_count="$new_count"
    done

    echo "Count of objects has reached $object_needed. Exiting the script."
    fi
