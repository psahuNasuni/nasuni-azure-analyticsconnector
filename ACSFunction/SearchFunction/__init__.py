import os
import logging
import json
import requests
import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

def generateResponse(response, access_url, unifs_toc_handle, nmc_volume_name):
    """
    Update the File URL in Response
    """
    updated_values = []
    response = json.loads(response.text)
    extract = lambda x: access_url + x["File_Location"].split("\\")[-1]
    for recordes in response['value']:
        recordes["File_Location"] = extract(recordes)
        recordes["TOC_Handle"] = unifs_toc_handle
        recordes["Volume_Name"] = nmc_volume_name
        updated_values.append(recordes)
    updated_values = {"value": updated_values}
    response.update(updated_values)
    return response


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

    web_access_appliance_address = "web-access-appliance-address"
    nmc_volume_name = "nmc-volume-name"
    unifs_toc_handle = "unifs-toc-handle"

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

        # Construct the access_url
        web_access_appliance_address = client.get_secret(web_access_appliance_address)
        nmc_volume_name = client.get_secret(nmc_volume_name)
        unifs_toc_handle = client.get_secret(unifs_toc_handle)

        access_url = "https://" + web_access_appliance_address.value + "/fs/view/" + nmc_volume_name.value + "/" 

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
                
        logging.info("Searching URl")
        if name == '*':
            r = requests.get(endpoint + "/indexes/" + index_name +
                 "/docs?&search=*", headers=headers, params=params)
        else:
            # Query the index to return the contents
            r = requests.get(endpoint + "/indexes/" + index_name +
                            "/docs?&search="+ name + '"', headers=headers, params=params)

        r = generateResponse(r, access_url, unifs_toc_handle.value, nmc_volume_name.value)
        return func.HttpResponse(
             json.dumps(r, indent=1),
             status_code=200
        )
