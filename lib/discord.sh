#!/bin/sh
# lib/discord.sh - Discord voice/video configuration
# An exact copy of the zapret4rocket (z4r) approach with extended UDP ports

# ==============================================================================
# DISCORD CONSTANTS
# ==============================================================================

# Extended UDP ports for Discord voice/video (same as z4r)
DISCORD_UDP_PORTS="443,50000:50099,1400,3478:3481,5349"

# Discord domains (will be loaded from discord.txt)
DISCORD_DOMAINS="
discord.com
discord.gg
discordapp.com
discordapp.io
discordapp.net
discord.media
discordcdn.com
discordstatus.com
discord-attachments-uploads-prd.storage.googleapis.com
"

# ==============================================================================
# DISCORD VOICE/VIDEO SETUP
# ==============================================================================

configure_discord_voice() {
    print_header "Setting up Discord: voice and video"

    # Check installation
    if ! is_zapret2_installed; then
        print_error "lock2 is not installed"
        return 1
    fi

    # Check for a list of Discord domains
    if [ ! -f "${LISTS_DIR}/discord.txt" ]; then
        print_warning "Discord.txt list not found"
        print_info "Loading a list of domains..."
        download_domain_lists || {
            print_error "Failed to load lists"
            return 1
        }
    fi

    print_separator
    print_info "Discord uses:"
    print_info "- TCP 443 for text chats"
    print_info "- UDP 443, 50000-50099 for voice/video"
    print_info "- UDP 1400, 3478-3481, 5349 for WebRTC"
    print_separator

    # Get current strategy
    local current_strategy
    current_strategy=$(get_current_strategy)

    if [ "$current_strategy" = "not specified" ] || [ -z "$current_strategy" ]; then
        print_warning "The current strategy is not set"
        printf "\nChoose a strategy for Discord (recommended from TOP-20).\n"
        printf "Enter strategy number:"
        read -r strategy_num </dev/tty
    else
        printf "\nCurrent strategy: #%s\n" "$current_strategy"
        printf "Use it for Discord? [Y/n]:"
        read -r answer </dev/tty

        case "$answer" in
            [Nn]|[Nn][Oo])
                printf "Enter the new strategy number:"
                read -r strategy_num </dev/tty
                ;;
            *)
                strategy_num=$current_strategy
                ;;
        esac
    fi

    # Check strategy
    if ! strategy_exists "$strategy_num"; then
        print_error "Strategy #$strategy_num not found"
        return 1
    fi

    # Get TCP strategy parameters
    local tcp_params
    tcp_params=$(get_strategy "$strategy_num")

    if [ -z "$tcp_params" ]; then
        print_error "Failed to get strategy parameters"
        return 1
    fi

    print_info "I'm using the #$strategy_num for Discord..."
    print_separator
    printf "TCP parameter:\n%s\n" "$tcp_params"
    print_separator

    # Generate Discord multi-profile configuration
    generate_discord_profile "$tcp_params"

    print_success "Discord is set up!"
    print_separator
    print_info "Configuration:"
    print_info "- TCP (text): strategy #$strategy_num"
    print_info "- UDP (voice/video): extended ports"
    print_info "- List of domains: ${LISTS_DIR}/discord.txt"
    print_separator

    return 0
}

# ==============================================================================
# GENERATING A DISCORD PROFILE
# ==============================================================================

generate_discord_profile() {
    local tcp_params=$1

    # Create a temporary file with Discord profile
    local discord_profile_file="/tmp/discord_profile.conf"

    cat > "$discord_profile_file" <<DISCORD_PROFILE
# Discord TCP Profile (text chats)
--filter-tcp=443
--hostlist=${LISTS_DIR}/discord.txt
$tcp_params

--new

# Discord UDP Profile (voice/video)
--filter-udp=${DISCORD_UDP_PORTS}
--hostlist=${LISTS_DIR}/discord.txt
--filter-l7=discord,stun
--payload=stun,discord_ip_discovery
--out-range=-n10
--lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2
DISCORD_PROFILE

    # Inject into init script
    inject_discord_to_init "$discord_profile_file"

    # Delete temporary file
    rm -f "$discord_profile_file"
}

# ==============================================================================
# INJECTION OF DISCORD CONFIGURATION INTO INIT SCRIPT
# ==============================================================================

inject_discord_to_init() {
    local profile_file=$1
    local init_script="${INIT_SCRIPT:-/opt/etc/init.d/S99zapret2}"

    if [ ! -f "$init_script" ]; then
        print_error "Init script not found: $init_script"
        return 1
    fi

    if [ ! -f "$profile_file" ]; then
        print_error "Profile file not found: $profile_file"
        return 1
    fi

    # Create backup
    backup_file "$init_script" || {
        print_error "Failed to create backup"
        return 1
    }

    # Read profile
    local discord_config
    discord_config=$(cat "$profile_file")

    # Modify init script
    # 1. Enable Discord (DISCORD_ENABLED=1)
    # 2. Set TCP and UDP parameters between markers

    awk -v config="$discord_config" '
        BEGIN {
            in_discord_marker=0
            discord_marker_found=0
            split(config, lines, "\n")

            # Extract TCP and UDP parts from config
            tcp_part=""
            udp_part=""
            in_new=0

            for (i in lines) {
                line = lines[i]
                if (line ~ /^--new/) {
                    in_new=1
                    continue
                }
                if (!in_new && line !~ /^#/ && line != "") {
                    if (tcp_part != "") tcp_part = tcp_part " "
                    tcp_part = tcp_part line
                }
                if (in_new && line !~ /^#/ && line != "") {
                    if (udp_part != "") udp_part = udp_part " "
                    udp_part = udp_part line
                }
            }
        }

        # Enable Discord
        /^DISCORD_ENABLED=/ {
            print "DISCORD_ENABLED=1"
            next
        }

        # Replace between markers
        /DISCORD_MARKER_START/ {
            print
            print "DISCORD_TCP=\"" tcp_part "\""
            print "DISCORD_UDP=\"" udp_part "\""
            in_discord_marker=1
            discord_marker_found=1
            next
        }

        /DISCORD_MARKER_END/ {
            in_discord_marker=0
            print
            next
        }

        !in_discord_marker { print }

        END {
            if (!discord_marker_found) {
                print "ERROR: DISCORD_MARKER not found" > "/dev/stderr"
                exit 1
            }
        }
    ' "$init_script" > "${init_script}.tmp"

    # Check success
    if [ $? -ne 0 ]; then
        print_error "Error modifying init script"
        return 1
    fi

    # Replace init script
    mv "${init_script}.tmp" "$init_script" || {
        print_error "Failed to replace init script"
        return 1
    }

    chmod +x "$init_script"

    # Restart service
    print_info "Restarting the service..."
    "$init_script" restart >/dev/null 2>&1

    sleep 2

    if is_zapret2_running; then
        print_success "Service restarted with Discord configuration"

        # Check that 2 nfqws2 processes are running
        local process_count
        process_count=$(pgrep -c -f "nfqws2")

        if [ "$process_count" -ge 2 ]; then
            print_success "nfqws2 processes running: $process_count (main + Discord)"
        else
            print_warning "Processes running: $process_count (expected 2)"
            print_info "Check the status: $init_script status"
        fi
    else
        print_error "The service did not start"
        print_info "Restoring the previous configuration..."
        restore_backup "$init_script"
        "$init_script" restart >/dev/null 2>&1
        return 1
    fi

    return 0
}

# ==============================================================================
# DISABLE DISCORD CONFIGURATION
# ==============================================================================

disable_discord() {
    print_header "Disabling Discord Configuration"

    local init_script="${INIT_SCRIPT:-/opt/etc/init.d/S99zapret2}"

    if [ ! -f "$init_script" ]; then
        print_error "Init script not found"
        return 1
    fi

    # Create backup
    backup_file "$init_script"

    # Disable Discord (DISCORD_ENABLED=0)
    awk '
        /^DISCORD_ENABLED=/ {
            print "DISCORD_ENABLED=0"
            next
        }
        { print }
    ' "$init_script" > "${init_script}.tmp"

    mv "${init_script}.tmp" "$init_script"
    chmod +x "$init_script"

    # Restart
    print_info "Restarting the service..."
    "$init_script" restart >/dev/null 2>&1

    if is_zapret2_running; then
        print_success "Discord config disabled"
    else
        print_error "Service restart error"
        return 1
    fi

    return 0
}

# ==============================================================================
# DISCORD CONFIGURATION STATUS
# ==============================================================================

discord_status() {
    print_header "Discord configuration status"

    local init_script="${INIT_SCRIPT:-/opt/etc/init.d/S99zapret2}"

    if [ ! -f "$init_script" ]; then
        print_error "Init script not found"
        return 1
    fi

    # Check DISCORD_ENABLED
    local discord_enabled
    discord_enabled=$(grep "^DISCORD_ENABLED=" "$init_script" | cut -d'=' -f2)

    if [ "$discord_enabled" = "1" ]; then
        print_success "Discord Configuration: ON"

        # Show UDP ports
        print_info "UDP ports: $DISCORD_UDP_PORTS"

        # Show options
        print_separator
        grep "^DISCORD_TCP=" "$init_script" | cut -d'"' -f2
        print_separator

        # Check processes
        local process_count
        process_count=$(pgrep -c -f "nfqws2")
        print_info "nfqws2 processes: $process_count"
    else
        print_info "Discord config: DISABLED"
    fi

    return 0
}

# ==============================================================================
# EXPORTING FUNCTIONS
# ==============================================================================

# All functions are available after the source of this file
