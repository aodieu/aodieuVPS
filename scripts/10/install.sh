#!/bin/bash
#######################################################
# aodieuVPS Script v1.0 for Rocky Linux 10
# To install type: 
# curl -sO https://aodieu.com/script/install && bash install
# or
# curl -fsSLO https://aodieu.com/script/scripts/10/install.sh && bash install.sh
#######################################################
aodieuvps_version="2.1"
phpmyadmin_version="5.2.3" # Released 2025-10-08. Compatible with PHP 7.2 to 8.4 and MySQL 5.5 and newer. Actively maintained and receives security updates.
filebrowser_quantum_version="2.0.1-stable" # pinned release, supplied via aodieu.com
filebrowser_sha256="42df10b6f2fcd4db17a53f64a9449e677a528164002fd13b050d348d7c477517" # pinned SHA256 of bundled amd64 release
script_root="https://aodieu.com/script/scripts"
script_url="https://aodieu.com/script/scripts/10"
low_ram='524288' # 512MB
# Called by the public launcher, which asks the user first. Also support direct
# execution of install.sh with no launcher.
installer_language=""
install_wordpress=false
for arg in "$@"; do
    case "$arg" in
        --lang=en|--lang=vi) installer_language="${arg#--lang=}" ;;
        wordpress) install_wordpress=true ;;
        *) printf 'Unknown installer argument: %s\n' "$arg" >&2; exit 2 ;;
    esac
done
if [ -z "$installer_language" ]; then
    printf 'Language / Ngon ngu: 1) English  2) Tieng Viet [2]: '
    read -r language_choice
    case "$language_choice" in 1) installer_language=en;; *) installer_language=vi;; esac
fi
# Localized installer output. Original Vietnamese wording remains the default.
msg() {
    local vi="$1" en="$2"
    if [ "$installer_language" = en ]; then printf '%s' "$en"; else printf '%s' "$vi"; fi
}
log_lang() { msg "$1" "$2"; printf '\n'; }

# Rocky Linux 10 compatibility: stop when required components cannot be installed.
fail() { printf '\n[aodieuVPS Rocky 10] ERROR: %s\n' "$*" >&2; exit 1; }
install_required() { dnf -y install "$@" || fail "Cannot install required packages: $*"; }
fetch_required() {
    local src="$1" dest="$2" tmp
    tmp="$(mktemp)" || fail "Cannot create temporary file"
    if ! curl -fsSL --retry 3 --connect-timeout 15 "$src" -o "$tmp" || [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        fail "Cannot download $src (check Wi-Fi, DNS, aodieu.com deployment and Internet access)"
    fi
    mv -f "$tmp" "$dest" || fail "Cannot save $dest"
}
# This is a fresh-server installer, not an updater. Check before
# downloading assets, installing RPMs, resetting database authentication,
# overwriting configs, or changing firewall/SSH rules.
existing_aodieuvps_path=""
if [ -e /etc/aodieuvps/scripts.conf ]; then
    existing_aodieuvps_path=/etc/aodieuvps/scripts.conf
elif [ -e /root/aodieuvps-script.txt ]; then
    existing_aodieuvps_path=/root/aodieuvps-script.txt
else
    for existing_admin_dir in /home/*/private_html/aodieuvps; do
        if [ -d "$existing_admin_dir" ]; then
            existing_aodieuvps_path="$existing_admin_dir"
            break
        fi
    done
fi
if [ -n "$existing_aodieuvps_path" ]; then
    fail "Existing or partial AodieuVPS installation detected at $existing_aodieuvps_path; refusing to reinstall over it. Use a component-level repair, or a fresh disposable Rocky Linux 10 system."
fi
[ -f /etc/rocky-release ] || fail "This installer is only for Rocky Linux 10"
[ "$(rpm -E %rhel)" = "10" ] || fail "This installer needs Rocky Linux 10"
getent hosts aodieu.com >/dev/null || fail "Cannot resolve aodieu.com; check Wi-Fi/NetworkManager and DNS"
[ "$(uname -m)" = x86_64 ] || fail "Bundled FileBrowser Quantum requires x86_64 (amd64); unsupported architecture"


# Fail before installing packages if mandatory AodieuVPS-hosted vendor asset
# is absent. No GitHub fetch is done by the VPS installer.
filebrowser_asset="$script_url/package/filebrowser-quantum-linux-amd64"
filebrowser_tmp=$(mktemp /tmp/aodieu-filebrowser.XXXXXX) || fail "Cannot create FileBrowser staging file"
chmod 600 "$filebrowser_tmp"
if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 180 "$filebrowser_asset" -o "$filebrowser_tmp"; then
    rm -f "$filebrowser_tmp"
    fail "Cannot download FileBrowser Quantum from aodieu.com: $filebrowser_asset (verify your deployed script/scripts/10/package/ files)"
fi
if [ "$(head -c 4 "$filebrowser_tmp" | od -An -tx1 | tr -d ' \n')" != 7f454c46 ]; then
    rm -f "$filebrowser_tmp"
    fail "FileBrowser Quantum download is not an ELF executable"
fi
# SHA256 accompanies the official binary on aodieu.com; require checksum.
filebrowser_checksum=$(mktemp /tmp/aodieu-sha.XXXXXX) || fail "No temporary checksum file"
if ! curl -fsSL "$filebrowser_asset.sha256" -o "$filebrowser_checksum"; then
    rm -f "$filebrowser_tmp" "$filebrowser_checksum"
    fail "Missing FileBrowser SHA256 manifest; deploy the binary and checksum together"
fi
expected_sha=$(awk 'NR == 1 { print $1 }' "$filebrowser_checksum")
rm -f "$filebrowser_checksum"
if [[ ! "$expected_sha" =~ ^[a-fA-F0-9]{64}$ ]] || [ "${expected_sha,,}" != "$filebrowser_sha256" ] || [ "$(sha256sum "$filebrowser_tmp" | awk '{print $1}')" != "$filebrowser_sha256" ]; then
    rm -f "$filebrowser_tmp"
    fail "FileBrowser Quantum binary checksum mismatch"
fi
# Preflight: both Beszel binaries MUST be mirrored on aodieu.com. No Docker,
# GitHub download, package builder or manual vendor installation is needed.
beszel_hub_sha="c0cbab161f322426228419fbbeab4163dded6464a537cc1e2f92e090892f6368"
beszel_agent_sha="898d67d456a4feed7d651bbac22def5eb41840d4f3d9bf058a5ed37c8c815599"
beszel_hub_tmp=$(mktemp /tmp/aodieu-beszel-hub.XXXXXX) || fail "Cannot stage Beszel hub"
beszel_agent_tmp=$(mktemp /tmp/aodieu-beszel-agent.XXXXXX) || fail "Cannot stage Beszel agent"
# Administrator package is checksum-pinned to detect stale website files/CDN cache
# BEFORE changing packages, ports, services, or the existing server configuration.
administrator_sha256="68830569374b575d02016fd210a35145e622b6f020951d96ad3c9318395a6396"
administrator_tmp=$(mktemp /tmp/aodieu-administrator.XXXXXX) || fail "Cannot stage administrator package"
trap 'rm -f "$filebrowser_tmp" "$beszel_hub_tmp" "$beszel_agent_tmp" "$administrator_tmp" "${phpmyadmin_tmp:-}"' EXIT
administrator_url="$script_url/package/administrator.zip"
if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 \
    -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
    "$administrator_url" -o "$administrator_tmp"; then
    fail "Cannot download administrator.zip from aodieu.com: $administrator_url"
fi
if [ "$(sha256sum "$administrator_tmp" | awk '{print $1}')" != "$administrator_sha256" ]; then
    fail "Outdated or modified administrator.zip at $administrator_url (SHA-256 mismatch). Upload the bundled administrator.zip from this release, clear server/CDN cache, then rerun on a clean test server."
fi
fetch_beszel_archive() {
    local url="$1" output="$2" expected="$3"
    if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 240 "$url" -o "$output"; then
        fail "Beszel asset missing on aodieu.com: $url"
    fi
    [ "$(sha256sum "$output" | awk '{print $1}')" = "$expected" ] || fail "Beszel archive SHA256 mismatch: $url"
}
fetch_beszel_archive "$script_url/package/beszel_linux_amd64.tar.gz" "$beszel_hub_tmp" "$beszel_hub_sha"
fetch_beszel_archive "$script_url/package/beszel-agent_linux_amd64.tar.gz" "$beszel_agent_tmp" "$beszel_agent_sha"


# Verify every AodieuVPS-hosted item before touching server repositories,
# firewall, Nginx, database, or SSH.  Catch missing deployment files up front.
for hosted_asset in \
    "html/index.html" "aodieuvps" "component/menu.zip" "component/beszel-register.py" \
    "component/aodieu-rocky10-diagnostics.sh" \
    "config/mysql/my-mdb10-min.cnf" "config/mysql/my-mdb10.cnf" \
    "config/mysql/my-mdb10-4gb.cnf" "config/mysql/my-mdb10-8gb.cnf" \
    "config/mysql/my-mdb10-16gb.cnf" "config/mysql/my-mdb10-32gb.cnf"; do
    if ! curl -fsSL --retry 2 --connect-timeout 15 --max-time 60 \
            "$script_url/$hosted_asset" -o /dev/null; then
        fail "Missing AodieuVPS website component: $script_url/$hosted_asset"
    fi
done
for shared_asset in \
    "config/php-fpm/php-fpm.conf" "config/php-fpm/php-fpm-min.conf" \
    "config/php-fpm/www.conf" "config/php-fpm/www-min.conf" \
    "component/opcache-gui/index.php.txt"; do
    if ! curl -fsSL --retry 2 --connect-timeout 15 --max-time 60 \
            "$script_root/$shared_asset" -o /dev/null; then
        fail "Missing AodieuVPS shared component: $script_root/$shared_asset"
    fi
done

install_required gawk bc wget lsof curl tar unzip openssl python3

# Download and inspect phpMyAdmin before any irreversible server changes.
# The official package is downloaded automatically: no manual dependency step.
phpmyadmin_tmp=$(mktemp /tmp/aodieu-phpmyadmin.XXXXXX) || fail "Cannot stage phpMyAdmin"
phpmyadmin_url="https://files.phpmyadmin.net/phpMyAdmin/$phpmyadmin_version/phpMyAdmin-$phpmyadmin_version-english.zip"
if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 240 \
        "$phpmyadmin_url" -o "$phpmyadmin_tmp"; then
    fail "phpMyAdmin release download unavailable: $phpmyadmin_url"
fi
unzip -tq "$phpmyadmin_tmp" >/dev/null || fail "Downloaded phpMyAdmin archive is corrupt"
unzip -Z1 "$phpmyadmin_tmp" | grep -Fxq "phpMyAdmin-$phpmyadmin_version-english/index.php" \
    || fail "phpMyAdmin archive is missing its entry point"

clear
printf "=========================================================================\n"
log_lang "Kiem tra tai nguyen VPS de cau hinh" "Checking VPS resources for installation"
printf "=========================================================================\n"

cpu_name=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo )
cpu_cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
cpu_freq=$( awk -F: ' /cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo )
server_ram_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
server_ram_mb=`echo "scale=0;$server_ram_total/1024" | bc`
server_hdd=$( df -h | awk 'NR==2 {print $2}' )
server_swap_total=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
server_swap_mb=`echo "scale=0;$server_swap_total/1024" | bc`
server_ip=$(curl -fsSL --max-time 10 https://api.ipify.org || true)
[ -n "$server_ip" ] || server_ip=$(hostname -I | awk '{print $1}')

printf "=========================================================================\n"
log_lang "Thong so server cua ban nhu sau" "Your server specifications"
printf "=========================================================================\n"
echo "$(msg "Loai CPU" "CPU model"): $cpu_name"
echo "$(msg "Tong so CPU core" "CPU cores"): $cpu_cores"
echo "$(msg "Toc do moi core" "CPU frequency"): $cpu_freq MHz"
echo "$(msg "Tong dung luong RAM" "Total RAM"): $server_ram_mb MB"
echo "$(msg "Tong dung luong swap" "Swap memory"): $server_swap_mb MB"
echo "$(msg "Tong dung luong o dia" "Disk capacity"): $server_hdd"
echo "$(msg "IP cua server" "Server IP"): $server_ip"
printf "=========================================================================\n"
printf "=========================================================================\n"

if [ $server_ram_total -lt $low_ram ]; then
	log_lang "Canh bao: RAM qua thap" "WARNING: Not enough RAM to install AodieuVPS"
	log_lang "huy cai dat..." "Installation cancelled"
	exit
fi
sleep 3

clear
printf "=========================================================================\n"
log_lang "Chuan bi qua trinh cai dat..." "Preparing installation..."
printf "=========================================================================\n"

log_lang "Ban hay lua chon phien ban PHP muon su dung:" "Choose the PHP version:"
prompt="$(msg "Nhap vao lua chon cua ban [1-8]: " "Your choice [1-8]: ")"
php_version="8.4"; # Default PHP 8.4
options=("PHP 8.4" "PHP 8.3" "PHP 8.2" "PHP 8.1" "PHP 8.0" "PHP 7.4" "PHP 7.3" "PHP 7.2")
PS3="$prompt"
select opt in "${options[@]}"; do 

    case "$REPLY" in
    1) php_version="8.4"; break;;
    2) php_version="8.3"; break;;
    3) php_version="8.2"; break;;
    4) php_version="8.1"; break;;
    5) php_version="8.0"; break;;
    6) php_version="7.4"; break;;
    7) php_version="7.3"; break;;
    8) php_version="7.2"; break;;

    $(( ${#options[@]}+1 )) ) log_lang "He thong se cai dat PHP 8.4" "Installing default PHP 8.4"; break;;
    *) log_lang "Lua chon khong hop le, cai dat PHP 8.4" "Invalid choice; installing default PHP 8.4"; break;;
    esac
    
done

printf "\n%s" "$(msg "Nhap vao ten mien chinh (non-www hoac www) roi an [ENTER]: " "Enter main domain (non-www or www), then press ENTER: ")" 
read server_name
if [ "$server_name" = "" ]; then
    server_name="aodieu.com"
    log_lang "Ban nhap sai, he thong dung aodieu.com lam ten mien chinh" "No domain entered; using the existing aodieu.com default"
fi
# Used in filesystem paths, Nginx directives and configuration substitutions.
if [[ ! "$server_name" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || [[ "$server_name" == *..* ]]; then
    fail "Invalid domain; enter a plain domain name (without https:// or /path)"
fi

printf "\n%s" "$(msg "Nhap vao port admin roi an [ENTER]: " "Enter administration port, then press ENTER: ")" 
read admin_port
if [[ ! "$admin_port" =~ ^[0-9]+$ ]] || [ "$admin_port" = "2222" ] || [ "$admin_port" -lt 2000 ] || [ "$admin_port" -gt 9999 ] || lsof -i -P | grep -q ":$admin_port "; then
	admin_port=$(date +'%Y')
	log_lang "Port admin khong phu hop. He thong su dung port mac dinh $admin_port" "Invalid admin port; defaulting to $admin_port"
	echo
fi

printf "=========================================================================\n"
log_lang "Hoan tat qua trinh chuan bi..." "Preparation complete"
printf "=========================================================================\n"


rm -f /etc/localtime
ln -sf /usr/share/zoneinfo/Asia/Ho_Chi_Minh /etc/localtime

if [ -s /etc/selinux/config ]; then
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
fi
setenforce 0

# Rocky 10 CRB and EPEL; retain Remi PHP and MariaDB 10.11 versions.
install_required dnf-plugins-core epel-release
dnf config-manager --set-enabled crb || fail "Unable to enable Rocky Linux 10 CRB"
install_required https://rpms.remirepo.net/enterprise/remi-release-10.rpm

# RHEL/Rocky 10 includes supported MariaDB 10.11 (mariadb-server).
# Do not install an EL8 MariaDB repo, mix RPM families, or touch existing DB files.

# Gracefully handle optional saslauthd service (may not be installed)
systemctl stop saslauthd.service 2>/dev/null || true
systemctl disable saslauthd.service 2>/dev/null || true

# Preserve the original PHP/Nginx/MariaDB stack selection and service layout.
# On a fresh machine no conflicting applications should be installed.
dnf -y update || fail "System update failed"

clear
printf "=========================================================================\n"
log_lang "Chuan bi xong, bat dau cai dat server..." "Installing server packages..."
printf "=========================================================================\n"
sleep 3

# Install Nginx, PHP-FPM and modules

# Install Nginx and PHP from the selected Remi module stream.
dnf config-manager --set-enabled remi || fail "Cannot enable Remi repository"
dnf -y module reset php || fail "Cannot reset default PHP module"
if ! dnf -y module enable "php:remi-$php_version"; then
    fail "PHP $php_version is not provided by Remi on Rocky 10. Re-run installer and choose a supported version (default: 8.4)."
fi
install_required nginx php-fpm php-common php-gd php-mysqlnd php-pdo php-xml php-mbstring php-opcache php-cli php-pecl-zip php-intl php-soap

# MariaDB 10.11 is a supported Rocky 10 application stream.
install_required mariadb-server mariadb

# EL10 ships iptables-nft-services, not the old iptables-services RPM.
install_required zip nano openssl wget curl cronie fail2ban iptables-nft iptables-nft-services chrony
if ! dnf -y install exim; then
    echo "WARNING: Exim could not be installed; outbound server mail is unavailable."
fi
# Optional logging service: install separately so one absent subpackage does not abort the stack.
if dnf -y install syslog-ng; then
    : # EL10 has no syslog-ng-libdbi package; core syslog-ng is sufficient
    systemctl enable --now syslog-ng.service || true
else
    install_required rsyslog
    systemctl enable --now rsyslog.service || true
fi

# Keep the existing iptables-based firewall design but stage access rules first.
# SSH port 22 remains temporarily open so a failed SSH port change cannot lock out the owner.
for port in 22 2222 80 25 443 465 587 "$admin_port"; do
    iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null ||
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT || fail "Cannot allow TCP $port"
done
mkdir -p /etc/sysconfig
iptables-save > /etc/sysconfig/iptables || fail "Could not save firewall rules"
if command -v ip6tables-save >/dev/null; then
    ip6tables-save > /etc/sysconfig/ip6tables || true
fi
systemctl stop firewalld.service 2>/dev/null || true
systemctl disable firewalld.service 2>/dev/null || true
systemctl mask firewalld.service 2>/dev/null || true
systemctl enable --now iptables.service || fail "Unable to activate iptables service"
if systemctl list-unit-files ip6tables.service --no-legend 2>/dev/null | grep -q '^ip6tables.service'; then
    systemctl enable --now ip6tables.service || true
fi

chronyc -a makestep
hwclock --systohc

clear
printf "=========================================================================\n"
log_lang "Cai dat xong, bat dau cau hinh server..." "Packages installed. Configuring server..."
printf "=========================================================================\n"
sleep 3

# Autostart
systemctl enable nginx.service
systemctl enable php-fpm.service
systemctl enable mariadb.service
systemctl enable fail2ban.service
# iptables service was configured and enabled before applying SSH/Nginx changes.

mkdir -p /home/$server_name/public_html
mkdir -p /home/$server_name/private_html
mkdir -p /home/$server_name/logs
chmod 777 /home/$server_name/logs

mkdir -p /var/log/nginx
chown -R nginx:nginx /var/log/nginx
mkdir -p /var/lib/php/session /var/lib/php/wsdlcache
chown -R nginx:nginx /var/lib/php/session /var/lib/php/wsdlcache

fetch_required "$script_url/html/index.html" "/home/$server_name/public_html/index.html"

systemctl start nginx.service || fail "Nginx failed to start"
systemctl start php-fpm.service || fail "PHP-FPM failed to start"
systemctl start mariadb.service || fail "MariaDB failed to start"
mariadb --version | grep -q '10\.11\.' || fail "Expected MariaDB 10.11 from Rocky Linux 10"

# PHP #
phplowmem='2097152'
check_phplowmem=$(expr $server_ram_total \< $phplowmem)
max_children=`echo "scale=0;$server_ram_mb*0.4/30" | bc`
[ "$max_children" -ge 4 ] || max_children=4
if [ "$check_phplowmem" == "1" ]; then
	lessphpmem=y
fi

if [[ "$lessphpmem" = [yY] ]]; then  
	# echo -e "\nCopying php-fpm-min.conf /etc/php-fpm.d/www.conf\n"
	fetch_required $script_root/config/php-fpm/php-fpm-min.conf /etc/php-fpm.conf
	fetch_required $script_root/config/php-fpm/www-min.conf /etc/php-fpm.d/www.conf
else
	# echo -e "\nCopying php-fpm.conf /etc/php-fpm.d/www.conf\n"
	fetch_required $script_root/config/php-fpm/php-fpm.conf /etc/php-fpm.conf
	fetch_required $script_root/config/php-fpm/www.conf /etc/php-fpm.d/www.conf
fi # lessphpmem

sed -i "s/server_name_here/$server_name/g" /etc/php-fpm.conf
sed -i "s/server_name_here/$server_name/g" /etc/php-fpm.d/www.conf
sed -i "s/max_children_here/$max_children/g" /etc/php-fpm.d/www.conf
# Enforce pm.start/min/max <= pm.max_children with the original memory budget.
if [ "$max_children" -lt 13 ]; then
    sed -i -E 's/^pm\.start_servers = .*/pm.start_servers = 2/;s/^pm\.min_spare_servers = .*/pm.min_spare_servers = 1/;s/^pm\.max_spare_servers = .*/pm.max_spare_servers = 3/' /etc/php-fpm.d/www.conf
fi

# dynamic PHP memory_limit calculation
if [[ "$server_ram_total" -le '262144' ]]; then
	php_memorylimit='48M'
	php_uploadlimit='48M'
	php_realpathlimit='256k'
	php_realpathttl='14400'
elif [[ "$server_ram_total" -gt '262144' && "$server_ram_total" -le '393216' ]]; then
	php_memorylimit='96M'
	php_uploadlimit='96M'
	php_realpathlimit='320k'
	php_realpathttl='21600'
elif [[ "$server_ram_total" -gt '393216' && "$server_ram_total" -le '524288' ]]; then
	php_memorylimit='128M'
	php_uploadlimit='128M'
	php_realpathlimit='384k'
	php_realpathttl='28800'
elif [[ "$server_ram_total" -gt '524288' && "$server_ram_total" -le '1049576' ]]; then
	php_memorylimit='160M'
	php_uploadlimit='160M'
	php_realpathlimit='384k'
	php_realpathttl='28800'
elif [[ "$server_ram_total" -gt '1049576' && "$server_ram_total" -le '2097152' ]]; then
	php_memorylimit='256M'
	php_uploadlimit='256M'
	php_realpathlimit='384k'
	php_realpathttl='28800'
elif [[ "$server_ram_total" -gt '2097152' && "$server_ram_total" -le '3145728' ]]; then
	php_memorylimit='320M'
	php_uploadlimit='320M'
	php_realpathlimit='512k'
	php_realpathttl='43200'
elif [[ "$server_ram_total" -gt '3145728' && "$server_ram_total" -le '4194304' ]]; then
	php_memorylimit='512M'
	php_uploadlimit='512M'
	php_realpathlimit='512k'
	php_realpathttl='43200'
elif [[ "$server_ram_total" -gt '4194304' ]]; then
	php_memorylimit='800M'
	php_uploadlimit='800M'
	php_realpathlimit='640k'
	php_realpathttl='86400'
fi

cat > "/etc/php.d/00-aodieuvps-custom.ini" <<END
date.timezone = Asia/Ho_Chi_Minh
max_execution_time = 180
max_input_time = 180
short_open_tag = On
realpath_cache_size = $php_realpathlimit
realpath_cache_ttl = $php_realpathttl
memory_limit = $php_memorylimit
upload_max_filesize = $php_uploadlimit
post_max_size = $php_uploadlimit
expose_php = Off
mail.add_x_header = Off
max_input_nesting_level = 128
max_input_vars = 2000
mysqlnd.net_cmd_buffer_size = 16384
always_populate_raw_post_data=-1
disable_functions=shell_exec
END

# Zend Opcache
opcache_path='opcache.so' #Default for PHP 5.5 and newer

if [ "$php_version" = "5.4" ]; then
	cd /usr/local/src
	wget http://pecl.php.net/get/ZendOpcache
	tar xvfz ZendOpcache
	cd zendopcache-7.*
	phpize
	php_config_path=`which php-config`
	./configure --with-php-config=$php_config_path
	make
	make install
	rm -rf /usr/local/src/zendopcache*
	rm -f ZendOpcache
	opcache_path=`find / -name 'opcache.so'`
fi

fetch_required "$script_root/component/opcache-gui/index.php.txt" "/home/$server_name/private_html/op.php"
cat > /etc/php.d/99-aodieuvps-opcache.ini <<END
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=4000
opcache.max_wasted_percentage=5
opcache.use_cwd=1
opcache.validate_timestamps=1
opcache.revalidate_freq=60
opcache.blacklist_filename=/etc/php.d/opcache-default.blacklist
END

cat > /etc/php.d/opcache-default.blacklist <<END
/home/*/public_html/wp-content/plugins/backwpup/*
/home/*/public_html/wp-content/plugins/duplicator/*
/home/*/public_html/wp-content/plugins/updraftplus/*
/home/$server_name/private_html/
END

php-fpm -t || fail "PHP-FPM configuration check failed"
systemctl restart php-fpm.service || fail "PHP-FPM failed to restart"

# Nginx #
cat > "/etc/nginx/nginx.conf" <<END

user nginx;
worker_processes auto;
worker_rlimit_nofile 260000;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
	worker_connections  2048;
	accept_mutex off;
	accept_mutex_delay 200ms;
	use epoll;
	#multi_accept on;
}

http {
	include       /etc/nginx/mime.types;
	default_type  application/octet-stream;

	log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
	              '\$status \$body_bytes_sent "\$http_referer" '
	              '"\$http_user_agent" "\$http_x_forwarded_for"';

	#Disable IFRAME
	add_header X-Frame-Options SAMEORIGIN;
	
	#Prevent Cross-site scripting (XSS) attacks
	add_header X-XSS-Protection "1; mode=block";
	
	#Prevent MIME-sniffing
	add_header X-Content-Type-Options nosniff;
	
	access_log  off;
	sendfile on;
	tcp_nopush on;
	tcp_nodelay off;
	types_hash_max_size 2048;
	server_tokens off;
	server_names_hash_bucket_size 128;
	client_max_body_size 0;
	client_body_buffer_size 256k;
	client_body_in_file_only off;
	client_body_timeout 60s;
	client_header_buffer_size 256k;
	client_header_timeout  20s;
	large_client_header_buffers 8 256k;
	keepalive_timeout 10;
	keepalive_disable msie6;
	reset_timedout_connection on;
	send_timeout 60s;
	
	gzip on;
	gzip_static on;
	gzip_disable "msie6";
	gzip_vary on;
	gzip_proxied any;
	gzip_comp_level 6;
	gzip_buffers 16 8k;
	gzip_http_version 1.1;
	gzip_types text/plain text/css application/json text/javascript application/javascript text/xml application/xml application/xml+rss;

	include /etc/nginx/conf.d/*.conf;
}
END

cat > "/usr/share/nginx/html/403.html" <<END
<html>
<head><title>403 Forbidden</title></head>
<body bgcolor="white">
<center><h1>403 Forbidden</h1></center>
<hr><center>aodieu-nginx</center>
</body>
</html>
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
END

cat > "/usr/share/nginx/html/404.html" <<END
<html>
<head><title>404 Not Found</title></head>
<body bgcolor="white">
<center><h1>404 Not Found</h1></center>
<hr><center>aodieu-nginx</center>
</body>
</html>
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
END

rm -rf /etc/nginx/conf.d/*
> /etc/nginx/conf.d/default.conf

server_name_alias="www.$server_name"
if [[ $server_name == *www* ]]; then
    server_name_alias=${server_name/www./''}
fi

cat > "/etc/nginx/conf.d/$server_name.conf" <<END
server {
	listen 80;
	
	server_name $server_name_alias;
	rewrite ^(.*) http://$server_name\$1 permanent;
}

server {
	listen 80 default_server;
		
	# access_log off;
	access_log /home/$server_name/logs/access.log;
	# error_log off;
    	error_log /home/$server_name/logs/error.log;
	
    	root /home/$server_name/public_html;
	index index.php index.html index.htm;
    	server_name $server_name;
 
    	location / {
		try_files \$uri \$uri/ /index.php?\$args;
	}
	
	# Custom configuration
	include /home/$server_name/public_html/*.conf;
 
    	location ~ \.php$ {
		fastcgi_split_path_info ^(.+\.php)(/.+)$;
        	include /etc/nginx/fastcgi_params;
        	fastcgi_pass 127.0.0.1:9000;
        	fastcgi_index index.php;
		fastcgi_connect_timeout 1000;
		fastcgi_send_timeout 1000;
		fastcgi_read_timeout 1000;
		fastcgi_buffer_size 256k;
		fastcgi_buffers 4 256k;
		fastcgi_busy_buffers_size 256k;
		fastcgi_temp_file_write_size 256k;
		fastcgi_intercept_errors on;
        	fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    	}
	
	location /nginx_status {
  		stub_status on;
  		access_log   off;
		allow 127.0.0.1;
		allow $server_ip;
		deny all;
	}
	
	location /php_status {
		fastcgi_pass 127.0.0.1:9000;
		fastcgi_index index.php;
		fastcgi_param SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
		include /etc/nginx/fastcgi_params;
		allow 127.0.0.1;
		allow $server_ip;
		deny all;
    	}
	
	# Disable .htaccess and other hidden files
	location ~ /\.(?!well-known).* {
		deny all;
		access_log off;
		log_not_found off;
	}
	
        location = /favicon.ico {
                log_not_found off;
                access_log off;
        }
	
	location = /robots.txt {
		allow all;
		log_not_found off;
		access_log off;
	}
	
	location ~* \.(3gp|gif|jpg|jpeg|png|ico|wmv|avi|asf|asx|mpg|mpeg|mp4|pls|mp3|mid|wav|swf|flv|exe|zip|tar|rar|gz|tgz|bz2|uha|7z|doc|docx|xls|xlsx|pdf|iso|eot|svg|ttf|woff)$ {
	        gzip_static off;
		add_header Pragma public;
		add_header Cache-Control "public, must-revalidate, proxy-revalidate";
		access_log off;
		expires 30d;
		break;
        }

        location ~* \.(txt|js|css)$ {
	        add_header Pragma public;
		add_header Cache-Control "public, must-revalidate, proxy-revalidate";
		access_log off;
		expires 30d;
		break;
        }
}

server {
	listen $admin_port;
	
 	access_log off;
	log_not_found off;
 	error_log /home/$server_name/logs/nginx_error.log;
	
    	root /home/$server_name/private_html;
	index index.php index.html index.htm;
    	server_name $server_name;
	
	auth_basic "Restricted";
	auth_basic_user_file /home/$server_name/private_html/aodieuvps/.htpasswd;

        # Beszel replaces the legacy single-file PHP Server Probe.
        # Only the existing authenticated admin port is exposed.
        # Beszel authenticates its own API using Authorization tokens. Disable
        # inherited Nginx Basic auth only here to prevent browser login loops.
        location = /serverinfo { auth_basic off; return 301 /serverinfo/; }
        location ^~ /serverinfo/ {
            auth_basic off;
            proxy_http_version 1.1;
            proxy_read_timeout 360s;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$http_host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Authorization \$http_authorization;
            rewrite ^/serverinfo/(.*) /\$1 break;
            proxy_pass http://127.0.0.1:8090;
        }

        location = /filemanager { return 301 /filemanager/; }
        location /filemanager/ {
            proxy_pass http://127.0.0.1:12787/filemanager/;
            proxy_http_version 1.1;
            proxy_set_header Host \$http_host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Authorization "";
            proxy_buffering off;
            client_max_body_size 10G;
        }
 
     	location / {
		autoindex on;
		try_files \$uri \$uri/ /index.php;
	}
	
    	location ~ \.php$ {
		fastcgi_split_path_info ^(.+\.php)(/.+)$;
        	include /etc/nginx/fastcgi_params;
        	fastcgi_pass 127.0.0.1:9000;
        	fastcgi_index index.php;
		fastcgi_connect_timeout 1000;
		fastcgi_send_timeout 1000;
		fastcgi_read_timeout 1000;
		fastcgi_buffer_size 256k;
		fastcgi_buffers 4 256k;
		fastcgi_busy_buffers_size 256k;
		fastcgi_temp_file_write_size 256k;
		fastcgi_intercept_errors on;
        	fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    	}
	
	location ~ /\. {
		deny all;
	}
}
END

cat >> "/etc/security/limits.conf" <<END
* soft nofile 262144
* hard nofile 262144
nginx soft nofile 262144
nginx hard nofile 262144
nobody soft nofile 262144
nobody hard nofile 262144
root soft nofile 262144
root hard nofile 262144
END

ulimit -n 262144

nginx -t || fail "Nginx configuration check failed"
systemctl restart nginx.service || fail "Nginx failed to restart"

# MariaDB (Rocky 10 native 10.11). Use separate version-compatible templates
# with the same memory-tier settings as Rocky 8, and never delete data files.
cp -a /etc/my.cnf /etc/my.cnf-original
if [ "$server_ram_total" -le 2099000 ]; then
    mysql_template="my-mdb10-min.cnf"
elif [ "$server_ram_total" -le 4190000 ]; then
    mysql_template="my-mdb10.cnf"
elif [ "$server_ram_total" -le 8199999 ]; then
    mysql_template="my-mdb10-4gb.cnf"
elif [ "$server_ram_total" -le 15999999 ]; then
    mysql_template="my-mdb10-8gb.cnf"
elif [ "$server_ram_total" -le 31999999 ]; then
    mysql_template="my-mdb10-16gb.cnf"
else
    mysql_template="my-mdb10-32gb.cnf"
fi
fetch_required "$script_url/config/mysql/$mysql_template" /etc/my.cnf
chmod 644 /etc/my.cnf
sed -i "s/server_name_here/$server_name/g" /etc/my.cnf
# Preserve the original server layout, logging and memory-tier values.
systemctl restart mariadb.service || fail "MariaDB could not start with selected memory-tier configuration"

# MariaDB 10.11 defaults to unix_socket authentication on local root.
# Set password authentication without rewriting mysql.* system tables.
root_password=$(openssl rand -hex 18)
admin_password=$(openssl rand -hex 18)
mariadb --protocol=socket -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$root_password';" || fail "Cannot set MariaDB root password"
cat > /root/.my.cnf <<END
[client]
user=root
password=$root_password
END
chmod 600 /root/.my.cnf
mariadb -e "CREATE USER IF NOT EXISTS 'admin'@'localhost' IDENTIFIED BY '$admin_password';" || fail "Cannot create admin DB account"
mariadb -e "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;" || fail "Cannot grant admin DB access"
mariadb -e "DROP USER IF EXISTS ''@'localhost'; DROP USER IF EXISTS ''@'%';" || fail "Cannot remove anonymous DB accounts"
mariadb -e "DROP DATABASE IF EXISTS test" || fail "Cannot remove test DB"
mariadb -e "FLUSH PRIVILEGES" || fail "Cannot flush DB privileges"
mariadb -NBe 'SELECT VERSION();' || fail "MariaDB authentication check failed"

if [ "$install_wordpress" = true ]; then
	clear
	printf "=========================================================================\n"
	log_lang "Cai dat WordPress..." "Installing WordPress..."
	printf "=========================================================================\n"
	cd /home/$server_name/public_html/
	rm -f index.html
	# Generate wordpress database
	wordpress_password=`date |md5sum |cut -c '1-15'`
	secure_table_prefix=`date |md5sum |cut -c '1-5'`
	mariadb -e "CREATE DATABASE wordpress; CREATE USER 'wordpress'@'localhost' IDENTIFIED BY '$wordpress_password'; GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost'; FLUSH PRIVILEGES;" || fail "WordPress database initialization failed"
	
	# Download latest WordPress and uncompress
	wget https://wordpress.org/latest.tar.gz
	tar zxf latest.tar.gz
	mv wordpress/* ./

	# Grab Salt Keys
	wget -O /tmp/wp.keys https://api.wordpress.org/secret-key/1.1/salt/

	# Butcher our wp-config.php file
	sed -e "s/database_name_here/wordpress/" -e "s/username_here/wordpress/" -e "s/password_here/"$wordpress_password"/"  -e "s/wp_/wp_"$secure_table_prefix"_/" wp-config-sample.php > wp-config.php
	sed -i '/#@-/r /tmp/wp.keys' wp-config.php
	sed -i "/#@+/,/#@-/d" wp-config.php

	# Tidy up
	rm -rf wordpress latest.tar.gz /tmp/wp.keys wp wp-config-sample.php
fi

clear

log_lang "Bat dau cai dat autossl..." "Checking automatic SSL eligibility..."

# Rocky Linux 10: use supported EPEL Certbot RPMs rather than snapd.
if dnf -y install certbot python3-certbot-nginx; then
    # Certificate issuance needs a resolvable public domain pointing to this server.
    # Public ACME HTTP validation is not appropriate when DNS points elsewhere,
    # e.g. aodieu.com behind Cloudflare during a local test. Prevent needless failures.
    resolved_ips=$(getent ahostsv4 "$server_name" | awk '{print $1}' | sort -u)
    if [ -n "$server_ip" ] && printf '%s\n' "$resolved_ips" | grep -Fxq "$server_ip"; then
        certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email \
            -d "$server_name" || echo "WARNING: SSL issuance failed; inspect DNS/HTTP challenge, configure later"
    else
        echo "NOTICE: SSL issuance skipped because $server_name does not resolve to this server ($server_ip)"
    fi
else
    echo "Certbot packages unavailable; SSL can be configured later."
fi

log_lang "Cai dat autossl hoan tat" "Automatic SSL step completed"

clear

printf "=========================================================================\n"
log_lang "Hoan tat qua trinh cau hinh..." "Server configuration completed"
printf "=========================================================================\n"
# aodieuVPS Script Admin
cd /home/$server_name/private_html/
mv -f "$administrator_tmp" administrator.zip || fail "Cannot stage checksum-verified administrator.zip"
unzip -q administrator.zip || fail "Cannot unpack administrator.zip"
rm -f administrator.zip
# Prevent partial admin upgrades or overwriting a pre-existing site. A fresh
# installation must have neither of these paths; use a separate repair for
# any server that already has an admin panel.
[ -d administrator/aodieuvps ] && [ -f administrator/index.php ] || fail "Administrator archive is incomplete"
if [ -e ./aodieuvps ] || [ -e ./index.php ]; then
    fail "Existing administrator files detected in $(pwd); refusing to overwrite an installed or partially installed panel"
fi
mv -- administrator/aodieuvps ./ || fail "Cannot install administrator directory"
mv -- administrator/index.php ./ || fail "Cannot install administrator index.php"
rmdir -- administrator || fail "Cannot finalize administrator staging directory"
# AodieuVPS admin was written for older PHP; reject parse errors during
# installation instead of displaying a broken admin panel after reboot.
while IFS= read -r -d '' admin_php; do
    php -l "$admin_php" >/dev/null || fail "Administrator PHP syntax error: $admin_php"
done < <(find "/home/$server_name/private_html/aodieuvps" -type f \( -name '*.php' -o -name '*.phtml' \) -print0)
php -l "/home/$server_name/private_html/index.php" >/dev/null || fail "Administrator index.php syntax error"
printf "admin:$(openssl passwd -apr1 $admin_password)\n" > /home/$server_name/private_html/aodieuvps/.htpasswd
sed -i "s/rootpassword/$root_password/g" /home/$server_name/private_html/aodieuvps/SQLManager.php

# Beszel v0.21.0: hub + local agent. Both bundled as checksum-pinned
# binary archives mirrored on aodieu.com; no Docker or Go required.
# The hub and agent listen on loopback only, behind the authenticated panel.
tar -tzf "$beszel_hub_tmp" | grep -qx 'beszel' || fail "Beszel hub archive invalid"
tar -tzf "$beszel_agent_tmp" | grep -qx 'beszel-agent' || fail "Beszel agent archive invalid"
mkdir -p /opt/aodieu-beszel /var/lib/aodieu-beszel /var/lib/aodieu-beszel-agent /etc/aodieuvps
tar -xOzf "$beszel_hub_tmp" beszel > /opt/aodieu-beszel/beszel || fail "Cannot unpack Beszel hub"
tar -xOzf "$beszel_agent_tmp" beszel-agent > /opt/aodieu-beszel/beszel-agent || fail "Cannot unpack Beszel agent"
chmod 755 /opt/aodieu-beszel/beszel /opt/aodieu-beszel/beszel-agent
[ "$(/opt/aodieu-beszel/beszel --version)" = "beszel version 0.21.0" ] || fail "Beszel hub version wrong"
/opt/aodieu-beszel/beszel-agent --version | grep -q '0.21.0' || fail "Beszel agent version wrong"
id beszel >/dev/null 2>&1 || useradd --system --home-dir /var/lib/aodieu-beszel --shell /sbin/nologin beszel
chown -R beszel:beszel /var/lib/aodieu-beszel /var/lib/aodieu-beszel-agent
chmod 700 /var/lib/aodieu-beszel /var/lib/aodieu-beszel-agent
chmod 755 /opt/aodieu-beszel
# Beszel creates its first user on the first run. Same generated admin password,
# but an email-style username is required for its independent login screen.
beszel_email='admin@localhost.localdomain'
beszel_admin_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')
[ -n "$beszel_admin_ip" ] || beszel_admin_ip=$(hostname -I | awk '{print $1}')
[ -n "$beszel_admin_ip" ] || beszel_admin_ip="$server_name"
printf 'APP_URL="http://%s:%s/serverinfo"\nUSER_EMAIL="%s"\nUSER_PASSWORD="%s"\n' "$beszel_admin_ip" "$admin_port" "$beszel_email" "$admin_password" > /etc/aodieuvps/beszel-hub.env
chmod 600 /etc/aodieuvps/beszel-hub.env
cat > /etc/systemd/system/aodieu-beszel.service <<'END'
[Unit]
Description=AodieuVPS Beszel Monitoring Hub
After=network.target
[Service]
Type=simple
User=beszel
Group=beszel
WorkingDirectory=/var/lib/aodieu-beszel
EnvironmentFile=/etc/aodieuvps/beszel-hub.env
ExecStart=/opt/aodieu-beszel/beszel serve --http 127.0.0.1:8090
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/lib/aodieu-beszel
PrivateTmp=true
[Install]
WantedBy=multi-user.target
END
systemctl daemon-reload
systemctl enable --now aodieu-beszel.service || fail "Beszel hub failed to start"
# Wait for PocketBase initial migrations/user bootstrap; no timed password guessing.
beszel_ready=false
for _ in $(seq 1 20); do
    if curl -fs --max-time 3 http://127.0.0.1:8090/api/health | grep -q 'API is healthy'; then beszel_ready=true; break; fi
    sleep 1
done
[ "$beszel_ready" = true ] || fail "Beszel hub did not become healthy"
fetch_required "$script_url/component/beszel-register.py" /tmp/aodieu-beszel-register.py
chmod 600 /tmp/aodieu-beszel-register.py
beszel_pubkey=$(AODIEUVPS_BESZEL_USER="$beszel_email" AODIEUVPS_BESZEL_PASSWORD="$admin_password" python3 /tmp/aodieu-beszel-register.py) || fail "Beszel local system registration failed"
rm -f /tmp/aodieu-beszel-register.py
[[ "$beszel_pubkey" == 'ssh-ed25519 '* ]] || fail "Beszel returned invalid local agent key"
# Remove bootstrap password from the service environment after first account exists.
printf 'APP_URL="http://%s:%s/serverinfo"\n' "$beszel_admin_ip" "$admin_port" > /etc/aodieuvps/beszel-hub.env
chmod 600 /etc/aodieuvps/beszel-hub.env
printf 'KEY="%s"\nLISTEN=127.0.0.1:45876\nNETWORK=tcp\nDATA_DIR=/var/lib/aodieu-beszel-agent\n' "$beszel_pubkey" > /etc/aodieuvps/beszel-agent.env
chmod 600 /etc/aodieuvps/beszel-agent.env
cat > /etc/systemd/system/aodieu-beszel-agent.service <<'END'
[Unit]
Description=AodieuVPS Beszel Local Monitoring Agent
After=network.target aodieu-beszel.service
Requires=aodieu-beszel.service
[Service]
Type=simple
User=beszel
Group=beszel
WorkingDirectory=/var/lib/aodieu-beszel-agent
EnvironmentFile=/etc/aodieuvps/beszel-agent.env
ExecStart=/opt/aodieu-beszel/beszel-agent
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/lib/aodieu-beszel-agent
PrivateTmp=true
[Install]
WantedBy=multi-user.target
END
systemctl daemon-reload
systemctl enable --now aodieu-beszel-agent.service || fail "Beszel agent failed to start"
sleep 2
systemctl is-active --quiet aodieu-beszel.service || fail "Beszel hub inactive"
systemctl is-active --quiet aodieu-beszel-agent.service || fail "Beszel agent inactive"

# phpMyAdmin (verify download and extraction instead of silently succeeding).
mkdir -p "/home/$server_name/private_html/phpmyadmin"
cd "/home/$server_name/private_html/phpmyadmin" || fail "Missing phpMyAdmin directory"
cp -- "$phpmyadmin_tmp" phpmyadmin.zip || fail "Cannot stage verified phpMyAdmin archive"
unzip -q phpmyadmin.zip || fail "Cannot extract phpMyAdmin ZIP"
[ -f "phpMyAdmin-$phpmyadmin_version-english/index.php" ] || fail "phpMyAdmin package is incomplete"
cp -a "phpMyAdmin-$phpmyadmin_version-english/." . || fail "Cannot install phpMyAdmin"
rm -rf phpmyadmin.zip "phpMyAdmin-$phpmyadmin_version-english"

# FileBrowser Quantum v2.0.1-stable, downloaded only from AodieuVPS hosting.
# The admin console remains at /filemanager/; daemon only binds loopback.
install -m 0755 "$filebrowser_tmp" /usr/local/bin/aodieu-filebrowser || fail "Cannot install FileBrowser Quantum"
mkdir -p /opt/aodieu-filebrowser /var/lib/aodieu-filebrowser
id nginx >/dev/null 2>&1 || fail "Nginx user unavailable"
chown root:nginx /opt/aodieu-filebrowser
chmod 750 /opt/aodieu-filebrowser
chown nginx:nginx /var/lib/aodieu-filebrowser
chmod 700 /var/lib/aodieu-filebrowser
cat > /opt/aodieu-filebrowser/config.yaml <<END
http:
  port: 12787
  listen: "127.0.0.1"
  baseURL: "/filemanager"
  trustProxyHeaders: true
server:
  database:
    path: "/var/lib/aodieu-filebrowser/database.sqlite"
  sources:
    - name: "Website"
      path: "/home/$server_name/public_html"
      config:
        defaultEnabled: true
auth:
  adminUsername: admin
  adminPassword: "$admin_password"
  methods:
    password:
      enabled: true
END
chown root:nginx /opt/aodieu-filebrowser/config.yaml
chmod 640 /opt/aodieu-filebrowser/config.yaml
cat > /etc/systemd/system/aodieu-filebrowser.service <<'END'
[Unit]
Description=AodieuVPS FileBrowser Quantum
After=network.target
[Service]
Type=simple
User=nginx
Group=nginx
WorkingDirectory=/var/lib/aodieu-filebrowser
ExecStart=/usr/local/bin/aodieu-filebrowser -c /opt/aodieu-filebrowser/config.yaml
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/lib/aodieu-filebrowser /home
[Install]
WantedBy=multi-user.target
END
systemctl daemon-reload
systemctl enable --now aodieu-filebrowser.service || fail "Cannot start FileBrowser Quantum"
# Readiness, not merely systemd's active state: initial DB/index setup takes time.
fb_ready=false
fb_deadline=$((SECONDS + 90))
while (( SECONDS < fb_deadline )); do
    fb_http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 --max-time 2 http://127.0.0.1:12787/filemanager/ || true)
    case "$fb_http_code" in
        200|301|302|303|307|308|401|403)
            if systemctl is-active --quiet aodieu-filebrowser.service; then fb_ready=true; break; fi ;;
    esac
    sleep 1
done
if [ "$fb_ready" != true ]; then
    systemctl status aodieu-filebrowser.service --no-pager -l >&2 || true
    journalctl -u aodieu-filebrowser.service -b -n 60 --no-pager >&2 || true
    fail "FileBrowser Quantum did not become ready within 90 seconds (HTTP $fb_http_code)"
fi

# Log Rotation
cat > "/etc/logrotate.d/nginx" <<END
/home/*/logs/access.log /home/*/logs/error.log /home/*/logs/nginx_error.log {
	create 640 nginx nginx
        daily
	dateext
        missingok
        rotate 5
        maxage 7
        compress
	size=100M
        notifempty
        sharedscripts
        postrotate
                [ -f /var/run/nginx.pid ] && kill -USR1 \`cat /var/run/nginx.pid\`
        endscript
	su nginx nginx
}
END
cat > "/etc/logrotate.d/php-fpm" <<END
/home/*/logs/php-fpm*.log {
        daily
	dateext
        compress
        maxage 7
        missingok
        notifempty
        sharedscripts
        size=100M
        postrotate
            /bin/kill -SIGUSR1 \`cat /var/run/php-fpm/php-fpm.pid 2>/dev/null\` 2>/dev/null || true
        endscript
	su nginx nginx
}
END
cat > "/etc/logrotate.d/mysql" <<END
/home/*/logs/mysql*.log {
        create 640 mysql mysql
        notifempty
        daily
        rotate 3
        maxage 7
        missingok
        compress
        postrotate
        # just if mysqld is really running
        if test -x /usr/bin/mysqladmin && \
           /usr/bin/mariadb-admin ping &>/dev/null
        then
           /usr/bin/mariadb-admin flush-logs
        fi
        endscript
	su mysql mysql
}
END

# Change port SSH
# Keep the original SSH port 2222, but ensure it takes effect on EL10.
if grep -qE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config; then
    sed -i -E 's/^[[:space:]]*Port[[:space:]]+[0-9]+/Port 2222/' /etc/ssh/sshd_config
else
    printf '\nPort 2222\n' >> /etc/ssh/sshd_config
fi
sshd -t || fail "SSH configuration invalid; SSH service left running"
systemctl reload sshd.service || fail "Cannot reload SSH for port 2222"

cat > "/etc/fail2ban/jail.local" <<END
[sshd]
enabled  = true
filter   = sshd
action   = iptables[name=SSH, port=2222, protocol=tcp]
logpath  = /var/log/secure
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
action = iptables[name=NoAuthFailures, port=$admin_port, protocol=tcp]
logpath = /home/$server_name/logs/nginx_error.log
maxretry = 3
bantime = 3600
END

systemctl start fail2ban.service || echo "WARNING: fail2ban did not start; review /etc/fail2ban/jail.local"

# Refresh persistent iptables rules (already opened above, before firewall switch).
iptables-save > /etc/sysconfig/iptables || fail "Unable to save persistent iptables rules"

mkdir -p /var/lib/php/session
chown -R nginx:nginx /var/lib/php
chown nginx:nginx /home/$server_name
chown -R nginx:nginx /home/*/public_html
chown -R nginx:nginx /home/*/private_html

rm -f /root/install
grep -qxF "cd /home" /root/.bashrc 2>/dev/null || echo "cd /home" >> /root/.bashrc

mkdir -p /etc/aodieuvps/

cat > "/etc/aodieuvps/scripts.conf" <<END
aodieuvps_version="$aodieuvps_version"
script_language="$installer_language"
server_name="$server_name"
server_ip="$server_ip"
admin_port="$admin_port"
script_url="$script_url"
mariadb_root_password="$root_password"
END
chmod 600 /etc/aodieuvps/scripts.conf

clear
printf "=========================================================================\n"
log_lang "Cau hinh hoan tat, bat dau them menu aodieuvps, nhanh thoi..." "Installing AodieuVPS administration menu..."
printf "=========================================================================\n"

fetch_required "$script_url/aodieuvps" /bin/aodieuvps && chmod +x /bin/aodieuvps
# Install read-only post-install diagnostics as an AodieuVPS-managed menu tool.
# Logs are collected on demand, never into an admin web directory or Downloads.
mkdir -p /usr/local/libexec/aodieuvps
fetch_required "$script_url/component/aodieu-rocky10-diagnostics.sh" /usr/local/libexec/aodieuvps/diagnostics.sh
chmod 700 /usr/local/libexec/aodieuvps/diagnostics.sh
bash -n /usr/local/libexec/aodieuvps/diagnostics.sh || fail "Invalid diagnostic collector script"
mkdir -p -m 700 /root/aodieuvps-diagnostics
chmod 700 /root/aodieuvps-diagnostics
mkdir /etc/aodieuvps/menu/
cd /etc/aodieuvps/menu/
fetch_required "$script_url/component/menu.zip" menu.zip
unzip -q menu.zip || fail "Cannot unpack menu.zip"
rm -f menu.zip
chmod +x /etc/aodieuvps/menu/*
chmod +x /etc/aodieuvps/menu/en/*

# Do not report installation success while mandatory components have failed.
for mandatory_service in nginx php-fpm mariadb iptables aodieu-filebrowser aodieu-beszel aodieu-beszel-agent; do
    systemctl is-active --quiet "$mandatory_service" || fail "Required service not active: $mandatory_service"
done
nginx -t || fail "Final Nginx configuration invalid"
php-fpm -t || fail "Final PHP-FPM configuration invalid"
curl -fsS --max-time 5 http://127.0.0.1:8090/api/health >/dev/null || fail "Beszel hub is not healthy"
[ -s "/home/$server_name/private_html/phpmyadmin/index.php" ] || fail "phpMyAdmin was not installed"

# The earlier PHP 8.4 failure passed static checks but broke the authenticated
# admin page. Exercise the full Nginx -> PHP-FPM -> administrator path before
# claiming installation complete.  No credentials or page bodies are logged.
admin_health_url="http://127.0.0.1:$admin_port"
admin_http_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
    -u "admin:$admin_password" "$admin_health_url/" || true)
[ "$admin_http_code" = 200 ] || fail "Administrator authenticated HTTP check failed: $admin_http_code; inspect /home/$server_name/logs/nginx_error.log and PHP-FPM logs"
phpmyadmin_http_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
    -u "admin:$admin_password" "$admin_health_url/phpmyadmin/" || true)
case "$phpmyadmin_http_code" in
    200|301|302|303) : ;;
    *) fail "phpMyAdmin HTTP check failed: $phpmyadmin_http_code" ;;
esac
filebrowser_http_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
    -u "admin:$admin_password" "$admin_health_url/filemanager/" || true)
case "$filebrowser_http_code" in
    200|301|302|303|307|308) : ;;
    *) fail "FileBrowser Nginx reverse-proxy check failed: $filebrowser_http_code" ;;
esac
# Beszel's own login page must not generate Nginx Basic-auth challenges.
# Sending a Basic Authorization header here masks the browser/Bearer conflict.
beszel_http_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
    "$admin_health_url/serverinfo/" || true)
if curl -sSI --max-time 15 "$admin_health_url/serverinfo/" | \
    grep -qi '^WWW-Authenticate:[[:space:]]*Basic'; then
    fail "Beszel login still triggers Nginx Basic authentication"
fi
case "$beszel_http_code" in
    200|301|302|303|307|308) : ;;
    *) fail "Beszel Nginx reverse-proxy check failed: $beszel_http_code" ;;
esac
# Safe-to-share compact status receipt: no passwords, hashes or tokens.
cat > /root/aodieuvps-install-health.txt <<HEALTH
AodieuVPS Rocky Linux 10 installation health
PHP: $(php -r 'echo PHP_VERSION;')
MariaDB: $(mariadb -NBe 'SELECT VERSION();')
Nginx configuration: PASS
PHP-FPM configuration: PASS
Administrator authenticated HTTP: $admin_http_code
phpMyAdmin HTTP: $phpmyadmin_http_code
FileBrowser HTTP: $filebrowser_http_code
Beszel HTTP: $beszel_http_code
Beszel hub and agent: ACTIVE
Services: nginx php-fpm mariadb iptables aodieu-filebrowser aodieu-beszel aodieu-beszel-agent
HEALTH
chmod 600 /root/aodieuvps-install-health.txt
clear
cat > "/root/aodieuvps-script.txt" <<END
=========================================================================
                           MANAGE VPS INFORMATION                        
=========================================================================
Lenh truy cap menu aodieuVPS Script: aodieuvps
Menu 21: Thu Thap Bao Cao Cai Dat / Collect Installation Diagnostics
Diagnostic result folder (no GUI): /root/aodieuvps-diagnostics/
Diagnostic file format: aodieu-rocky10-diagnostics-YYYYMMDD-HHMMSS.tar.gz
Menu 22: Thoat / Exit

Domain chinh: http://$server_name/ hoac http://$server_ip/

aodieuVPS Script Admin:	http://$server_name:$admin_port/ hoac http://$server_ip:$admin_port/
File Manager:		http://$server_name:$admin_port/filemanager/ hoac http://$server_ip:$admin_port/filemanager/
phpMyAdmin:		http://$server_name:$admin_port/phpmyadmin/ hoac http://$server_ip:$admin_port/phpmyadmin/
Beszel monitoring:		http://$server_name:$admin_port/serverinfo/ hoac http://$server_ip:$admin_port/serverinfo/
PHP OPcache:		http://$server_name:$admin_port/op.php hoac http://$server_ip:$admin_port/op.php

Thong tin dang nhap mac dinh cho tat ca tool:
Username: admin
Password: $admin_password
Beszel email: admin@localhost.localdomain
Beszel password: $admin_password

Neu can ho tro, cac ban hay truy cap https://aodieu.com/script/
END

chmod 600 /root/aodieuvps-script.txt

if [ "$installer_language" = en ]; then
    printf '========================================================================\n'
    printf 'AodieuVPS installation complete. Save /root/aodieuvps-script.txt securely.\n'
    printf 'Primary domain: http://%s/ or http://%s/\n' "$server_name" "$server_ip"
    printf 'Administrator: http://%s:%s/\n' "$server_name" "$admin_port"
    printf 'FileBrowser Quantum: http://%s:%s/filemanager/\n' "$server_name" "$admin_port"
    printf 'Beszel monitoring: http://%s:%s/serverinfo/\n' "$server_name" "$admin_port"
    printf 'phpMyAdmin: http://%s:%s/phpmyadmin/\n' "$server_name" "$admin_port"
    printf 'Username: admin\nPassword: %s\n' "$admin_password"
    printf 'Beszel login email: admin@localhost.localdomain (same generated password)\n' 
    printf 'SSH port: 2222. Admin interface currently uses HTTP; configure HTTPS before public exposure.\n'
    printf 'Menu 21: collect diagnostics to /root/aodieuvps-diagnostics/ (root-only).\n'
    printf 'Run aodieuvps to open the management menu. Rebooting in 3 seconds...\n'
else
    printf '========================================================================\n'
    printf 'Cai dat aodieuVPS thanh cong. Luu /root/aodieuvps-script.txt an toan.\n'
    printf 'Ten mien: http://%s/ hoac http://%s/\n' "$server_name" "$server_ip"
    printf 'Quan tri: http://%s:%s/\n' "$server_name" "$admin_port"
    printf 'FileBrowser Quantum: http://%s:%s/filemanager/\n' "$server_name" "$admin_port"
    printf 'Beszel monitoring: http://%s:%s/serverinfo/\n' "$server_name" "$admin_port"
    printf 'phpMyAdmin: http://%s:%s/phpmyadmin/\n' "$server_name" "$admin_port"
    printf 'Tai khoan: admin\nMat khau: %s\n' "$admin_password"
    printf 'Beszel email: admin@localhost.localdomain (cung mat khau)\n' 
    printf 'Port SSH: 2222. Giao dien quan tri hien la HTTP, hay cau hinh HTTPS truoc khi cong khai.\n'
    printf 'Menu 21: thu thap bao cao vao /root/aodieuvps-diagnostics/ (chi root).\n'
    printf 'Chay aodieuvps de mo menu quan ly. Khoi dong lai sau 3 giay...\n'
fi
printf '========================================================================\n'
sleep 3
reboot
exit
