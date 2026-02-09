#!/bin/sh
# lib/system_init.sh - Initializing system variables for z2k
# Replaces the check_system() call from zapret2/common/installer.sh

# ==============================================================================
# DETERMINING THE SYSTEM TYPE
# ==============================================================================

init_system_vars() {
    print_info "Determining the type of system..."

    # Determine OS
    UNAME=$(uname -s)

    # Define subsystem
    SUBSYS=""

    # For Linux, determine the init type of the system
    if [ "$UNAME" = "Linux" ]; then
        # Check systemd
        if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
            SYSTEM="systemd"
            SYSTEMCTL="systemctl"
            INIT="systemd"
        # Check OpenRC
        elif [ -f /sbin/openrc-run ] || [ -f /usr/sbin/openrc-run ]; then
            SYSTEM="openrc"
            INIT="openrc"
        # Check OpenWrt/Keenetic (procd)
        elif [ -f /etc/openwrt_release ] || [ -f /opt/etc/init.d/rc.func ]; then
            SYSTEM="openwrt"
            INIT="procd"
        # Generic Linux (SysV init или custom)
        else
            SYSTEM="linux"
            INIT="sysv"
        fi

        print_success "System: $SYSTEM (init: $INIT)"

    elif [ "$UNAME" = "FreeBSD" ] || [ "$UNAME" = "OpenBSD" ]; then
        SYSTEM="bsd"
        INIT="rc"
        print_success "System: BSD"

    elif [ "$UNAME" = "Darwin" ]; then
        SYSTEM="macos"
        INIT="launchd"
        print_success "System: macOS"

    else
        print_warning "Unknown system: $UNAME"
        SYSTEM="unknown"
        INIT="unknown"
    fi

    # Export variables for use in other modules
    export SYSTEM
    export SUBSYS
    export UNAME
    export INIT
    export SYSTEMCTL

    # Show details
    print_info "Environment Variables:"
    print_info "  SYSTEM=$SYSTEM"
    print_info "  UNAME=$UNAME"
    print_info "  INIT=$INIT"
    [ -n "$SYSTEMCTL" ] && print_info "  SYSTEMCTL=$SYSTEMCTL"

    return 0
}

# ==============================================================================
# AUXILIARY FUNCTIONS
# ==============================================================================

# Determine whether the Keenetic system is
is_keenetic() {
    # Checking for Keenetic-specific files
    [ -f /opt/etc/init.d/rc.func ] && return 0

    # Checking for NDM (Keenetic firmware)
    [ -d /opt/etc/ndm ] && return 0

    return 1
}

# Get the Keenetic firmware version (if available)
get_keenetic_version() {
    if [ -f /etc/os-release ]; then
        grep VERSION_ID /etc/os-release | cut -d'=' -f2 | tr -d '"'
    elif command -v ndmc >/dev/null 2>&1; then
        ndmc -c "show version" 2>/dev/null | grep "release:" | awk '{print $2}'
    else
        echo "unknown"
    fi
}

# ==============================================================================
# KEENETIC SPECIFIC CHECKS
# ==============================================================================

check_keenetic_specifics() {
    if is_keenetic; then
        print_info "Keenetic router detected"

        local fw_version
        fw_version=$(get_keenetic_version)
        [ "$fw_version" != "unknown" ] && print_info "Firmware version: $fw_version"

        # Check availability of NDM hooks
        if [ -d /opt/etc/ndm ]; then
            print_info "NDM hooks available"
        fi

        # Check fastnat
        if [ -f /sys/kernel/fastnat/mode ]; then
            local fastnat_mode
            fastnat_mode=$(cat /sys/kernel/fastnat/mode 2>/dev/null || echo "unknown")
            print_info "Fastnat mode: $fastnat_mode"
        fi

        return 0
    fi

    return 1
}
