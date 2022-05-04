#!/bin/bash/
# CONFIG_PATH=$1

echo "INFO ::: Encrypting config.dat file : STARTED"
nac_manager encrypt -c config.dat -p pass@123
echo "INFO ::: Encrypting config.dat file : COMPLETED"
echo "INFO ::: NAC Deployment : STARTED"

STATUS=`nac_manager deploy -c config.dat -p pass@123`
echo "$STATUS" 
if [ "$STATUS" == "0" ]; then 
    echo "INFO ::: NAC Deployment : COMPLETED"
else
    echo "ERROR ::: NAC Deployment : FAILED"       
fi 

