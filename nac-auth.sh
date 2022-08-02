#!/bin/bash/
az login --identity
echo "INFO ::: Encrypting config.dat file : STARTED"
nac_manager encrypt -c config.dat -p pass@123456
echo "INFO ::: Encrypting config.dat file : COMPLETED"
echo "INFO ::: NAC Deployment : STARTED"
nac_manager deploy -c config.dat -p pass@123456
