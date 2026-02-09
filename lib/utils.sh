#!/bin/sh
# lib/utils.sh - Utilities, checks and constants for z2k
# Part z2k v2.0 - Modular installer zapret2 for Keenetic

# ==============================================================================
# CONSTANTS
# ==============================================================================

# Version z2k
Z2K_VERSION="2.0.0"

# Installation paths
ZAPRET2_DIR="/opt/zapret2"
CONFIG_DIR="/opt/etc/zapret2"
LISTS_DIR="${ZAPRET2_DIR}/lists"

# Z2K-specific variable for init script (does not conflict with zapret2)
Z2K_INIT_SCRIPT="/opt/etc/init.d/S99zapret2"

# Backwards compatible (can be overwritten by zapret2 modules)
INIT_SCRIPT="/opt/etc/init.d/S99zapret2"

# Export for use in functions
export ZAPRET2_DIR
export CONFIG_DIR
export LISTS_DIR
export Z2K_INIT_SCRIPT
export INIT_SCRIPT

# Working directory
WORK_DIR="/tmp/z2k"
LIB_DIR="${WORK_DIR}/lib"

# GitHub URLs
GITHUB_RAW="https://raw.githubusercontent.com/necronicle/z2k/master"
Z4R_BASE_URL="https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/master"
Z4R_LISTS_URL="${Z4R_BASE_URL}/lists"

# Configuration files
STRATEGIES_CONF="${CONFIG_DIR}/strategies.conf"
HTTP_STRATEGIES_CONF="${CONFIG_DIR}/http_strategies.conf"
CURRENT_STRATEGY_FILE="${CONFIG_DIR}/current_strategy"
QUIC_STRATEGIES_CONF="${CONFIG_DIR}/quic_strategies.conf"
QUIC_STRATEGY_FILE="${CONFIG_DIR}/quic_strategy.conf"
RUTRACKER_QUIC_STRATEGY_FILE="${CONFIG_DIR}/rutracker_quic_strategy.conf"

# Output colors (if terminal supports)
if [ -t 1 ]; then
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_RESET='\033[0m'
else
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_RESET=''
fi

# ==============================================================================
# OUTPUT FUNCTIONS
# ==============================================================================

print_success() {
    printf "${COLOR_GREEN}[[OK]]${COLOR_RESET} %s\n" "$1"
}

print_error() {
    printf "${COLOR_RED}[[FAIL]]${COLOR_RESET} %s\n" "$1" >&2
}

print_warning() {
    printf "${COLOR_YELLOW}[!]${COLOR_RESET} %s\n" "$1"
}

print_info() {
    printf "${COLOR_BLUE}[i]${COLOR_RESET} %s\n" "$1"
}

print_header() {
    printf "\n${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n"
    printf "${COLOR_BLUE}  %s${COLOR_RESET}\n" "$1"
    printf "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n\n"
}

print_separator() {
    printf "${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n"
}

# ==============================================================================
# SYSTEM CHECKS
# ==============================================================================

# Entware Availability Check
check_entware() {
    if [ ! -d "/opt" ] || [ ! -x "/opt/bin/opkg" ]; then
        print_error "Entware is not installed!"
        print_info "Install Entware before starting z2k"
        print_info "Инструкция: https://help.keenetic.com/hc/ru/articles/360021888880"
        return 1
    fi
    return 0
}

# Checking for root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "Requires root permissions for installation"
        print_info "Run: sudo sh z2k.sh"
        return 1
    fi
    return 0
}

# Get system architecture
get_arch() {
    uname -m
}

# Architecture check (ARM64 only for Keenetic)
check_arch() {
    local arch
    arch=$(get_arch)

    case "$arch" in
        aarch64|arm64)
            return 0
            ;;
        *)
            print_warning "$arch architecture not tested"
            print_warning "z2k is designed for ARM64 Keenetic routers"
            printf "Continue? [y/N]:"
            read -r answer </dev/tty
            [ "$answer" = "y" ] || return 1
            ;;
    esac
    return 0
}

# Checking free disk space
check_disk_space() {
    local required_mb=50
    local available_mb

    # Get free space in /opt (in MB)
    available_mb=$(df -m /opt 2>/dev/null | awk 'NR==2 {print $4}')

    if [ -z "$available_mb" ]; then
        print_warning "Unable to determine free space"
        return 0
    fi

    if [ "$available_mb" -lt "$required_mb" ]; then
        print_error "Not enough space in /opt"
        print_info "Required: ${required_mb}MB, available: ${available_mb}MB"
        return 1
    fi

    return 0
}

# Checking for curl
check_curl() {
    if ! command -v curl >/dev/null 2>&1; then
        print_error "curl is not installed"
        print_info "Installing curl..."
        opkg update && opkg install curl || return 1
    fi
    return 0
}

# Checking the presence of necessary utilities
check_required_tools() {
    local missing_tools=""

    for tool in awk sed grep; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools="$missing_tools $tool"
        fi
    done

    if [ -n "$missing_tools" ]; then
        print_error "Missing utilities: $missing_tools"
        return 1
    fi

    return 0
}

# Checking if zapret2 is installed
is_zapret2_installed() {
    [ -d "$ZAPRET2_DIR" ] && [ -x "${ZAPRET2_DIR}/nfq2/nfqws2" ]
}

# Checking whether the zapret2 service is running
is_zapret2_running() {
    if [ -f "$INIT_SCRIPT" ]; then
        pgrep -f "nfqws2" >/dev/null 2>&1
    else
        return 1
    fi
}

# Get service status
get_service_status() {
    if is_zapret2_running; then
        echo "Active"
    elif is_zapret2_installed; then
        echo "Stopped"
    else
        echo "Not installed"
    fi
}

# Get current strategy
get_current_strategy() {
    if [ -f "$CURRENT_STRATEGY_FILE" ]; then
        . "$CURRENT_STRATEGY_FILE"
        echo "$CURRENT_STRATEGY"
    else
        echo "not specified"
    fi
}

# ==============================================================================
# AUXILIARY FUNCTIONS
# ==============================================================================

# Download the file with verification
download_file() {
    local url=$1
    local output=$2
    local description=${3:-"Downloading the file"}

    print_info "$description..."

    if curl -fsSL "$url" -o "$output"; then
        print_success "Loaded: $output"
        return 0
    else
        print_error "Load Error: $url"
        return 1
    fi
}

# Create a backup copy of the file
backup_file() {
    local file=$1
    local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    local max_backups=5  # Store only the last 5 backups

    if [ -f "$file" ]; then
        # Clear old backups, leaving only the latest ones (max_backups - 1)
        # -1 because now we will create another one
        local old_backups
        old_backups=$(ls -t "${file}.backup."* 2>/dev/null | tail -n +${max_backups})
        if [ -n "$old_backups" ]; then
            echo "$old_backups" | while read -r old_backup; do
                rm -f "$old_backup" 2>/dev/null
            done
        fi

        # Create a new backup
        cp "$file" "$backup" || return 1
        print_info "Backup: $backup"
    fi
    return 0
}

# Restore from backup
restore_backup() {
    local file=$1
    local backup

    # Find the latest backup
    backup=$(ls -t "${file}.backup."* 2>/dev/null | head -n 1)

    if [ -n "$backup" ] && [ -f "$backup" ]; then
        cp "$backup" "$file" || return 1
        print_success "Restored from: $backup"
        return 0
    else
        print_error "Backup not found"
        return 1
    fi
}

# Clear old backups for a file
cleanup_backups() {
    local file=$1
    local keep=${2:-5}  # By default, store the last 5

    local all_backups
    all_backups=$(ls -t "${file}.backup."* 2>/dev/null)

    if [ -z "$all_backups" ]; then
        print_info "No backups found for $file"
        return 0
    fi

    local total_count
    total_count=$(echo "$all_backups" | wc -l)

    if [ "$total_count" -le "$keep" ]; then
        print_info "Backups: $total_count (within normal limits)"
        return 0
    fi

    local to_delete
    to_delete=$(echo "$all_backups" | tail -n +$((keep + 1)))

    local deleted=0
    echo "$to_delete" | while read -r backup; do
        rm -f "$backup" 2>/dev/null && deleted=$((deleted + 1))
    done

    local remaining=$keep
    print_success "Backups cleared: $((total_count - remaining)), remaining: $remaining"
    return 0
}

# Check binary file
verify_binary() {
    local binary=$1

    if [ ! -f "$binary" ]; then
        print_error "File not found: $binary"
        return 1
    fi

    if [ ! -x "$binary" ]; then
        print_error "File not executable: $binary"
        return 1
    fi

    # Try running with --version
    local version_output
    version_output=$("$binary" --version 2>&1 | head -1)

    if echo "$version_output" | grep -q "github version"; then
        return 0
    fi

    print_warning "Failed to validate binary: $binary"
    return 0
}

# Checking kernel module loading
check_kernel_module() {
    local module=$1

    if lsmod | grep -q "^${module}"; then
        return 0
    else
        return 1
    fi
}

# Loading a kernel module
load_kernel_module() {
    local module=$1

    if check_kernel_module "$module"; then
        print_info "Module $module is already loaded"
        return 0
    fi

    print_info "Loading module: $module"

    # There is no system modprobe on Keenetic, only Entware
    # Используем /opt/sbin/insmod с полным путём к .ko файлу
    local kernel_ver
    kernel_ver=$(uname -r)
    local module_path="/lib/modules/${kernel_ver}/${module}.ko"

    if [ ! -f "$module_path" ]; then
        print_error "Module file not found: $module_path"
        return 1
    fi

    if /opt/sbin/insmod "$module_path" 2>/dev/null; then
        print_success "Module $module loaded"
        return 0
    else
        print_error "Error loading module: $module"
        return 1
    fi
}

# Check URL availability
check_url_accessible() {
    local url=$1
    local timeout=${2:-5}

    if curl -s -m "$timeout" -I "$url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Get nfqws2 version
get_nfqws2_version() {
    local nfqws2="${ZAPRET2_DIR}/nfq2/nfqws2"

    if [ -x "$nfqws2" ]; then
        "$nfqws2" --help 2>&1 | head -n 1 | awk '{print $NF}' || echo "unknown"
    else
        echo "not installed"
    fi
}

# Show system information
show_system_info() {
    print_header "System Information"

    printf "%-20s: %s\n" "Architecture" "$(get_arch)"
    printf "%-20s: %s\n" "Entware" "$([ -d /opt ] && echo 'установлен' || echo 'не установлен')"
    printf "%-20s: %s\n" "Free space" "$(df -h /opt 2>/dev/null | awk 'NR==2 {print $4}' || echo 'unknown')"
    printf "%-20s: %s\n" "zapret2" "$(is_zapret2_installed && echo 'установлен' || echo 'не установлен')"
    printf "%-20s: %s\n" "nfqws2 version" "$(get_nfqws2_version)"
    printf "%-20s: %s\n" "Service" "$(get_service_status)"
    printf "%-20s: %s\n" "Current strategy" "#$(get_current_strategy)"

    print_separator
}

# Prompt user for confirmation
confirm() {
    local prompt=${1:-"Continue?"}
    local default=${2:-"Y"}

    if [ "$default" = "Y" ]; then
        printf "%s [Y/n]: " "$prompt"
    else
        printf "%s [y/N]: " "$prompt"
    fi

    read -r answer </dev/tty

    case "$answer" in
        [Yy]|[Yy][Ee][Ss]|"")
            [ "$default" = "Y" ] && return 0
            [ "$answer" != "" ] && return 0
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Pause with a message
pause() {
    local message=${1:-"Press Enter to continue..."}
    printf "%s" "$message"
    read -r _ </dev/tty
}

# Clear screen (if in interactive mode)
clear_screen() {
    if [ -t 1 ]; then
        clear
    fi
}

# ==============================================================================
# INITIALIZATION
# ==============================================================================

# Create working directory
init_work_dir() {
    mkdir -p "$WORK_DIR" "$LIB_DIR" || {
        print_error "Failed to create $WORK_DIR"
        return 1
    }
    return 0
}

# Clearing the working directory
cleanup_work_dir() {
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
        print_info "Working directory cleared"
    fi
}

# Error handler
error_handler() {
    local exit_code=$1
    local line_no=$2

    print_error "Error in line $line_no (code: $exit_code)"
    cleanup_work_dir
    exit "$exit_code"
}

# Interrupt handler (Ctrl+C)
interrupt_handler() {
    printf "\n"
    print_warning "Aborted by user"
    cleanup_work_dir
    exit 130
}

# Install signal handlers
setup_signal_handlers() {
    trap 'interrupt_handler' INT TERM
}

# ==============================================================================
# EXPORTING FUNCTIONS (for use in other modules)
# ==============================================================================

# All functions are automatically available after the source of this file
