#!/bin/bash 

shopt -s expand_aliases
echo [INFO] $(date)
echo [INFO] $0 $@

[[ $EUID -ne 0 ]] && echo [ERROR] needs root, expecting: sudo $0 launch_script_name && exit 999

platform=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
if [[ $platform == 'fedora' ]];
then 
    if [[ $(firewall-cmd --state) == 'running' ]];
    then 
        alias firewall_get_number=firewalld_get_number
        alias firewall_get_ip=firewalld_get_ip
        alias firewall_delete=firewalld_delete
        alias firewall_add=firewalld_add
    else
        echo "[ERROR] only firewalld is supported on Fedora"
    fi
elif [[ $platform == 'ubuntu' ]];
then
    ufw status | grep -q 'Status: active'
    if [[ $? -eq 0 ]]; 
    then 
        alias firewall_get_number=ufw_get_number
        alias firewall_get_ip=ufw_get_ip
        alias firewall_delete=ufw_delete
        alias firewall_add=ufw_add
    else
        echo "[ERROR] only UFW is supported on Ubuntu"
    fi 
else 
    echo "[ERROR] platform ($platform) not supported (expecting fedora or ubuntu)" 
    exit 9
fi

fqdn="$1"
label="$2"
port="$3"

[[ -z $fqdn ]] && echo "[ERROR] Missing FQDN" && echo "[INFO] usage: $0 fqdn label port" && exit 1 
[[ -z $label ]] && echo "[ERROR] Missing label" && echo "[INFO] usage: $0 fqdn label port" && exit 2
[[ -z $port ]] && echo "[ERROR] Missing port" && echo "[INFO] usage: $0 fqdn label port" && exit 3

# firewalld 
firewalld_add () {
    firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$(dig +short $fqdn)\" port protocol=\"tcp\" port=\"$port\" accept log prefix=\"$label\""
    firewall-cmd --reload
}

firewalld_delete () {
    rule="$(firewall-cmd --list-rich-rules | grep $label)"
    firewall-cmd --permanent --remove-rich-rule="$rule"
    firewall-cmd --reload
}

firewalld_get_ip() {
    firewall-cmd --list-rich-rules | grep $label | grep -o -P '(?<=source address=").*(?=" port)'
}

# ufw
ufw_get_number() {
    ufw status numbered | grep $label | awk -v FS="(\[|\])" '{print $2}'
}

ufw_get_ip() {
    ufw status numbered | grep $label | grep $label | awk -v FS="(ALLOW IN|#)" '{print $2}' | sed 's/ //g'
}

ufw_add () {
    ufw allow proto tcp from $(dig +short "$fqdn") to any port $port comment $label
}

ufw_delete () {
    [[ ! -z $(ufw_get_number) ]] && ufw --force delete $(ufw_get_number)
}

# logic
new_ip=$(dig +short "$fqdn")
echo "[INFO] $fqdn = $new_ip"

old_ip=$(firewall_get_ip)
echo "[INFO] Old Source IP: [$old_ip]"

if [[ $old_ip == $new_ip ]] 
then
    echo "[INFO] Same IP"
    exit 0
else
    echo "[INFO] Different IP"
    firewall_delete
    firewall_add
fi
