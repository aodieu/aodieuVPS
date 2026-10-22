#!/bin/bash
# Only for the supplied Rocky 10 install interrupted at the FileBrowser HTTP gate.
set -e
umask 077
[ "$(id -u)" = 0 ] || { echo "Run as root" >&2; exit 1; }
base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fail() { printf 'Recovery ERROR: %s\n' "$*" >&2; exit 1; }
installer_language=en
msg() { printf '%s' "$2"; }
log_lang() { msg "$@"; printf '\n'; }
script_url=https://aodieu.com/script/scripts/10
aodieuvps_version=2.1
fetch_required() {
    local relative=${1#"$script_url/"}
    [ "$relative" != "$1" ] || fail "Unexpected asset path"
    [ -s "$base/$relative" ] || fail "Missing local asset: $relative; extract the entire package"
    cp -- "$base/$relative" "$2" || fail "Cannot install local asset"
}
[ ! -e /etc/aodieuvps/scripts.conf ] || fail "Installation already finalized; this is not an updater"
[ -f /etc/nginx/nginx.conf ] || fail "Missing existing Nginx installation"
[ -f /root/.my.cnf ] || fail "Missing existing MariaDB credentials"
[ -f /opt/aodieu-filebrowser/config.yaml ] || fail "Missing existing FileBrowser configuration"
# Parse only the exact generated scalar fields; never execute existing configs.
mapfile -t recovered < <(python3 - <<'RECOVER'
import re
from pathlib import Path
s=Path('/opt/aodieu-filebrowser/config.yaml').read_text()
def field(pattern,text):
    m=re.search(pattern,text,re.M)
    if not m: raise SystemExit('Cannot recognize original installer configuration')
    return m.group(1)
domain=field(r'^      path: "/home/([^/]+)/public_html"$',s)
if not re.fullmatch(r'[A-Za-z0-9.-]+',domain): raise SystemExit('Invalid domain')
ng=Path('/etc/nginx/conf.d/'+domain+'.conf').read_text()
port=field(r'listen\s+(\d+);\s*access_log off;',ng)
password=field(r'^  adminPassword: "([a-f0-9]{36})"$',s)
db=field(r'^password=([a-f0-9]{36})$',Path('/root/.my.cnf').read_text())
print(domain); print(port); print(password); print(db)
RECOVER
)
[ "${#recovered[@]}" = 4 ] || fail "Could not recover original settings; no finalization performed"
server_name=${recovered[0]}
admin_port=${recovered[1]}
admin_password=${recovered[2]}
root_password=${recovered[3]}
server_ip=$(hostname -I | awk '{print $1}')
[ -n "$server_ip" ] || fail "No local IP address"
nginx -t || fail "Existing Nginx configuration invalid"
mariadb -NBe 'SELECT 1' >/dev/null || fail "Existing database credentials do not work"
# Preserve files changed by the remaining original installation steps.
backup=/root/aodieuvps-recovery-$(date +%Y%m%d-%H%M%S)-$$
mkdir -m 700 "$backup"
for item in /etc/logrotate.d/nginx /etc/logrotate.d/php-fpm /etc/logrotate.d/mysql /etc/ssh/sshd_config /etc/fail2ban/jail.local /etc/sysconfig/iptables /root/.bashrc; do
    [ ! -e "$item" ] || cp --parents -a "$item" "$backup/"
done
printf 'Configuration backup: %s\n' "$backup"
# Do not restart services or reset any account/password/database.
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

# Recovery preserves existing SSH and fail2ban settings.

# Refresh persistent iptables rules (already opened above, before firewall switch).
iptables-save > /etc/sysconfig/iptables || fail "Unable to save persistent iptables rules"

mkdir -p /var/lib/php/session
chown -R nginx:nginx /var/lib/php
chown nginx:nginx /home/$server_name
chown -R nginx:nginx /home/*/public_html
chown -R nginx:nginx /home/*/private_html

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
mkdir -p /etc/aodieuvps/menu/
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
    printf 'SSH configuration preserved. Admin interface currently uses HTTP; configure HTTPS before public exposure.\n'
    printf 'Menu 21: collect diagnostics to /root/aodieuvps-diagnostics/ (root-only).\n'
    printf 'Run aodieuvps to open the management menu. Recovery complete; no reboot requested.\n'
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
exit 0
