from cProfile import label
import os
import logging
import json
import requests
import azure.functions as func
import re
from azure.appconfiguration import AzureAppConfigurationClient

def remove_special_characters(input_str):
    pattern=r'[^a-zA-Z0-9]'
    output=re.sub(pattern,'',input_str)
    return output

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('INFO ::: Python HTTP trigger function processed a request.')
    ### Connect to an App Configuration store
    connection_string = os.environ["AZURE_APP_CONFIG"]
    logging.info('INFO ::: AZURE_APP_CONFIG:{}'.format(connection_string))
    app_config_client = AzureAppConfigurationClient.from_connection_string(connection_string)
    logging.info('INFO ::: App Config client Creation is successfull')    

    # Get Volume Name
    nmc_volume_name=req.params.get("nmc_volume_name")
    
    retrieved_config_acs_api_key = app_config_client.get_configuration_setting(key='acs-api-key', label='acs-api-key')
    retrieved_config_nmc_api_acs_url = app_config_client.get_configuration_setting(key='nmc-api-acs-url', label='nmc-api-acs-url')
    retrieved_config_datasource_connection_string = app_config_client.get_configuration_setting(key='datasource-connection-string', label=nmc_volume_name+'-datasource-connection-string')
    retrieved_config_destination_container_name = app_config_client.get_configuration_setting(key='destination-container-name', label=nmc_volume_name+'-destination-container-name')
    
    logging.info('Fetching Secretes from Azure App Configuration')
    acs_api_key = retrieved_config_acs_api_key.value
    nmc_api_acs_url = retrieved_config_nmc_api_acs_url.value
    datasource_connection_string = retrieved_config_datasource_connection_string.value
    destination_container_name = retrieved_config_destination_container_name.value

    acs_nmc_volume_name=remove_special_characters(nmc_volume_name)
    # Define the names for the data source, index and indexer
    datasource_name = acs_nmc_volume_name+"dts"
    index_name = "index"
    indexer_name = acs_nmc_volume_name+"indexer"

    logging.info('Setting the endpoint')
    # Setup the endpoint
    endpoint = nmc_api_acs_url
    headers = {'Content-Type': 'application/json',
            'api-key': acs_api_key}
    params = {
        'api-version': '2020-06-30'
    }
    logging.info("Create a data source")
    # Create a data source
    datasourceConnectionString = datasource_connection_string
    datasource_payload = {
        "name": datasource_name,
        "description": "Destination container datasource.",
        "type": "azureblob",
        "credentials": {
            "connectionString": datasourceConnectionString
        },
        "container": {
            "name": destination_container_name
        }
    }
    r = requests.put(endpoint + "/datasources/" + datasource_name,
                    data=json.dumps(datasource_payload), headers=headers, params=params)
    print(r.status_code)
    logging.info("Datasource setup completed: ")

    logging.info("Creating Index setup")
    # Create an index
    index_payload = {
        "name": index_name,
        "fields": [
            {
                "name": "id",
                "type": "Edm.String",
                "key": "true",
                "searchable": "true",
                "filterable": "false",
                "facetable": "false",
                "sortable": "true"
            },
            {
                "name": "content",
                "type": "Edm.String",
                "sortable": "false",
                "searchable": "true",
                "filterable": "false",
                "facetable": "false",
                "retrievable": "true"
            },
            {
                "name": "file_location",
                "type": "Edm.String",
                "searchable": "true",
                "filterable": "false",
                "facetable": "false",
                "retrievable": "true",
                "sortable": "true"
            },
            {
                "name": "volume_name",
                "type": "Edm.String",
                "searchable": "true",
                "filterable": "true",
                "facetable": "false",
                "retrievable": "true",
                "sortable": "true"
            },
            {
                "name": "file_path",
                "type": "Edm.String",
                "searchable": "true",
                "filterable": "true",
                "facetable": "false",
                "retrievable": "true"
            }
        ]
    }

    r = requests.put(endpoint + "/indexes/" + index_name,
                    data=json.dumps(index_payload), headers=headers, params=params)
    logging.info("Indexes setup completed: ")

    logging.info("Creating Indexer setup")
    # Create an indexer
    indexer_payload = {
        "name": indexer_name,
        "dataSourceName": datasource_name,
        "targetIndexName": index_name,
        "fieldMappings": [
            {
                "sourceFieldName": "metadata_storage_path",
                "targetFieldName": "id",
                "mappingFunction":
                {"name": "base64Encode"}
            },
            {
                "sourceFieldName": "content",
                "targetFieldName": "content"
            },
            {
                "sourceFieldName": "metadata_storage_name",
                "targetFieldName": "file_location"
            },
            {
                "sourceFieldName": "volume_name",
                "targetFieldName": "volume_name"
            },
            {
                "sourceFieldName": "metadata_storage_path",
                "targetFieldName": "file_path"
            }
        ],
        "parameters":
        {
            "maxFailedItems": 0,
            "maxFailedItemsPerBatch": 0,
            "configuration":
            {
                "dataToExtract": "contentAndMetadata"
            }
        }
    }

    r = requests.put(endpoint + "/indexers/" + indexer_name,
                    data=json.dumps(indexer_payload), headers=headers, params=params)

    logging.info("Indexer setup completed: ")

    return func.HttpResponse(
            "This NAC Discovery Function Executed Successfully.",
            status_code=200
    )
