#!/usr/bin/env bash
# AodieuVPS Rocky Linux 10 — post-install diagnostic collector (menu option 21)
# Read-only collection, except temporary files and the final archive.
# Never bundles config secrets, password files, database content, or private keys.
set -u
umask 077

if [[ $EUID -ne 0 ]]; then
    printf 'ERROR: run as root, preferably: sudo bash %s\n' "$0" >&2
    exit 1
fi
for utility in bash tar mktemp python3; do
    command -v "$utility" >/dev/null 2>&1 || { echo "ERROR: required utility not found: $utility" >&2; exit 1; }
done

STAMP=$(date +%Y%m%d-%H%M%S)
TMP=$(mktemp -d -t aodieu-diagnostics.XXXXXXXX) || exit 1
OUT="$TMP/aodieu-rocky10-diagnostics-$STAMP"
mkdir -m 700 "$OUT"
trap 'rm -rf -- "$TMP"' EXIT

# Works on headless servers. Store archives in a root-only persistent directory.
# Optional absolute-path override is useful for offline testing or administration.
DEST="${AODIEUVPS_DIAGNOSTICS_DIR:-/root/aodieuvps-diagnostics}"
case "$DEST" in
    /*) ;;
    *) printf 'ERROR: diagnostic destination must be an absolute path\n' >&2; exit 1 ;;
esac
if [[ -L "$DEST" ]]; then
    printf 'ERROR: diagnostic destination must not be a symlink: %s\n' "$DEST" >&2
    exit 1
fi
mkdir -p -m 700 -- "$DEST" || exit 1
chmod 700 -- "$DEST" || exit 1

cat > "$OUT/README-FIRST.txt" <<'EOF'
AodieuVPS — Rocky Linux 10 post-install diagnostic bundle

Collected using only local, read-only diagnostic commands. Password/configuration
files, shell history, database data, .htpasswd, SSH keys and environment secrets
are deliberately NOT included. Included diagnostic excerpts have been automatically
redacted as a defense in depth, but redaction is NOT guaranteed perfect.

Archive default location: /root/aodieuvps-diagnostics/ (no desktop GUI required).

Before uploading to ChatGPT, review this archive and remove any private details
(e.g., home network IPs, domain names, user names, or credentials) you do not
wish to share. Upload the .tar.gz file only; not /root/aodieuvps-script.txt.

The latest installer creates /root/aodieuvps-install-health.txt after its final
smoke tests. An interactive install terminal log cannot be reconstructed after
the fact unless it was already recorded by 'script' or similar.

Status 401 on an unauthenticated admin URL is expected. Look in
http-admin-authenticated.txt to see status codes obtained with the local admin
password WITHOUT writing that password into this archive.
EOF

# Redact all captured text. Stronger protection: omit raw configs and secrets entirely.
# This also strips known generated secrets from their values, if found in logs.
cat > "$TMP/redact.py" <<'PY'
import pathlib, re, sys
secrets=set()
for p in (pathlib.Path('/etc/aodieuvps/scripts.conf'), pathlib.Path('/root/aodieuvps-script.txt')):
    try:
        src=p.read_text(errors='replace')
    except (OSError, UnicodeError):
        continue
    for line in src.splitlines():
        m=re.match(r'^\s*(?:mariadb_root_password|mysql_root_password|root_password|admin_password|Password|Beszel password)\s*[:=]\s*(.*?)\s*$',line,re.I)
        if m:
            token=m.group(1).strip().strip('"\'')
            if len(token)>=4:
                secrets.add(token)
raw=sys.stdin.read()
for token in sorted(secrets,key=len,reverse=True):
    raw=raw.replace(token,'[REDACTED-KNOWN-SECRET]')
patterns=[
    (r'(?i)(authorization\s*:\s*(?:basic|bearer)\s+)\S+',r'\1[REDACTED]'),
    (r'(?i)((?:password|passwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|mariadb_root_password|root_password|admin_password)\s*[:=]\s*)[^\s,;]+',r'\1[REDACTED]'),
    (r'(?i)([?&](?:password|passwd|token|key|secret|authorization)=)[^\s&]+',r'\1[REDACTED]'),
    (r'(?i)(https?://[^:/\s]+:)[^@/\s]+@',r'\1[REDACTED]@'),
    (r'(?i)(-u\s+[^:\s]+:)[^\s]+',r'\1[REDACTED]'),
    (r'(?i)(cookie\s*:\s*).*',r'\1[REDACTED]'),
    (r'(?i)(set-cookie\s*:\s*).*',r'\1[REDACTED]'),
]
for find,sub in patterns:
    raw=re.sub(find,sub,raw)
sys.stdout.write(raw)
PY

capture() {
    local name=$1; shift
    local raw="$TMP/current-command.txt"
    { "$@"; } >"$raw" 2>&1 || true
    python3 "$TMP/redact.py" < "$raw" > "$OUT/$name.txt"
    : > "$raw"
}

capture_shell() {
    local name=$1; shift
    capture "$name" bash -c "$*"
}

# Exact version, stack, and networking evidence; no configuration file contents.
capture_shell system-and-resources '
  echo "== Collected at =="; date -Is
  echo "== Rocky / OS =="; cat /etc/rocky-release /etc/os-release 2>/dev/null
  echo "== Kernel =="; uname -a
  echo "== Hostname =="; hostname
  echo "== Uptime =="; uptime
  echo "== Architecture =="; uname -m
  echo "== Memory =="; free -h
  echo "== Disk / inodes =="; df -hT / /home /var 2>/dev/null; df -ih / /home /var 2>/dev/null
  echo "== Mount types =="; findmnt -rno TARGET,FSTYPE,OPTIONS / /home /var 2>/dev/null
  echo "== Selinux =="; getenforce 2>/dev/null; sestatus 2>/dev/null
  echo "== Host firewalls =="; systemctl is-active firewalld iptables nftables 2>/dev/null
  echo "== Active devices =="; nmcli -f DEVICE,TYPE,STATE device status 2>/dev/null
  echo "== IP addresses =="; ip -br addr 2>/dev/null
  echo "== Routes =="; ip route 2>/dev/null
  echo "== DNS lookup =="; getent ahostsv4 aodieu.com 2>/dev/null | head -n 6
  echo "== Time and timezone =="; timedatectl status 2>/dev/null
'

capture_shell software-versions '
  echo "== nginx =="; nginx -v 2>&1
  echo "== php CLI =="; php -v 2>&1
  echo "== php-fpm =="; php-fpm -v 2>&1
  echo "== PHP modules =="; php -m 2>&1
  echo "== PHP ini paths =="; php --ini 2>&1
  echo "== MariaDB =="; mariadb --version 2>&1
  echo "== MariaDB server version (no database data) =="; timeout 8 mariadb --batch --skip-column-names -e "SELECT VERSION();" 2>&1
  echo "== Certbot =="; certbot --version 2>&1
  echo "== Python =="; python3 --version 2>&1
  echo "== FileBrowser Quantum =="; timeout 6 /usr/local/bin/aodieu-filebrowser version 2>&1 | head -n 15
  echo "== Beszel Hub =="; timeout 6 /opt/aodieu-beszel/beszel --version 2>&1 | head -n 15
  echo "== Beszel Agent =="; timeout 6 /opt/aodieu-beszel/beszel-agent --version 2>&1 | head -n 15
'

capture_shell service-state '
  echo "== Failed units =="; systemctl --no-pager --failed --type=service
  for name in nginx php-fpm mariadb iptables firewalld fail2ban sshd crond syslog-ng rsyslog aodieu-filebrowser aodieu-beszel aodieu-beszel-agent; do
    echo "== $name =="
    systemctl show "$name.service" --no-pager \
      -p LoadState -p ActiveState -p SubState -p UnitFileState \
      -p Result -p ExecMainCode -p ExecMainStatus -p NRestarts 2>&1
  done
'

capture_shell configuration-validation '
  echo "== nginx -t =="; nginx -t 2>&1
  echo "== php-fpm -t =="; php-fpm -t 2>&1
  echo "== sshd -t =="; sshd -t 2>&1; echo "sshd-exit=${PIPESTATUS[0]}"
  echo "== sshd effective port =="; sshd -T 2>/dev/null | grep -E "^(port|permitrootlogin|passwordauthentication) "
  echo "== PHP config (non-secret selected settings) =="
  php -r '\''foreach(["date.timezone","memory_limit","upload_max_filesize","post_max_size","max_execution_time","opcache.enable","opcache.memory_consumption"] as $k) echo "$k=".ini_get($k).PHP_EOL;'\'' 2>&1
  echo "== SELinux Nginx proxy boolean =="; getsebool httpd_can_network_connect 2>&1
'

capture_shell sockets-firewall '
  echo "== Listeners =="; ss -lntp 2>&1
  echo "== Firewall IPv4 INPUT =="; iptables -S INPUT 2>&1
  echo "== Firewall IPv4 current rules =="; iptables -L INPUT -n -v --line-numbers 2>&1
  echo "== Nftables summary =="; nft -a list tables 2>&1
  echo "== Fail2Ban =="; timeout 8 fail2ban-client status 2>&1
  echo "== Fail2Ban Nginx jail =="; timeout 8 fail2ban-client status nginx-http-auth 2>&1
'

capture_shell installation-artifacts '
  echo "== Known installer reports =="
  for f in /root/aodieuvps-install-health.txt /root/aodieu-test/install.sanitized.log /root/aodieu-test/post-install.log; do
    if [ -f "$f" ]; then stat -c "%n size=%s modified=%y" "$f"; else echo "NOT FOUND: $f"; fi
  done
  echo "== Package state =="; rpm -q nginx php-fpm mariadb-server iptables-nft-services fail2ban certbot syslog-ng 2>&1
  echo "== Installed AodieuVPS configuration presence, not values =="
  for f in /etc/aodieuvps/scripts.conf /root/aodieuvps-script.txt /etc/aodieuvps/beszel-hub.env /etc/aodieuvps/beszel-agent.env /opt/aodieu-filebrowser/config.yaml /etc/systemd/system/aodieu-beszel.service /etc/systemd/system/aodieu-beszel-agent.service /etc/systemd/system/aodieu-filebrowser.service; do
    if [ -e "$f" ]; then stat -c "%n mode=%a owner=%U:%G size=%s" "$f"; else echo "MISSING: $f"; fi
  done
  echo "== AodieuVPS admin app files, metadata only =="
  for f in /home/*/private_html/aodieuvps/{index.php,EncryptionMd5.php,.htpasswd}; do
    if [ -e "$f" ]; then stat -c "%n mode=%a owner=%U:%G size=%s" "$f"; fi
  done
  echo "== DNF history =="; dnf history list 2>&1 | head -n 45
  echo "== Package repository list =="; dnf repolist --enabled 2>&1
'

# Installer-generated report contains only statuses / versions; never the password file.
if [[ -f /root/aodieuvps-install-health.txt ]]; then
    capture "installer-health-report" cat /root/aodieuvps-install-health.txt
else
    printf 'NOT FOUND: /root/aodieuvps-install-health.txt\nThe installer may have failed before its final checks.\n' > "$OUT/installer-health-report.txt"
fi

# If 'script' was used earlier, collect the already-sanitized transcript. Do not
# collect install.raw.log: it may contain administrator credentials.
if [[ -f /root/aodieu-test/install.sanitized.log ]]; then
    capture_shell prior-install-terminal-log 'tail -n 1500 /root/aodieu-test/install.sanitized.log'
else
    printf 'No previously recorded, sanitized terminal transcript was found.\nFull interactive output cannot be recovered retroactively.\n' > "$OUT/prior-install-terminal-log.txt"
fi

# Exact local authenticated smoke checks, credentials retained in memory only.
# Python's http.client does not follow redirects or print page contents.
PORT=$(sed -nE 's/^[[:space:]]*admin_port="?([0-9]{2,5})"?.*/\1/p' /etc/aodieuvps/scripts.conf 2>/dev/null | head -n 1)
if [[ ! "$PORT" =~ ^[0-9]{2,5}$ ]] || (( PORT < 1 || PORT > 65535 )); then PORT=2026; fi
python3 - "$PORT" > "$OUT/http-admin-authenticated.txt" 2>&1 <<'PY'
import base64, http.client, pathlib, re, sys
port=int(sys.argv[1]); password=None
try:
    source=pathlib.Path('/root/aodieuvps-script.txt').read_text(errors='replace')
    match=re.search(r'^Password:\s*(.+?)\s*$', source, re.M)
    if match: password=match.group(1).strip()
except OSError: pass
print('Admin port:',port)
if not password: print('Password could not be read locally; checking URLs without credentials.')
for path in ('/', '/phpmyadmin/', '/filemanager/', '/serverinfo/', '/op.php'):
    headers={'Host':'127.0.0.1', 'User-Agent':'AodieuVPS-PostInstall-Diagnostics/1'}
    if password:
        headers['Authorization']='Basic '+base64.b64encode(('admin:'+password).encode()).decode()
    try:
        c=http.client.HTTPConnection('127.0.0.1',port,timeout=8)
        c.request('GET',path,headers=headers)
        r=c.getresponse()
        print(f'{path:18s} HTTP {r.status} {r.reason}')
        c.close()
    except Exception as exc:
        print(f'{path:18s} CONNECTION ERROR: {type(exc).__name__}')
PY
python3 "$TMP/redact.py" < "$OUT/http-admin-authenticated.txt" > "$TMP/safe-http.txt"
cp "$TMP/safe-http.txt" "$OUT/http-admin-authenticated.txt"

capture_shell http-local-backends '
  echo "== Admin without credentials (401 expected) =="
  for path in / /phpmyadmin/ /filemanager/ /serverinfo/ /op.php; do
    code=$(curl --noproxy "*" -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 8 "http://127.0.0.1:'"$PORT"'${path}" || true)
    echo "${path} HTTP ${code:-unavailable}"
  done
  echo "== Beszel hub health =="
  curl --noproxy "*" -s -o /dev/null -w "HTTP %{http_code}\n" --connect-timeout 3 --max-time 8 http://127.0.0.1:8090/api/health || true
  echo "== FileBrowser local endpoint =="
  curl --noproxy "*" -s -o /dev/null -w "HTTP %{http_code}\n" --connect-timeout 3 --max-time 8 http://127.0.0.1:12787/filemanager/ || true
  echo "== Beszel agent listening =="; ss -lntp 2>/dev/null | grep 45876 || true
'

capture_shell administrator-php-lint '
  echo "== Administrator PHP compatibility check =="
  for dir in /home/*/private_html/aodieuvps; do
    if [ ! -d "$dir" ]; then continue; fi
    echo "Admin directory: $dir"
    find "$dir" -type f -name "*.php" -print0 2>/dev/null | head -z -n 120 | while IFS= read -r -d "" f; do
      php -l "$f" 2>&1 || true
    done
  done
'

# Targeted journal and web server errors; bounded to avoid oversized uploads.
for unit in nginx php-fpm mariadb iptables fail2ban sshd aodieu-filebrowser aodieu-beszel aodieu-beszel-agent; do
    capture "journal-${unit}" journalctl -b -u "$unit.service" --no-pager -o short-iso -n 250
    capture "previous-boot-${unit}" journalctl -b -1 -u "$unit.service" --no-pager -o short-iso -n 60
done
capture "system-errors" journalctl -b -p err --no-pager -o short-iso -n 220
capture "dnf-recent-log" bash -c 'tail -n 350 /var/log/dnf.log /var/log/dnf.rpm.log /var/log/dnf5.log 2>/dev/null'

for logfile in /var/log/nginx/error.log /var/log/php-fpm/error.log /var/log/mariadb/mariadb.log /var/log/mysql/mysqld.log /var/log/secure; do
    if [[ -f "$logfile" ]]; then
        key=$(basename "$(dirname "$logfile")")-$(basename "$logfile" | tr . _)
        capture "log-${key}" tail -n 220 "$logfile"
    fi
done
for logfile in /home/*/logs/nginx_error.log /home/*/logs/error.log /home/*/logs/php-fpm*.log /home/*/logs/mysql*.log; do
    if [[ -f "$logfile" ]]; then
        # Avoid uploading full paths with potentially sensitive account names in filenames.
        label="site-log-$(basename "$logfile" | tr . _ )"
        [[ ! -f "$OUT/$label.txt" ]] || label="${label}-additional"
        capture "$label" tail -n 220 "$logfile"
    fi
done

capture_shell websites-http-reachability '
  echo "No downloads performed. These are header-only network checks."
  for url in \
    https://aodieu.com/script/install \
    https://aodieu.com/script/scripts/10/install.sh \
    https://aodieu.com/script/scripts/10/package/administrator.zip \
    https://aodieu.com/script/scripts/10/package/beszel_linux_amd64.tar.gz \
    https://aodieu.com/script/scripts/10/package/beszel-agent_linux_amd64.tar.gz \
    https://aodieu.com/script/scripts/10/package/filebrowser-quantum-linux-amd64; do
      echo "$url"
      curl -L -I -s -o /dev/null -w "HTTP %{http_code}; remote_ip=%{remote_ip}\n" \
        --connect-timeout 4 --max-time 12 "$url" || true
  done
'

cat > "$OUT/collection-summary.txt" <<EOF
Diagnostic collection finished at: $(date -Is)
Detected Rocky release: $(cat /etc/rocky-release 2>/dev/null || echo 'unknown')
Admin port used for checks: $PORT
Full installer transcript: $([[ -f /root/aodieu-test/install.sanitized.log ]] && echo 'sanitized capture included' || echo 'not recorded; no historical terminal transcript available')
Installation health report: $([[ -f /root/aodieuvps-install-health.txt ]] && echo 'included' || echo 'missing')
EOF

ARCHIVE="$DEST/aodieu-rocky10-diagnostics-$STAMP.tar.gz"
tar -C "$TMP" -czf "$ARCHIVE" "$(basename "$OUT")" || { echo 'ERROR: archive creation failed' >&2; exit 1; }
chmod 600 "$ARCHIVE"
printf '\nDiagnostics collected successfully.\nArchive: %s\nSize: ' "$ARCHIVE"
du -h "$ARCHIVE" | awk '{print $1}'
printf '\nReview the archive before uploading it here. Do NOT upload password/config files.\n'
