#!/bin/sh
# lib/menu.sh - Interactive z2k control menu
# 9 options for complete control of zapret2

# ==============================================================================
# AUXILIARY FUNCTION FOR READING INPUT
# ==============================================================================

# Read user input (works even when stdin is redirected via pipe)
read_input() {
    read -r "$@" </dev/tty
}

# ==============================================================================
# MAIN MENU
# ==============================================================================

show_main_menu() {
    while true; do
        clear_screen

        cat <<'MENU'
+===================================================+
|   z2k - Zapret2 для Keenetic (ALPHA)            |
+===================================================+


MENU

        # Show current status
        printf "\n"
        printf "Status: %s\n" "$(is_zapret2_installed && echo 'Установлен' || echo 'Не установлен')"

        if is_zapret2_installed; then
            printf "Service: %s\n" "$(get_service_status)"

            # Check strategy mode
            if [ -f "$CATEGORY_STRATEGIES_CONF" ]; then
                local count
                count=$(grep -c ":" "$CATEGORY_STRATEGIES_CONF" 2>/dev/null || echo 0)
                printf "Strategies: %s categories\n" "$count"
            else
                printf "Current strategy: #%s\n" "$(get_current_strategy)"
            fi

            # Check ALL TCP-443 mode
            local all_tcp443_conf="${CONFIG_DIR}/all_tcp443.conf"
            if [ -f "$all_tcp443_conf" ]; then
                . "$all_tcp443_conf"
                if [ "$ENABLED" = "1" ]; then
                    printf "ALL TCP-443: On (strategy #%s)\n" "$STRATEGY"
                fi
            fi

            # QUIC RuTracker status
            if is_rutracker_quic_enabled; then
                printf "RuTracker QUIC: Enabled\n"
            fi
        fi

        cat <<'MENU'

[1] Установить/Переустановить zapret2
[2] Выбрать стратегию по номеру
[3] Автотест стратегий
[4] Управление сервисом
[6] Обновить списки доменов
[8] Резервная копия/Восстановление
[9] Удалить zapret2
[A] Режим ALL TCP-443 (без хостлистов)
[Q] Настройки QUIC
[W] Whitelist (исключения)
[0] Выход

MENU

        printf "Select option [0-9,A,Q,W]:"
        read_input choice

        case "$choice" in
            1)
                menu_install
                ;;
            2)
                menu_select_strategy
                ;;
            3)
                menu_autotest
                ;;
            4)
                menu_service_control
                ;;
            6)
                menu_update_lists
                ;;
            8)
                menu_backup_restore
                ;;
            9)
                menu_uninstall
                ;;
            a|A)
                menu_all_tcp443
                ;;
            q|Q)
                menu_quic_settings
                ;;
            w|W)
                menu_whitelist
                ;;
            0)
                print_info "Exit menu"
                return 0
                ;;
            *)
                print_error "Wrong choice: $choice"
                pause
                ;;
        esac
    done
}

# ==============================================================================
# SUBMENU: INSTALLATION
# ==============================================================================

menu_install() {
    clear_screen
    print_header "[1] Installing/Reinstalling zapret2"

    if is_zapret2_installed; then
        print_warning "lock2 is already installed"
        printf "\nReinstall? [y/N]:"
        read_input answer

        case "$answer" in
            [Yy]|[Yy][Ee][Ss])
                run_full_install
                ;;
            *)
                print_info "Installation canceled"
                ;;
        esac
    else
        run_full_install
    fi

    pause
}

# ==============================================================================
# SUBMENU: STRATEGY SELECTION
# ==============================================================================

menu_select_strategy() {
    clear_screen
    print_header "[2] Selecting a strategy by category"

    if ! is_zapret2_installed; then
        print_error "lock2 is not installed"
        print_info "Install first (option 1)"
        pause
        return
    fi

    local total_count
    total_count=$(get_strategies_count)
    # Read current strategies
    local config_file="${CONFIG_DIR}/category_strategies.conf"
    local current_yt_tcp="1"
    local current_yt_gv="1"
    local current_rkn="1"

    if [ -f "$config_file" ]; then
        current_yt_tcp=$(grep "^youtube_tcp:" "$config_file" 2>/dev/null | cut -d':' -f2)
        current_yt_gv=$(grep "^youtube_gv:" "$config_file" 2>/dev/null | cut -d':' -f2)
        current_rkn=$(grep "^rkn:" "$config_file" 2>/dev/null | cut -d':' -f2)
        [ -z "$current_yt_tcp" ] && current_yt_tcp="1"
        [ -z "$current_yt_gv" ] && current_yt_gv="1"
        [ -z "$current_rkn" ] && current_rkn="1"
    fi

    print_info "Total strategies available: $total_count"
    print_separator
    print_info "Current strategies:"
    printf "  YouTube TCP: #%s\n" "$current_yt_tcp"
    printf "  YouTube GV:  #%s\n" "$current_yt_gv"
    printf "  RKN:         #%s\n" "$current_rkn"
    printf "  QUIC YouTube:    #%s\n" "$(get_current_quic_strategy)"
    printf "  QUIC RuTracker:  #%s\n" "$(get_rutracker_quic_strategy)"
    print_separator

    # Category selection submenu
    cat <<'SUBMENU'

Выберите категорию для изменения стратегии:
[1] YouTube TCP (youtube.com)
[2] YouTube GV (googlevideo CDN)
[3] RKN (заблокированные сайты)
[4] QUIC (UDP 443)
[5] Все категории сразу
[6] Уровень агрессивности (soft/medium/aggressive)
[B] Назад

SUBMENU
    printf "Your choice:"
    read_input category_choice

    case "$category_choice" in
        1)
            # YouTube TCP
            menu_select_single_strategy "YouTube TCP" "$current_yt_tcp" "$total_count"
            if [ $? -eq 0 ] && [ -n "$SELECTED_STRATEGY" ]; then
                local new_strategy="$SELECTED_STRATEGY"
                print_separator
                print_info "I'm using the #$new_strategy for testing..."
                apply_category_strategies_v2 "$new_strategy" "$current_yt_gv" "$current_rkn"
                print_separator
                test_category_availability "YouTube TCP" "youtube.com"
                print_separator

                printf "Apply this strategy permanently? [Y/n]:"
                read_input apply_confirm
                case "$apply_confirm" in
                    [Nn]|[Nn][Oo])
                        print_info "I roll back to the previous strategy #$current_yt_tcp..."
                        apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
                        print_success "Rollback completed"
                        ;;
                    *)
                        save_category_strategies "$new_strategy" "$current_yt_gv" "$current_rkn"
                        apply_category_strategies_v2 "$new_strategy" "$current_yt_gv" "$current_rkn"
                        print_success "The YouTube TCP strategy is applied permanently!"
                        ;;
                esac
            fi
            return
            ;;
        2)
            # YouTube GV
            menu_select_single_strategy "YouTube GV" "$current_yt_gv" "$total_count"
            if [ $? -eq 0 ] && [ -n "$SELECTED_STRATEGY" ]; then
                local new_strategy="$SELECTED_STRATEGY"
                print_separator
                print_info "I'm using the #$new_strategy for testing..."
                apply_category_strategies_v2 "$current_yt_tcp" "$new_strategy" "$current_rkn"
                print_separator
                local gv_domain
                gv_domain=$(generate_gv_domain)
                test_category_availability "YouTube GV" "$gv_domain"
                print_separator

                printf "Apply this strategy permanently? [Y/n]:"
                read_input apply_confirm
                case "$apply_confirm" in
                    [Nn]|[Nn][Oo])
                        print_info "I roll back to the previous strategy #$current_yt_gv..."
                        apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
                        print_success "Rollback completed"
                        ;;
                    *)
                        save_category_strategies "$current_yt_tcp" "$new_strategy" "$current_rkn"
                        apply_category_strategies_v2 "$current_yt_tcp" "$new_strategy" "$current_rkn"
                        print_success "YouTube GV strategy applied continuously!"
                        ;;
                esac
            fi
            return
            ;;
        3)
            # RKN
            menu_select_single_strategy "RKN" "$current_rkn" "$total_count"
            if [ $? -eq 0 ] && [ -n "$SELECTED_STRATEGY" ]; then
                local new_strategy="$SELECTED_STRATEGY"
                print_separator
                print_info "I'm using the #$new_strategy for testing..."
                apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$new_strategy"
                print_separator
                test_category_availability_rkn
                print_separator

                printf "Apply this strategy permanently? [Y/n]:"
                read_input apply_confirm
                case "$apply_confirm" in
                    [Nn]|[Nn][Oo])
                        print_info "I roll back to the previous strategy #$current_rkn..."
                        apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
                        print_success "Rollback completed"
                        ;;
                    *)
                        save_category_strategies "$current_yt_tcp" "$current_yt_gv" "$new_strategy"
                        apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$new_strategy"
                        print_success "The RKN strategy is applied continuously!"
                        ;;
                esac
            fi
            return
            ;;
        4)
            # QUIC (UDP 443)
            menu_select_quic_strategy
            return
            ;;
        5)
            # All categories
            menu_select_all_strategies "$total_count"
            pause
            return
            ;;
        6)
            print_separator
            print_info "Select aggressiveness level:"
            printf "[1] Soft -> TCP #1/#4/#7, QUIC #1\n"
            printf "[2] Medium -> TCP #2/#5/#8, QUIC #2\n"
            printf "[3] Aggressive (hard)-> TCP #3/#6/#9, QUIC #3\n"
            printf "Your choice [1/2/3]:"
            read_input tier_choice

            case "$tier_choice" in
                1) apply_default_strategies ;;
                2) apply_medium_strategies ;;
                3) apply_new_default_strategies ;;
                *) print_warning "Incorrect level selection" ;;
            esac
            pause
            return
            ;;
        [Bb])
            return
            ;;
        *)
            print_error "Wrong choice"
            pause
            return
            ;;
    esac
}

# Helper Function: Category Availability Check
test_category_availability() {
    local category_name=$1
    local test_domain=$2

    print_info "Availability check: $category_name ($test_domain)..."

    # Wait 2 seconds for rules to apply
    sleep 2

    # Run test
    if test_strategy_tls "$test_domain" 5; then
        print_success "[OK] $category_name is available! The strategy is working."
    else
        print_error "[FAIL] $category_name is not available. Try a different strategy."
        print_info "Recommendation: run Autotest [3] to find a working strategy"
    fi
}

# Helper function: RKN availability check (3 domains)
test_category_availability_rkn() {
    local test_domains="meduza.io facebook.com rutracker.org"
    local success_count=0

    print_info "Availability check: RKN (meduza.io, facebook.com, rutracker.org)..."

    sleep 2

    for domain in $test_domains; do
        if test_strategy_tls "$domain" 5; then
            success_count=$((success_count + 1))
        fi
    done

    if [ "$success_count" -ge 2 ]; then
        print_success "[OK] RKN is available! The strategy is working. (${success_count}/3)"
    else
        print_error "[FAIL] RKN is not available. Try a different strategy. (${success_count}/3)"
        print_info "Recommendation: run Autotest [3] to find a working strategy"
    fi
}

# Global variable to transfer the selected strategy
SELECTED_STRATEGY=""

# Helper function: select strategy for one category
menu_select_single_strategy() {
    local category_name=$1
    local current_strategy=$2
    local total_count=$3

    # Resetting a global variable
    SELECTED_STRATEGY=""

    printf "\n"
    print_info "Selecting a strategy for: $category_name"
    printf "Current strategy: #%s\n\n" "$current_strategy"

    while true; do
        printf "Enter strategy number [1-%s] or Enter to cancel:" "$total_count"
        read_input new_strategy

        # Cancel
        if [ -z "$new_strategy" ]; then
            print_info "Cancelled"
            return 1
        fi

        # Checks
        if ! echo "$new_strategy" | grep -qE '^[0-9]+$'; then
            print_error "Invalid number format"
            continue
        fi

        if [ "$new_strategy" -lt 1 ] || [ "$new_strategy" -gt "$total_count" ]; then
            print_error "Number out of range"
            continue
        fi

        if ! strategy_exists "$new_strategy"; then
            print_error "Strategy #$new_strategy not found"
            continue
        fi

        # Show options
        local params
        params=$(get_strategy "$new_strategy")
        print_info "Strategy #$new_strategy selected:"
        printf "  %s\n\n" "$params"

        # Save to a global variable
        SELECTED_STRATEGY="$new_strategy"
        return 0
    done
}

# Apply current category strategies (YouTube TCP/GV/RKN)
apply_current_category_strategies() {
    local config_file="${CONFIG_DIR}/category_strategies.conf"
    local current_yt_tcp="1"
    local current_yt_gv="1"
    local current_rkn="1"

    if [ -f "$config_file" ]; then
        current_yt_tcp=$(grep "^youtube_tcp:" "$config_file" 2>/dev/null | cut -d':' -f2)
        current_yt_gv=$(grep "^youtube_gv:" "$config_file" 2>/dev/null | cut -d':' -f2)
        current_rkn=$(grep "^rkn:" "$config_file" 2>/dev/null | cut -d':' -f2)
        [ -z "$current_yt_tcp" ] && current_yt_tcp="1"
        [ -z "$current_yt_gv" ] && current_yt_gv="1"
        [ -z "$current_rkn" ] && current_rkn="1"
    fi

    print_info "Applying current category strategies..."
    apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
}

# Helper function: QUIC strategy selection (UDP 443)
menu_select_quic_strategy() {
    clear_screen
    print_header "QUIC strategy (UDP 443)"

    if ! is_zapret2_installed; then
        print_error "lock2 is not installed"
        pause
        return
    fi

    local total_quic
    total_quic=$(get_quic_strategies_count)
    if [ "$total_quic" -lt 1 ]; then
        print_error "QUIC strategies not found"
        pause
        return
    fi

    printf "\n"
    print_info "Total QUIC strategies: $total_quic"
    printf "Current QUIC strategies:\n"
    printf "  YouTube:    #%s\n" "$(get_current_quic_strategy)"
    printf "  RuTracker:  #%s\n\n" "$(get_rutracker_quic_strategy)"

    while true; do
        printf "Select QUIC category:\n"
        printf "[1] YouTube QUIC\n"
        printf "[2] RuTracker QUIC\n"
        printf "[B] Back\n\n"
        printf "Your choice:"
        read_input quic_choice

        case "$quic_choice" in
            1)
                local category_name="YouTube QUIC"
                local current_quic
                current_quic=$(get_current_quic_strategy)
                ;;
            2)
                local category_name="RuTracker QUIC"
                local current_quic
                current_quic=$(get_rutracker_quic_strategy)
                ;;
            [Bb])
                return
                ;;
            *)
                print_error "Wrong choice"
                continue
                ;;
        esac

        printf "\nCurrent QUIC strategy: #%s\n" "$current_quic"
        printf "Enter the QUIC strategy number [1-%s] or Enter to cancel:" "$total_quic"
        read_input new_strategy

        if [ -z "$new_strategy" ]; then
            print_info "Cancelled"
            return
        fi

        if ! echo "$new_strategy" | grep -qE '^[0-9]+$'; then
            print_error "Invalid number format"
            continue
        fi

        if [ "$new_strategy" -lt 1 ] || [ "$new_strategy" -gt "$total_quic" ]; then
            print_error "Number out of range"
            continue
        fi

        if ! quic_strategy_exists "$new_strategy"; then
            print_error "QUIC strategy #$new_strategy not found"
            continue
        fi

        local name
        local desc
        local params
        name=$(get_quic_strategy_name "$new_strategy")
        desc=$(get_quic_strategy_desc "$new_strategy")
        params=$(get_quic_strategy "$new_strategy")

        print_info "Selected QUIC strategy #$new_strategy (${name})"
        [ -n "$desc" ] && printf "  %s\n" "$desc"
        printf "  %s\n\n" "$params"

        printf "Apply this QUIC strategy to %s? [Y/n]:" "$category_name"
        read_input apply_confirm
        case "$apply_confirm" in
            [Nn]|[Nn][Oo])
                print_info "Cancelled"
                return
                ;;
            *)
                if [ "$quic_choice" = "1" ]; then
                    set_current_quic_strategy "$new_strategy"
                else
                    set_rutracker_quic_strategy "$new_strategy"
                fi
                apply_current_category_strategies
                print_success "QUIC strategy applied"
                pause
                return
                ;;
        esac
    done
}

# Helper function: select strategies for all categories
menu_select_all_strategies() {
    local total_count=$1

    printf "\n"
    print_info "Selection of strategies for all categories:"
    printf "\n"

    # YouTube TCP
    local yt_tcp_strategy
    while true; do
        printf "YouTube TCP [1-%s]: " "$total_count"
        read_input yt_tcp_strategy

        if ! echo "$yt_tcp_strategy" | grep -qE '^[0-9]+$'; then
            print_error "Invalid format"
            continue
        fi

        if [ "$yt_tcp_strategy" -lt 1 ] || [ "$yt_tcp_strategy" -gt "$total_count" ]; then
            print_error "Number out of range"
            continue
        fi

        if ! strategy_exists "$yt_tcp_strategy"; then
            print_error "Strategy not found"
            continue
        fi

        break
    done

    # YouTube GV
    local yt_gv_strategy
    while true; do
        printf "YouTube GV [1-%s, Enter=use %s]:" "$total_count" "$yt_tcp_strategy"
        read_input yt_gv_strategy

        if [ -z "$yt_gv_strategy" ]; then
            yt_gv_strategy="$yt_tcp_strategy"
            print_info "Used: #$yt_gv_strategy"
            break
        fi

        if ! echo "$yt_gv_strategy" | grep -qE '^[0-9]+$'; then
            print_error "Invalid format"
            continue
        fi

        if [ "$yt_gv_strategy" -lt 1 ] || [ "$yt_gv_strategy" -gt "$total_count" ]; then
            print_error "Number out of range"
            continue
        fi

        if ! strategy_exists "$yt_gv_strategy"; then
            print_error "Strategy not found"
            continue
        fi

        break
    done

    # RKN
    local rkn_strategy
    while true; do
        printf "RKN [1-%s, Enter=use %s]:" "$total_count" "$yt_tcp_strategy"
        read_input rkn_strategy

        if [ -z "$rkn_strategy" ]; then
            rkn_strategy="$yt_tcp_strategy"
            print_info "Used: #$rkn_strategy"
            break
        fi

        if ! echo "$rkn_strategy" | grep -qE '^[0-9]+$'; then
            print_error "Invalid format"
            continue
        fi

        if [ "$rkn_strategy" -lt 1 ] || [ "$rkn_strategy" -gt "$total_count" ]; then
            print_error "Number out of range"
            continue
        fi

        if ! strategy_exists "$rkn_strategy"; then
            print_error "Strategy not found"
            continue
        fi

        break
    done

    # Final table
    printf "\n"
    print_separator
    printf "%-20s | %s\n" "Category" "Strategy"
    print_separator
    printf "%-20s | #%s\n" "YouTube TCP" "$yt_tcp_strategy"
    printf "%-20s | #%s\n" "YouTube GV" "$yt_gv_strategy"
    printf "%-20s | #%s\n" "RKN" "$rkn_strategy"
    print_separator

    printf "\nApply? [Y/n]:"
    read_input answer

    case "$answer" in
        [Nn]|[Nn][Oo])
            print_info "Cancelled"
            ;;
        *)
            save_category_strategies "$yt_tcp_strategy" "$yt_gv_strategy" "$rkn_strategy"
            apply_category_strategies_v2 "$yt_tcp_strategy" "$yt_gv_strategy" "$rkn_strategy"
            print_success "All strategies applied!"
            print_separator

            # Auto check of all categories
            print_info "Running accessibility check..."
            print_separator
            test_category_availability "YouTube TCP" "youtube.com"
            print_separator
            local gv_domain
            gv_domain=$(generate_gv_domain)
            test_category_availability "YouTube GV" "$gv_domain"
            print_separator
            test_category_availability_rkn
            ;;
    esac
}

# ==============================================================================
# SUBMENU: AUTOTEST
# ==============================================================================

menu_autotest() {
    clear_screen
    print_header "[3] Autotest of strategies"

    if ! is_zapret2_installed; then
        print_error "lock2 is not installed"
        pause
        return
    fi

    local total_count
    total_count=$(get_strategies_count)
    if [ "$total_count" -lt 1 ]; then
        total_count="?"
    fi

    printf "Test modes:\n\n"
    printf "[1] By category Z4R (YouTube TCP/GV + RKN, ~8-10 min)\n"
    printf "[2] General test (all strategies, ~2-3 min)\n"
    printf "[3] Range (specify manually)\n"
    printf "[4] All strategies (HTTPS only, %s pieces, ~15 min)\n" "$total_count"
    printf "[5] QUIC test (UDP 443, ~5-10 min)\n"
    printf "[B] Back\n\n"

    printf "Select mode:"
    read_input test_mode

    case "$test_mode" in
        1)
            clear_screen
            print_info "Autotest by category Z4R (YouTube TCP, YouTube GV, RKN)"
            if confirm "Start testing?" "Y"; then
                auto_test_categories
            fi
            ;;
        2)
            clear_screen
            auto_test_top20
            ;;
        3)
            printf "\nStart of range:"
            read_input start_range
            printf "End of range:"
            read_input end_range

            if [ -n "$start_range" ] && [ -n "$end_range" ]; then
                clear_screen
                test_strategy_range "$start_range" "$end_range"
            else
                print_error "Invalid range"
            fi
            ;;
        4)
            clear_screen
            print_warning "It will take about 15 minutes!"
            if confirm "Continue?" "N"; then
                local total_count
                total_count=$(get_strategies_count)
                if [ "$total_count" -lt 1 ]; then
                    print_error "No strategies found"
                    pause
                    return
                fi
                test_strategy_range 1 "$total_count"
            fi
            ;;
        5)
            clear_screen
            auto_test_quic
            ;;
        [Bb])
            return
            ;;
        *)
            print_error "Wrong choice"
            ;;
    esac

    pause
}

# ==============================================================================
# SUBMENU: SERVICE MANAGEMENT
# ==============================================================================

menu_service_control() {
    clear_screen
    print_header "[4] Service management"

    if ! is_zapret2_installed; then
        print_error "lock2 is not installed"
        pause
        return
    fi

    cat <<'SUBMENU'
[1] Запустить сервис
[2] Остановить сервис
[3] Перезапустить сервис
[4] Статус сервиса
[B] Назад

SUBMENU

    printf "Select action:"
    read_input action

    case "$action" in
        1)
            print_info "Starting the service..."
            "$INIT_SCRIPT" start
            ;;
        2)
            print_info "Stopping the service..."
            "$INIT_SCRIPT" stop
            ;;
        3)
            print_info "Restarting the service..."
            "$INIT_SCRIPT" restart
            ;;
        4)
            "$INIT_SCRIPT" status
            ;;
        [Bb])
            return
            ;;
        *)
            print_error "Wrong choice"
            ;;
    esac

    pause
}

# ==============================================================================
# SUBMENU: VIEW STRATEGY
# ==============================================================================

menu_view_strategy() {
    clear_screen
    print_header "[5] Current strategies"

    if ! is_zapret2_installed; then
        print_error "lock2 is not installed"
        pause
        return
    fi

    # Check for the presence of a file with categories
    if [ -f "$CATEGORY_STRATEGIES_CONF" ]; then
        print_info "Strategies by category:"
        print_separator

        # Read and show strategies for each category
        while IFS=':' read -r category strategy score; do
            [ -z "$category" ] && continue

            local params
            local type
            params=$(get_strategy "$strategy" 2>/dev/null)
            type=$(get_strategy_type "$strategy" 2>/dev/null)

            printf "\n[%s]\n" "$(echo "$category" | tr '[:lower:]' '[:upper:]')"
            printf "Strategy: #%s (score: %s/5)\n" "$strategy" "$score"
            printf "Type: %s\n" "$type"
        done < "$CATEGORY_STRATEGIES_CONF"

        print_separator
    else
        # Old regime - one strategy
        local current
        current=$(get_current_strategy)

        if [ "$current" = "not specified" ] || [ -z "$current" ]; then
            print_warning "No strategy selected"
            print_info "The default strategy from the init script is used"
        else
            print_info "Current strategy: #$current"
            print_separator

            local params
            params=$(get_strategy "$current")
            local type
            type=$(get_strategy_type "$current")

            printf "Type: %s\n\n" "$type"
            printf "Parameter:\n%s\n" "$params"
            print_separator
        fi
    fi

    # Show service status
    printf "\nService status: %s\n" "$(get_service_status)"

    if is_zapret2_running; then
        printf "\nProcesses nfqws2:\n"
        pgrep -af "nfqws2" 2>/dev/null || print_info "No processes found"
    fi

    pause
}

# ==============================================================================
# SUBMENU: LIST UPDATE
# ==============================================================================

menu_update_lists() {
    clear_screen
    print_header "[6] Updating domain lists"

    if ! is_zapret2_installed; then
        print_error "lock2 is not installed"
        pause
        return
    fi

    # Show current listings
    show_domain_lists_stats

    printf "\nUpdate lists from zapret4rocket? [Y/n]:"
    read_input answer

    case "$answer" in
        [Nn]|[Nn][Oo])
            print_info "Cancelled"
            ;;
        *)
            update_domain_lists
            ;;
    esac

    pause
}

# ==============================================================================
# SUBMENU: DISCORD
# ==============================================================================

menu_discord() {
    clear_screen
    print_header "[7] Setting up Discord (voice/video)"

    if ! is_zapret2_installed; then
        print_error "lock2 is not installed"
        pause
        return
    fi

    # Call a function from lib/discord.sh
    configure_discord_voice

    pause
}

# ==============================================================================
# SUBMENU: BACKUP/RESTORE
# ==============================================================================

menu_backup_restore() {
    clear_screen
    print_header "[8] Backup/Restore"

    if ! is_zapret2_installed; then
        print_error "lock2 is not installed"
        pause
        return
    fi

    cat <<'SUBMENU'
[1] Создать резервную копию
[2] Восстановить из резервной копии
[3] Сбросить конфигурацию
[B] Назад

SUBMENU

    printf "Select action:"
    read_input action

    case "$action" in
        1)
            backup_config
            ;;
        2)
            restore_config
            ;;
        3)
            reset_config
            ;;
        [Bb])
            return
            ;;
        *)
            print_error "Wrong choice"
            ;;
    esac

    pause
}

# ==============================================================================
# SUBMENU: DELETE
# ==============================================================================

menu_uninstall() {
    clear_screen
    print_header "[9] Removing zapret2"

    if ! is_zapret2_installed; then
        print_info "lock2 is not installed"
        pause
        return
    fi

    uninstall_zapret2

    pause
}

# ==============================================================================
# SUBMENU: ALL TCP-443 MODE (WITHOUT HOSTLISTS)
# ==============================================================================

menu_all_tcp443() {
    clear_screen
    print_header "ALL TCP-443 mode (no hostlists)"

    local conf_file="${CONFIG_DIR}/all_tcp443.conf"

    # Check the existence of the config
    if [ ! -f "$conf_file" ]; then
        print_error "Configuration file not found: $conf_file"
        print_info "Run the installation first"
        pause
        return 1
    fi

    # Read current configuration
    . "$conf_file"
    local current_enabled=$ENABLED
    local current_strategy=$STRATEGY

    print_separator

    print_info "Current configuration:"
    printf "Status: %s\n" "$([ "$current_enabled" = "1" ] && echo 'Включен' || echo 'Выключен')"
    printf "Strategy: #%s\n" "$current_strategy"

    print_separator

    cat <<'SUBMENU'

ВНИМАНИЕ: Этот режим применяет стратегию ко ВСЕМУ трафику HTTPS (TCP-443)
без фильтрации по доменам из хостлистов!

Использование:
  - Для обхода блокировок ВСЕХ сайтов одной стратегией
  - Когда хостлисты не помогают
  - Для тестирования универсальных стратегий

Недостатки:
  - Может замедлить ВСЕ HTTPS соединения
  - Увеличивает нагрузку на роутер
  - Может вызвать проблемы с некоторыми сайтами

[1] Включить режим ALL TCP-443
[2] Выключить режим ALL TCP-443
[3] Изменить стратегию
[B] Назад

SUBMENU

    printf "Select option [1-3,B]:"
    read_input sub_choice

    case "$sub_choice" in
        1)
            # Enable mode
            print_info "Selecting a strategy for the ALL TCP-443... mode"
            print_separator

            # Show top strategies
            print_info "Recommended strategies for TCP-443 ALL mode:"
            printf "  #1 - multidisorder (basic)\n"
            printf "  #7  - multidisorder:pos=1\n"
            printf "  #13 - multidisorder:pos=sniext+1\n"
            printf "  #67 - fakedsplit with ip_autottl (advanced)\n"
            print_separator

            printf "Enter strategy number [1-199] or Enter for #1:"
            read_input strategy_num

            # Validation
            if [ -z "$strategy_num" ]; then
                strategy_num=1
            fi

            if ! echo "$strategy_num" | grep -qE '^[0-9]+$' || [ "$strategy_num" -lt 1 ] || [ "$strategy_num" -gt 199 ]; then
                print_error "Invalid strategy number: $strategy_num"
                pause
                return 1
            fi

            # Update config
            sed -i "s/^ENABLED=.*/ENABLED=1/" "$conf_file"
            sed -i "s/^STRATEGY=.*/STRATEGY=$strategy_num/" "$conf_file"

            print_success "TCP-443 ALL mode enabled with strategy #$strategy_num"
            print_separator

            # Restarting the service
            if is_zapret2_running; then
                print_info "Restarting the service to apply the changes..."
                "$INIT_SCRIPT" restart
                print_success "Service restarted"
            else
                print_warning "The service is not running. Run via [4] Service Management"
            fi

            pause
            ;;

        2)
            # Turn off mode
            if [ "$current_enabled" != "1" ]; then
                print_info "ALL TCP-443 mode is already disabled"
                pause
                return 0
            fi

            sed -i "s/^ENABLED=.*/ENABLED=0/" "$conf_file"
            print_success "ALL TCP-443 mode is disabled"
            print_separator

            # Restarting the service
            if is_zapret2_running; then
                print_info "Restarting the service to apply the changes..."
                "$INIT_SCRIPT" restart
                print_success "Service restarted"
            fi

            pause
            ;;

        3)
            # Change strategy
            if [ "$current_enabled" != "1" ]; then
                print_warning "ALL TCP-443 mode is disabled"
                print_info "First enable the mode via [1]"
                pause
                return 0
            fi

            printf "Current strategy: #%s\n" "$current_strategy"
            print_separator
            printf "Enter new strategy number [1-199]:"
            read_input new_strategy

            # Validation
            if ! echo "$new_strategy" | grep -qE '^[0-9]+$' || [ "$new_strategy" -lt 1 ] || [ "$new_strategy" -gt 199 ]; then
                print_error "Invalid strategy number: $new_strategy"
                pause
                return 1
            fi

            sed -i "s/^STRATEGY=.*/STRATEGY=$new_strategy/" "$conf_file"
            print_success "Strategy changed to #$new_strategy"
            print_separator

            # Restarting the service
            if is_zapret2_running; then
                print_info "Restarting the service to apply the changes..."
                "$INIT_SCRIPT" restart
                print_success "Service restarted"
            fi

            pause
            ;;

        b|B)
            return 0
            ;;

        *)
            print_error "Wrong choice: $sub_choice"
            pause
            ;;
    esac
}

# ==============================================================================
# SUBMENU: WHITELIST
# ==============================================================================

menu_whitelist() {
    clear_screen
    print_header "Whitelist - Exceptions from processing"

    local whitelist_file="${LISTS_DIR}/whitelist.txt"

    # Check file existence
    if [ ! -f "$whitelist_file" ]; then
        print_warning "Whitelist file not found: $whitelist_file"
        print_info "I'm creating a file..."

        # Create directory if it doesn't exist
        if ! mkdir -p "$LISTS_DIR" 2>/dev/null; then
            print_error "Failed to create directory: $LISTS_DIR"
            print_info "Check permissions"
            pause
            return 1
        fi

        # Create a basic whitelist
        cat > "$whitelist_file" <<'EOF'
# Whitelist - domains excluded from processing by zapret2
# Critical government services of the Russian Federation

# Public servants (ESIA)
gosuslugi.ru
esia.gosuslugi.ru
lk.gosuslugi.ru

# Tax service
nalog.gov.ru
lkfl2.nalog.ru

# Pension fund
pfr.gov.ru
es.pfr.gov.ru

# Other important government services
mos.ru
pgu.mos.ru
EOF

        if [ ! -f "$whitelist_file" ]; then
            print_error "Failed to create whitelist file"
            print_info "Check permissions"
            pause
            return 1
        fi

        print_success "Whitelist file created: $whitelist_file"
    fi

    print_separator

    cat <<'INFO'

Whitelist содержит домены, которые ИСКЛЮЧЕНЫ из обработки zapret2.
Это полезно для критичных сервисов, которые могут сломаться
при применении DPI-обхода (госуслуги, банки, и т.д.)

По умолчанию в whitelist включены:
  - gosuslugi.ru (Госуслуги, ЕСИА)
  - nalog.gov.ru (Налоговая служба)
  - pfr.gov.ru (Пенсионный фонд)
  - mos.ru (Москва)

[1] Просмотреть whitelist
[2] Редактировать whitelist (vi)
[3] Добавить домен
[4] Удалить домен
[B] Назад

INFO

    printf "Select option [1-4,B]:"
    read_input sub_choice

    case "$sub_choice" in
        1)
            # View
            clear_screen
            print_header "Current whitelist"
            print_separator
            cat "$whitelist_file"
            print_separator
            pause
            ;;

        2)
            # Editing in vi
            print_info "Opening whitelist in the editor..."
            vi "$whitelist_file"

            # Restarting the service
            if is_zapret2_running; then
                print_info "Restarting the service to apply the changes..."
                "$INIT_SCRIPT" restart
                print_success "Service restarted"
            fi
            pause
            ;;

        3)
            # Add a domain
            printf "Enter the domain to add (for example: example.com):"
            read_input new_domain

            # Simple domain validation
            if ! echo "$new_domain" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
                print_error "Invalid domain format: $new_domain"
                pause
                return 1
            fi

            # Check for duplicates
            if grep -qx "$new_domain" "$whitelist_file"; then
                print_warning "Domain $new_domain is already in the whitelist"
                pause
                return 0
            fi

            # Add a domain
            echo "$new_domain" >> "$whitelist_file"
            print_success "Domain $new_domain added to whitelist"
            print_separator

            # Restarting the service
            if is_zapret2_running; then
                print_info "Restarting the service to apply the changes..."
                "$INIT_SCRIPT" restart
                print_success "Service restarted"
            fi
            pause
            ;;

        4)
            # Delete domain
            printf "Enter the domain to delete:"
            read_input del_domain

            # Check availability
            if ! grep -qx "$del_domain" "$whitelist_file"; then
                print_error "Domain $del_domain not found in whitelist"
                pause
                return 1
            fi

            # Delete domain
            sed -i "/^${del_domain}$/d" "$whitelist_file"
            print_success "Domain $del_domain removed from whitelist"
            print_separator

            # Restarting the service
            if is_zapret2_running; then
                print_info "Restarting the service to apply the changes..."
                "$INIT_SCRIPT" restart
                print_success "Service restarted"
            fi
            pause
            ;;

        b|B)
            return 0
            ;;

        *)
            print_error "Wrong choice: $sub_choice"
            pause
            ;;
    esac
}

# ==============================================================================
# SUBMENU: QUIC CONTROL
# ==============================================================================

menu_quic_settings() {
    clear_screen
    print_header "QUIC Settings"

    # Current status
    local quic_yt_enabled="On"
    local quic_rkn_status
    if is_rutracker_quic_enabled; then
        quic_rkn_status="On"
    else
        quic_rkn_status="Off"
    fi

    printf "\nCurrent settings:\n"
    printf "YouTube QUIC: %s (strategy #%s)\n" "$quic_yt_enabled" "$(get_current_quic_strategy)"
    printf "  RuTracker QUIC:  %s" "$quic_rkn_status"
    if is_rutracker_quic_enabled; then
        printf "(strategy #%s)\n" "$(get_rutracker_quic_strategy)"
    else
        printf "\n"
    fi

    cat <<'MENU'

[1] YouTube QUIC - выбрать стратегию
[2] RuTracker QUIC - включить/выключить
[3] RuTracker QUIC - выбрать стратегию
[B] Назад

MENU

    printf "Select an option:"
    read_input choice

    case "$choice" in
        1)
            # YouTube QUIC - choosing a strategy
            menu_select_quic_strategy_youtube
            ;;
        2)
            # RuTracker QUIC - enable/disable
            menu_toggle_rutracker_quic
            ;;
        3)
            # RuTracker QUIC - choosing a strategy
            if is_rutracker_quic_enabled; then
                menu_select_quic_strategy_rutracker
            else
                print_warning "RuTracker QUIC is disabled"
                print_info "First enable RuTracker QUIC (option [2])"
                pause
            fi
            ;;
        b|B)
            return 0
            ;;
        *)
            print_error "Wrong choice: $choice"
            pause
            ;;
    esac
}

# Enable/disable QUIC for RuTracker
menu_toggle_rutracker_quic() {
    clear_screen
    print_header "RuTracker QUIC - enable/disable"

    local current_status
    if is_rutracker_quic_enabled; then
        current_status="turned on"
    else
        current_status="off"
    fi

    printf "\nTecular status: %s\n" "$current_status"
    printf "\nWhat to do?\n"
    printf "[1] Enable RuTracker QUIC\n"
    printf "[2] Turn off RuTracker QUIC\n"
    printf "[B] Back\n\n"

    printf "Your choice:"
    read_input choice

    case "$choice" in
        1)
            # Turn on
            set_rutracker_quic_enabled 1
            print_success "RuTracker QUIC enabled"

            # Get current strategies
            local config_file="${CONFIG_DIR}/category_strategies.conf"
            local current_yt_tcp=1
            local current_yt_gv=1
            local current_rkn=1

            if [ -f "$config_file" ]; then
                current_yt_tcp=$(grep "^youtube_tcp:" "$config_file" 2>/dev/null | cut -d':' -f2)
                current_yt_gv=$(grep "^youtube_gv:" "$config_file" 2>/dev/null | cut -d':' -f2)
                current_rkn=$(grep "^rkn:" "$config_file" 2>/dev/null | cut -d':' -f2)
                [ -z "$current_yt_tcp" ] && current_yt_tcp=1
                [ -z "$current_yt_gv" ] && current_yt_gv=1
                [ -z "$current_rkn" ] && current_rkn=1
            fi

            # Apply changes
            apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
            print_success "Changes applied"
            pause
            ;;
        2)
            # Turn off
            set_rutracker_quic_enabled 0
            print_success "RuTracker QUIC is disabled"

            # Get current strategies
            local config_file="${CONFIG_DIR}/category_strategies.conf"
            local current_yt_tcp=1
            local current_yt_gv=1
            local current_rkn=1

            if [ -f "$config_file" ]; then
                current_yt_tcp=$(grep "^youtube_tcp:" "$config_file" 2>/dev/null | cut -d':' -f2)
                current_yt_gv=$(grep "^youtube_gv:" "$config_file" 2>/dev/null | cut -d':' -f2)
                current_rkn=$(grep "^rkn:" "$config_file" 2>/dev/null | cut -d':' -f2)
                [ -z "$current_yt_tcp" ] && current_yt_tcp=1
                [ -z "$current_yt_gv" ] && current_yt_gv=1
                [ -z "$current_rkn" ] && current_rkn=1
            fi

            # Apply changes
            apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
            print_success "Changes applied"
            pause
            ;;
        b|B)
            return 0
            ;;
        *)
            print_error "Wrong choice: $choice"
            pause
            ;;
    esac
}

# Choosing a QUIC strategy for YouTube
menu_select_quic_strategy_youtube() {
    clear_screen
    print_header "YouTube QUIC - choosing a strategy"

    local total_quic
    total_quic=$(get_quic_strategies_count)

    if [ "$total_quic" -eq 0 ]; then
        print_error "QUIC strategies not found"
        pause
        return 1
    fi

    local current_quic
    current_quic=$(get_current_quic_strategy)

    printf "\nTotal QUIC strategies: %s\n" "$total_quic"
    printf "Current strategy: #%s\n\n" "$current_quic"

    printf "Enter strategy number [1-%s] or Enter to cancel:" "$total_quic"
    read_input new_strategy

    if [ -z "$new_strategy" ]; then
        print_info "Cancelled"
        pause
        return 0
    fi

    if ! echo "$new_strategy" | grep -qE '^[0-9]+$'; then
        print_error "Invalid format"
        pause
        return 1
    fi

    if [ "$new_strategy" -lt 1 ] || [ "$new_strategy" -gt "$total_quic" ]; then
        print_error "Number out of range"
        pause
        return 1
    fi

    if ! quic_strategy_exists "$new_strategy"; then
        print_error "QUIC strategy #$new_strategy not found"
        pause
        return 1
    fi

    set_current_quic_strategy "$new_strategy"

    # Get current strategies
    local config_file="${CONFIG_DIR}/category_strategies.conf"
    local current_yt_tcp=1
    local current_yt_gv=1
    local current_rkn=1

    if [ -f "$config_file" ]; then
        current_yt_tcp=$(grep "^youtube_tcp:" "$config_file" 2>/dev/null | cut -d':' -f2)
        current_yt_gv=$(grep "^youtube_gv:" "$config_file" 2>/dev/null | cut -d':' -f2)
        current_rkn=$(grep "^rkn:" "$config_file" 2>/dev/null | cut -d':' -f2)
        [ -z "$current_yt_tcp" ] && current_yt_tcp=1
        [ -z "$current_yt_gv" ] && current_yt_gv=1
        [ -z "$current_rkn" ] && current_rkn=1
    fi

    apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
    print_success "YouTube QUIC strategy #$new_strategy applied"
    pause
}

# Choosing a QUIC strategy for RuTracker
menu_select_quic_strategy_rutracker() {
    clear_screen
    print_header "RuTracker QUIC - choosing a strategy"

    local total_quic
    total_quic=$(get_quic_strategies_count)

    if [ "$total_quic" -eq 0 ]; then
        print_error "QUIC strategies not found"
        pause
        return 1
    fi

    local current_quic
    current_quic=$(get_rutracker_quic_strategy)

    printf "\nTotal QUIC strategies: %s\n" "$total_quic"
    printf "Current strategy: #%s\n\n" "$current_quic"

    printf "Enter strategy number [1-%s] or Enter to cancel:" "$total_quic"
    read_input new_strategy

    if [ -z "$new_strategy" ]; then
        print_info "Cancelled"
        pause
        return 0
    fi

    if ! echo "$new_strategy" | grep -qE '^[0-9]+$'; then
        print_error "Invalid format"
        pause
        return 1
    fi

    if [ "$new_strategy" -lt 1 ] || [ "$new_strategy" -gt "$total_quic" ]; then
        print_error "Number out of range"
        pause
        return 1
    fi

    if ! quic_strategy_exists "$new_strategy"; then
        print_error "QUIC strategy #$new_strategy not found"
        pause
        return 1
    fi

    set_rutracker_quic_strategy "$new_strategy"

    # Get current strategies
    local config_file="${CONFIG_DIR}/category_strategies.conf"
    local current_yt_tcp=1
    local current_yt_gv=1
    local current_rkn=1

    if [ -f "$config_file" ]; then
        current_yt_tcp=$(grep "^youtube_tcp:" "$config_file" 2>/dev/null | cut -d':' -f2)
        current_yt_gv=$(grep "^youtube_gv:" "$config_file" 2>/dev/null | cut -d':' -f2)
        current_rkn=$(grep "^rkn:" "$config_file" 2>/dev/null | cut -d':' -f2)
        [ -z "$current_yt_tcp" ] && current_yt_tcp=1
        [ -z "$current_yt_gv" ] && current_yt_gv=1
        [ -z "$current_rkn" ] && current_rkn=1
    fi

    apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
    print_success "RuTracker QUIC strategy #$new_strategy applied"
    pause
}


# ==============================================================================
# EXPORTING FUNCTIONS
# ==============================================================================

# All functions are available after the source of this file
