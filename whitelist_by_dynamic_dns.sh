#!/bin/bash 

shopt -s expand_aliases

DNS="1.1.1.1"

log="/var/log/$(basename $0).log"
info () { 
    echo "[INFO] $@" | tee -a $log
} 

debug () { 
    [[ $DEBUG ]] && echo "[DEBUG] $@" | tee -a $log
}

warn () { 
    echo "[WARN] $@" | tee -a $log
}

error () { 
    echo "[ERROR] $@" | tee -a $log
}

critical () { 
    echo "[CRITICAL] $@" | tee -a $log
    exit $2
}

[[ $EUID -ne 0 ]] && critical "needs root, expecting: sudo $0 whitelist.conf[whitelist_folder]" 999

info $(date)
info $0 $@

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
        error "only firewalld is supported on Fedora"
        exit 1
    fi
elif [[ $platform == 'ubuntu' ]];
then
    /usr/sbin/ufw status | grep -q 'Status: active'
    if [[ $? -eq 0 ]]; 
    then 
        alias firewall_get_number=ufw_get_number
        alias firewall_get_ip=ufw_get_ip
        alias firewall_delete=ufw_delete
        alias firewall_add=ufw_add
    else
        error "UFW not enabled"
        info "[HELP] apt install -y ufw && ufw enable"
        exit 1
    fi 
else 
    error "platform ($platform) not supported (expecting fedora or ubuntu)" 
    exit 9
fi

# firewalld 
firewalld_add () {
    firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$(get_ip)\" port protocol=\"tcp\" port=\"$port\" accept log prefix=\"$label\""
    firewall-cmd --reload
}

firewalld_delete () {
    local rule="$(firewall-cmd --list-rich-rules | grep $label)"
    firewall-cmd --permanent --remove-rich-rule="$rule"
    firewall-cmd --reload
}

firewalld_get_ip() {
    firewall-cmd --list-rich-rules | grep $label | grep -o -P '(?<=source address=").*(?=" port)'
}

# ufw
ufw_get_ip() {
    /usr/sbin/ufw status numbered | grep $label | grep $label | awk -v FS="(ALLOW IN|#)" '{print $2}' | sed 's/ //g'
}

ufw_add () {
    debug "/usr/sbin/ufw allow proto tcp from $(get_ip) to any port $port comment $label"
    /usr/sbin/ufw allow proto tcp from $(get_ip) to any port $port comment $label
}

ufw_delete () {
    local ufw_get_number=$(/usr/sbin/ufw status numbered | sort -r | grep $label | awk -v FS="(\[|\])" '{print $2}')
    for old_rule in $ufw_get_number
    do
        [[ ! -z $old_rule ]] && ufw --force delete $old_rule
    done
}

get_ip () {
    local ip=""
    if [[ $fqdn =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
    then
        # Note it doesnt test the authenticity of the IP, eg. >256 for any of the octets
        ip=$fqdn
    elif [[ $fqdn =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]
    then
        # Note it doesnt test the authenticity of the IP, eg. >256 for any of the octets
        ip=$fqdn
    else
        ip=$(dig +short "$fqdn")
        ip=$(dig +short @"$DNS" "$fqdn")
        [[ -z $ip ]] && ip=$(dig +short @"$DNS" "$fqdn")
    fi
    echo "$ip"
}


whitelist () {
    label="$1"
    fqdn="$2"
    port="$3"

    debug "$LINENO: label fqdn port $label $fqdn $port"

    [[ -z $fqdn ]] || [[ -z $label ]] || [[ -z $port ]] && info "usage: $0 fqdn label port" && return 1

    new_ip=$(get_ip)
    info "$fqdn = $new_ip"

    old_ip=$(firewall_get_ip)
    info "Old Source IP: [$old_ip]"

    if [[ $old_ip == $new_ip ]] 
    then
        info "Same IP"
    else
        info "Different IP"
        firewall_delete
        firewall_add
    fi
}

read_config () { 
    info reading $1
    filename="$(basename $1)"
    owner="${filename%.*}"
    while read -r fqdn port
    do
        [[ $fqdn =~ ^#.* ]] && warn [SKIPPED] $fqdn $port && continue

        label=$port
        [[ "$port" == "443" ]] && label="https"
        [[ "$port" == "22" ]] && label="ssh"

        debug "$LINENO: label fqdn port $label $fqdn $port"
        if [[ ! -z $label ]]; then
        if [[ ! -z $fqdn ]]; then
        if [[ ! -z $port ]]; then
            whitelist "${owner}_${label}" $fqdn $port
        fi
        fi
        fi
    done < $1
}

if [[ -f $1 ]]
then
    read_config $1
elif [[ -d $1 ]] 
then 
    for config in $(find "$1" -name "*.conf")
    do
        read_config $config
    done
else
    error [$1] is not a file or folder
fi
