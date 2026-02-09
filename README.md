# Z2k v2.0 - Zapret2 Agricultural (ALPHA TEST)

The project is under active development. Status: alpha test. Possible bugs and changes without backward compatibility.

Support the project:

- TON: `UQA6Y6Mf1Qge2dVSl3_vSqb29SKrhI8VgJtoRBjgp08oB8QY`
- USDT (ERC20): `0xA1D6d7d339f05C1560ecAF0c5CB8c4dc80Dc46A9`

Если нужно максимально простое и проверенное решение, посмотрите также: https://github.com/IndeecFOX/zapret4rocket

Important: After installation, autocircular strategies are applied by default. They need time and several attempts to adjust to the DPI. If the site does not open right away, open it and let the page reload several times - the parameters are sorted out, and after that the site usually starts to open.

---

## What is this

z2k is a modular zapret2 installer for Keenetic routers with Entware.

The goal of the project: to simplify the installation of zapret2 on Keenetic as much as possible and provide a working set of strategies with auto-selection (autocircular) and IPv6 support where possible.

---

## Features (current)

- Installation of zapret2 (openwrt-embedded release) without compilation, with `nfqws2` functionality check
- Generation and application of strategies under categories:
  - RKN (TCP/TLS)
  - YouTube TCP (TLS)
  - Googlevideo (TCP/TLS)
  - YouTube QUIC (UDP/443) by domain list
  - Discord (TCP/UDP) with separate profiles
- Hostlist и autohostlist:
  - hostlist for selective use (not “for the entire Internet”)
  - `--hostlist-auto` support for TCP profiles
- IPv6:
  - auto-detection of IPv6 availability on the router and enabling rules (iptables/ip6tables), if possible
  - if IPv6 is not supported/not configured - IPv6 rules are not enabled
- Domain lists are installed automatically (source: zapret4rocket)

---

## Installation

### 1) Requirements for Keenetic firmware (required)

Before installing zapret2 in the Keenetic web interface, you need to install the following components:

1) "IPv6 protocol"
2) “Netfilter subsystem kernel modules” (appears only after selecting the “IPv6 Protocol” component)

### 2) Preparing USB and installing Entware (required)

Prepare a USB drive and install Entware according to the official Keenetic instructions:
https://help.keenetic.com/hc/ru/articles/360021214160-%D0%A3%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0-%D1%81%D0%B8%D1%81%D1%82%D0%B5%D0%BC%D1%8B-%D0%BF%D0%B0%D0%BA%D0%B5%D1%82%D0%BE%D0%B2-%D1%80%D0%B5%D0%BF%D0%BE%D0%B7%D0%B8%D1%82%D0%BE%D1%80%D0%B8%D1%8F-Entware-%D0%BD%D0%B0-USB-%D0%BD%D0%B0%D0%BA%D0%BE%D0%BF%D0%B8%D1%82%D0%B5%D0%BB%D1%8C

After installing Entware, update the package index and install dependencies:

```bash
opkg update
opkg install coreutils-sort curl grep gzip ipset iptables kmod_ndms xtables-addons_legacy
```

### 3) Installing z2k (Zapret2 for Keenetic)

```bash
curl -fsSL https://raw.githubusercontent.com/necronicle/z2k/master/z2k.sh | sh
```

---

## What does the installer do (in general)

- Checks the environment (Entware, dependencies, architecture).
- Устанавливает zapret2 в `/opt/zapret2` и ставит init-скрипт `/opt/etc/init.d/S99zapret2`.
- Downloads/updates domain lists.
- Generates and applies default strategies with autocircular selection for key categories.
- Enables IPv6 rules if IPv6 is actually available and the backend is available (ip6tables/nft).

---

## Usage

### Rerunning the installer

```bash
curl -fsSL https://raw.githubusercontent.com/necronicle/z2k/master/z2k.sh | sh
```

### Management of the service ban2

```bash
/opt/etc/init.d/S99zapret2 start
/opt/etc/init.d/S99zapret2 stop
/opt/etc/init.d/S99zapret2 restart
/opt/etc/init.d/S99zapret2 status
```

### Manually updating lists

```bash
/opt/zapret2/ipset/get_config.sh
```

---

## Notes

- If you are using IPv6 on your network, make sure it is enabled in the firmware (see requirements above). The installer tries to enable IPv6 rules automatically, but if there is no IPv6 route/address, IPv6 will be disabled.
- If the system does not have `cron`, automatic updating of lists may not be available - update the lists manually.

---

## License

MIT
