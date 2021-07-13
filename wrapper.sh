#!/bin/bash 

SCRIPT="$(realpath $0)"
SCRIPTDIR="$(dirname $SCRIPT)"

while read -r label fqdn port
do
    if [[ ! -z $label ]]; then 
    if [[ ! -z $fqdn ]]; then
    if [[ ! -z $port ]]; then 
    if [[ $label != "^#"* ]]; then 
        $SCRIPTDIR/$1 $label $fqdn $port | tee -a /var/log/$1.log
    fi
    fi 
    fi
    fi
done < $2
