#!/bin/bash
resource_group="$1"
resource_list_json=""
cosmosdb_account_name=""
database_name="Nasuni"
container_name="Metrics"

echo " Argument received is : $resource_group"

get_resource_list () {
    $resource_list_json=""
    while [ -z "$resource_list_json" ]; do
        resource_list_json=$(az resource list --resource-group "$resource_group")
    done
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
        sleep 60
        current_minute=$((current_minute + 1))
        get_resource_list
        fi
done

sleep 

db_state=$(az cosmosdb show --name "$cosmosdb_account_name" --resource-group "$resource_group" --query "provisioningState" -o tsv)

while true; do
  db_state=$(az cosmosdb show --name "$cosmosdb_name" --resource-group "$resource_group" --query "provisioningState" -o tsv)
  
  if [ "$db_state" == "Succeeded" ]; then
    echo "Cosmos DB provisioning is completed"
    break
  elif [ "$db_state" == "Creating" ] || [ "$db_state" == "Updating" ]; then
    echo "Cosmos DB provisioning state is $db_state. Waiting for 1 minute to re-check the state"
    sleep 60
  else
    echo "Cosmos DB provisioning state is $db_state. Exiting the nac_helper script"
    exit 1
  fi
done

echo "Trying to retrieve count of objects in cosmos db"

result=$(az cosmosdb sql container show --account-name "$cosmosdb_account_name" --resource-group "$resource_group" --database-name "$database_name" --name "$container_name")
count=$(echo "$result" | jq -r '.resource.statistics[].documentCount' | awk '{s+=$1} END {print s}')

echo "Document Count in $database_name/$container_name: $count"

if [ "$count" -lt 1 ]; then
        echo "Document count is less than 1. Exiting the script."
        
        pgrep -f 'nac_manager' > nac_manager_pids.tmp
        while read -r pid; do
            echo "Killing process with PID: $pid"
            kill "$pid"
        done < nac_manager_pids.tmp
        rm nac_manager_pids.tmp
        exit 1

else
    echo "Count of objects are greater than 1. No issues"
    fi