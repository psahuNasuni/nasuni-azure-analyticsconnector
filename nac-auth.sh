#!/bin/bash
rm -rf /usr/local/bin/config.dat
connector_location=`pwd`
chmod 777 $connector_location/config.dat
mv $connector_location/config.dat /usr/local/bin/
echo "INFO ::: Encrypting config.dat file : START"
nac_manager encrypt -c config.dat -p pass@123456
echo "INFO ::: Encrypting config.dat file : END"
echo "INFO ::: NAC Deployment : STARTED ........."
nac_manager deploy -c config.dat -p pass@123456
echo "INFO ::: NAC Deployment : COMPLETED !!!"
