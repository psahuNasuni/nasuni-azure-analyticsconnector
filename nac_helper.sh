#!/bin/bash
resource_group="$1"
resource_list_json=""
cosmosdb_account_name=""
database_name="Nasuni"
container_name="Metrics"

echo " Argument received is : $resource_group"

get_resource_list () {
    resource_list_json=""
    while [ -z "$resource_list_json" ]; do
        resource_list_json=$(az resource list --resource-group "$resource_group" 2> /dev/null)
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

echo "Trying to retrieve count of objects in cosmos db"

result=$(az cosmosdb sql container show --account-name "$cosmosdb_account_name" --resource-group "$resource_group" --database-name "$database_name" --name "$container_name" 2> /dev/null)
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
