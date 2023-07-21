#!/bin/bash
NAC_DISCOVERY_FUNCTION_APP="$1"
NMC_VOLUME_NAME="$2"

echo "curl -X GET 'https://${NAC_DISCOVERY_FUNCTION_APP}/api/IndexFunction' -H 'Content-Type:application/json'"
n=0
until [ "$n" -ge 5 ]
do
    COMMAND=$(curl -X GET "https://${NAC_DISCOVERY_FUNCTION_APP}/api/IndexFunction" -H "Content-Type:application/json")
    ### COMMAND=$(curl -X GET "https://nasuni-function-app-9edd87bb.azurewebsites.net/api/IndexFunction" -H "Content-Type:application/json")
    if [[ $COMMAND == "This NAC Discovery Function Executed Successfully." ]];then
        echo "INFO ::: NAC Discovery Function :: ${NAC_DISCOVERY_FUNCTION_APP} :: Executed Successfully. NAC Deployment STARTED . . . . . "
        rm -rf /usr/local/bin/$NMC_VOLUME_NAME.dat
        connector_location=`pwd`
        chmod 777 $connector_location/$NMC_VOLUME_NAME.dat
        mv $connector_location/$NMC_VOLUME_NAME.dat /usr/local/bin/$NMC_VOLUME_NAME.dat
        echo "INFO ::: Encrypting $NMC_VOLUME_NAME.dat file : START"
        nac_manager encrypt -c $NMC_VOLUME_NAME.dat -p pass@123456
        echo "INFO ::: Encrypting $NMC_VOLUME_NAME.dat file : END"
        echo "INFO ::: NAC Deployment : STARTED ........."
        nac_manager deploy -c $NMC_VOLUME_NAME.dat -p pass@123456
        echo "INFO ::: NAC Deployment : COMPLETED !!!"
        break
    else
        n=$((n+1)) 
        echo "INFO ::: Attempt $n :: Could not execute NAC Discovery Function :: ${NAC_DISCOVERY_FUNCTION_APP} :: Re-trying . . . . . "
        if [ $n -ne 5 ]; then
            sleep 75
        fi 
    fi
done