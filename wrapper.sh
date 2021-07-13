#!/bin/bash 

while read -r label fqdn port
do
    ./whitelist_by_dynamic_dns.sh $label $fqdn $port | tee -a /var/log/whitelist_by_dynamic_dns.log
done < $1
