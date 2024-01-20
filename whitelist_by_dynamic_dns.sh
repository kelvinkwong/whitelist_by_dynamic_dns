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

if grep -q 'fedora' /etc/os-release; then
    if [[ $(firewall-cmd --state) == 'running' ]]; then
        alias firewall_get_number=firewalld_get_number
        alias firewall_get_ip=firewalld_get_ip
        alias firewall_delete=firewalld_delete
        alias firewall_add=firewalld_add
        platform='fedora'
    else
        error "only firewalld is supported on Fedora"
        exit 1
    fi
elif grep -q 'ubuntu' /etc/os-release; then
    if /usr/sbin/ufw status | grep -q 'Status: active'; then
        alias firewall_get_number=ufw_get_number
        alias firewall_get_ip=ufw_get_ip
        alias firewall_delete=ufw_delete
        alias firewall_add=ufw_add
        platform='ubuntu'
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
    local ip=$1

    rule="rule family=\"ipv4\" source address=\"$ip\" port protocol=\"${protocol}\" port=\"$port\" accept log prefix=\"$label\""
    command="firewall-cmd --permanent --add-rich-rule=\"$rule\""
    info $command
    eval $command
#    firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$(get_ip)\" port protocol=\"${protocol}\" port=\"$port\" accept log prefix=\"$label\""
    firewall-cmd --reload
}

firewalld_delete () {
    local rule="$(firewall-cmd --list-rich-rules | grep $label)"
    firewall-cmd --permanent --remove-rich-rule="$rule"
    firewall-cmd --reload
}

firewalld_get_ip() {
#    firewall-cmd --list-rich-rules | grep $label | grep -o -P '(?<=source address=").*(?=" port)'
    firewall-cmd --list-rich-rules | grep $label | grep -o "[0-9]*\\.[0-9]*\\.[0-9]*\\.[0-9]*"
}

# ufw
ufw_get_ip() {
    # /usr/sbin/ufw status numbered | grep $label | grep $label | awk -v FS="(ALLOW IN|#)" '{print $2}' | sed 's/ //g'
    /usr/sbin/ufw status numbered | grep $label | grep -o "[0-9]*\\.[0-9]*\\.[0-9]*\\.[0-9]*"
}

ufw_add () {
    local ip=$1

    command="/usr/sbin/ufw allow proto ${protocol} from $ip to any port $port comment $label"
    info $command
    eval $command
}

ufw_delete () {
    local ufw_get_number=$(/usr/sbin/ufw status numbered | sort -r | grep $label | awk -v FS="(\[|\])" '{print $2}')
    for old_rule in $ufw_get_number
    do
        [[ ! -z $old_rule ]] && ufw --force delete $old_rule
    done
}

query_dns () {
    local fqdn=$1

    # https://serverfault.com/questions/965368/how-do-i-ask-dig-to-only-return-the-ip-from-a-cname-record#comment1435301_965488
    # dig +noall +yaml +answer @"$DNS" "$fqdn" | awk '/IN\s+A/ {print $NF}'

    # https://serverfault.com/a/965488
    curl --silent -H 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=${fqdn}&type=A" | jq -r -c '.Answer[] | select(.type == 1) | .data'
}

get_ip () {
    local fqdn=$1
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
        # ip=$(dig +short @"$DNS" "$fqdn")
        ip=$(query_dns $fqdn)
        [[ -z $ip ]] && sleep 5 && ip=$(query_dns $fqdn)
    fi
    echo "$ip"
}


whitelist () {
    local label="$1"
    local fqdn="$2"
    local port="$3"
    local protocol="$4"

    debug "$LINENO: label [$label]"
    debug "$LINENO: fqdn  [$fqdn]"
    debug "$LINENO: port  [$port]"
    debug "$LINENO: protocol  [$protocol]"

    new_ip=$(get_ip $fqdn)
    old_ip=$(firewall_get_ip)
    info "$fqdn, old:$old_ip, new:$new_ip, port:${port}/${protocol}"

    if [[ $old_ip == $new_ip ]] 
    then
        info "Same IP"
    else
        info "Different IP"
        firewall_delete
        firewall_add $new_ip
    fi
}

read_config () { 
    info reading $1
    filename="$(basename $1)"
    owner="${filename%.*}"
    while IFS=, read port fqdn comment
    do
        [[ -z $fqdn ]] && warn [SKIPPED1] [$port] [$fqdn] && continue
        [[ -z $port ]] && warn [SKIPPED2] [$port] [$fqdn] && continue
        [[ $port =~ ^#.* ]] && warn [SKIPPED3] [$port] [$fqdn] && continue

        protocol=$(echo $port | awk -F '/' '{print $2}')
        port=$(echo $port | awk -F '/' '{print $1}')

        [[ -z "${protocol}" ]] && protocol='tcp'

        local label=$port
        [[ "$port" == "21" ]] && label="ftp_request"
        [[ "$port" == "22" ]] && label="ssh"
        [[ "$port" == "80" ]] && label="http"
        [[ "$port" == "443" ]] && label="https"
        [[ "$port" == "21000" ]] && label="ftp_data"
        [[ "$port" == "1194" ]] && label="openvpn"
        [[ "$port" == "51820" ]] && label="wireguard"

        debug "$LINENO: label [$label]"
        debug "$LINENO: fqdn  [$fqdn]"
        debug "$LINENO: port  [$port]"
        debug "$LINENO: protocol  [$protocol]"

        local OIFS=$IFS
        local IFS=' '
        local fqdns=($fqdn)
        IFS=$OIFS
        local occurance=0
        for fqdn in ${fqdns[@]}
        do
            occurance=$((occurance + 1))
            whitelist "${owner}_${label}_${occurance}" $fqdn $port $protocol
        done
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
