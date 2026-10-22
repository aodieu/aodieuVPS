# AodieuVPS. Install and manage a Linux web server from your SSH terminal — without a heavyweight hosting control panel.

### aodieuVPS is a script that runs via SSH and automatically installs all the essential components for a VPS with a single command:

   ```bash
   curl -fsSLO https://aodieu.com/script/install && bash install
   ```

AodieuVPS is a Bash-based server setup and management toolkit designed to simplify VPS administration. It installs the core software needed to host PHP websites and provides an easy-to-use, numbered command-line menu for everyday tasks such as adding domains, managing databases, creating backups, and installing SSL certificates.

With the Rocky Linux 10 edition, AodieuVPS also brings browser-based file management, server monitoring, bilingual menus, and installation diagnostics into one streamlined hosting environment.

**Website:** https://aodieu.com/script/  
**GitHub:** https://github.com/aodieu/aodieuVPS

## Highlights

- **Automated web stack:** Install and configure Nginx, PHP-FPM, MariaDB, and commonly used PHP extensions.
- **Configurable PHP:** Choose a PHP version during setup (PHP 8.4 is the default in the Rocky Linux 10 installer; availability of other offered versions depends on the package repositories).
- **Simple website management:** Add, list, or remove domains; configure parked domains and redirects; and manage webserver permissions.
- **SSL certificates:** Use Let's Encrypt/Certbot for eligible domains and manage certificates through the menu.
- **Database tools:** Create or remove MariaDB databases and access phpMyAdmin through the administration interface.
- **Backups:** Back up website files and databases, with options to schedule or disable automatic database backups.
- **Web-based utilities:** Access FileBrowser Quantum for file management, Beszel for resource monitoring, and a PHP OPcache status page.
- **Server administration:** Access common maintenance operations, including server upgrades, SSH port changes, and administration-port changes.
- **Basic host protections:** Configure an iptables-based firewall and Fail2ban, alongside Nginx and service settings.
- **English & Vietnamese:** Select your language during installation or change it later using menu option 20.
- **Built-in diagnostics:** Generate a troubleshooting package from menu option 21, directly on headless servers.

## System Requirements

The current Rocky Linux 10 edition is intended for:

| Requirement | Details |
| --- | --- |
| Operating system | Fresh **Rocky Linux 10** installation |
| Architecture | **x86_64 (AMD64)** |
| Access | Root access through SSH or a local terminal |
| Memory | **2 GB RAM or more recommended** |
| Storage | **10 GB or more free space recommended**, plus space for sites and backups |
| Network | Working Internet connection and DNS resolution |
| Domain | Recommended for public websites; required for domain-validated SSL issuance |

> **Important:** Use a clean server without cPanel, Plesk, DirectAdmin, or an existing production web stack. The installer modifies system services, firewall rules, SSH settings, and other configurations. Older CentOS/Rocky Linux script folders are legacy editions and should not be assumed to have Rocky Linux 10 features.

## Installation

1. Connect to your fresh Rocky Linux 10 server and switch to root:

   ```bash
   sudo -i
   ```

2. Download and run the AodieuVPS installer:

   ```bash
   curl -fsSLO https://aodieu.com/script/install && bash install
   ```

3. Follow the on-screen prompts to choose your language, PHP version, primary domain, and administration port.

4. Allow the installer to configure the server. The Rocky Linux 10 installer reboots the machine after successful setup, so reconnect to SSH afterward.

**Before installing:** Make sure the server has an active network connection, a default route, and functioning DNS. For example, `getent hosts aodieu.com` should resolve successfully.

## Managing Your Server

Connect over SSH and run:

```bash
aodieuvps
```

The numbered management menu includes:

| Menu options | What you can do |
| --- | --- |
| 1–3 | List, add, and remove domains |
| 4–7 | Back up website files/databases and configure scheduled database backups |
| 8–9 | Create and delete databases |
| 10–11 | Change the VPS password or administration port |
| 12–14 | Park domains, configure forwarding, and fix webserver permissions |
| 15–16 | Upgrade server packages and change the SSH port |
| 17–19 | Install domain/subdomain SSL or remove SSL |
| 20 | Switch between English and Vietnamese |
| 21 | Collect installation diagnostics |
| 22 | Exit |

Some operations can change or delete data. Review your selections and maintain independent backups before running destructive actions.

## Web Administration

After installation, use the administration port you selected:

| Tool | Address |
| --- | --- |
| Administration home | `http://SERVER_IP:ADMIN_PORT/` |
| FileBrowser Quantum | `http://SERVER_IP:ADMIN_PORT/filemanager/` |
| phpMyAdmin | `http://SERVER_IP:ADMIN_PORT/phpmyadmin/` |
| Beszel monitoring | `http://SERVER_IP:ADMIN_PORT/serverinfo/` |
| PHP OPcache status | `http://SERVER_IP:ADMIN_PORT/op.php` |

Your installation details and generated credentials are saved in:

```text
/root/aodieuvps-script.txt
```

Read them on your server with `sudo cat /root/aodieuvps-script.txt` and **keep the file private**. Beszel uses an email-style login (`admin@localhost.localdomain` in the Rocky Linux 10 installer) and the generated administration password.

> **Security notice:** The Rocky Linux 10 installer initially exposes the administration interface over **HTTP**, not HTTPS. Configure a trusted HTTPS access path and restrict network access to administration services before exposing the panel publicly. The installer also changes firewall/SSH settings; verify that you can reconnect after installation.

## Installation Diagnostics

If you need to review or troubleshoot an installation, open `aodieuvps` and select **21 — Collect Installation Diagnostics**.

The Rocky Linux 10 collector saves a timestamped archive on the server, without requiring a desktop environment:

```text
/root/aodieuvps-diagnostics/aodieu-rocky10-diagnostics-YYYYMMDD-HHMMSS.tar.gz
```

The archive is intended to help inspect installation health, service status, and configuration issues. **Review it for sensitive information before sharing it with anyone.**

You can also check core services manually:

```bash
systemctl status nginx php-fpm mariadb aodieu-filebrowser aodieu-beszel aodieu-beszel-agent
```

## Important Notes

- **Fresh installation only:** Do not rerun the full installer on a configured server as an upgrade or repair procedure.
- **SSL requires correct DNS:** Let's Encrypt issuance may be skipped or fail if the domain does not resolve to your server or the validation challenge cannot reach it.
- **Backups are your responsibility:** Keep tested, off-server backups in addition to any local backups made through the menu.
- **Supported components vary by edition:** Legacy installers in older OS directories do not include every Rocky Linux 10 feature.
- **Protect administrative access:** Use strong credentials, restrict access to management ports, and review the security configuration before production deployment.

## Project

AodieuVPS aims to make self-managed Linux hosting approachable: install a practical web stack with one command, then handle routine server work through a familiar SSH menu.

For the project and installation entry point, visit **https://aodieu.com/script/**.
