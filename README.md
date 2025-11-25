# aodieuVPS
A bash script running on SSH that will auto install all essential components to your VPS with a single command line.

Compatible with:
- CentOS 6
- CentOS 7
- Rocky Linux 8

## Installation

```bash
curl -sO https://aodieu.com/script/install && bash install
```

## Features

- Automated LEMP stack installation (Linux, Nginx, MariaDB, PHP-FPM)
- Multiple PHP version support (7.0 - 8.4)
- phpMyAdmin for database management
- eXtplorer file manager
- Server monitoring tools
- Automated SSL certificate installation via Certbot
- Security hardening (fail2ban, custom SSH port, firewall)
- Auto-configured based on server resources (RAM/CPU)

## Requirements

- Minimum 256MB RAM
- Fresh server installation (no existing control panels)
