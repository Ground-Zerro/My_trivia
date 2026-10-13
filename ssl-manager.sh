#!/usr/bin/env bash
set -euo pipefail

readonly CONF_DIR=/root/ssl
readonly CONF_FILE=$CONF_DIR/ssl.conf
readonly CERT_ROOT=/root/cert
readonly ACME_WEBROOT=/var/www/acme
readonly IP_RENEW_DAYS=3

export HOME=${HOME:-/root}
readonly ACME_HOME=$HOME/.acme.sh
readonly ACME=$ACME_HOME/acme.sh

readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' PLAIN='\033[0m'

CHALLENGE=()

log()  { printf '%b[INF]%b %s\n' "$GREEN" "$PLAIN" "$*" >&2; }
warn() { printf '%b[WRN]%b %s\n' "$YELLOW" "$PLAIN" "$*" >&2; }
die()  { printf '%b[ERR]%b %s\n' "$RED" "$PLAIN" "$*" >&2; exit 1; }

interactive() { [ -t 0 ]; }

ask() {
    local answer
    interactive || die "$1 is required"
    read -rp "$1${2:+ [$2]}: " answer
    printf '%s' "${answer:-${2:-}}"
}

confirm() {
    local answer
    interactive || return 0
    read -rp "$1 [y/N]: " answer
    [[ $answer == [yY] ]]
}

config_get() {
    [ ! -r "$CONF_FILE" ] || sed -n "s/^$1=//p" "$CONF_FILE"
}

config_set() {
    local key=$1 value=$2
    install -d -m 0700 "$CONF_DIR"
    touch "$CONF_FILE"
    chmod 0600 "$CONF_FILE"
    sed -i "/^$key=/d" "$CONF_FILE"
    printf '%s=%s\n' "$key" "$value" >> "$CONF_FILE"
}

is_ipv4() {
    local octet="(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])"
    [[ $1 =~ ^$octet(\.$octet){3}$ ]]
}

is_ipv6() {
    [[ $1 =~ ^[0-9a-f:]+$ && $1 == *:*:* ]]
}

is_domain() {
    [[ $1 =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z]{2,63}|xn--[a-z0-9-]{2,59})$ ]]
}

install_dependencies() {
    local cmd missing=0
    for cmd in curl socat crontab openssl ss; do
        command -v "$cmd" >/dev/null || missing=1
    done
    [ "$missing" -eq 1 ] || return 0

    log "Installing curl, socat, cron, openssl, iproute2"
    if command -v apt-get >/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get -qq -o DPkg::Lock::Timeout=600 update
        DEBIAN_FRONTEND=noninteractive apt-get -qq -o DPkg::Lock::Timeout=600 -y install curl socat cron openssl ca-certificates iproute2
    elif command -v dnf >/dev/null; then
        dnf -q -y install curl socat cronie openssl iproute
    elif command -v yum >/dev/null; then
        yum -q -y install curl socat cronie openssl iproute
    elif command -v pacman >/dev/null; then
        pacman -Sy --noconfirm --needed curl socat cronie openssl iproute2
    elif command -v zypper >/dev/null; then
        zypper -q -n install curl socat cronie openssl iproute2
    elif command -v apk >/dev/null; then
        apk add -q curl socat openssl iproute2
    else
        die "Unsupported package manager: install curl, socat, cron, openssl and iproute2 manually"
    fi
}

enable_cron() {
    local unit
    if [ -d /run/systemd/system ]; then
        for unit in cron crond cronie; do
            if systemctl list-unit-files "$unit.service" --no-legend 2>/dev/null | grep -q .; then
                systemctl enable --now "$unit.service" >/dev/null 2>&1
                return
            fi
        done
    elif command -v rc-service >/dev/null; then
        rc-update add crond default >/dev/null 2>&1 || true
        rc-service crond start >/dev/null 2>&1 || true
        return
    fi
    die "No cron service found"
}

bootstrap() {
    [ "$(id -u)" -eq 0 ] || die "Run as root"
    install_dependencies
    enable_cron
    if [ ! -x "$ACME" ]; then
        log "Installing acme.sh"
        curl -fsSL https://get.acme.sh | sh >/dev/null 2>&1 || die "acme.sh installation failed"
        [ -x "$ACME" ] || die "acme.sh installation failed"
        "$ACME" --upgrade --auto-upgrade >/dev/null
    fi
    "$ACME" --set-default-ca --server letsencrypt >/dev/null
    "$ACME" --install-cronjob >/dev/null 2>&1
    install -d -m 0700 "$CERT_ROOT"
    sync_http_modes
}

state_dir() {
    local dir
    for dir in "$ACME_HOME/${1}_ecc" "$ACME_HOME/$1"; do
        if [ -f "$dir/$1.conf" ]; then
            printf '%s' "$dir"
            return
        fi
    done
    return 1
}

state_value() {
    local dir
    dir=$(state_dir "$1") || return 0
    sed -n "s/^$2='\{0,1\}\([^']*\)'\{0,1\}$/\1/p" "$dir/$1.conf"
}

has_certificate() {
    local dir
    dir=$(state_dir "$1") && [ -s "$dir/fullchain.cer" ] && [ -s "$dir/$1.key" ]
}

forget_state() {
    "$ACME" --remove -d "$1" >/dev/null 2>&1 || true
    rm -rf "${ACME_HOME:?}/$1" "${ACME_HOME:?}/${1}_ecc"
}

assert_owned() {
    local installed
    installed=$(state_value "$1" Le_RealFullChainPath)
    if [ -n "$installed" ] && [ "$installed" != "$CERT_ROOT/$1/fullchain.pem" ]; then
        die "Certificate for $1 is installed to $installed by another tool (for example the mirror deploy), manage it there"
    fi
}

port80_owner() {
    ss -Hltnp 'sport = :80' | sed -n 's/.*users:(("\([^"]*\)".*/\1/p' | head -n1
}

serves_webroot() {
    local host=$1 token body
    [ -d "$ACME_WEBROOT/.well-known/acme-challenge" ] || return 1
    token=probe-$$-$RANDOM
    printf '%s' "$token" > "$ACME_WEBROOT/.well-known/acme-challenge/$token"
    [[ $host == *:* ]] && host="[$host]"
    body=$(curl -s --max-time 5 --connect-to ::127.0.0.1: "http://$host/.well-known/acme-challenge/$token" || true)
    rm -f "$ACME_WEBROOT/.well-known/acme-challenge/$token"
    [ "$body" = "$token" ]
}

http_mode() {
    local owner
    if ! ss -Hltn 'sport = :80' | grep -q .; then
        printf no
        return
    fi
    if serves_webroot "$1"; then
        printf '%s' "$ACME_WEBROOT"
        return
    fi
    owner=$(port80_owner)
    die "Port 80 is taken by ${owner:-another process}, which does not serve http://$1/.well-known/acme-challenge/ from $ACME_WEBROOT.
      Add to its port-80 server:  location ^~ /.well-known/acme-challenge/ { root $ACME_WEBROOT; }
      and create the directory:   mkdir -p $ACME_WEBROOT/.well-known/acme-challenge"
}

select_http_challenge() {
    local mode
    mode=$(http_mode "$1")
    if [ "$mode" = no ]; then
        CHALLENGE=(--standalone)
        ip -4 addr show scope global 2>/dev/null | grep -q inet || CHALLENGE+=(--listen-v6)
    else
        CHALLENGE=(--webroot "$mode")
    fi
    log "HTTP-01 validation: $(validation_method "$mode")"
}

sync_http_mode() {
    local id=$1 saved mode
    saved=$(state_value "$id" Le_Webroot)
    [[ $saved == no || $saved == /* ]] || return 0
    if ! mode=$(http_mode "$id" 2>/dev/null); then
        warn "$id: port 80 is taken by $(port80_owner) without $ACME_WEBROOT, renewal will fail; run issue for details"
        return 0
    fi
    [ "$mode" != "$saved" ] || return 0
    sed -i "s|^Le_Webroot=.*|Le_Webroot='$mode'|" "$(state_dir "$id")/$id.conf"
    log "$id: renewal switched to $(validation_method "$mode")"
}

sync_http_modes() {
    local id
    for id in $(managed_certificates); do
        sync_http_mode "$id"
    done
}

reload_command() {
    local saved
    saved=$(config_get RELOAD_CMD)
    if interactive; then
        ask "Command to run after every issue/renewal (empty for none)" "$saved"
    else
        printf '%s' "$saved"
    fi
}

install_certificate() {
    local id=$1 dir=$CERT_ROOT/$1 reload
    reload=$(reload_command)
    install -d -m 0700 "$dir"
    if ! "$ACME" --install-cert -d "$id" \
        --key-file "$dir/privkey.pem" \
        --fullchain-file "$dir/fullchain.pem" \
        ${reload:+--reloadcmd "$reload"}; then
        if [ ! -s "$dir/fullchain.pem" ] || [ ! -s "$dir/privkey.pem" ]; then
            die "Installing certificate for $id failed"
        fi
        warn "Certificate installed, but the reload command failed: $reload"
    fi
    chmod 0600 "$dir/privkey.pem"
    chmod 0644 "$dir/fullchain.pem"
    log "Certificate: $dir/fullchain.pem"
    log "Private key: $dir/privkey.pem"
    log "Renewal:     automatic, acme.sh cron job"
}

issue() {
    local id=$1 challenge=$2
    shift 2
    assert_owned "$id"
    if has_certificate "$id"; then
        log "acme.sh already holds a certificate for $id, installing it (use renew to reissue)"
    else
        if state_dir "$id" >/dev/null; then
            warn "Incomplete acme.sh state for $id, starting over"
            forget_state "$id"
        fi
        "$challenge" "$id"
        if ! "$ACME" --issue --keylength ec-256 "$@" "${CHALLENGE[@]}"; then
            forget_state "$id"
            die "Issuing certificate for $id failed"
        fi
    fi
    install_certificate "$id"
}

issue_domain() {
    local domain=${1:-}
    [ -n "$domain" ] || domain=$(ask "Domain name")
    domain=${domain,,}
    is_domain "$domain" || die "Not a domain name: '$domain'"
    getent ahosts "$domain" >/dev/null || die "$domain does not resolve, create its DNS record first"
    issue "$domain" select_http_challenge -d "$domain"
}

detect_ipv4() {
    local url ip
    for url in https://api4.ipify.org https://ipv4.icanhazip.com https://4.ident.me; do
        ip=$(curl -4 -fs --max-time 3 "$url" | tr -d '[:space:]' || true)
        if is_ipv4 "$ip"; then
            printf '%s' "$ip"
            return
        fi
    done
}

issue_ip() {
    local ipv4=${1:-} ipv6=${2:-}
    if [ -z "$ipv4" ]; then
        ipv4=$(ask "Public IPv4 address of this server" "$(detect_ipv4)")
        ipv6=$(ask "Public IPv6 address to include (empty to skip)")
    fi
    ipv6=${ipv6,,}
    is_ipv4 "$ipv4" || die "Not an IPv4 address: '$ipv4'"
    [ -z "$ipv6" ] || is_ipv6 "$ipv6" || die "Not an IPv6 address: '$ipv6'"
    log "IP certificates are short-lived (160 hours) and renew every $IP_RENEW_DAYS days; port 80 must be reachable on $ipv4"
    issue "$ipv4" select_http_challenge -d "$ipv4" ${ipv6:+-d "$ipv6"} \
        --cert-profile shortlived --days "$IP_RENEW_DAYS"
}

cloudflare_challenge() {
    local kind email
    CHALLENGE=(--dns dns_cf)
    [ -z "${CF_Token:-}${CF_Key:-}" ] || return 0
    if ! interactive; then
        grep -q '^SAVED_CF_\(Token\|Key\)=' "$ACME_HOME/account.conf" 2>/dev/null \
            || die "Cloudflare credentials required: export CF_Token, or CF_Key with CF_Email"
        return
    fi
    kind=$(ask "Cloudflare API token (t) or Global API key (g)" t)
    if [[ $kind == [gG] ]]; then
        read -rsp "Global API key: " CF_Key
        printf '\n' >&2
        email=$(ask "Cloudflare account email" "$(config_get CF_EMAIL)")
        config_set CF_EMAIL "$email"
        export CF_Key CF_Email=$email
    else
        read -rsp "API token (Zone.DNS edit): " CF_Token
        printf '\n' >&2
        export CF_Token
    fi
}

issue_cloudflare() {
    local domain=${1:-}
    [ -n "$domain" ] || domain=$(ask "Domain name (certificate covers it and *.$domain)")
    domain=${domain,,}
    is_domain "$domain" || die "Not a domain name: '$domain'"
    issue "$domain" cloudflare_challenge -d "$domain" -d "*.$domain"
}

managed_certificates() {
    find "$CERT_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

pick_certificate() {
    local id=${1:-} ids
    ids=$(managed_certificates)
    [ -n "$ids" ] || die "No certificates under $CERT_ROOT"
    if [ -z "$id" ]; then
        printf '%s\n' "$ids" | nl -w2 -s'. ' >&2
        id=$(ask "Certificate (number or name)")
        [[ $id =~ ^[0-9]+$ ]] && id=$(printf '%s\n' "$ids" | sed -n "${id}p")
    fi
    printf '%s\n' "$ids" | grep -qxF -- "$id" || die "Unknown certificate: '$id'"
    printf '%s' "$id"
}

renew_certificate() {
    local id
    id=$(pick_certificate "${1:-}")
    sync_http_mode "$id"
    "$ACME" --renew -d "$id" --force || die "Renewing $id failed"
    log "Renewed $id"
}

remove_certificate() {
    local id
    id=$(pick_certificate "${1:-}")
    confirm "Revoke and delete the certificate for $id?" || die "Aborted"
    if has_certificate "$id"; then
        "$ACME" --revoke -d "$id" || warn "Revocation failed, deleting anyway"
    fi
    forget_state "$id"
    rm -rf "${CERT_ROOT:?}/$id"
    log "Certificate for $id revoked and deleted"
}

validation_method() {
    case $1 in
        "")     printf 'unknown' ;;
        no)     printf 'HTTP-01 standalone, acme.sh listens on free port 80' ;;
        dns_*)  printf 'DNS-01 %s' "$1" ;;
        *)      printf 'HTTP-01 webroot %s' "$1" ;;
    esac
}

list_certificates() {
    local id cert names
    if [ -z "$(managed_certificates)" ]; then
        log "No certificates under $CERT_ROOT"
        return
    fi
    for id in $(managed_certificates); do
        cert=$CERT_ROOT/$id/fullchain.pem
        printf '%b%s%b\n' "$GREEN" "$id" "$PLAIN"
        if [ ! -s "$cert" ] || [ ! -s "$CERT_ROOT/$id/privkey.pem" ]; then
            printf '  %bcertificate or key missing%b\n' "$RED" "$PLAIN"
            continue
        fi
        names=$(openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null \
            | grep -Eo '(DNS|IP Address):[^,[:space:]]+' | sed 's/^IP Address:/IP:/' | paste -sd' ')
        printf '  Names:       %s\n' "$names"
        printf '  Expires:     %s\n' "$(openssl x509 -in "$cert" -noout -enddate | cut -d= -f2)"
        printf '  Next renew:  %s\n' "$(state_value "$id" Le_NextRenewTimeStr)"
        printf '  Validation:  %s\n' "$(validation_method "$(state_value "$id" Le_Webroot)")"
        printf '  Certificate: %s\n' "$cert"
        printf '  Private key: %s\n' "$CERT_ROOT/$id/privkey.pem"
    done
}

show_status() {
    log "acme.sh $("$ACME" --version | tail -n1), default CA Let's Encrypt"
    if crontab -l 2>/dev/null | grep -q 'acme.sh.* --cron'; then
        log "Renewal cron job: $(crontab -l | grep 'acme.sh.* --cron' | cut -d' ' -f1-5)"
    else
        warn "Renewal cron job is missing"
    fi
    printf '\nAll certificates known to acme.sh (including ones managed by other tools):\n'
    "$ACME" --list
}

configure_reload() {
    local cmd=${1:-} unit
    if [ -z "$cmd" ]; then
        log "Current reload command: $(config_get RELOAD_CMD)"
        cmd=$(ask "New command ('auto' to detect the web server, 'none' to clear)")
    fi
    case $cmd in
        auto)
            cmd=""
            for unit in nginx apache2 httpd caddy haproxy x-ui; do
                if systemctl is-active --quiet "$unit" 2>/dev/null; then
                    cmd="systemctl reload-or-restart $unit"
                    break
                fi
            done
            [ -n "$cmd" ] || die "No running web server detected"
            ;;
        none) cmd="" ;;
    esac
    config_set RELOAD_CMD "$cmd"
    log "Reload command for new certificates: ${cmd:-none}"
}

usage() {
    cat >&2 <<EOF
Usage: $0                                   interactive menu
       $0 issue domain [name]               HTTP-01 certificate for a domain
       $0 issue ip [ipv4] [ipv6]            short-lived certificate for IP addresses
       $0 issue cf [domain]                 DNS-01 via Cloudflare, domain + wildcard
       $0 renew [name]                      force renewal
       $0 remove [name]                     revoke and delete
       $0 list                              certificates under $CERT_ROOT
       $0 status                            acme.sh, cron job, all certificates
       $0 config [command|auto|none]        reload command for new certificates
EOF
    exit 1
}

run_action() {
    set +e
    (set -e; "$@")
    set -e
}

menu() {
    local choice
    while true; do
        printf '\n%bSSL certificate manager%b\n' "$GREEN" "$PLAIN"
        printf '  1. Issue certificate for a domain (HTTP-01)\n'
        printf '  2. Issue certificate for a domain + wildcard (Cloudflare DNS)\n'
        printf '  3. Issue certificate for the server IP address\n'
        printf '  4. Force renew a certificate\n'
        printf '  5. Revoke and delete a certificate\n'
        printf '  6. List certificates\n'
        printf '  7. Status of acme.sh and auto-renewal\n'
        printf '  8. Configure reload command\n'
        printf '  0. Exit\n'
        read -rp "Choose an option: " choice || exit 0
        case $choice in
            1) run_action issue_domain ;;
            2) run_action issue_cloudflare ;;
            3) run_action issue_ip ;;
            4) run_action renew_certificate ;;
            5) run_action remove_certificate ;;
            6) run_action list_certificates ;;
            7) run_action show_status ;;
            8) run_action configure_reload ;;
            0) exit 0 ;;
            *) warn "Unknown option: $choice" ;;
        esac
    done
}

main() {
    case ${1:-} in -h|--help) usage ;; esac
    bootstrap
    case ${1:-} in
        "") menu ;;
        issue)
            case ${2:-} in
                domain) issue_domain "${3:-}" ;;
                ip)     issue_ip "${3:-}" "${4:-}" ;;
                cf)     issue_cloudflare "${3:-}" ;;
                *)      usage ;;
            esac
            ;;
        renew)  renew_certificate "${2:-}" ;;
        remove) remove_certificate "${2:-}" ;;
        list)   list_certificates ;;
        status) show_status ;;
        config) configure_reload "${2:-}" ;;
        *)      usage ;;
    esac
}

main "$@"
