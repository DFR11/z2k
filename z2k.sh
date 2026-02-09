#!/bin/sh
# z2k.sh - Bootstrap script for z2k v2.0
# Modular installer zapret2 for Keenetic routers
# https://github.com/necronicle/z2k

set -e

# ==============================================================================
# CONSTANTS
# ==============================================================================

Z2K_VERSION="2.0.0"
WORK_DIR="/tmp/z2k"
LIB_DIR="${WORK_DIR}/lib"
GITHUB_RAW="https://raw.githubusercontent.com/necronicle/z2k/master"

# Export variables for use in functions
export WORK_DIR
export LIB_DIR
export GITHUB_RAW

# List of modules to download
MODULES="utils system_init install strategies config config_official menu discord"

# ==============================================================================
# BUILT-IN FALLBACK FUNCTIONS
# ==============================================================================
# Minimum functions to work before loading modules

print_info() {
    printf "[i] %s\n" "$1"
}

print_success() {
    printf "[[OK]] %s\n" "$1"
}

print_error() {
    printf "[[FAIL]] %s\n" "$1" >&2
}

die() {
    print_error "$1"
    [ -n "$2" ] && exit "$2" || exit 1
}

clear_screen() {
    if [ -t 1 ]; then
        clear 2>/dev/null || printf "\033c"
    fi
}

print_header() {
    printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "  %s\n" "$1"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
}

print_separator() {
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
}

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

# ==============================================================================
# ENVIRONMENT CHECKS
# ==============================================================================

check_environment() {
    print_info "Checking the environment..."

    # Entware check
    if [ ! -d "/opt" ] || [ ! -x "/opt/bin/opkg" ]; then
        die "Entware is not installed! Install Entware before starting z2k."
    fi

    # curl check
    if ! command -v curl >/dev/null 2>&1; then
        print_info "curl not found, installing..."
        /opt/bin/opkg update || die "Failed to update opkg"
        /opt/bin/opkg install curl || die "Failed to install curl"
    fi

    # Architecture review
    local arch
    arch=$(uname -m)
    if [ "$arch" != "aarch64" ] && [ "$arch" != "arm64" ]; then
        print_info "ATTENTION: z2k is designed for ARM64 Keenetic"
        print_info "Your architecture: $arch"
        printf "Continue? [y/N]:"
        read -r answer </dev/tty
        [ "$answer" = "y" ] || [ "$answer" = "Y" ] || die "Canceled by user" 0
    fi

    print_success "Environment checked"
}

# ==============================================================================
# LOADING MODULES
# ==============================================================================

download_modules() {
    print_info "Loading z2k modules..."

    # Create directories
    mkdir -p "$LIB_DIR" || die "Failed to create $LIB_DIR"

    # Download each module
    for module in $MODULES; do
        local url="${GITHUB_RAW}/lib/${module}.sh"
        local output="${LIB_DIR}/${module}.sh"

        print_info "Loading lib/${module}.sh..."

        if curl -fsSL "$url" -o "$output"; then
            print_success "Loaded: ${module}.sh"
        else
            die "Error loading module: ${module}.sh"
        fi
    done

    print_success "All modules are loaded"
}

source_modules() {
    print_info "Loading modules into memory..."

    for module in $MODULES; do
        local module_file="${LIB_DIR}/${module}.sh"

        if [ -f "$module_file" ]; then
            . "$module_file" || die "Error loading module: ${module}.sh"
        else
            die "Module not found: ${module}.sh"
        fi
    done

    print_success "Modules loaded"
}

# ==============================================================================
# LOADING STRATEGIES
# ==============================================================================

download_strategies_source() {
    print_info "Loading the strategy file (strats_new2.txt)..."

    local url="${GITHUB_RAW}/strats_new2.txt"
    local output="${WORK_DIR}/strats_new2.txt"

    if curl -fsSL "$url" -o "$output"; then
        local lines
        lines=$(wc -l < "$output")
        print_success "Loaded: strats_new2.txt ($lines lines)"
    else
        die "Error loading strats_new2.txt"
    fi

    print_info "Loading QUIC strategies (quic_strats.ini)..."
    local quic_url="${GITHUB_RAW}/quic_strats.ini"
    local quic_output="${WORK_DIR}/quic_strats.ini"

    if curl -fsSL "$quic_url" -o "$quic_output"; then
        local lines
        lines=$(wc -l < "$quic_output")
        print_success "Loaded: quic_strats.ini ($lines lines)"
    else
        die "Error loading quic_strats.ini"
    fi
}

download_fake_blobs() {
    print_info "Loading fake blobs (TLS + QUIC)..."

    local fake_dir="${WORK_DIR}/files/fake"
    mkdir -p "$fake_dir" || die "Failed to create $fake_dir"

    local files="
tls_clienthello_max_ru.bin
"

    echo "$files" | while read -r file; do
        [ -z "$file" ] && continue
        local url="${GITHUB_RAW}/files/fake/${file}"
        local output="${fake_dir}/${file}"
        if curl -fsSL "$url" -o "$output"; then
            print_success "Uploaded: files/fake/${file}"
        else
            die "Error loading files/fake/${file}"
        fi
    done
}

download_init_script() {
    print_info "Loading init script (S99zapret2.new)..."

    local files_dir="${WORK_DIR}/files"
    mkdir -p "$files_dir" || die "Failed to create $files_dir"

    local url="${GITHUB_RAW}/files/S99zapret2.new"
    local output="${files_dir}/S99zapret2.new"

    if curl -fsSL "$url" -o "$output"; then
        print_success "Uploaded by: files/S99zapret2.new"
    else
        die "Error loading files/S99zapret2.new"
    fi
}

generate_strategies_database() {
    print_info "Generating a strategy database (strategies.conf)..."

    # This function is defined in lib/strategies.sh
    if command -v generate_strategies_conf >/dev/null 2>&1; then
        generate_strategies_conf "${WORK_DIR}/strats_new2.txt" "${WORK_DIR}/strategies.conf" || \
            die "Error generating strategies.conf"

        local count
        count=$(wc -l < "${WORK_DIR}/strategies.conf" | tr -d ' ')
        print_success "Strategies generated: $count"
    else
        die "function generate_strategies_conf not found"
    fi

    print_info "Generating a database of QUIC strategies (quic_strategies.conf)..."
    if command -v generate_quic_strategies_conf >/dev/null 2>&1; then
        generate_quic_strategies_conf "${WORK_DIR}/quic_strats.ini" "${WORK_DIR}/quic_strategies.conf" || \
            die "Error generating quic_strategies.conf"
    else
        die "Function generate_quic_strategies_conf not found"
    fi
}

# ==============================================================================
# BOOTSTRAP MAIN MENU
# ==============================================================================

show_welcome() {
    clear_screen

    cat <<'EOF'
+===================================================+
|   z2k - Zapret2 для Keenetic (ALPHA)            |
|                   Версия 2.0.0                    |
+===================================================+

  [WARN]  ВНИМАНИЕ: Проект в активной разработке!
  [WARN]  Это пре-альфа версия - НЕ используйте в production!

  GitHub: https://github.com/necronicle/z2k

EOF

    print_info "Initialization..."
}

check_installation_status() {
    if is_zapret2_installed; then
        print_info "lock2 is already installed"
        print_info "Service status: $(get_service_status)"
        print_info "Current strategy: #$(get_current_strategy)"
        return 0
    else
        print_info "lock2 is not installed"
        return 1
    fi
}

prompt_install_or_menu() {
    printf "\n"

    if is_zapret2_installed; then
        print_info "I open the control menu..."
        sleep 1
        show_main_menu
    else
        print_info "zapret2 is not installed - I start the installation..."
        run_full_install
    fi
}


# ==============================================================================
# PROCESSING COMMAND LINE ARGUMENTS
# ==============================================================================

handle_arguments() {
    local command=$1

    case "$command" in
        install|i)
            print_info "Starting the installation of lock2..."
            run_full_install
            print_info "I open the control menu..."
            sleep 1
            show_main_menu
            ;;
        menu|m)
            print_info "Opening menu..."
            show_main_menu
            ;;
        uninstall|remove)
            print_info "Removing lock2..."
            uninstall_zapret2
            ;;
        status|s)
            show_system_info
            ;;
        update|u)
            print_info "z2k update..."
            update_z2k
            ;;
        version|v)
            echo "z2k v${Z2K_VERSION}"
            echo "zapret2: $(get_nfqws2_version)"
            ;;
        cleanup)
            print_info "Cleaning up old backups..."
            cleanup_backups "${INIT_SCRIPT:-/opt/etc/init.d/S99zapret2}" 5
            ;;
        check|info)
            print_info "Checking the active configuration..."
            show_active_processing
            ;;
        help|h|-h|--help)
            show_help
            ;;
        "")
            # No arguments - show welcome and offer installation
            prompt_install_or_menu
            ;;
        *)
            print_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

show_help() {
    cat <<EOF
Использование: sh z2k.sh [команда]

Команды:
  install, i       Установить zapret2
  menu, m          Открыть интерактивное меню
  uninstall        Удалить zapret2
  status, s        Показать статус системы
  check, info      Показать какие списки обрабатываются
  update, u        Обновить z2k до последней версии
  cleanup          Очистить старые бэкапы (оставить 5 последних)
  version, v       Показать версию
  help, h          Показать эту справку

Без аргументов:
  - Если zapret2 не установлен: предложит установку
  - Если zapret2 установлен: откроет меню

Примеры:
  curl -fsSL https://raw.githubusercontent.com/necronicle/z2k/master/z2k.sh | sh
  sh z2k.sh install
  sh z2k.sh menu
  sh z2k.sh check
  sh z2k.sh cleanup

EOF
}

# ==============================================================================
# Z2K UPDATE FUNCTION
# ==============================================================================

update_z2k() {
    print_header "z2k update"

    local latest_url="${GITHUB_RAW}/z2k.sh"
    local current_script
    current_script=$(readlink -f "$0")

    print_info "Current version: $Z2K_VERSION"
    print_info "Downloading the latest version..."

    # Download the new version to a temporary file
    local temp_file
    temp_file=$(mktemp)

    if curl -fsSL "$latest_url" -o "$temp_file"; then
        # Get version from new file
        local new_version
        new_version=$(grep '^Z2K_VERSION=' "$temp_file" | cut -d'"' -f2)

        if [ "$new_version" = "$Z2K_VERSION" ]; then
            print_success "You already have the latest version: $Z2K_VERSION"
            rm -f "$temp_file"
            return 0
        fi

        print_info "New version: $new_version"

        # Create a backup of the current script
        if [ -f "$current_script" ]; then
            cp "$current_script" "${current_script}.backup" || {
                print_error "Failed to create backup"
                rm -f "$temp_file"
                return 1
            }
        fi

        # Replace script
        mv "$temp_file" "$current_script" && chmod +x "$current_script"

        print_success "z2k updated: $Z2K_VERSION → $new_version"
        print_info "Backup saved: ${current_script}.backup"

        print_info "Restart z2k to apply changes"

    else
        print_error "Failed to download update"
        rm -f "$temp_file"
        return 1
    fi
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

main() {
    # Show greeting
    show_welcome

    # Check environment
    check_environment

    # Initialize working directory
    mkdir -p "$WORK_DIR" "$LIB_DIR"

    # Set signal handlers (will be overridden after utils.sh is loaded)
    trap 'echo ""; print_error "Прервано пользователем"; rm -rf "$WORK_DIR"; exit 130' INT TERM

    # Download modules
    download_modules

    # Load modules into memory
    source_modules

    # All module functions are now available
    # Reinstall signal handlers with correct functions
    setup_signal_handlers

    # Initialize system variables (SYSTEM, UNAME, INIT)
    init_system_vars || die "System type detection error"

    # Initialization (creating a working directory with checks from utils.sh)
    init_work_dir || die "Initialization error"

    # Check root permissions (needed for installation)
    if [ "$1" = "install" ] || [ "$1" = "i" ]; then
        check_root || die "Requires root permissions for installation"
    fi

    # Download strats_new2.txt
    download_strategies_source

    # Download fake blobs
    download_fake_blobs

    # Download init script
    download_init_script


    # Generate strategies.conf
    generate_strategies_database

    # Process command line arguments
    handle_arguments "$1"

    # Clear on exit (if not cleared automatically)
    # cleanup_work_dir
}

# ==============================================================================
# LAUNCH
# ==============================================================================

main "$@"
