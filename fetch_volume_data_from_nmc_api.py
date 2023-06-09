import pprint
import shlex
import urllib.parse, json, subprocess
import urllib.request as urlrq
import ssl, os
import sys,logging
from datetime import *
import boto3
import requests
from azure.appconfiguration import AzureAppConfigurationClient


if len(sys.argv) < 7:
    print(
        'Usage -- python3 fetch_nmc_api_23-8.py <ip_address> <username> <password> <volume_name> <rid> <web_access_appliance_address>')
    exit()

logging.getLogger().setLevel(logging.INFO)
logging.info(f'date={date}')

if not os.environ.get('PYTHONHTTPSVERIFY', '') and getattr(ssl, '_create_unverified_context', None):
    ssl._create_default_https_context = ssl._create_unverified_context

file_name, endpoint, username, password, volume_name, rid, web_access_appliance_address = sys.argv
try:
    session = boto3.Session(profile_name="nasuni")
    credentials = session.get_credentials()

    credentials = credentials.get_frozen_credentials()
    access_key = credentials.access_key
    secret_key = credentials.secret_key
    access_key_file = open('Zaccess_' + rid + '.txt', 'w')
    access_key_file.write(access_key)

    secret_key_file = open('Zsecret_' + rid + '.txt', 'w')
    secret_key_file.write(secret_key)
    access_key_file.close()
    secret_key_file.close()

except Exception as e:
    print('Runtime error while extracting aws keys')

try:
    #file_name, endpoint, username, password, volume_name, rid, web_access_appliance_address = sys.argv
    logging.info(sys.argv)
    url = 'https://' + endpoint + '/api/v1.1/auth/login/'
    logging.info(url)
    values = {'username': username, 'password': password}
    data = urllib.parse.urlencode(values).encode("utf-8")
    logging.info(data)
    response = urllib.request.urlopen(url, data, timeout=5)
    logging.info(response)
    result = json.loads(response.read().decode('utf-8'))
    logging.info(result)

    cmd = 'curl -k -X GET -H \"Accept: application/json\" -H \"Authorization: Token ' + result[
        'token'] + '\" \"https://' + endpoint + '/api/v1.1/volumes/\"'
    logging.info(cmd)
    args = shlex.split(cmd)
    process = subprocess.Popen(args, shell=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    json_data = json.loads(stdout.decode('utf-8'))
    vv_guid = ''
    for i in json_data['items']:
        if i['name'] == volume_name:
            print(i)
            toc_file = open('nmc_api_data_root_handle_' + rid + '.txt', 'w')
            toc_file.write(i['root_handle'])
            # print('toc_handle',i['root_handle'])
            src_bucket = open('nmc_api_data_source_bucket_' + rid + '.txt', 'w')
            src_bucket.write(i['bucket'])
            # print('source_bucket', i['bucket'])
            v_guid = open('nmc_api_data_v_guid_' + rid + '.txt', 'w')
            v_guid.write(i['guid'])
            vv_guid = i['guid']
    cmd = 'curl -k -X GET -H \"Accept: application/json\" -H \"Authorization: Token ' + result[
        'token'] + '\" \"https://' + endpoint + '/api/v1.1/volumes/filers/shares/\"'
    logging.info(cmd)
    args = shlex.split(cmd)
    process = subprocess.Popen(args, shell=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = process.communicate()
    json_data = json.loads(stdout.decode('utf-8'))
    # My Accelerate Test
    share_url = open('nmc_api_data_external_share_url_' + rid + '.txt', 'w')
    share_url.write(web_access_appliance_address)

    headers = {
        'Accept': 'application/json',
        'Authorization': 'Token {}'.format(result['token'])
    }
    try:
        r = requests.get('https://' + endpoint + '/api/v1.1/volumes/filers/shares/', headers = headers,verify=False)
    except requests.exceptions.RequestException as err:
        logging.error ("OOps: Something Else {}".format(err))
    except requests.exceptions.HTTPError as errh:
        logging.error ("Http Error: {}".format(errh))
    except requests.exceptions.ConnectionError as errc:
        logging.error ("Error Connecting: {}".format(errc))
    except requests.exceptions.Timeout as errt:
        logging.error ("Timeout Error: {}".format(errt))
    except Exception as e:
        logging.error('ERROR: {0}'.format(str(e)))
    
    share_data={}
    name=[]
    path=[]
    for i in r.json()['items']:
        if i['volume_guid'] == vv_guid and i['path']!='\\' and i['browser_access']==True:
            name.append(r""+i['name'].replace('\\','/'))
            path.append(r""+i['path'].replace('\\','/'))
            

    share_data['name']=name
    share_data['path']=path

    logging.info(share_data)

    #Uploading files to blob storage

    connection_string = os.environ["AZURE_APP_CONFIG"]

    storage_account_name=connection_string.split(';')[1].split('=')[1]
    container_name = "nasuni-share-data-container"

    command = "az storage container create \
    --account-name {} \
    --name {} --connection-string {}".format(storage_account_name,container_name,connection_string)
    subprocess.run(command, shell=True)
   
    files=[]

    if len(share_data['name'])==0 or len(share_data['path']) == 0:
        logging.info('dict is empty'.format(share_data))
        share_name = open('nmc_api_data_v_share_name_' + rid + '.txt', 'w')
        share_name.write('-')
        files.append(share_name.name)

        share_path = open('nmc_api_data_v_share_path_' + rid + '.txt', 'w')
        share_path.write('-')
        files.append(share_path.name)

        share_name.close()
        share_path.close()
    else:
        logging.info('dict has data'.format(share_data))
        share_name = open('nmc_api_data_v_share_name_' + rid + '.txt', 'w')
        share_name.write(str((','.join(share_data['name']))))
        files.append(share_name.name)

        share_path = open('nmc_api_data_v_share_path_' + rid + '.txt', 'w')
        share_path.write(str((','.join(share_data['path']))))
        files.append(share_path.name)
        
        share_name.close()
        share_path.close()
    

    for file in files:
        command = "az storage blob upload \
        --account-name {} \
        --container-name {} \
        --name {} \
        --file {}  --connection-string {}".format(storage_account_name,container_name, file, file,connection_string)
        subprocess.run(command, shell=True)


except Exception as e:
    print('Runtime Errors', e)
