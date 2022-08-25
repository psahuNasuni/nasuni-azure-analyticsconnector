from cProfile import label
import os
import logging
import json
import requests
import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.appconfiguration import AzureAppConfigurationClient, ConfigurationSetting


def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('INFO ::: Python HTTP trigger function processed a request.')
    ### Connect to an App Configuration store
    connection_string = os.getenv('ACS_ADMIN_APP_CONFIG_CONNECTION_STRING')
    logging.info('INFO ::: ACS_ADMIN_APP_CONFIG_CONNECTION_STRING:{}'.format(connection_string))
    app_config_client = AzureAppConfigurationClient.from_connection_string(connection_string)
    logging.info('INFO ::: App Config client Creation is successfull')    

    retrieved_config_acs_api_key = app_config_client.get_configuration_setting(key='acs-api-key', label='acs-api-key')
    retrieved_config_nmc_api_acs_url = app_config_client.get_configuration_setting(key='nmc-api-acs-url', label='nmc-api-acs-url')
    retrieved_config_datasource_connection_string = app_config_client.get_configuration_setting(key='datasource-connection-string', label='datasource-connection-string')
    retrieved_config_destination_container_name = app_config_client.get_configuration_setting(key='destination-container-name', label='destination-container-name')
    retrieved_config_nmc_volume_name = app_config_client.get_configuration_setting(key='nmc-volume-name', label='nmc-volume-name')
    retrieved_config_unifs_toc_handle = app_config_client.get_configuration_setting(key='unifs-toc-handle', label='unifs-toc-handle')
    retrieved_config_web_access_appliance_address = app_config_client.get_configuration_setting(key='web-access-appliance-address', label='web-access-appliance-address')
    
    logging.info('Fetching Secretes from Azure App Configuration')
    acs_api_key = retrieved_config_acs_api_key.value
    nmc_api_acs_url = retrieved_config_nmc_api_acs_url.value
    datasource_connection_string = retrieved_config_datasource_connection_string.value
    destination_container_name = retrieved_config_destination_container_name.value
    nmc_volume_name = retrieved_config_nmc_volume_name.value
    unifs_toc_handle = retrieved_config_unifs_toc_handle.value
    web_access_appliance_address = retrieved_config_web_access_appliance_address.value

    logging.info('acs_api_key:{}'.format(acs_api_key))
    logging.info('nmc_api_acs_url:{}'.format(nmc_api_acs_url))
    logging.info('datasource_connection_string:{}'.format(datasource_connection_string))
    logging.info('destination_container_name:{}'.format(destination_container_name))
    logging.info('nmc_volume_name:{}'.format(nmc_volume_name))
    logging.info('unifs_toc_handle:{}'.format(unifs_toc_handle))
    logging.info('web_access_appliance_address:{}'.format(web_access_appliance_address))

    access_url = "https://" + web_access_appliance_address + "/fs/view/" + nmc_volume_name + "/" 
    logging.info('access_url:{}'.format(access_url))
    #############################################################

    # Define the names for the data source, skillset, index and indexer
    datasource_name = "datasource"
    skillset_name = "skillset"
    index_name = "index"
    indexer_name = "indexer"

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
        "description": "Demo files to demonstrate cognitive search capabilities.",
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

    logging.info("Setting Skillset: ")
    # Create a skillset
    skillset_payload = {
        "name": skillset_name,
        "description":
        "Extract entities, detect language and extract key-phrases",
        "skills":
        [
            {
                "@odata.type": "#Microsoft.Skills.Text.V3.EntityRecognitionSkill",
                "categories": ["Organization"],
                "defaultLanguageCode": "en",
                "inputs": [
                    {
                        "name": "text",
                        "source": "/document/content"
                    }
                ],
                "outputs": [
                    {
                        "name": "organizations",
                        "targetName": "organizations"
                    }

                ]
            },
            {
                "@odata.type": "#Microsoft.Skills.Text.LanguageDetectionSkill",
                "inputs": [
                    {
                        "name": "text",
                        "source": "/document/content"
                    }
                ],
                "outputs": [
                    {
                        "name": "languageCode",
                        "targetName": "languageCode"
                    }
                ]
            },
            {
                "@odata.type": "#Microsoft.Skills.Text.SplitSkill",
                "textSplitMode": "pages",
                "maximumPageLength": 4000,
                "inputs": [
                    {
                        "name": "text",
                        "source": "/document/content"
                    },
                    {
                        "name": "languageCode",
                        "source": "/document/languageCode"
                    }
                ],
                "outputs": [
                    {
                        "name": "textItems",
                        "targetName": "pages"
                    }
                ]
            },
            {
                "@odata.type": "#Microsoft.Skills.Text.KeyPhraseExtractionSkill",
                "context": "/document/pages/*",
                "inputs": [
                    {
                        "name": "text",
                        "source": "/document/pages/*"
                    },
                    {
                        "name": "languageCode",
                        "source": "/document/languageCode"
                    }
                ],
                "outputs": [
                    {
                        "name": "keyPhrases",
                        "targetName": "keyPhrases"
                    }
                ]
            }
        ]
    }

    r = requests.put(endpoint + "/skillsets/" + skillset_name,
                    data=json.dumps(skillset_payload), headers=headers, params=params)
    logging.info("Skill set completed: ")

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
                "facetable": "false"
            },
            {
                "name": "languageCode",
                "type": "Edm.String",
                "searchable": "true",
                "filterable": "false",
                "facetable": "false"
            },
            {
                "name": "keyPhrases",
                "type": "Collection(Edm.String)",
                "searchable": "true",
                "filterable": "false",
                "facetable": "false"
            },
            {
                "name": "organizations",
                "type": "Collection(Edm.String)",
                "searchable": "true",
                "sortable": "false",
                "filterable": "false",
                "facetable": "false"
            },
            {
                "name": "File_Location",
                "type": "Edm.String",
                "searchable": "true",
                "filterable": "false",
                "facetable": "false",
                "retrievable": "true",
                "sortable": "true"
            },
            {
                "name": "TOC_Handle",
                "type": "Edm.String",
                "searchable": "false",
                "filterable": "false",
                "facetable": "false",
                "retrievable": "true",
                "sortable": "true"
            },
            {
                "name": "Volume_Name",
                "type": "Edm.String",
                "searchable": "false",
                "filterable": "false",
                "facetable": "false"
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
        "skillsetName": skillset_name,
        "schedule" : { "interval" : "PT50M" },
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
                "targetFieldName": "File_Location"
            }
        ],
        "outputFieldMappings":
        [
            {
                "sourceFieldName": "/document/organizations",
                "targetFieldName": "organizations"
            },
            {
                "sourceFieldName": "/document/pages/*/keyPhrases/*",
                "targetFieldName": "keyPhrases"
            },
            {
                "sourceFieldName": "/document/languageCode",
                "targetFieldName": "languageCode"
            },
            {
                "sourceFieldName": "/document/languageCode",
                "targetFieldName": "TOC_Handle"
            },
            {
                "sourceFieldName": "/document/languageCode",
                "targetFieldName": "Volume_Name"
            }
        ],
        "parameters":
        {
            "maxFailedItems": -1,
            "maxFailedItemsPerBatch": -1,
            "configuration":
            {
                "dataToExtract": "contentAndMetadata",
                "imageAction": "generateNormalizedImages"
            }
        }
    }

    r = requests.put(endpoint + "/indexers/" + indexer_name,
                    data=json.dumps(indexer_payload), headers=headers, params=params)

    logging.info("Indexer setup completed: ")

    return func.HttpResponse(
            "This HTTP triggered function executed successfully.",
            status_code=200
    )
