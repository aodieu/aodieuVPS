#!/usr/bin/env bash
# AodieuVPS Rocky Linux 10: targeted Beszel login fix, no reinstall.
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo "Run this script as root" >&2; exit 1; fi
shopt -s nullglob
candidates=()
for conf in /etc/nginx/conf.d/*.conf; do
  if grep -Fq 'location ^~ /serverinfo/ {' "$conf"; then candidates+=("$conf"); fi
done
if (( ${#candidates[@]} != 1 )); then
  printf 'Expected exactly one Beszel Nginx server configuration, found %s. No changes made.\n' "${#candidates[@]}" >&2
  exit 1
fi
target="${candidates[0]}"
mkdir -p -m 700 /root/aodieuvps-nginx-backups
backup=$(mktemp "/root/aodieuvps-nginx-backups/$(basename "$target").beszel.XXXXXXXX")
chmod 600 "$backup"
cp -p "$target" "$backup"
restore() { cp -p "$backup" "$target"; nginx -t || true; systemctl reload nginx || true; }
if ! python3 - "$target" <<'PYFIX'
from pathlib import Path
import sys, os, tempfile
p=Path(sys.argv[1]); original=p.read_text()
start=original.find('location ^~ /serverinfo/ {')
if start<0: sys.exit('Missing Beszel proxy location')
end=original.find('\n        }',start)
if end<0: sys.exit('Could not safely find end of Beszel location')
block=original[start:end]
if 'auth_basic off;' not in block:
    block=block.replace('location ^~ /serverinfo/ {','location ^~ /serverinfo/ {\n            auth_basic off;',1)
if 'proxy_set_header Authorization "";' in block:
    block=block.replace('proxy_set_header Authorization "";', 'proxy_set_header Authorization $http_authorization;',1)
if 'proxy_set_header Authorization $http_authorization;' not in block:
    sys.exit('Cannot verify Beszel Bearer authorization forwarding; refusing to change file')
new=original[:start]+block+original[end:]
old_redirect='location = /serverinfo { return 301 /serverinfo/; }'
new_redirect='location = /serverinfo { auth_basic off; return 301 /serverinfo/; }'
if old_redirect in new:
    new=new.replace(old_redirect,new_redirect,1)
elif new_redirect not in new:
    sys.exit('Cannot verify Beszel redirect; refusing to change file')
if new==original:
    print('Beszel Nginx authentication already corrected.')
else:
    fd,name=tempfile.mkstemp(prefix='.beszel-',dir=str(p.parent))
    try:
        os.fchmod(fd,p.stat().st_mode & 0o777)
        with os.fdopen(fd,'w') as f: f.write(new)
        os.replace(name,p)
    finally:
        if os.path.exists(name): os.unlink(name)
    print('Updated Beszel authentication in:',p)
PYFIX
then
  restore
  exit 1
fi
if ! nginx -t; then
  echo 'Invalid Nginx config. Restoring backup.' >&2
  restore
  exit 1
fi
if ! systemctl reload nginx; then
  echo 'Nginx reload failed. Restoring backup.' >&2
  restore
  exit 1
fi
printf 'Beszel login fix applied. Config backup: %s\n' "$backup"
echo 'Other AodieuVPS administration pages retain Nginx Basic authentication.'
echo 'Open http://YOUR_SERVER_IP:2026/serverinfo/ and sign in with your Beszel email/password.'
