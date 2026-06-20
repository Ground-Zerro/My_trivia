#!/bin/bash

SCRIPT_VERSION="1.0.0"
CONF_DIR="/root/ssl"
CONF_FILE="${CONF_DIR}/ssl.conf"
CERT_BASE_DIR="/root/cert"

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

LOGD() { echo -e "${yellow}[DEG] $* ${plain}"; }
LOGE() { echo -e "${red}[ERR] $* ${plain}"; }
LOGI() { echo -e "${green}[INF] $* ${plain}"; }
LOGW() { echo -e "${yellow}[WRN] $* ${plain}"; }

is_port_in_use() {
    local port="$1"
    if command -v ss > /dev/null 2>&1; then
        ss -ltn 2> /dev/null | awk -v p=":${port}$" '$4 ~ p {exit 0} END {exit 1}'
        return
    fi
    if command -v netstat > /dev/null 2>&1; then
        netstat -lnt 2> /dev/null | awk -v p=":${port} " '$4 ~ p {exit 0} END {exit 1}'
        return
    fi
    if command -v lsof > /dev/null 2>&1; then
        lsof -nP -iTCP:${port} -sTCP:LISTEN > /dev/null 2>&1 && return 0
    fi
    return 1
}

is_ipv4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 0 || return 1; }
is_ipv6() { [[ "$1" =~ : ]] && return 0 || return 1; }
is_domain() { [[ "$1" =~ ^([A-Za-z0-9](-*[A-Za-z0-9])*\.)+(xn--[a-z0-9]{2,}|[A-Za-z]{2,})$ ]] && return 0 || return 1; }

acme_listen_flag() {
    if ip -4 addr show scope global 2> /dev/null | grep -q "inet "; then
        echo ""
    else
        echo "--listen-v6"
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [Default $2]: " temp
        [[ "${temp}" == "" ]] && temp=$2
    else
        read -rp "$1 [y/n]: " temp
    fi
    [[ "${temp}" == "y" || "${temp}" == "Y" ]] && return 0 || return 1
}

before_show_menu() {
    echo && echo -n -e "${yellow}Press enter to return to the menu: ${plain}" && read -r temp
    ssl_menu
}

[[ $EUID -ne 0 ]] && LOGE "ERROR: You must be root to run this script! \n" && exit 1

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS." >&2
    exit 1
fi

os_version=""
os_version=$(grep "^VERSION_ID" /etc/os-release | cut -d '=' -f2 | tr -d '"' | tr -d '.')

mkdir -p "${CONF_DIR}" "${CERT_BASE_DIR}"

load_config() {
    RELOAD_CMD=""
    CERT_DAYS=""
    DEFAULT_WEB_PORT="80"
    DEFAULT_CF_EMAIL=""
    if [[ -f "${CONF_FILE}" ]]; then
        source "${CONF_FILE}"
    fi
}

save_config() {
    cat > "${CONF_FILE}" <<EOF
RELOAD_CMD="${RELOAD_CMD}"
CERT_DAYS="${CERT_DAYS}"
DEFAULT_WEB_PORT="${DEFAULT_WEB_PORT}"
DEFAULT_CF_EMAIL="${DEFAULT_CF_EMAIL}"
EOF
    chmod 600 "${CONF_FILE}"
}

detect_ip() {
    local URL_lists=(
        "https://api4.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://v4.api.ipinfo.io/ip"
        "https://ipv4.myexternalip.com/raw"
        "https://4.ident.me"
        "https://check-host.net/ip"
    )
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        local response=$(curl -s -w "\n%{http_code}" --max-time 3 "${ip_address}" 2> /dev/null)
        local http_code=$(echo "$response" | tail -n1)
        local ip_result=$(echo "$response" | head -n-1 | tr -d '[:space:]"')
        if [[ "${http_code}" == "200" && "${ip_result}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            server_ip="${ip_result}"
            break
        fi
    done
    echo "${server_ip}"
}

prompt_ip() {
    local server_ip
    server_ip=$(detect_ip)
    if [[ -z "$server_ip" ]]; then
        LOGW "Could not auto-detect server IP."
        while [[ -z "$server_ip" ]]; do
            read -rp "Please enter your server's public IPv4 address: " server_ip
            server_ip="${server_ip// /}"
            if [[ ! "$server_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                LOGE "Invalid IPv4 address."
                server_ip=""
            fi
        done
    fi
    echo "${server_ip}"
}

install_acme() {
    if command -v ~/.acme.sh/acme.sh &> /dev/null; then
        LOGI "acme.sh is already installed."
        return 0
    fi
    LOGI "Installing acme.sh..."
    cd ~ || return 1
    curl -s https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "Installation of acme.sh failed."
        return 1
    fi
    LOGI "Installation of acme.sh succeeded."
    return 0
}

install_socat() {
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update > /dev/null 2>&1 && apt-get install socat -y > /dev/null 2>&1
            ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf -y update > /dev/null 2>&1 && dnf -y install socat > /dev/null 2>&1
            ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum -y update > /dev/null 2>&1 && yum -y install socat > /dev/null 2>&1
            else
                dnf -y update > /dev/null 2>&1 && dnf -y install socat > /dev/null 2>&1
            fi
            ;;
        arch | manjaro | parch)
            pacman -Sy --noconfirm socat > /dev/null 2>&1
            ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper refresh > /dev/null 2>&1 && zypper -q install -y socat > /dev/null 2>&1
            ;;
        alpine)
            apk add socat curl openssl > /dev/null 2>&1
            ;;
        *)
            LOGW "Unsupported OS for automatic socat installation"
            ;;
    esac
}

prompt_reload_cmd() {
    load_config
    local default_cmd="${RELOAD_CMD:-}"
    LOGI "Current reload command: ${default_cmd:-<none>}"
    LOGI "This command runs after every certificate issue/renew."
    read -rp "Set reload command (leave empty for none, 'default' to auto-detect): " input_cmd
    if [[ "$input_cmd" == "default" ]]; then
        if systemctl is-active --quiet nginx 2>/dev/null; then
            RELOAD_CMD="systemctl reload nginx"
        elif systemctl is-active --quiet apache2 2>/dev/null; then
            RELOAD_CMD="systemctl reload apache2"
        elif systemctl is-active --quiet httpd 2>/dev/null; then
            RELOAD_CMD="systemctl reload httpd"
        elif systemctl is-active --quiet caddy 2>/dev/null; then
            RELOAD_CMD="systemctl reload caddy"
        else
            LOGW "No common web server detected. Reload command cleared."
            RELOAD_CMD=""
        fi
    elif [[ -n "$input_cmd" ]]; then
        RELOAD_CMD="${input_cmd}"
    fi
    save_config
    LOGI "Reload command set to: ${RELOAD_CMD:-<none>}"
}

ssl_cert_issue_domain() {
    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "install acme failed, please check logs"
            return 1
        fi
    fi

    install_socat

    local domain=""
    while true; do
        read -rp "Please enter your domain name: " domain
        domain="${domain// /}"
        if [[ -z "$domain" ]]; then
            LOGE "Domain name cannot be empty."
            continue
        fi
        if ! is_domain "$domain"; then
            LOGE "Invalid domain format: ${domain}."
            continue
        fi
        break
    done
    LOGD "Your domain is: ${domain}, checking it..."

    local cert_exists=0
    if ~/.acme.sh/acme.sh --list 2> /dev/null | awk '{print $1}' | grep -Fxq "${domain}"; then
        local acmeCertDir=""
        if [[ -s ~/.acme.sh/${domain}_ecc/fullchain.cer && -s ~/.acme.sh/${domain}_ecc/${domain}.key ]]; then
            acmeCertDir=~/.acme.sh/${domain}_ecc
        elif [[ -s ~/.acme.sh/${domain}/fullchain.cer && -s ~/.acme.sh/${domain}/${domain}.key ]]; then
            acmeCertDir=~/.acme.sh/${domain}
        fi
        if [[ -n "${acmeCertDir}" ]]; then
            cert_exists=1
            LOGI "Existing certificate found for ${domain}, will reuse it."
        else
            LOGW "Incomplete acme.sh state for ${domain}; cleaning up."
            rm -rf ~/.acme.sh/${domain} ~/.acme.sh/${domain}_ecc
        fi
    fi
    if [[ ${cert_exists} -eq 0 ]]; then
        LOGI "Your domain is ready for issuing certificates now..."
    fi

    certPath="${CERT_BASE_DIR}/${domain}"
    rm -rf "$certPath"
    mkdir -p "$certPath"

    load_config
    local WebPort="${DEFAULT_WEB_PORT}"
    read -rp "Port for ACME HTTP-01 listener [${WebPort}]: " input_port
    [[ -n "$input_port" ]] && WebPort="$input_port"
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        LOGE "Invalid port, using default 80."
        WebPort=80
    fi
    LOGI "Will use port: ${WebPort} to issue certificates."

    if [[ ${cert_exists} -eq 0 ]]; then
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force
        ~/.acme.sh/acme.sh --issue -d ${domain} $(acme_listen_flag) --standalone --httpport ${WebPort} --force
        if [ $? -ne 0 ]; then
            LOGE "Issuing certificate failed."
            rm -rf ~/.acme.sh/${domain} ~/.acme.sh/${domain}_ecc
            return 1
        fi
        LOGI "Issuing certificate succeeded, installing..."
    else
        LOGI "Using existing certificate, installing..."
    fi

    local reloadCmd="${RELOAD_CMD:-}"
    if [[ -z "$reloadCmd" ]]; then
        LOGI "No reload command configured."
        read -rp "Enter a reload command (leave empty for none): " reloadCmd
    fi

    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file "${certPath}/privkey.pem" \
        --fullchain-file "${certPath}/fullchain.pem" \
        ${reloadCmd:+--reloadcmd "${reloadCmd}"} 2>&1
    local installRc=$?

    if [[ -f "${certPath}/privkey.pem" && -f "${certPath}/fullchain.pem" && (${installRc} -eq 0 || $(wc -c < "${certPath}/fullchain.pem") -gt 0) ]]; then
        LOGI "Installing certificate succeeded, enabling auto renew..."
    else
        LOGE "Installing certificate failed."
        if [[ ${cert_exists} -eq 0 ]]; then
            rm -rf ~/.acme.sh/${domain} ~/.acme.sh/${domain}_ecc
        fi
        return 1
    fi

    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    chmod 600 "${certPath}/privkey.pem"
    chmod 644 "${certPath}/fullchain.pem"

    LOGI "Certificate installed successfully:"
    LOGI "  Domain: ${domain}"
    LOGI "  Certificate: ${certPath}/fullchain.pem"
    LOGI "  Private Key: ${certPath}/privkey.pem"
    LOGI "  Auto-renewal: enabled (acme.sh cron)"
    ls -lah "${certPath}"/

    return 0
}

ssl_cert_issue_cloudflare() {
    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "install acme failed, please check logs"
            return 1
        fi
    fi

    LOGI "****** Cloudflare DNS Certificate ******"
    LOGI "You need a Cloudflare API Token (or Global API Key) and a domain."

    confirm "Do you want to proceed? [y/n]" "y"
    [[ $? -ne 0 ]] && return 0

    CF_Domain=""
    read -rp "Input your domain: " CF_Domain
    LOGD "Domain: ${CF_Domain}"

    load_config
    local saved_email="${DEFAULT_CF_EMAIL}"

    CF_KeyType=""
    read -rp "Using API Token or Global API Key? (t/g) [Default t]: " CF_KeyType
    CF_KeyType=${CF_KeyType:-t}

    if [[ "$CF_KeyType" == "g" || "$CF_KeyType" == "G" ]]; then
        CF_GlobalKey=""
        CF_AccountEmail=""
        read -rp "Global API Key: " CF_GlobalKey
        read -rp "Account email [${saved_email}]: " CF_AccountEmail
        CF_AccountEmail="${CF_AccountEmail:-${saved_email}}"
        export CF_Key="${CF_GlobalKey}"
        export CF_Email="${CF_AccountEmail}"
        DEFAULT_CF_EMAIL="${CF_AccountEmail}"
    else
        CF_ApiToken=""
        read -rp "API Token: " CF_ApiToken
        export CF_Token="${CF_ApiToken}"
    fi
    save_config

    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force
    if [ $? -ne 0 ]; then
        LOGE "Default CA setup failed."
        return 1
    fi

    ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log --force
    if [ $? -ne 0 ]; then
        LOGE "Certificate issuance failed."
        return 1
    fi
    LOGI "Certificate issued successfully, Installing..."

    certPath="${CERT_BASE_DIR}/${CF_Domain}"
    rm -rf "${certPath}"
    mkdir -p "${certPath}"

    local reloadCmd="${RELOAD_CMD:-}"
    if [[ -z "$reloadCmd" ]]; then
        read -rp "Enter a reload command (leave empty for none): " reloadCmd
    fi

    ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} \
        --key-file "${certPath}/privkey.pem" \
        --fullchain-file "${certPath}/fullchain.pem" \
        ${reloadCmd:+--reloadcmd "${reloadCmd}"}
    if [ $? -ne 0 ]; then
        LOGE "Certificate installation failed."
        return 1
    fi

    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    chmod 600 "${certPath}/privkey.pem"
    chmod 644 "${certPath}/fullchain.pem"

    LOGI "Certificate installed successfully:"
    LOGI "  Domain: ${CF_Domain}"
    LOGI "  Certificate: ${certPath}/fullchain.pem"
    LOGI "  Private Key: ${certPath}/privkey.pem"
    LOGI "  Auto-renewal: enabled (acme.sh cron)"
    ls -lah "${certPath}"/*

    return 0
}

ssl_cert_issue_ip() {
    LOGI "Let's Encrypt SSL Certificate for IP Address (shortlived ~6 days, auto-renews)"
    LOGI "Port 80 must be open and accessible from the internet."

    confirm "Do you want to proceed?" "y"
    [[ $? -ne 0 ]] && return 0

    local server_ip
    server_ip=$(prompt_ip)
    LOGI "Server IP: ${server_ip}"

    local ipv6_addr=""
    read -rp "Optional IPv6 address (leave empty to skip): " ipv6_addr
    ipv6_addr="${ipv6_addr// /}"

    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "Failed to install acme.sh"
            return 1
        fi
    fi

    install_socat

    certPath="${CERT_BASE_DIR}/ip"
    mkdir -p "$certPath"

    local domain_args="-d ${server_ip}"
    if [[ -n "$ipv6_addr" ]] && is_ipv6 "$ipv6_addr"; then
        domain_args="${domain_args} -d ${ipv6_addr}"
        LOGI "Including IPv6 address: ${ipv6_addr}"
    fi

    load_config
    local WebPort="${DEFAULT_WEB_PORT}"
    read -rp "Port for ACME HTTP-01 listener [${WebPort}]: " input_port
    [[ -n "$input_port" ]] && WebPort="$input_port"
    if ! [[ "${WebPort}" =~ ^[0-9]+$ ]] || ((WebPort < 1 || WebPort > 65535)); then
        LOGE "Invalid port. Falling back to 80."
        WebPort=80
    fi
    LOGI "Using port ${WebPort} for IP certificate."

    while true; do
        if is_port_in_use "${WebPort}"; then
            LOGI "Port ${WebPort} is currently in use."
            local alt_port=""
            read -rp "Enter another port (leave empty to abort): " alt_port
            alt_port="${alt_port// /}"
            if [[ -z "${alt_port}" ]]; then
                LOGE "Port ${WebPort} busy; cannot proceed."
                return 1
            fi
            if ! [[ "${alt_port}" =~ ^[0-9]+$ ]] || ((alt_port < 1 || alt_port > 65535)); then
                LOGE "Invalid port."
                return 1
            fi
            WebPort="${alt_port}"
            continue
        else
            LOGI "Port ${WebPort} is free."
            break
        fi
    done

    local reloadCmd="${RELOAD_CMD:-}"

    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force
    ~/.acme.sh/acme.sh --issue \
        ${domain_args} \
        --standalone \
        --server letsencrypt \
        --certificate-profile shortlived \
        --days 6 \
        --httpport ${WebPort} \
        --force

    if [ $? -ne 0 ]; then
        LOGE "Failed to issue certificate for IP: ${server_ip}"
        rm -rf ~/.acme.sh/${server_ip} ~/.acme.sh/${server_ip}_ecc 2> /dev/null
        [[ -n "$ipv6_addr" ]] && rm -rf ~/.acme.sh/${ipv6_addr} ~/.acme.sh/${ipv6_addr}_ecc 2> /dev/null
        rm -rf "${certPath}" 2> /dev/null
        return 1
    fi
    LOGI "Certificate issued successfully for IP: ${server_ip}"

    ~/.acme.sh/acme.sh --installcert -d ${server_ip} \
        --key-file "${certPath}/privkey.pem" \
        --fullchain-file "${certPath}/fullchain.pem" \
        ${reloadCmd:+--reloadcmd "${reloadCmd}"} 2>&1 || true

    if [[ ! -f "${certPath}/fullchain.pem" || ! -f "${certPath}/privkey.pem" ]]; then
        LOGE "Certificate files not found after installation."
        rm -rf ~/.acme.sh/${server_ip} ~/.acme.sh/${server_ip}_ecc 2> /dev/null
        [[ -n "$ipv6_addr" ]] && rm -rf ~/.acme.sh/${ipv6_addr} ~/.acme.sh/${ipv6_addr}_ecc 2> /dev/null
        rm -rf "${certPath}" 2> /dev/null
        return 1
    fi

    LOGI "Certificate installed successfully"
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade > /dev/null 2>&1
    chmod 600 "${certPath}/privkey.pem"
    chmod 644 "${certPath}/fullchain.pem"

    LOGI "Certificate files:"
    LOGI "  IP: ${server_ip}"
    LOGI "  Certificate: ${certPath}/fullchain.pem"
    LOGI "  Private Key: ${certPath}/privkey.pem"
    LOGI "  Validity: ~6 days (auto-renews via acme.sh cron)"

    return 0
}

ssl_revoke() {
    local domains=$(find "${CERT_BASE_DIR}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2> /dev/null)
    if [ -z "$domains" ]; then
        echo "No certificates found to revoke."
        return
    fi
    echo "Existing certificates:"
    echo "$domains"
    read -rp "Enter domain to revoke and remove: " domain
    if echo "$domains" | grep -qw "$domain"; then
        local acme_ids="${domain}"
        if [[ "${domain}" == "ip" ]]; then
            acme_ids=$(~/.acme.sh/acme.sh --list 2> /dev/null | awk 'NR>1 {print $1}' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$|:')
        fi
        for id in ${acme_ids}; do
            ~/.acme.sh/acme.sh --revoke -d "${id}" 2> /dev/null
            ~/.acme.sh/acme.sh --remove -d "${id}" 2> /dev/null
            rm -rf ~/.acme.sh/"${id}" ~/.acme.sh/"${id}_ecc"
        done
        rm -rf "${CERT_BASE_DIR}/${domain}"
        LOGI "Certificate revoked and removed for: ${domain}"
    else
        echo "Invalid domain."
    fi
}

ssl_force_renew() {
    local domains=$(find "${CERT_BASE_DIR}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2> /dev/null)
    if [ -z "$domains" ]; then
        echo "No certificates found to renew."
        return
    fi
    echo "Existing certificates:"
    echo "$domains"
    read -rp "Enter domain to force renew: " domain
    if echo "$domains" | grep -qw "$domain"; then
        ~/.acme.sh/acme.sh --renew -d ${domain} --force
        LOGI "Certificate forcefully renewed for: $domain"
    else
        echo "Invalid domain."
    fi
}

ssl_show_existing() {
    local domains=$(find "${CERT_BASE_DIR}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2> /dev/null)
    if [ -z "$domains" ]; then
        echo "No certificates found under ${CERT_BASE_DIR}."
        return
    fi
    echo "Existing certificates:"
    for domain in $domains; do
        local cert_path="${CERT_BASE_DIR}/${domain}/fullchain.pem"
        local key_path="${CERT_BASE_DIR}/${domain}/privkey.pem"
        if [[ -f "${cert_path}" && -f "${key_path}" ]]; then
            echo -e "  Domain/IP: ${domain}"
            echo -e "    Certificate: ${cert_path}"
            echo -e "    Private Key: ${key_path}"
            if command -v openssl > /dev/null 2>&1; then
                local expiry
                expiry=$(openssl x509 -in "${cert_path}" -noout -enddate 2>/dev/null | cut -d= -f2)
                [[ -n "$expiry" ]] && echo -e "    Expires: ${expiry}"
                local sans
                sans=$(openssl x509 -in "${cert_path}" -noout -ext subjectAltName 2> /dev/null \
                    | grep -Eo 'DNS:[^,[:space:]]+' | cut -d: -f2 | tr '\n' ' ')
                [[ -n "$sans" ]] && echo -e "    SANs: ${sans}"
            fi
        else
            echo -e "  Domain/IP: ${domain} - ${red}Certificate or Key missing${plain}"
        fi
    done
}

ssl_set_paths() {
    echo -e "${green}\t1.${plain} Use a certificate from ${CERT_BASE_DIR}"
    echo -e "${green}\t2.${plain} Enter custom certificate file paths"
    read -rp "Choose an option: " pathChoice

    if [[ "$pathChoice" == "2" ]]; then
        read -rp "Certificate file (fullchain): " webCertFile
        read -rp "Private key file: " webKeyFile
        if [[ -f "${webCertFile}" && -f "${webKeyFile}" ]]; then
            echo -e "${green}Certificate:${plain} ${webCertFile}"
            echo -e "${green}Private Key:${plain} ${webKeyFile}"
            echo ""
            echo "Use these paths in your web server / proxy configuration:"
            echo "  ssl_certificate     ${webCertFile};"
            echo "  ssl_certificate_key ${webKeyFile};"
        else
            LOGE "File(s) not found."
        fi
        return
    fi

    local domains=$(find "${CERT_BASE_DIR}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2> /dev/null)
    if [ -z "$domains" ]; then
        echo "No certificates found."
        return
    fi
    echo "Available domains:"
    echo "$domains"
    read -rp "Choose a domain: " domain
    if echo "$domains" | grep -qw "$domain"; then
        local webCertFile="${CERT_BASE_DIR}/${domain}/fullchain.pem"
        local webKeyFile="${CERT_BASE_DIR}/${domain}/privkey.pem"
        if [[ -f "${webCertFile}" && -f "${webKeyFile}" ]]; then
            echo -e "${green}Certificate:${plain} ${webCertFile}"
            echo -e "${green}Private Key:${plain} ${webKeyFile}"
            echo ""
            echo "Use these paths in your web server / proxy configuration:"
            echo "  ssl_certificate     ${webCertFile};"
            echo "  ssl_certificate_key ${webKeyFile};"
        else
            LOGE "Certificate or key not found for: $domain"
        fi
    else
        echo "Invalid domain."
    fi
}

ssl_auto_renew_status() {
    LOGI "acme.sh auto-renewal status:"
    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        LOGE "acme.sh is not installed."
        return
    fi
    local cron_installed
    crontab -l 2> /dev/null | grep -q "acme.sh" && cron_installed=1 || cron_installed=0
    if [[ $cron_installed -eq 1 ]]; then
        LOGI "Auto-renewal cron job: ${green}active${plain}"
    else
        LOGW "Auto-renewal cron job: ${red}not found${plain}"
        LOGI "Run: ~/.acme.sh/acme.sh --install-cronjob to enable it."
    fi
    echo ""
    LOGI "Certificates tracked by acme.sh:"
    ~/.acme.sh/acme.sh --list 2> /dev/null || echo "  (none)"
}

ssl_menu() {
    echo -e "
╔══════════════════════════════════════════════╗
║   ${green}SSL Certificate Manager v${SCRIPT_VERSION}${plain}             ║
╠══════════════════════════════════════════════╣
║   ${green}1.${plain} Get SSL Certificate (Domain)            ║
║   ${green}2.${plain} Get SSL Certificate (Cloudflare DNS)    ║
║   ${green}3.${plain} Get SSL Certificate (IP Address)        ║
║   ${green}4.${plain} Revoke & Remove Certificate             ║
║   ${green}5.${plain} Force Renew Certificate                 ║
║   ${green}6.${plain} Show Existing Certificates              ║
║   ${green}7.${plain} Show Certificate Paths for Config       ║
║   ${green}8.${plain} Auto-Renewal Status                     ║
║   ${green}9.${plain} Configure Reload Command                ║
║  ${green}10.${plain} Install / Update acme.sh                ║
║   ${green}0.${plain} Exit                                    ║
╚══════════════════════════════════════════════╝
"
    read -rp "Choose an option: " choice
    case "$choice" in
        0) exit 0 ;;
        1) ssl_cert_issue_domain ;;
        2) ssl_cert_issue_cloudflare ;;
        3) ssl_cert_issue_ip ;;
        4) ssl_revoke ;;
        5) ssl_force_renew ;;
        6) ssl_show_existing ;;
        7) ssl_set_paths ;;
        8) ssl_auto_renew_status ;;
        9) prompt_reload_cmd ;;
        10) install_acme ;;
        *) LOGE "Invalid option." ;;
    esac
    before_show_menu
}

load_config

if [[ $# > 0 ]]; then
    case $1 in
        "issue")
            case "${2:-}" in
                "domain" | "") ssl_cert_issue_domain ;;
                "cf" | "cloudflare") ssl_cert_issue_cloudflare ;;
                "ip") ssl_cert_issue_ip ;;
                *) echo "Usage: $0 issue [domain|cf|ip]" ;;
            esac
            ;;
        "revoke") ssl_revoke ;;
        "renew") ssl_force_renew ;;
        "list") ssl_show_existing ;;
        "status") ssl_auto_renew_status ;;
        "config") prompt_reload_cmd ;;
        "install-acme") install_acme ;;
        *)
            echo "Usage: $0 [issue [domain|cf|ip]|revoke|renew|list|status|config|install-acme]"
            ;;
    esac
else
    ssl_menu
fi
