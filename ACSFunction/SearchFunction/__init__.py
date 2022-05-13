import os
import logging
import json
import requests
import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')
    # Extract Key Vault name 
    key_valut = os.environ["AZURE_KEY_VAULT"]
    key_valut_url = f"https://{key_valut}.vault.azure.net/"

    # Set the Azure Cognitive Search Variables
    acs_api_key = "acs-api-key"
    nmc_api_acs_url = "nmc-api-acs-url"
    datasource_connection_string = "datasource-connection-string"
    destination_container_name = "destination-container-name"

    name = req.params.get("name")
    if not name:
        try:
            req_body = req.get_json()
        except ValueError:
            pass
        else:
            name = req_body.get("name")

    if not name:
        return func.HttpResponse(f"Search Query is empty, {name}")
    else:
        logging.info('Fetching Default credentials')
        credential = DefaultAzureCredential()
        client = SecretClient(vault_url=key_valut_url, credential=credential)
        logging.info('Fetching Secretes from Azure Key Vault')
        acs_api_key = client.get_secret(acs_api_key)
        nmc_api_acs_url = client.get_secret(nmc_api_acs_url)
        datasource_connection_string = client.get_secret(datasource_connection_string)
        destination_container_name = client.get_secret(destination_container_name)

        # Define the names for the data source, skillset, index and indexer
        datasource_name = "datasource"
        skillset_name = "skillset"
        index_name = "index"
        indexer_name = "indexer"

        logging.info('Setting the endpoint')
        # Setup the endpoint
        endpoint = nmc_api_acs_url.value
        headers = {'Content-Type': 'application/json',
                'api-key': acs_api_key.value}
        params = {
            'api-version': '2020-06-30'
        }
        logging.info("Create a data source")
        # Create a data source
        datasourceConnectionString = datasource_connection_string.value
        datasource_payload = {
            "name": datasource_name,
            "description": "Demo files to demonstrate cognitive search capabilities.",
            "type": "azureblob",
            "credentials": {
                "connectionString": datasourceConnectionString
            },
            "container": {
                "name": destination_container_name.value
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

        logging.info("Searching URl")
        if name == '*':
            r = requests.get(endpoint + "/indexes/" + index_name +
                 "/docs?&search=*", headers=headers, params=params)
        else:
            # Query the index to return the contents
            r = requests.get(endpoint + "/indexes/" + index_name +
                            "/docs?&search="+ name + '"', headers=headers, params=params)

        logging.info("Search URl setup completed: ")

        return func.HttpResponse(
             json.dumps(r.json(), indent=1),
             status_code=200
        )

