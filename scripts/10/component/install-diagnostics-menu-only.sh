#!/usr/bin/env bash
# Optional non-destructive menu-only patch for an already-installed Rocky 10 VPS.
# It does NOT rerun AodieuVPS installation or change runtime configurations.
set -euo pipefail
umask 077
if (( EUID != 0 )); then echo 'Run as root.' >&2; exit 1; fi
if [[ ! -f /etc/aodieuvps/scripts.conf ]] || [[ ! -f /etc/rocky-release ]] || [[ "$(rpm -E %rhel)" != '10' ]]; then
  echo 'Existing AodieuVPS on Rocky Linux 10 required; no changes made.' >&2
  exit 1
fi
base='https://aodieu.com/script/scripts/10'
tmpdir=$(mktemp -d /tmp/aodieuvps-menu21.XXXXXXXX)
trap 'rm -rf -- "$tmpdir"' EXIT
curl -fsSL --retry 3 --connect-timeout 15 "$base/aodieuvps" -o "$tmpdir/aodieuvps"
curl -fsSL --retry 3 --connect-timeout 15 "$base/component/aodieu-rocky10-diagnostics.sh" -o "$tmpdir/diagnostics.sh"
bash -n "$tmpdir/aodieuvps"
bash -n "$tmpdir/diagnostics.sh"
grep -q 'Collect Installation Diagnostics' "$tmpdir/aodieuvps" || { echo 'Downloaded menu lacks option 21' >&2; exit 1; }
grep -q '/root/aodieuvps-diagnostics' "$tmpdir/diagnostics.sh" || { echo 'Downloaded collector lacks root output directory' >&2; exit 1; }
# Only update the menu and install collector; no service restart, firewall,
# PHP, database, Beszel or FileBrowser changes.
install -d -m 755 /usr/local/libexec/aodieuvps
install -m 700 "$tmpdir/diagnostics.sh" /usr/local/libexec/aodieuvps/diagnostics.sh
install -d -m 700 /root/aodieuvps-diagnostics
if [[ -f /bin/aodieuvps ]]; then
  cp -p /bin/aodieuvps "/root/aodieuvps-menu-pre-diagnostics-$(date +%Y%m%d-%H%M%S).bak"
fi
install -m 755 "$tmpdir/aodieuvps" /bin/aodieuvps
summary=/root/aodieuvps-script.txt
if [[ -f "$summary" ]] && ! grep -Fq 'Menu 21: Thu Thap Bao Cao Cai Dat / Collect Installation Diagnostics' "$summary"; then
cat >> "$summary" <<'EOF'

Menu 21: Thu Thap Bao Cao Cai Dat / Collect Installation Diagnostics
Diagnostic result folder (no GUI): /root/aodieuvps-diagnostics/
Diagnostic file format: aodieu-rocky10-diagnostics-YYYYMMDD-HHMMSS.tar.gz
Menu 22: Thoat / Exit
EOF
chmod 600 "$summary"
fi
printf '\nAodieuVPS menu updated. Run "aodieuvps" and choose 21.\nArchives: /root/aodieuvps-diagnostics/\n'
