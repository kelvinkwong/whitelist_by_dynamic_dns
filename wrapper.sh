#!/bin/bash 

SCRIPT="$(realpath $0)"
SCRIPTDIR="$(dirname $SCRIPT)"

if [[ ! -f $2 ]]
then
    echo "[INFO] $(date)" |& tee -a /var/log/$1.log
    echo "[INFO] $0" |& tee -a /var/log/$1.log
    echo "[ERROR] $2 not found" |& tee -a /var/log/$1.log
    exit 1
fi 

while read -r label fqdn port
do
#    echo LABEL: [$label]
#    echo FQDN: [$fqdn]
#    echo PORT: [$port]
    if [[ ! -z $label ]]; then 
    if [[ ! -z $fqdn ]]; then
    if [[ ! -z $port ]]; then 
    if [[ $label != "^#"* ]]; then 
        $SCRIPTDIR/$1 $label $fqdn $port |& tee -a /var/log/$1.log
    fi
    fi 
    fi
    fi
done < $2
