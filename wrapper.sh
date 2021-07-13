#!/bin/bash 

while read -r label fqdn port
do
    if [[ ! -z $label ]]; then 
    if [[ ! -z $fqdn ]]; then
    if [[ ! -z $port ]]; then 
    if [[ $label != "^#"* ]]; then 
        ./whitelist_by_dynamic_dns.sh $label $fqdn $port | tee -a /var/log/whitelist_by_dynamic_dns.log
    fi
    fi 
    fi
    fi
done < $1
