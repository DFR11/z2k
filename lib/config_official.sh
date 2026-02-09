#!/bin/sh
# lib/config_official.sh - Generate the official config file for zapret2
# Adapted for z2k with multi-profile strategies

# ==============================================================================
# GENERATING NFQWS2_OPT FROM Z2K STRATEGIES
# ==============================================================================

generate_nfqws2_opt_from_strategies() {
    # Generates NFQWS2_OPT for a config file based on current policies

    local config_dir="/opt/etc/zapret2"
    local extra_strats_dir="/opt/zapret2/extra_strats"
    local lists_dir="/opt/zapret2/lists"

    # Download current strategies from categories
    local youtube_tcp_tcp=""
    local youtube_gv_tcp=""
    local rkn_tcp=""
    local quic_udp=""
    local quic_rkn_udp=""
    local discord_tcp=""
    local discord_udp=""
    local custom_tcp=""

    # Read strategies from category files
    if [ -f "${extra_strats_dir}/TCP/YT/Strategy.txt" ]; then
        youtube_tcp_tcp=$(cat "${extra_strats_dir}/TCP/YT/Strategy.txt")
    fi

    if [ -f "${extra_strats_dir}/TCP/YT_GV/Strategy.txt" ]; then
        youtube_gv_tcp=$(cat "${extra_strats_dir}/TCP/YT_GV/Strategy.txt")
    fi

    if [ -f "${extra_strats_dir}/TCP/RKN/Strategy.txt" ]; then
        rkn_tcp=$(cat "${extra_strats_dir}/TCP/RKN/Strategy.txt")
    fi

    if [ -f "${extra_strats_dir}/UDP/YT/Strategy.txt" ]; then
        quic_udp=$(cat "${extra_strats_dir}/UDP/YT/Strategy.txt")
    fi

    if [ -f "${extra_strats_dir}/UDP/RUTRACKER/Strategy.txt" ]; then
        quic_rkn_udp=$(cat "${extra_strats_dir}/UDP/RUTRACKER/Strategy.txt")
    fi

    # Discord strategies (usually fixed)
    discord_tcp="--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=tls_clienthello_14:tls_mod=rnd,dupsid:ip_autottl=-2,3-20 --lua-desync=multisplit:pos=sld+1"
    discord_udp="--filter-udp=50000-50099,1400,3478-3481,5349 --filter-l7=discord,stun --payload=stun,discord_ip_discovery --out-range=-n10 --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2"

    # Default strategy if not loaded
    local default_strategy="--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:repeats=6"

    # Use default if strategy is empty
    [ -z "$youtube_tcp_tcp" ] && youtube_tcp_tcp="$default_strategy"
    [ -z "$youtube_gv_tcp" ] && youtube_gv_tcp="$default_strategy"
    [ -z "$rkn_tcp" ] && rkn_tcp="$default_strategy"
    [ -z "$quic_udp" ] && quic_udp="--filter-udp=443 --filter-l7=quic --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6"
    [ -z "$quic_rkn_udp" ] && quic_rkn_udp="--filter-udp=443 --filter-l7=quic --payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6"
    custom_tcp="$default_strategy"

    # Generate NFQWS2_OPT in official config format
    # ������������ NFQWS2_OPT � ������� ������������ config
    local nfqws2_opt_lines=""

    # Helper: �������� ������ ���� hostlist ���������� � �� ������
    add_hostlist_line() {
        local list_path="$1"
        shift
        if [ -s "$list_path" ]; then
            nfqws2_opt_lines="$nfqws2_opt_lines$*\\n"
        else
            echo "WARN: hostlist file missing or empty: $list_path (skip profile)" 1>&2
        fi
    }

    # RKN TCP
    add_hostlist_line "${extra_strats_dir}/TCP/RKN/List.txt" "--hostlist-exclude=${lists_dir}/whitelist.txt --hostlist=${extra_strats_dir}/TCP/RKN/List.txt $rkn_tcp <HOSTLIST> --new"

    # YouTube TCP
    add_hostlist_line "${extra_strats_dir}/TCP/YT/List.txt" "--hostlist-exclude=${lists_dir}/whitelist.txt --hostlist=${extra_strats_dir}/TCP/YT/List.txt $youtube_tcp_tcp <HOSTLIST> --new"

    # YouTube GV (domains list �������)
    nfqws2_opt_lines="$nfqws2_opt_lines--hostlist-exclude=${lists_dir}/whitelist.txt --hostlist-domains=googlevideo.com $youtube_gv_tcp <HOSTLIST> --new\\n"

    # QUIC YT
    add_hostlist_line "${extra_strats_dir}/UDP/YT/List.txt" "--hostlist-exclude=${lists_dir}/whitelist.txt --hostlist=${extra_strats_dir}/UDP/YT/List.txt $quic_udp <HOSTLIST_NOAUTO> --new"

    # QUIC RUTRACKER (disabled)
    : # disabled by default

    # Discord TCP/UDP
    add_hostlist_line "${lists_dir}/discord.txt" "--hostlist-exclude=${lists_dir}/whitelist.txt --hostlist=${lists_dir}/discord.txt $discord_tcp <HOSTLIST> --new"
    add_hostlist_line "${lists_dir}/discord.txt" "--hostlist-exclude=${lists_dir}/whitelist.txt --hostlist=${lists_dir}/discord.txt $discord_udp <HOSTLIST_NOAUTO> --new"

    # Custom TCP
    add_hostlist_line "${lists_dir}/custom.txt" "--hostlist-exclude=${lists_dir}/whitelist.txt --hostlist=${lists_dir}/custom.txt $custom_tcp <HOSTLIST>"

    local nfqws2_opt_value
    nfqws2_opt_value=$(printf "%b" "$nfqws2_opt_lines" | sed '/^$/d')
    cat <<NFQWS2_OPT
NFQWS2_OPT="
$nfqws2_opt_value
"
NFQWS2_OPT
}

# ==============================================================================
# CREATING AN OFFICIAL CONFIG FILE
# ==============================================================================

create_official_config() {
    # $1 - путь к config файлу (обычно /opt/zapret2/config)

    local config_file="${1:-/opt/zapret2/config}"

    print_info "Creating an official config file: $config_file"

    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$config_file")"

    # Generate NFQWS2_OPT
    local nfqws2_opt_section=$(generate_nfqws2_opt_from_strategies)

    # =========================================================================
    # VALIDATION OF NFQWS2 OPTIONS (IMPORTANT)
    # =========================================================================
    print_info "Validation of generated nfqws2... options"

    # Extract NFQWS2_OPT from generated section
    local nfqws2_opt_value=$(echo "$nfqws2_opt_section" | grep "^NFQWS2_OPT=" | sed 's/^NFQWS2_OPT=//' | tr -d '"')

    # Load modules for dry_run_nfqws()
    if [ -f "/opt/zapret2/common/base.sh" ]; then
        . "/opt/zapret2/common/base.sh"
    fi

    if [ -f "/opt/zapret2/common/linux_daemons.sh" ]; then
        . "/opt/zapret2/common/linux_daemons.sh"

        # Set temporarily NFQWS2_OPT for testing
        export NFQWS2_OPT="$nfqws2_opt_value"
        export NFQWS2="/opt/zapret2/nfq2/nfqws2"

        # Check options
        if dry_run_nfqws 2>/dev/null; then
            print_success "nfqws2 options are valid"
        else
            print_warning "Some nfqws2 options may not be correct"
            print_info "We continue with the installation (the init script will check again upon startup)"
        fi
    else
        print_info "Validation modules not found, skip the check"
    fi

    z2k_have_cmd() { command -v "$1" >/dev/null 2>&1; }

    # Get FWTYPE and FLOWOFFLOAD from the environment (if installed)
    local fwtype_value="${FWTYPE:-iptables}"
    local flowoffload_value="${FLOWOFFLOAD:-none}"
    local tmpdir_value="${TMPDIR:-}"

    # ==============================================================================
    # IPv6 auto-detect (Keenetic)
    # ==============================================================================
    # Default behavior historically was DISABLE_IPV6=1 because many Keenetic builds
    # don't ship ip6tables. Here we enable IPv6 only if:
    # - IPv6 looks configured (default route or global address exists)
    # - and the firewall backend can actually handle IPv6 rules:
    #   - iptables => ip6tables must exist
    #   - nftables => nft must exist
    local disable_ipv6_value="${DISABLE_IPV6:-}"
    if [ -z "$disable_ipv6_value" ]; then
        disable_ipv6_value="1"
        local v6_ok="0"
        if z2k_have_cmd ip; then
            ip -6 route show default 2>/dev/null | grep -q . && v6_ok="1"
            if [ "$v6_ok" = "0" ]; then
                ip -6 addr show scope global 2>/dev/null | grep -q "inet6" && v6_ok="1"
            fi
        fi

        if [ "$v6_ok" = "1" ]; then
            if [ "$fwtype_value" = "nftables" ]; then
                if z2k_have_cmd nft; then
                    disable_ipv6_value="0"
                    print_info "IPv6 detected, backend=nftables: enable IPv6 processing (DISABLE_IPV6=0)"
                else
                    print_info "IPv6 detected, but nft not found: leave IPv6 disabled (DISABLE_IPV6=1)"
                fi
            else
                if z2k_have_cmd ip6tables; then
                    disable_ipv6_value="0"
                    print_info "IPv6 detected, backend=iptables: enable IPv6 processing (DISABLE_IPV6=0)"
                else
                    print_info "IPv6 detected, but ip6tables not found: leave IPv6 disabled (DISABLE_IPV6=1)"
                fi
            fi
        else
            print_info "IPv6 not detected (no default route/global addr): leave IPv6 disabled (DISABLE_IPV6=1)"
        fi
    else
        print_info "DISABLE_IPV6 is set manually: DISABLE_IPV6=$disable_ipv6_value"
    fi

    # Create a complete config file
    cat > "$config_file" <<CONFIG
# zapret2 configuration for Keenetic
# Generated by z2k installer
# Based on official zapret2 config structure

# ==============================================================================
# BASIC SETTINGS
# ==============================================================================

# Enable zapret2 service
ENABLED=1

# Mode filter: none, ipset, hostlist, autohostlist
# For z2k we use hostlist mode with multi-profile filtering
MODE_FILTER=autohostlist

# Firewall type - AUTO-DETECTED by init script, DO NOT set manually
# Init script calls linux_fwtype() which detects iptables/nftables automatically
# If FWTYPE is set here, linux_fwtype() will skip detection!
#FWTYPE=iptables

# ==============================================================================
# NFQWS2 DAEMON SETTINGS
# ==============================================================================

# Enable nfqws2
NFQWS2_ENABLE=1

# TCP ports to process (will be filtered by --filter-tcp in NFQWS2_OPT)
NFQWS2_PORTS_TCP="80,443,2053,2083,2087,2096,8443"

# UDP ports to process (will be filtered by --filter-udp in NFQWS2_OPT)
NFQWS2_PORTS_UDP="443,50000:50099,1400,3478:3481,5349"

# Packet direction filters (connbytes)
# NOTE: These are packet counts, NOT ranges
# PKT_OUT=20 means "first 20 packets" (connbytes 1:20)
# Official zapret2 defaults: TCP_PKT_OUT=20, UDP_PKT_OUT=5
NFQWS2_TCP_PKT_OUT="20"
NFQWS2_TCP_PKT_IN=""
NFQWS2_UDP_PKT_OUT="5"
NFQWS2_UDP_PKT_IN=""

# ==============================================================================
# NFQWS2 OPTIONS (MULTI-PROFILE MODE)
# ==============================================================================
# This section is auto-generated from z2k strategy database
# Each --new separator creates independent profile with own filters and strategy
# Order: RKN TCP → YouTube TCP → YouTube GV → QUIC YT → QUIC RKN → Discord TCP → Discord UDP → Custom
# Placeholders: <HOSTLIST> and <HOSTLIST_NOAUTO> are expanded based on MODE_FILTER
# This enables standard hostlists and autohostlist like upstream zapret2
CONFIG

    # Add generated NFQWS2_OPT
    echo "$nfqws2_opt_section" >> "$config_file"

    # Add other settings
    cat >> "$config_file" <<'CONFIG'

# ==============================================================================
# FIREWALL SETTINGS
# ==============================================================================

# Queue number for NFQUEUE
QNUM=200

# Firewall mark for desync prevention
DESYNC_MARK=0x40000000
DESYNC_MARK_POSTNAT=0x20000000

# Apply firewall rules in init script
INIT_APPLY_FW=1

# Flow offloading mode: none, software, hardware, donttouch
# Set during installation based on system detection
FLOWOFFLOAD=$flowoffload_value

# WAN interface override (space/comma separated). Empty = auto-detect
#WAN_IFACE=

# ==============================================================================
# SYSTEM SETTINGS
# ==============================================================================

# Temporary directory for downloads and processing
# Empty = use system default /tmp (tmpfs, in RAM)
# Set to disk path for low RAM systems (e.g., /opt/zapret2/tmp)
CONFIG
    # Add TMPDIR only if installed
    if [ -n "$tmpdir_value" ]; then
        echo "TMPDIR=$tmpdir_value" >> "$config_file"
    else
        echo "#TMPDIR=/opt/zapret2/tmp" >> "$config_file"
    fi

    # Disable IPv6 processing (0=enabled, 1=disabled)
    # Auto-detected during install; can be overridden by setting DISABLE_IPV6 in environment/config.
    echo "" >> "$config_file"
    echo "# Disable IPv6 processing (0=enabled, 1=disabled)" >> "$config_file"
    echo "DISABLE_IPV6=$disable_ipv6_value" >> "$config_file"

    cat >> "$config_file" <<'CONFIG'

# ==============================================================================
# IPSET SETTINGS
# ==============================================================================

# Maximum elements in ipsets
SET_MAXELEM=522288

# ipset options
IPSET_OPT="hashsize 262144 maxelem $SET_MAXELEM"

# ip2net options
IP2NET_OPT4="--prefix-length=22-30 --v4-threshold=3/4"
IP2NET_OPT6="--prefix-length=56-64 --v6-threshold=5"

# ==============================================================================
# AUTOHOSTLIST SETTINGS
# ==============================================================================

AUTOHOSTLIST_INCOMING_MAXSEQ=4096
AUTOHOSTLIST_RETRANS_MAXSEQ=32768
AUTOHOSTLIST_RETRANS_RESET=1
AUTOHOSTLIST_RETRANS_THRESHOLD=3
AUTOHOSTLIST_FAIL_THRESHOLD=3
AUTOHOSTLIST_FAIL_TIME=60
AUTOHOSTLIST_UDP_IN=1
AUTOHOSTLIST_UDP_OUT=4
AUTOHOSTLIST_DEBUGLOG=0

# ==============================================================================
# CUSTOM SCRIPTS
# ==============================================================================

# Directory for custom scripts
CUSTOM_DIR="/opt/zapret2/init.d/keenetic"

# ==============================================================================
# MISCELLANEOUS
# ==============================================================================

# Temporary directory (if /tmp is too small)
#TMPDIR=/opt/zapret2/tmp

# User for zapret daemons (required on Keenetic)
#WS_USER=nobody

# Compress large lists
GZIP_LISTS=1

# Number of parallel threads for domain resolves
MDIG_THREADS=30

# EAI_AGAIN retries
MDIG_EAGAIN=10
MDIG_EAGAIN_DELAY=500
CONFIG

    print_success "Config file created: $config_file"
    return 0
}

# ==============================================================================
# UPDATING NFQWS2_OPT IN AN EXISTING CONFIG
# ==============================================================================

update_nfqws2_opt_in_config() {
    # Updates only the NFQWS2_OPT section in an existing config file
    # $1 - path to the config file

    local config_file="${1:-/opt/zapret2/config}"

    if [ ! -f "$config_file" ]; then
        print_error "Config file not found: $config_file"
        return 1
    fi

    print_info "Update NFQWS2_OPT in: $config_file"

    # Create backup
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"

    # Generate new NFQWS2_OPT
    local nfqws2_opt_section=$(generate_nfqws2_opt_from_strategies)

    # Create temporary file
    local temp_file="${config_file}.tmp"

    # Remove old NFQWS2_OPT and add new one
    awk '
    /^NFQWS2_OPT=/ {
        in_nfqws_opt=1
        next
    }
    in_nfqws_opt && /^"$/ {
        in_nfqws_opt=0
        next
    }
    !in_nfqws_opt { print }
    ' "$config_file" > "$temp_file"

    # Add new NFQWS2_OPT to the end of the file (before the last section)
    # Find the position to insert (before FIREWALL SETTINGS or at the end)
    if grep -q "# FIREWALL SETTINGS" "$temp_file"; then
        # Insert before FIREWALL SETTINGS
        awk -v opt="$nfqws2_opt_section" '
        /# FIREWALL SETTINGS/ {
            print opt
            print ""
        }
        { print }
        ' "$temp_file" > "${temp_file}.2"
        mv "${temp_file}.2" "$temp_file"
    else
        # Add to end
        echo "" >> "$temp_file"
        echo "$nfqws2_opt_section" >> "$temp_file"
    fi

    # Replace original file
    mv "$temp_file" "$config_file"

    print_success "NFQWS2_OPT updated in config file"
    return 0
}

# ==============================================================================
# EXPORTING FUNCTIONS
# ==============================================================================

# Functions are available after the source of this file
