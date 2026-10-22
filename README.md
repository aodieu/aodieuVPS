# AodieuVPS — Rocky Linux 10 (same directory layout as Rocky Linux 8)

Single hosting directory: `/script` at `aodieu.com`, containing the launcher `install` and its original sibling `scripts/`. **Do not create a separate `/scripts` directory at the website root.**

```text
/script/
  install
  scripts/
    6/
    7/
    8/
    10/
      install.sh
      aodieuvps
      component/menu.zip
      config/mysql/*.cnf
      html/index.html
      package/*.zip
    config/
      mysql/*.cnf
      php-fpm/*.conf
    component/opcache-gui/index.php.txt
```

- Entry URL: `https://aodieu.com/script/install`
- Version 8 installer: `https://aodieu.com/script/scripts/8/install.sh`
- Version 10 installer: `https://aodieu.com/script/scripts/10/install.sh`
- Shared config: `https://aodieu.com/script/scripts/config/`
- Version 10 management menu: `https://aodieu.com/script/scripts/10/component/menu.zip`

Upload the contents of the website ZIP into the existing website document root, preserving the `script/` directory. Or merge the `scripts/10` directory into your existing `/script/scripts` folder, plus replace `/script/install` and the changed legacy transport scripts.

Run on a fresh Rocky Linux 10 host with working internet/DNS:

```bash
curl -sO https://aodieu.com/script/install && bash install
```

AodieuVPS script/config/asset downloads come from `aodieu.com` only. Vendor package repositories and third-party application download sources are preserved; those external sources are not mirrored by this package. Existing version 6, 7, 8 installation configurations are unchanged aside from their own AodieuVPS asset URLs and the bundled OPcache view. Rocky 10 component versions and defaults are maintained from the prior patch. No live Rocky 10 installation has been performed as part of these static checks.

**Source delivery caution:** `index.php.txt` is intentionally a downloadable text asset, not executable by the aodieu.com web server. It is saved to the VPS as `op.php` by the installer, behind the VPS administration access control.

## Rocky Linux 10 (2026-10-21 update)

- Before installation choose `1) English` or `2) Tieng Viet` (Vietnamese default).
- Installed `aodieuvps` management menu retains the selected language;
  existing options 1–19 are unchanged; option 20 changes language.
- FileBrowser Quantum v2.0.1-stable replaces the legacy eXtplorer application.
- New read-only, single-file PHP 8.4 AodieuVPS Server Probe replaces Yahei Prober.
- **Mandatory packaging step:** the official FileBrowser Quantum Linux amd64
  binary and its SHA-256 manifest must be hosted under
  `/script/scripts/10/package/` before running the installer.
  The Rocky Linux installer itself downloads no application files from GitHub.
- See `DEPLOYMENT_README.txt` and `PREPARE_FILEBROWSER_ASSET.sh`
  in the website distribution archive.
- Offline static checks do not replace a fresh Rocky Linux 10 run.
