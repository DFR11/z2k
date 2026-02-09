#!/bin/sh
# lib/config.sh - Manage configuration and domain lists
# Download, update and manage lists for zapret2

# ==============================================================================
# MANAGING DOMAIN LISTS
# ==============================================================================

# Download domain lists from zapret4rocket (z4r)
download_domain_lists() {
    print_header "Loading domain lists"
    print_info "Source: zapret4rocket (master branch)"
    print_info "Lists are used as is, without modifications"

    # Create directory structure
    local yt_tcp_dir="${ZAPRET2_DIR}/extra_strats/TCP/YT"
    local rkn_tcp_dir="${ZAPRET2_DIR}/extra_strats/TCP/RKN"
    local yt_udp_dir="${ZAPRET2_DIR}/extra_strats/UDP/YT"
    local rt_udp_dir="${ZAPRET2_DIR}/extra_strats/UDP/RUTRACKER"

    mkdir -p "$yt_tcp_dir" "$rkn_tcp_dir" "$yt_udp_dir" "$rt_udp_dir" "$LISTS_DIR" || {
        print_error "Failed to create directories"
        return 1
    }

    # 1. YouTube TCP - download from extra_strats/TCP/YT/List.txt
    print_info "Loading YouTube TCP list..."
    if curl -fsSL "${Z4R_BASE_URL}/extra_strats/TCP/YT/List.txt" -o "${yt_tcp_dir}/List.txt"; then
        local count
        count=$(wc -l < "${yt_tcp_dir}/List.txt" 2>/dev/null || echo "0")
        print_success "YouTube TCP: $count domains"
    else
        print_error "Error loading YouTube TCP list"
    fi

    # 2. YouTube GV - uses --hostlist-domains=googlevideo.com (no list needed)
    print_info "YouTube GV: using --hostlist-domains=googlevideo.com"

    # 3. RKN - download from extra_strats/TCP/RKN/List.txt (WITHOUT modifications)
    print_info "Loading RKN list..."
    if curl -fsSL "${Z4R_BASE_URL}/extra_strats/TCP/RKN/List.txt" -o "${rkn_tcp_dir}/List.txt"; then
        local count
        count=$(wc -l < "${rkn_tcp_dir}/List.txt" 2>/dev/null || echo "0")
        print_success "RKN: $count domains"
    else
        print_error "Error loading RKN list"
    fi

    # 4. QUIC YouTube - download from extra_strats/UDP/YT/List.txt
    print_info "Loading QUIC YouTube list..."
    if curl -fsSL "${Z4R_BASE_URL}/extra_strats/UDP/YT/List.txt" -o "${yt_udp_dir}/List.txt"; then
        local count
        count=$(wc -l < "${yt_udp_dir}/List.txt" 2>/dev/null || echo "0")
        print_success "QUIC YouTube: $count domains"
    else
        print_warning "Failed to load QUIC YouTube list"
    fi

    # 5. Discord - download from lists/russia-discord.txt
    print_info "Loading Discord list..."
    if curl -fsSL "${Z4R_LISTS_URL}/russia-discord.txt" -o "${LISTS_DIR}/discord.txt"; then
        local count
        count=$(wc -l < "${LISTS_DIR}/discord.txt" 2>/dev/null || echo "0")
        print_success "Discord: $count domains"
    else
        print_error "Error loading Discord list"
    fi

    # 6. Custom - create an empty file for custom domains
    if [ ! -f "${LISTS_DIR}/custom.txt" ]; then
        touch "${LISTS_DIR}/custom.txt"
        print_info "Created custom.txt for custom domains"
    fi

    # 7. RuTracker QUIC - local list
    cat > "${rt_udp_dir}/List.txt" <<'EOF'
rutracker.org
www.rutracker.org
static.rutracker.cc
fastpic.org
t-ru.org
www.t-ru.org
EOF
    print_success "RuTracker QUIC: local list created"

    print_separator
    print_success "Domain lists loaded"

    return 0
}

# Update domain lists
update_domain_lists() {
    print_header "Updating domain lists"

    # Download updated lists
    download_domain_lists

    # Show statistics
    print_separator
    show_domain_lists_stats

    # Ask about restarting the service
    if is_zapret2_running; then
        printf "\nDo you want to restart the service to apply the changes? [Y/n]:"
        read -r answer </dev/tty

        case "$answer" in
            [Nn]|[Nn][Oo])
                print_info "The service has not been restarted"
                print_info "Перезапустите вручную: /opt/etc/init.d/S99zapret2 restart"
                ;;
            *)
                print_info "Restarting the service..."
                "$INIT_SCRIPT" restart
                sleep 2
                if is_zapret2_running; then
                    print_success "Service restarted"
                else
                    print_error "Failed to restart service"
                fi
                ;;
        esac
    fi

    return 0
}

# Show statistics on domain lists
show_domain_lists_stats() {
    print_header "Domain list statistics"

    printf "%-30s | %-10s\n" "List" "Domains"
    print_separator

    # YouTube TCP
    local yt_tcp_list="${ZAPRET2_DIR}/extra_strats/TCP/YT/List.txt"
    if [ -f "$yt_tcp_list" ]; then
        local count
        count=$(wc -l < "$yt_tcp_list" 2>/dev/null || echo "0")
        printf "%-30s | %-10s\n" "YouTube TCP" "$count"
    fi

    # YouTube GV
    printf "%-30s | %-10s\n" "YouTube GV" "--hostlist-domains"

    # RKN
    local rkn_list="${ZAPRET2_DIR}/extra_strats/TCP/RKN/List.txt"
    if [ -f "$rkn_list" ]; then
        local count
        count=$(wc -l < "$rkn_list" 2>/dev/null || echo "0")
        printf "%-30s | %-10s\n" "RKN" "$count"
    fi

    # QUIC YouTube
    local quic_yt_list="${ZAPRET2_DIR}/extra_strats/UDP/YT/List.txt"
    if [ -f "$quic_yt_list" ]; then
        local count
        count=$(wc -l < "$quic_yt_list" 2>/dev/null || echo "0")
        printf "%-30s | %-10s\n" "QUIC YouTube" "$count"
    fi

    # Discord
    local discord_list="${LISTS_DIR}/discord.txt"
    if [ -f "$discord_list" ]; then
        local count
        count=$(wc -l < "$discord_list" 2>/dev/null || echo "0")
        printf "%-30s | %-10s\n" "Discord" "$count"
    fi

    # Custom
    local custom_list="${LISTS_DIR}/custom.txt"
    if [ -f "$custom_list" ]; then
        local count
        count=$(wc -l < "$custom_list" 2>/dev/null || echo "0")
        printf "%-30s | %-10s\n" "Custom" "$count"
    fi

    # RuTracker QUIC
    local rt_quic_list="${ZAPRET2_DIR}/extra_strats/UDP/RUTRACKER/List.txt"
    if [ -f "$rt_quic_list" ]; then
        local count
        count=$(wc -l < "$rt_quic_list" 2>/dev/null || echo "0")
        printf "%-30s | %-10s\n" "RuTracker QUIC" "$count"
    fi

    print_separator
}

# Show which lists are processed and operating mode
show_active_processing() {
    print_header "Active traffic processing"

    # Check ALL_TCP443 mode
    local all_tcp443_enabled=0
    local all_tcp443_strategy=""
    local all_tcp443_conf="${CONFIG_DIR}/all_tcp443.conf"

    if [ -f "$all_tcp443_conf" ]; then
        . "$all_tcp443_conf"
        all_tcp443_enabled=$ENABLED
        all_tcp443_strategy=$STRATEGY
    fi

    # Check QUIC RuTracker
    local rkn_quic_enabled=0
    if is_rutracker_quic_enabled 2>/dev/null; then
        rkn_quic_enabled=1
    fi

    # Show operating mode
    print_info "Traffic processing mode:"
    printf "\n"

    if [ "$all_tcp443_enabled" = "1" ]; then
        print_warning "[WARN] ALL TCP-443 MODE ON"
        printf "ALL HTTPS traffic is processed (port 443)\n"
        printf "Strategy: #%s\n" "$all_tcp443_strategy"
        printf "Domain lists are NOT used!\n"
        print_separator
    else
        print_success "[OK] Domain list mode (normal)"
        printf "\n"
    fi

    # Show active lists
    print_info "Processed domain lists:"
    print_separator
    printf "%-30s | %-10s | %s\n" "Category" "Domains" "Status"
    print_separator

    # RKN TCP
    local rkn_list="${ZAPRET2_DIR}/extra_strats/TCP/RKN/List.txt"
    if [ -f "$rkn_list" ]; then
        local count
        count=$(wc -l < "$rkn_list" 2>/dev/null || echo "0")
        printf "%-30s | %-10s | %s\n" "RKN (locked)" "$count" "Active"
    fi

    # YouTube TCP
    local yt_tcp_list="${ZAPRET2_DIR}/extra_strats/TCP/YT/List.txt"
    if [ -f "$yt_tcp_list" ]; then
        local count
        count=$(wc -l < "$yt_tcp_list" 2>/dev/null || echo "0")
        printf "%-30s | %-10s | %s\n" "YouTube TCP" "$count" "Active"
    fi

    # YouTube GV
    printf "%-30s | %-10s | %s\n" "YouTube GV (CDN)" "googlevideo.com" "Active"

    # QUIC YouTube
    local quic_yt_list="${ZAPRET2_DIR}/extra_strats/UDP/YT/List.txt"
    if [ -f "$quic_yt_list" ]; then
        local count
        count=$(wc -l < "$quic_yt_list" 2>/dev/null || echo "0")
        printf "%-30s | %-10s | %s\n" "QUIC YouTube (UDP 443)" "$count" "Active"
    fi

    # QUIC RuTracker
    local rt_quic_list="${ZAPRET2_DIR}/extra_strats/UDP/RUTRACKER/List.txt"
    if [ -f "$rt_quic_list" ]; then
        local count
        count=$(wc -l < "$rt_quic_list" 2>/dev/null || echo "0")
        local status
        if [ "$rkn_quic_enabled" = "1" ]; then
            status="Active"
        else
            status="Off"
        fi
        printf "%-30s | %-10s | %s\n" "QUIC RuTracker (UDP 443)" "$count" "$status"
    fi

    # Discord
    local discord_list="${LISTS_DIR}/discord.txt"
    if [ -f "$discord_list" ]; then
        local count
        count=$(wc -l < "$discord_list" 2>/dev/null || echo "0")
        printf "%-30s | %-10s | %s\n" "Discord (TCP+UDP)" "$count" "Active"
    fi

    # Custom
    local custom_list="${LISTS_DIR}/custom.txt"
    if [ -f "$custom_list" ]; then
        local count
        count=$(wc -l < "$custom_list" 2>/dev/null || echo "0")
        local status="Empty"
        if [ "$count" -gt 0 ]; then
            status="Active"
        fi
        printf "%-30s | %-10s | %s\n" "Custom" "$count" "$status"
    fi

    print_separator

    # Show exceptions
    print_info "Exceptions (whitelist):"
    local whitelist="${LISTS_DIR}/whitelist.txt"
    if [ -f "$whitelist" ]; then
        local count
        count=$(grep -v "^#" "$whitelist" | grep -v "^$" | wc -l 2>/dev/null || echo "0")
        printf "%s domains are excluded from processing\n" "$count"
        printf "File: %s\n" "$whitelist"
    else
        printf "Whitelist not found\n"
    fi

    print_separator

    # Total
    if [ "$all_tcp443_enabled" = "1" ]; then
        print_warning "ATTENTION: All HTTPS traffic is processed!"
        print_info "To turn off: sh z2k.sh menu → [A] ALL TCP-443 mode"
    else
        print_success "Operation mode: domain lists only (recommended)"
    fi
}

# Add domain in cut.txt
add_custom_domain() {
    local domain=$1

    if [ -z "$domain" ]; then
        print_error "Specify the domain to add"
        return 1
    fi

    local custom_list="${LISTS_DIR}/custom.txt"

    # Create file if does not exist
    if [ ! -f "$custom_list" ]; then
        mkdir -p "$LISTS_DIR"
        touch "$custom_list"
    fi

    # Check if it already exists
    if grep -qx "$domain" "$custom_list" 2>/dev/null; then
        print_warning "Domain is already in the list: $domain"
        return 0
    fi

    # Add a domain
    echo "$domain" >> "$custom_list"
    print_success "Added domain: $domain"

    return 0
}

# Remove the domain from custom.txt
remove_custom_domain() {
    local domain=$1
    local custom_list="${LISTS_DIR}/custom.txt"

    if [ -z "$domain" ]; then
        print_error "Specify the domain to delete"
        return 1
    fi

    if [ ! -f "$custom_list" ]; then
        print_error "File custom.txt not found"
        return 1
    fi

    # Delete domain
    if grep -qx "$domain" "$custom_list"; then
        grep -vx "$domain" "$custom_list" > "${custom_list}.tmp"
        mv "${custom_list}.tmp" "$custom_list"
        print_success "Deleted domain: $domain"
    else
        print_warning "Domain not found in the list: $domain"
    fi

    return 0
}

# Specifies the custom.txt
show_custom_domains() {
    local custom_list="${LISTS_DIR}/custom.txt"

    print_header "Custom Domains"

    if [ ! -f "$custom_list" ]; then
        print_info "The list is empty (the file has not been created)"
        return 0
    fi

    local count
    count=$(wc -l < "$custom_list" 2>/dev/null || echo "0")

    if [ "$count" -eq 0 ]; then
        print_info "The list is empty"
    else
        print_info "Total domains: $count"
        print_separator
        cat "$custom_list"
        print_separator
    fi

    return 0
}

# Signate the custom.txt
clear_custom_domains() {
    local custom_list="${LISTS_DIR}/custom.txt"

    if [ ! -f "$custom_list" ]; then
        print_info "The list is already empty"
        return 0
    fi

    printf "Clear list of custom domains? [y/N]:"
    read -r answer </dev/tty

    case "$answer" in
        [Yy]|[Yy][Ee][Ss])
            > "$custom_list"
            print_success "List cleared"
            ;;
        *)
            print_info "Cancelled"
            ;;
    esac

    return 0
}

# ==============================================================================
# CONFIGURATION MANAGEMENT
# ==============================================================================

# Create a basic zapret2 configuration
create_base_config() {
    print_info "Creating a basic configuration..."

    mkdir -p "$CONFIG_DIR" || {
        print_error "Failed to create $CONFIG_DIR"
        return 1
    }

    # Copy strategies.conf from working directory
    if [ -f "${WORK_DIR}/strategies.conf" ]; then
        cp "${WORK_DIR}/strategies.conf" "$STRATEGIES_CONF" || {
            print_error "Failed to copy strategies.conf"
            return 1
        }
        print_success "Strategies file created: $STRATEGIES_CONF"
    fi

    # Copy quic_strategies.conf from the working directory
    if [ -f "${WORK_DIR}/quic_strategies.conf" ]; then
        cp "${WORK_DIR}/quic_strategies.conf" "$QUIC_STRATEGIES_CONF" || {
            print_error "Failed to copy quic_strategies.conf"
            return 1
        }
        print_success "The QUIC strategies file has been created: $QUIC_STRATEGIES_CONF"
    fi

    # Create a file for the current strategy
    touch "$CURRENT_STRATEGY_FILE"

    # Create a file for the current QUIC strategy
    if [ ! -f "$QUIC_STRATEGY_FILE" ]; then
        echo "QUIC_STRATEGY=24" > "$QUIC_STRATEGY_FILE"
    fi

    # Create a file for QUIC strategy RuTracker
    if [ ! -f "$RUTRACKER_QUIC_STRATEGY_FILE" ]; then
        echo "RUTRACKER_QUIC_STRATEGY=43" > "$RUTRACKER_QUIC_STRATEGY_FILE"
    fi

    # Create a config to enable/disable QUIC RuTracker (disabled by default)
    local rutracker_quic_enabled_conf="${CONFIG_DIR}/rutracker_quic_enabled.conf"
    if [ ! -f "$rutracker_quic_enabled_conf" ]; then
        echo "RUTRACKER_QUIC_ENABLED=0" > "$rutracker_quic_enabled_conf"
        print_success "RuTracker QUIC is disabled by default"
    fi

    # Delete old QUIC strategy file by category (no longer used)
    local quic_category_conf="${CONFIG_DIR}/quic_category_strategies.conf"
    if [ -f "$quic_category_conf" ]; then
        rm -f "$quic_category_conf"
    fi

    # Create a config for the ALL_TCP443 mode (without hostlists)
    local all_tcp443_conf="${CONFIG_DIR}/all_tcp443.conf"
    if [ ! -f "$all_tcp443_conf" ]; then
        cat > "$all_tcp443_conf" <<'EOF'
# Operation mode for ALL TCP-443 domains without hostlists
# WARNING: This mode applies the policy to all HTTPS traffic
# May slow down connections, but bypasses any blockages

# Enable mode: 1 = enabled, 0 = disabled
ENABLED=0

# Strategy number to apply (1-199)
STRATEGY=1
EOF
        print_success "The ALL_TCP443 mode config has been created"
    fi

    # Create a directory for lists if it does not exist
    if ! mkdir -p "$LISTS_DIR" 2>/dev/null; then
        print_error "Failed to create directory: $LISTS_DIR"
        print_info "Check permissions"
        return 1
    fi

    # Check that the directory really exists
    if [ ! -d "$LISTS_DIR" ]; then
        print_error "Directory does not exist: $LISTS_DIR"
        return 1
    fi

    # Create a whitelist to exclude critical services
    local whitelist="${LISTS_DIR}/whitelist.txt"
    if [ ! -f "$whitelist" ]; then
        cat > "$whitelist" <<'EOF'
# Whitelist - domains excluded from processing by zapret2
# Services that may not work correctly with DPI bypass

# Social networks and media
pinterest.com
vkvideo.ru
vk.com
rutube.ru

# E-commerce and ads
avito.ru

# Streaming
netflix.com
vsetop.org
twitch.tv
ttvnw.net
static-cdn.jtvnw.net

# Google API
jnn-pa.googleapis.com
ogs.google.com
encrypted-tbn0.gstatic.com
encrypted-tbn1.gstatic.com
encrypted-tbn2.gstatic.com
encrypted-tbn3.gstatic.com

# Gaming
steamcommunity.com
steampowered.com
tarkov.com
escapefromtarkov.com

# Monitoring and CDN
browser-intake-datadoghq.com
datadoghq.com
okcdn.ru
api.mycdn.me

# Public services
gosuslugi.ru

# Development
raw.githubusercontent.com
EOF

        # Check that the file was actually created
        if [ ! -f "$whitelist" ]; then
            print_error "Failed to create whitelist: $whitelist"
            print_info "Check directory permissions"
            return 1
        fi

        print_success "Whitelist created: $whitelist"
    fi

    print_success "Basic configuration created"
    return 0
}

# Show current configuration
show_current_config() {
    print_header "Current configuration"

    printf "%-25s: %s\n" "Directory zapret2" "$ZAPRET2_DIR"
    printf "%-25s: %s\n" "Directory config" "$CONFIG_DIR"
    printf "%-25s: %s\n" "Lists directory" "$LISTS_DIR"
    printf "%-25s: %s\n" "Init script" "$INIT_SCRIPT"

    print_separator

    printf "%-25s: %s\n" "Service status" "$(get_service_status)"
    printf "%-25s: #%s\n" "Current strategy" "$(get_current_strategy)"

    if [ -f "$STRATEGIES_CONF" ]; then
        local count
        count=$(get_strategies_count)
        printf "%-25s: %s\n" "Total strategies" "$count"
    else
        printf "%-25s: %s\n" "Total strategies" "not installed"
    fi

    if [ -f "$QUIC_STRATEGIES_CONF" ]; then
        local qcount
        qcount=$(get_quic_strategies_count)
        printf "%-25s: %s\n" "QUIC strategies" "$qcount"
    fi

    if [ -f "$QUIC_STRATEGY_FILE" ]; then
        printf "%-25s: #%s\n" "QUIC YouTube" "$(get_current_quic_strategy)"
    fi
    if [ -f "$RUTRACKER_QUIC_STRATEGY_FILE" ]; then
        printf "%-25s: #%s\n" "QUIC RuTracker" "$(get_rutracker_quic_strategy)"
    fi

    print_separator

    # Domain Lists
    if [ -d "$LISTS_DIR" ]; then
        print_info "Domain lists:"
        for list in discord.txt youtube.txt rkn.txt custom.txt; do
            if [ -f "${LISTS_DIR}/${list}" ]; then
                local count
                count=$(wc -l < "${LISTS_DIR}/${list}" 2>/dev/null || echo "0")
                printf "%-20s: %s domains\n" "$list" "$count"
            fi
        done
        local yt_quic_list="${ZAPRET2_DIR}/extra_strats/UDP/YT/List.txt"
        if [ -f "$yt_quic_list" ]; then
            local yt_quic_count
            yt_quic_count=$(wc -l < "$yt_quic_list" 2>/dev/null || echo "0")
            printf "%-20s: %s domains\n" "extra_strats/UDP/YT/List.txt" "$yt_quic_count"
        fi
        local rt_quic_list="${ZAPRET2_DIR}/extra_strats/UDP/RUTRACKER/List.txt"
        if [ -f "$rt_quic_list" ]; then
            local rt_quic_count
            rt_quic_count=$(wc -l < "$rt_quic_list" 2>/dev/null || echo "0")
            printf "%-20s: %s domains\n" "extra_strats/UDP/RUTRACKER/List.txt" "$rt_quic_count"
        fi
    else
        print_info "Domain lists: not installed"
    fi

    print_separator
}

# Reset configuration to defaults
reset_config() {
    print_header "Reset configuration"

    print_warning "This will remove:"
    print_warning "- Current strategy"
    print_warning "- Custom domains (custom.txt)"
    print_warning "Discord/youtube lists will NOT be deleted"

    printf "\nContinue reset? [y/N]:"
    read -r answer </dev/tty

    case "$answer" in
        [Yy]|[Yy][Ee][Ss])
            # Clear current strategy
            if [ -f "$CURRENT_STRATEGY_FILE" ]; then
                rm -f "$CURRENT_STRATEGY_FILE"
                print_info "Current strategy reset"
            fi

            # Signate the custom.txt
            if [ -f "${LISTS_DIR}/custom.txt" ]; then
                > "${LISTS_DIR}/custom.txt"
                print_info "Cleared the list of custom domains"
            fi

            print_success "Configuration reset"

            # Suggest restart
            if is_zapret2_running; then
                printf "\nRestart the service? [Y/n]:"
                read -r restart_answer </dev/tty

                case "$restart_answer" in
                    [Nn]|[Nn][Oo])
                        print_info "The service has not been restarted"
                        ;;
                    *)
                        "$INIT_SCRIPT" restart
                        print_success "Service restarted"
                        ;;
                esac
            fi
            ;;
        *)
            print_info "Cancelled"
            ;;
    esac

    return 0
}

# Create backup configuration
backup_config() {
    local backup_dir="${CONFIG_DIR}/backups"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${backup_dir}/config_backup_${timestamp}.tar.gz"

    print_header "Creating a Backup"

    mkdir -p "$backup_dir" || {
        print_error "Failed to create backup directory"
        return 1
    }

    print_info "Creating an archive..."

    # Create tar.gz with configuration
    tar -czf "$backup_file" \
        -C "$CONFIG_DIR" \
        strategies.conf \
        current_strategy \
        -C "$LISTS_DIR" \
        custom.txt \
        2>/dev/null

    if [ -f "$backup_file" ]; then
        local size
        size=$(du -h "$backup_file" | cut -f1)
        print_success "Backup created: $backup_file ($size)"
        return 0
    else
        print_error "Failed to create backup"
        return 1
    fi
}

# Restore configuration from backup
restore_config() {
    local backup_dir="${CONFIG_DIR}/backups"

    print_header "Restoring the configuration"

    if [ ! -d "$backup_dir" ]; then
        print_error "Directory backups not found"
        return 1
    fi

    # Find the latest backup
    local latest_backup
    latest_backup=$(ls -t "${backup_dir}"/config_backup_*.tar.gz 2>/dev/null | head -n 1)

    if [ -z "$latest_backup" ]; then
        print_error "No backups found"
        return 1
    fi

    print_info "Latest backup: $latest_backup"
    printf "Restore? [y/N]:"
    read -r answer </dev/tty

    case "$answer" in
        [Yy]|[Yy][Ee][Ss])
            print_info "Recovery..."

            # Extract backup
            tar -xzf "$latest_backup" -C "$CONFIG_DIR" 2>/dev/null

            if [ $? -eq 0 ]; then
                print_success "Configuration restored"

                # Suggest restart
                if is_zapret2_running; then
                    printf "Restart the service? [Y/n]:"
                    read -r restart_answer </dev/tty

                    case "$restart_answer" in
                        [Nn]|[Nn][Oo])
                            print_info "The service has not been restarted"
                            ;;
                        *)
                            "$INIT_SCRIPT" restart
                            print_success "Service restarted"
                            ;;
                    esac
                fi
            else
                print_error "Restore Error"
                return 1
            fi
            ;;
        *)
            print_info "Cancelled"
            ;;
    esac

    return 0
}

# ==============================================================================
# EXPORTING FUNCTIONS
# ==============================================================================

# All functions are available after the source of this file
