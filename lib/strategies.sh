#!/bin/sh
# lib/strategies.sh - Managing zapret2 strategies
# Parsing, testing, applying strategies from strats_new2.txt
# QUIC/UDP strategies are taken from quic_strats.ini

# ==============================================================================
# CONSTANTS FOR STRATEGIES
# ==============================================================================

TOP20_STRATEGIES="1 7 13 19 25 31 37 43 49 55 61 67 73 79 85 91 97 103 109 115"

# Domains for testing strategies
TEST_DOMAINS="
http://rutracker.org
https://rutracker.org
https://www.youtube.com
https://discord.com
https://googlevideo.com
"

# ==============================================================================
# WORKING WITH STRATEGY FILES BY CATEGORIES (CONFIG-DRIVEN ARCHITECTURE)
# ==============================================================================

# Save strategy to category file
# $1 - category (YT, YT_GV, RKN, RUTRACKER)
# $2 - protocol (TCP or UDP)
# $3 - strategy parameters
save_strategy_to_category() {
    local category=$1
    local protocol=$2
    local params=$3

    if [ -z "$category" ] || [ -z "$protocol" ] || [ -z "$params" ]; then
        print_error "save_strategy_to_category: incorrect parameters"
        return 1
    fi

    local strategy_file="${ZAPRET2_DIR:-/opt/zapret2}/extra_strats/${protocol}/${category}/Strategy.txt"

    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$strategy_file")" || {
        print_error "Failed to create directory for strategy $category/$protocol"
        return 1
    }

    # Save settings
    echo "$params" > "$strategy_file" || {
        print_error "Failed to save strategy in $strategy_file"
        return 1
    }

    return 0
}

# Create default strategy files during installation
# Called from step_create_config_and_init()
create_default_strategy_files() {
    local extra_strats_dir="${ZAPRET2_DIR:-/opt/zapret2}/extra_strats"

    print_info "Creating default strategy files..."

    # Default TCP strategy
    local default_tcp="--filter-tcp=443,2053,2083,2087,2096,8443 --filter-l7=tls --payload=tls_client_hello --out-range=-n10 --lua-desync=fake:blob=fake_default_tls:repeats=4"

    # Default UDP strategy (QUIC)
    local default_udp="--filter-udp=443 --filter-l7=quic --payload=quic_initial --out-range=-n10 --lua-desync=fake:blob=fake_default_quic:repeats=3"

    # Create directories and files
    mkdir -p "$extra_strats_dir/TCP/YT"
    mkdir -p "$extra_strats_dir/TCP/YT_GV"
    mkdir -p "$extra_strats_dir/TCP/RKN"
    mkdir -p "$extra_strats_dir/UDP/YT"
    mkdir -p "$extra_strats_dir/UDP/RUTRACKER"

    # Save default strategies
    echo "$default_tcp" > "$extra_strats_dir/TCP/YT/Strategy.txt"
    echo "$default_tcp" > "$extra_strats_dir/TCP/YT_GV/Strategy.txt"
    echo "$default_tcp" > "$extra_strats_dir/TCP/RKN/Strategy.txt"
    echo "$default_udp" > "$extra_strats_dir/UDP/YT/Strategy.txt"
    echo "$default_udp" > "$extra_strats_dir/UDP/RUTRACKER/Strategy.txt"

    print_success "Default strategy files have been created"
    return 0
}

# ==============================================================================
# PARSING STRATS.TXT → STRATEGIES.CONF
# ==============================================================================

# Generation of strategies.conf from strats_new2.txt
# Формат входа: curl_test_http[s] ipv4 rutracker.org : nfqws2 <параметры>
# Output format: [NUMBER]|[TYPE]|[PARAMETERS]
generate_strategies_conf() {
    local input_file=$1
    local output_file=$2

    if [ ! -f "$input_file" ]; then
        print_error "File not found: $input_file"
        return 1
    fi

    print_info "Parsing $input_file..."

    # Create title
    cat > "$output_file" <<'EOF'
# Zapret2 Strategies Database
# Generated from blockcheck2 output
# Format: [NUMBER]|[TYPE]|[PARAMETERS]
EOF

    local num=1
    local https_count=0

    # Skip first line (header)
    # IMPORTANT: the delimiter is " : " (space-colon-space), and NOT ":", because parameters contain colons!
    tail -n +2 "$input_file" | while read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue

        # Split by " : " using awk
        local test_cmd
        test_cmd=$(echo "$line" | awk -F ' : ' '{print $1}')
        local nfqws_params
        nfqws_params=$(echo "$line" | awk -F ' : ' '{print $2}')

        local type="https"
        https_count=$((https_count + 1))

        # Extract nfqws2 parameters (remove "nfqws2" at the beginning)
        local params
        params=$(echo "$nfqws_params" | sed 's/^ *nfqws2 *//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

        # Skip if parameters are empty
        [ -z "$params" ] && continue

        # Write to strategies.conf
        echo "${num}|${type}|${params}" >> "$output_file"

        num=$((num + 1))
    done

    # Count
    local total_count
    total_count=$(grep -c '^[0-9]' "$output_file" 2>/dev/null || echo "0")

    print_success "Strategies generated: $total_count"
    print_info "HTTPS стратегии: ~$https_count"

    return 0
}

# ==============================================================================
# WORKING WITH STRATEGIES
# ==============================================================================

# Get strategy by number
get_strategy() {
    local num=$1
    local conf="${STRATEGIES_CONF:-${CONFIG_DIR}/strategies.conf}"

    if [ ! -f "$conf" ]; then
        print_error "Strategy file not found: $conf"
        return 1
    fi

    grep "^${num}|" "$conf" | cut -d'|' -f3
}

# Получить тип стратегии (http/https)
get_strategy_type() {
    local num=$1
    local conf="${STRATEGIES_CONF:-${CONFIG_DIR}/strategies.conf}"

    if [ ! -f "$conf" ]; then
        return 1
    fi

    grep "^${num}|" "$conf" | cut -d'|' -f2
}

# Get QUIC strategy by number
get_quic_strategy() {
    local num=$1
    local conf="${QUIC_STRATEGIES_CONF:-${CONFIG_DIR}/quic_strategies.conf}"

    if [ ! -f "$conf" ]; then
        print_error "QUIC strategies file not found: $conf"
        return 1
    fi

    grep "^${num}|" "$conf" | cut -d'|' -f3
}

# Get the QUIC strategy name
get_quic_strategy_name() {
    local num=$1
    local conf="${QUIC_STRATEGIES_CONF:-${CONFIG_DIR}/quic_strategies.conf}"

    if [ ! -f "$conf" ]; then
        return 1
    fi

    grep "^${num}|" "$conf" | cut -d'|' -f2
}

# Get a description of the QUIC strategy
get_quic_strategy_desc() {
    local num=$1
    local conf="${QUIC_STRATEGIES_CONF:-${CONFIG_DIR}/quic_strategies.conf}"

    if [ ! -f "$conf" ]; then
        return 1
    fi

    grep "^${num}|" "$conf" | cut -d'|' -f4
}

# Get the total number of QUIC strategies
get_quic_strategies_count() {
    local conf="${QUIC_STRATEGIES_CONF:-${CONFIG_DIR}/quic_strategies.conf}"

    if [ ! -f "$conf" ]; then
        echo "0"
        return
    fi

    grep -c '^[0-9]' "$conf" 2>/dev/null || echo "0"
}

# Get a list of all QUIC strategies
get_all_quic_strategies_list() {
    local conf="${QUIC_STRATEGIES_CONF:-${CONFIG_DIR}/quic_strategies.conf}"

    if [ ! -f "$conf" ]; then
        return 1
    fi

    grep -o '^[0-9]\+' "$conf" | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

# Check the existence of a QUIC strategy
quic_strategy_exists() {
    local num=$1
    local conf="${QUIC_STRATEGIES_CONF:-${CONFIG_DIR}/quic_strategies.conf}"

    [ -f "$conf" ] && grep -q "^${num}|" "$conf"
}

# Get current QUIC strategy
get_current_quic_strategy() {
    local conf="${QUIC_STRATEGY_FILE:-${CONFIG_DIR}/quic_strategy.conf}"
    if [ -f "$conf" ]; then
        . "$conf"
        [ -n "$QUIC_STRATEGY" ] && echo "$QUIC_STRATEGY" && return 0
    fi
    echo "1"
}

# Get the current QUIC strategy for RuTracker
get_rutracker_quic_strategy() {
    local conf="${RUTRACKER_QUIC_STRATEGY_FILE:-${CONFIG_DIR}/rutracker_quic_strategy.conf}"
    if [ -f "$conf" ]; then
        . "$conf"
        [ -n "$RUTRACKER_QUIC_STRATEGY" ] && echo "$RUTRACKER_QUIC_STRATEGY" && return 0
    fi
    echo "43"
}

# Check if QUIC is enabled for RuTracker
is_rutracker_quic_enabled() {
    local conf="${CONFIG_DIR}/rutracker_quic_enabled.conf"
    if [ -f "$conf" ]; then
        . "$conf"
        [ "$RUTRACKER_QUIC_ENABLED" = "1" ] && return 0
    fi
    return 1
}

# Enable/disable QUIC for RuTracker
set_rutracker_quic_enabled() {
    local enabled=$1  # 1 or 0
    local conf="${CONFIG_DIR}/rutracker_quic_enabled.conf"
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    echo "RUTRACKER_QUIC_ENABLED=${enabled}" > "$conf"
}


# Save current QUIC strategy
set_current_quic_strategy() {
    local num=$1
    local conf="${QUIC_STRATEGY_FILE:-${CONFIG_DIR}/quic_strategy.conf}"
    echo "QUIC_STRATEGY=$num" > "$conf"
}

# Save the current QUIC strategy for RuTracker
set_rutracker_quic_strategy() {
    local num=$1
    local conf="${RUTRACKER_QUIC_STRATEGY_FILE:-${CONFIG_DIR}/rutracker_quic_strategy.conf}"
    echo "RUTRACKER_QUIC_STRATEGY=$num" > "$conf"
}


# Build QUIC profile parameters from strategy
build_quic_profile_params() {
    local params=$1
    echo "--filter-udp=443 --filter-l7=quic ${params}"
}

# Get parameters of the current QUIC strategy
get_current_quic_profile_params() {
    local quic_strategy
    quic_strategy=$(get_current_quic_strategy)
    local quic_params
    quic_params=$(get_quic_strategy "$quic_strategy" 2>/dev/null)

    if [ -z "$quic_params" ]; then
        quic_params="--payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6"
    fi

    build_quic_profile_params "$quic_params"
}

# Get QUIC profile parameters for RuTracker
get_rutracker_quic_profile_params() {
    local quic_strategy
    quic_strategy=$(get_rutracker_quic_strategy)
    local quic_params
    quic_params=$(get_quic_strategy "$quic_strategy" 2>/dev/null)

    if [ -z "$quic_params" ]; then
        quic_params="--payload=quic_initial --lua-desync=fake:blob=fake_default_quic:repeats=6"
    fi

    build_quic_profile_params "$quic_params"
}


# Check HTTP/3 (QUIC) support in curl
curl_supports_http3() {
    curl --version 2>/dev/null | grep -qi "HTTP3"
}

# Checking QUIC availability
test_strategy_quic() {
    local domain=$1
    local timeout=${2:-5}
    local url=$domain

    if ! curl_supports_http3; then
        print_warning "curl does not support HTTP/3, QUIC test is not available"
        return 2
    fi

    case "$url" in
        http://*|https://*)
            ;;
        *)
            url="https://${url}"
            ;;
    esac

    curl --http3 -I -s -m "$timeout" "$url" >/dev/null 2>&1
}

# Get the total number of strategies
get_strategies_count() {
    local conf="${STRATEGIES_CONF:-${CONFIG_DIR}/strategies.conf}"

    if [ ! -f "$conf" ]; then
        echo "0"
        return
    fi

    grep -c '^[0-9]' "$conf" 2>/dev/null || echo "0"
}

# Get a list of all strategies from strategies.conf
get_all_strategies_list() {
    local conf="${STRATEGIES_CONF:-${CONFIG_DIR}/strategies.conf}"

    if [ ! -f "$conf" ]; then
        return 1
    fi

    grep -o '^[0-9]\+' "$conf" | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

# Check the existence of a strategy
strategy_exists() {
    local num=$1
    local conf="${STRATEGIES_CONF:-${CONFIG_DIR}/strategies.conf}"

    [ -f "$conf" ] && grep -q "^${num}|" "$conf"
}

# List of strategies by type
list_strategies_by_type() {
    local type=$1
    local conf="${STRATEGIES_CONF:-${CONFIG_DIR}/strategies.conf}"

    if [ ! -f "$conf" ]; then
        return 1
    fi

    grep "|${type}|" "$conf"
}

# Checking the presence of parameters in a strategy
params_has_filter_tcp() {
    case " $1 " in
        *" --filter-tcp="*) return 0 ;;
        *) return 1 ;;
    esac
}

params_has_filter_l7() {
    case " $1 " in
        *" --filter-l7="*) return 0 ;;
        *) return 1 ;;
    esac
}

params_has_payload() {
    case " $1 " in
        *" --payload="*) return 0 ;;
        *) return 1 ;;
    esac
}

build_tls_profile_params() {
    local params=$1
    local prefix=""
    local payload=""

    if ! params_has_filter_tcp "$params"; then
        prefix="--filter-tcp=443,2053,2083,2087,2096,8443"
    fi
    if ! params_has_filter_l7 "$params"; then
        prefix="${prefix} --filter-l7=tls"
    fi
    if ! params_has_payload "$params"; then
        payload="--payload=tls_client_hello"
    fi

    printf "%s %s %s" "$prefix" "$payload" "$params"
}

# ==============================================================================
# GENERATION OF MULTI-PROFILE CONFIGURATION
# ==============================================================================

# Generation of a multi-profile (TCP + UDP) from basic parameters
generate_multiprofile() {
    local base_params=$1
    local type=$2

    # Generating variables for init script (applies to all categories)
    local tcp_params

    if [ "$type" = "http" ]; then
        tcp_params=$(build_http_profile_params "$base_params")
    else
        tcp_params=$(build_tls_profile_params "$base_params")
    fi

    local quic_params
    quic_params=$(get_current_quic_profile_params)

    local discord_udp
    discord_udp=$(get_init_udp_params "DISCORD" "${INIT_SCRIPT:-/opt/etc/init.d/S99zapret2}")
    if [ -z "$discord_udp" ]; then
        discord_udp="--filter-udp=50000-50099,1400,3478-3481,5349 --filter-l7=discord,stun --payload=stun,discord_ip_discovery --out-range=-n10 --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2"
    fi

    # Generate variables for all categories (YouTube TCP, GV, RKN)
    cat <<PROFILE
# YouTube TCP Strategy (YouTube Interface)
# YOUTUBE_TCP_MARKER_START
YOUTUBE_TCP_TCP="$tcp_params"
YOUTUBE_TCP_UDP=""
# YOUTUBE_TCP_MARKER_END

# YouTube GV Strategy (Google Video CDN)
# YOUTUBE_GV_MARKER_START
YOUTUBE_GV_TCP="$tcp_params"
YOUTUBE_GV_UDP=""
# YOUTUBE_GV_MARKER_END

# RKN strategy (blocked sites)
# RKN_MARKER_START
RKN_TCP="$tcp_params"
RKN_UDP=""
# RKN_MARKER_END

# Discord strategy (messages and voice)
# DISCORD_MARKER_START
DISCORD_TCP="$tcp_params"
DISCORD_UDP="$discord_udp"
# DISCORD_MARKER_END

# Custom strategy (custom domains)
# CUSTOM_MARKER_START
CUSTOM_TCP="$tcp_params"
CUSTOM_UDP=""
# CUSTOM_MARKER_END

# QUIC strategy (YouTube UDP 443)
# QUIC_MARKER_START
QUIC_TCP=""
QUIC_UDP="$quic_params"
# QUIC_MARKER_END

# QUIC strategy (RuTracker UDP 443)
# QUIC_RKN_MARKER_START
QUIC_RKN_TCP=""
QUIC_RKN_UDP="$quic_params"
# QUIC_RKN_MARKER_END
PROFILE
}

# ==============================================================================
# APPLYING STRATEGIES TO AN INIT SCRIPT
# ==============================================================================

# Apply strategy (config-driven architecture)
# Saves the strategy to category files and updates the config file
apply_strategy() {
    local strategy_num=$1
    local zapret_config="${ZAPRET2_DIR:-/opt/zapret2}/config"
    # Use Z2K_INIT_SCRIPT which is not overwritten by zapret2 modules
    local init_script="${Z2K_INIT_SCRIPT:-/opt/etc/init.d/S99zapret2}"

    # Check the existence of a strategy
    if ! strategy_exists "$strategy_num"; then
        print_error "Strategy #$strategy_num not found"
        return 1
    fi

    # Get strategy parameters
    local params
    params=$(get_strategy "$strategy_num")

    if [ -z "$params" ]; then
        print_error "Failed to get strategy parameters #$strategy_num"
        return 1
    fi

    # Get strategy type
    local type
    type=$(get_strategy_type "$strategy_num")

    print_info "Applying strategy #$strategy_num (type: $type)..."

    # Build full TCP parameters
    local tcp_params
    if [ "$type" = "http" ]; then
        tcp_params=$(build_http_profile_params "$params")
    else
        tcp_params=$(build_tls_profile_params "$params")
    fi

    # Get current QUIC parameters
    local udp_params
    udp_params=$(get_current_quic_profile_params)

    # Save strategy to all categories (single strategy for all)
    print_info "Saving strategy to category files..."
    save_strategy_to_category "YT" "TCP" "$tcp_params" || return 1
    save_strategy_to_category "YT_GV" "TCP" "$tcp_params" || return 1
    save_strategy_to_category "RKN" "TCP" "$tcp_params" || return 1
    save_strategy_to_category "YT" "UDP" "$udp_params" || return 1
    save_strategy_to_category "RUTRACKER" "UDP" "$udp_params" || return 1

    # Update config file (NFQWS2_OPT section)
    print_info "Updating config file..."
    . "${LIB_DIR}/config_official.sh" || {
        print_error "Failed to load config_official.sh"
        return 1
    }

    update_nfqws2_opt_in_config "$zapret_config" || {
        print_error "Failed to update config file"
        return 1
    }

    # Save current strategy number
    mkdir -p "$CONFIG_DIR"
    echo "CURRENT_STRATEGY=$strategy_num" > "$CURRENT_STRATEGY_FILE"

    print_success "Strategy #$strategy_num applied"

    # Restart service
    print_info "Restarting the service..."

    # Check that the init script exists
    if [ ! -f "$init_script" ]; then
        print_error "Init script not found: $init_script"
        return 1
    fi

    # Suppress restart output for purity (only errors are visible)
    "$init_script" restart >/dev/null 2>&1

    sleep 2

    if is_zapret2_running; then
        print_success "Service restarted"
        return 0
    else
        print_warning "The service did not start, check the logs"
        return 1
    fi
}

# ==============================================================================
# TESTING STRATEGIES
# ==============================================================================

# Test of one strategy with a score of 0-5
test_strategy_score() {
    local score=0
    local timeout=5

    if test_strategy_http "rutracker.org" "$timeout"; then
        score=$((score + 1))
    fi

    if test_strategy_tls "rutracker.org" "$timeout"; then
        score=$((score + 1))
    fi

    # YouTube test
    if test_strategy_tls "www.youtube.com" "$timeout"; then
        score=$((score + 1))
    fi

    # Discord test
    if test_strategy_tls "discord.com" "$timeout"; then
        score=$((score + 1))
    fi

    # Test googlevideo
    if test_strategy_tls "googlevideo.com" "$timeout"; then
        score=$((score + 1))
    fi

    echo "$score"
}

# The old test_strategy_score_category() function has been removed
# Use test_strategy_tls() instead

# Apply a strategy with a test and rollback if failure
apply_strategy_safe() {
    local num=$1
    local init_script="${INIT_SCRIPT:-/opt/etc/init.d/S99zapret2}"

    # Apply strategy
    if ! apply_strategy "$num"; then
        return 1
    fi

    # Wait 3 seconds
    print_info "Strategy testing..."
    sleep 3

    # Test
    local score
    score=$(test_strategy_score)

    printf "#%s Strategy Score: %s/5\n" "$num" "$score"

    if [ "$score" -lt 3 ]; then
        print_warning "The strategy doesn't work well (score: $score/5)"
        printf "Apply anyway? [y/N]:"
        read -r answer </dev/tty </dev/tty

        case "$answer" in
            [Yy]|[Yy][Ee][Ss])
                print_info "The strategy is left to the user's choice"
                return 0
                ;;
            *)
                print_info "Rollback to previous configuration..."
                restore_backup "$init_script" || {
                    print_error "Failed to roll back!"
                    return 1
                }
                "$init_script" restart >/dev/null 2>&1
                print_info "Rollback completed"
                return 1
                ;;
        esac
    fi

    print_success "Strategy #$num applied successfully (score: $score/5)"
    return 0
}

# ==============================================================================
# TESTING STRATEGIES (TLS HANDSHAKE)
# ==============================================================================

# Domain accessibility test via TLS (based on check_access from Z4R)
# Checks TLS 1.2 and TLS 1.3 after applying the strategy
test_strategy_tls() {
    local domain=$1
    local timeout=${2:-3}  # By default 3 seconds

    local tls12_success=0
    local tls13_success=0

    # CRITICAL: Add temporary rules to the OUTPUT chain for curl from the router
    iptables -t mangle -I OUTPUT -p tcp --dport 443 -j NFQUEUE --queue-num 200 --queue-bypass 2>/dev/null
    iptables -t mangle -I OUTPUT -p udp --dport 443 -j NFQUEUE --queue-num 200 --queue-bypass 2>/dev/null

    # TLS 1.2 check
    if curl --tls-max 1.2 --max-time "$timeout" -s -o /dev/null "https://${domain}" 2>/dev/null; then
        tls12_success=1
    fi

    # TLS 1.3 check
    if curl --tlsv1.3 --max-time "$timeout" -s -o /dev/null "https://${domain}" 2>/dev/null; then
        tls13_success=1
    fi

    # Delete temporary rules
    iptables -t mangle -D OUTPUT -p tcp --dport 443 -j NFQUEUE --queue-num 200 --queue-bypass 2>/dev/null
    iptables -t mangle -D OUTPUT -p udp --dport 443 -j NFQUEUE --queue-num 200 --queue-bypass 2>/dev/null

    # Success if at least one of the protocols works
    if [ "$tls12_success" -eq 1 ] || [ "$tls13_success" -eq 1 ]; then
        return 0
    else
        return 1
    fi
}

test_strategy_http() {
    local domain=$1
    local timeout=${2:-3}

    iptables -t mangle -I OUTPUT -p tcp --dport 80 -j NFQUEUE --queue-num 200 --queue-bypass 2>/dev/null

    if curl -s -m "$timeout" -I "http://${domain}" 2>/dev/null | grep -q "HTTP"; then
        iptables -t mangle -D OUTPUT -p tcp --dport 80 -j NFQUEUE --queue-num 200 --queue-bypass 2>/dev/null
        return 0
    fi

    iptables -t mangle -D OUTPUT -p tcp --dport 80 -j NFQUEUE --queue-num 200 --queue-bypass 2>/dev/null
    return 1
}

# Generating a Google Video test domain (based on get_yt_cluster_domain from Z4R)
# Uses an external API to get a real live YouTube cluster
generate_gv_domain() {
    # Original algorithm from zapret4rocket (lib/netcheck.sh)
    # Letter maps for cipher mapping (32 characters separated by spaces)
    local letters_map_a="u z p k f a 5 0 v q l g b 6 1 w r m h c 7 2 x s n i d 8 3 y t o j e 9 4 -"
    local letters_map_b="0 1 2 3 4 5 6 7 8 9 a b c d e f g h i j k l m n o p q r s t u v w x y z -"

    # Get cluster codename (TWICE to break through irrelevant response)
    local cluster_codename
    cluster_codename=$(curl -s --max-time 2 "https://redirector.xn--ngstr-lra8j.com/report_mapping?di=no" 2>/dev/null | sed -n 's/.*=>[[:space:]]*\([^ (:)]*\).*/\1/p')
    # Second time to break through an irrelevant answer
    cluster_codename=$(curl -s --max-time 2 "https://redirector.xn--ngstr-lra8j.com/report_mapping?di=no" 2>/dev/null | sed -n 's/.*=>[[:space:]]*\([^ (:)]*\).*/\1/p')

    # If fetch fails, return known working domain
    if [ -z "$cluster_codename" ]; then
        echo "rr1---sn-5goeenes.googlevideo.com" >&2
        echo "rr1---sn-5goeenes.googlevideo.com"
        return 0
    fi

    # Cipher mapping
    local converted_name=""
    local i=0
    while [ "$i" -lt "${#cluster_codename}" ]; do
        # Get symbol
        local char
        if command -v cut >/dev/null 2>&1; then
            char=$(echo "$cluster_codename" | cut -c$((i+1)))
        else
            # Fallback for systems without cut
            char="${cluster_codename:$i:1}"
        fi

        # Find index in map_a
        local idx=1
        for a in $letters_map_a; do
            if [ "$a" = "$char" ]; then
                break
            fi
            idx=$((idx+1))
        done

        # Get the corresponding symbol from map_b
        local b
        b=$(echo "$letters_map_b" | cut -d' ' -f $idx)
        converted_name="${converted_name}${b}"

        i=$((i+1))
    done

    echo "rr1---sn-${converted_name}.googlevideo.com"
}

# Generating quic_strategies.conf from quic_strats.ini
# Input format: INI section [name], desc=..., args=...
# Output format: [NUMBER]|[NAME]|[ARGS]|[DESC]
generate_quic_strategies_conf() {
    local input_file=$1
    local output_file=$2

    if [ ! -f "$input_file" ]; then
        print_error "File not found: $input_file"
        return 1
    fi

    print_info "Parsing $input_file..."

    cat > "$output_file" <<'EOF'
# Zapret2 QUIC/UDP Strategies Database
# Generated from quic_strats.ini
# Format: [NUMBER]|[NAME]|[ARGS]|[DESC]
EOF

    local num=1
    local name=""
    local desc=""
    local args=""

    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
            \[*\])
                if [ -n "$name" ] && [ -n "$args" ]; then
                    echo "${num}|${name}|${args}|${desc}" >> "$output_file"
                    num=$((num + 1))
                fi
                name=$(echo "$line" | sed 's/^\[\(.*\)\]$/\1/')
                desc=""
                args=""
                ;;
            desc=*)
                desc=${line#desc=}
                ;;
            args=*)
                args=${line#args=}
                ;;
        esac
    done < "$input_file"

    if [ -n "$name" ] && [ -n "$args" ]; then
        echo "${num}|${name}|${args}|${desc}" >> "$output_file"
    fi

    local total_count
    total_count=$(grep -c '^[0-9]' "$output_file" 2>/dev/null || echo "0")
    print_success "Generated by QUIC strategies: $total_count"

    return 0
}

# ==============================================================================
# AUTO TEST BY CATEGORIES (Z4R METHOD)
# ==============================================================================

# YouTube TCP Autotest (youtube.com)
# Tests all strategies and returns the number of the first one that works
auto_test_youtube_tcp() {
    local strategies_list="${1:-$(get_all_strategies_list)}"
    local domain="www.youtube.com"
    local tested=0
    local total=0

    for _ in $strategies_list; do
        total=$((total + 1))
    done

    if [ "$total" -eq 0 ]; then
        print_warning "The list of strategies is empty"
        echo "1"
        return 1
    fi

    print_info "Testing YouTube TCP (youtube.com)..." >&2

    for num in $strategies_list; do
        tested=$((tested + 1))
        printf "[%d/%d] Strategy #%s..." "$tested" "$total" "$num" >&2

        # Apply strategy (suppress output for cleanliness)
        apply_strategy "$num" >/dev/null 2>&1
        local apply_result=$?
        if [ "$apply_result" -ne 0 ]; then
            printf "ERROR\n" >&2
            continue
        fi

        # Wait 2 seconds to apply
        sleep 2

        # Test via TLS
        if test_strategy_tls "$domain" 3; then
            printf "WORKING\n" >&2
            print_success "Found a working strategy for YouTube TCP: #$num" >&2
            echo "$num"
            return 0
        else
            printf "NOT WORKING\n" >&2
        fi
    done

    # If nothing works, return the default strategy
    print_warning "No working strategies found for YouTube TCP, using #1" >&2
    echo "1"
    return 1
}

# Autotest YouTube GV (googlevideo CDN)
# Tests all strategies for Google Video and returns the number of the first one that works
auto_test_youtube_gv() {
    local strategies_list="${1:-$(get_all_strategies_list)}"
    local tested=0
    local total=0

    for _ in $strategies_list; do
        total=$((total + 1))
    done

    if [ "$total" -eq 0 ]; then
        print_warning "The list of strategies is empty"
        echo "1"
        return 1
    fi

    print_info "Generating a Google Video test domain..." >&2
    local domain
    domain=$(generate_gv_domain)
    print_info "Test domain: $domain" >&2

    print_info "Testing YouTube GV (Google Video)..." >&2

    for num in $strategies_list; do
        tested=$((tested + 1))
        printf "[%d/%d] Strategy #%s..." "$tested" "$total" "$num" >&2

        # Apply strategy (suppress output for cleanliness)
        apply_strategy "$num" >/dev/null 2>&1
        local apply_result=$?
        if [ "$apply_result" -ne 0 ]; then
            printf "ERROR\n" >&2
            continue
        fi

        # Wait 2 seconds to apply
        sleep 2

        # Test via TLS
        if test_strategy_tls "$domain" 3; then
            printf "WORKING\n" >&2
            print_success "Found a working strategy for YouTube GV: #$num" >&2
            echo "$num"
            return 0
        else
            printf "NOT WORKING\n" >&2
        fi
    done

    # If nothing works, return the default strategy
    print_warning "No working strategies found for YouTube GV, using #1" >&2
    echo "1"
    return 1
}

# Autotest RKN (meduza.io, facebook.com, rutracker.org)
# Tests all strategies for RKN domains and returns the number of the first one that works
auto_test_rkn() {
    local strategies_list="${1:-$(get_all_strategies_list)}"
    local test_domains="meduza.io facebook.com rutracker.org"
    local tested=0
    local total=0

    for _ in $strategies_list; do
        total=$((total + 1))
    done

    if [ "$total" -eq 0 ]; then
        print_warning "The list of strategies is empty"
        echo "1"
        return 1
    fi

    print_info "Testing RKN (meduza.io, facebook.com, rutracker.org)..." >&2

    for num in $strategies_list; do
        tested=$((tested + 1))
        printf "[%d/%d] Strategy #%s..." "$tested" "$total" "$num" >&2

        # Apply strategy (suppress output for cleanliness)
        apply_strategy "$num" >/dev/null 2>&1
        local apply_result=$?
        if [ "$apply_result" -ne 0 ]; then
            printf "ERROR\n" >&2
            continue
        fi

        # Wait 2 seconds to apply
        sleep 2

        # Test on all three domains
        local success_count=0
        for domain in $test_domains; do
            if test_strategy_tls "$domain" 3; then
                success_count=$((success_count + 1))
            fi
        done

        # Success if it works on at least 2 of 3 domains
        if [ "$success_count" -ge 2 ]; then
            printf "WORKING (%d/3)\n" "$success_count" >&2
            print_success "Found a working strategy for RKN: #$num" >&2
            echo "$num"
            return 0
        else
            printf "NOT WORKING (%d/3)\n" "$success_count" >&2
        fi
    done

    # If nothing works, return the default strategy
    print_warning "No working strategies found for RKN, using #1" >&2
    echo "1"
    return 1
}

# ==============================================================================
# AUTO TEST OF ALL STRATEGIES
# ==============================================================================

# Automatic testing of all strategies
auto_test_top20() {
    local auto_mode=0

    # Check --auto flag
    if [ "$1" = "--auto" ]; then
        auto_mode=1
    fi

    if [ ! -f "${STRATEGIES_CONF:-${CONFIG_DIR}/strategies.conf}" ]; then
        print_error "Strategies file not found: ${STRATEGIES_CONF:-${CONFIG_DIR}/strategies.conf}"
        return 1
    fi

    print_header "Autotest of strategies"

    print_info "All available strategies will be tested"
    print_info "Score: 0-5 points (5 domains)"
    print_info "It will take about 2-3 minutes"
    printf "\n"

    if [ "$auto_mode" -eq 0 ]; then
        if ! confirm "Start testing?"; then
            print_info "Self test cancelled"
            return 0
        fi
    fi

    local strategies_list
    strategies_list=$(get_all_strategies_list)
    local best_score=0
    local best_strategy=0
    local tested=0
    local total=0

    for _ in $strategies_list; do
        total=$((total + 1))
    done

    if [ "$total" -eq 0 ]; then
        print_error "No strategies found to test"
        return 1
    fi

    for num in $strategies_list; do
        tested=$((tested + 1))

        printf "\n[%d/%d] Testing strategy #%s...\n" "$tested" "$total" "$num"

        # Apply strategy (without confirmation)
        apply_strategy "$num" >/dev/null 2>&1 || {
            print_warning "Failed to apply #$num strategy"
            continue
        }

        # Wait
        sleep 3

        # Test
        local score
        score=$(test_strategy_score)

        printf "Rating: %s/5\n" "$score"

        # Update best
        if [ "$score" -gt "$best_score" ]; then
            best_score=$score
            best_strategy=$num
            print_success "New leader: #$num ($score/5)"
        fi
    done

    printf "\n"
    print_separator
    print_success "Autotest completed"
    printf "Best strategy: #%s (score: %s/5)\n" "$best_strategy" "$best_score"
    print_separator

    if [ "$best_strategy" -eq 0 ]; then
        print_error "No working strategies found"
        print_info "Try manual menu selection"
        return 1
    fi

    # Apply immediately in automatic mode
    if [ "$auto_mode" -eq 1 ]; then
        apply_strategy "$best_strategy"
        print_success "Strategy #$best_strategy applied automatically"
        return 0
    fi

    # Ask interactively
    printf "\nApply strategy #%s? [Y/n]:" "$best_strategy"
    read -r answer </dev/tty

    case "$answer" in
        [Nn]|[Nn][Oo])
            print_info "Strategy not applied"
            print_info "Use menu for manual selection"
            return 0
            ;;
        *)
            apply_strategy "$best_strategy"
            print_success "Strategy #$best_strategy applied"
            return 0
            ;;
    esac
}

# ==============================================================================
# AUTO TEST BY CATEGORIES V2 (Z4R REFERENCE)
# ==============================================================================

# Automatic testing of all strategies for each category (Z4R method)
# Tests 3 categories: YouTube TCP, YouTube GV, RKN
# Each category gets its first working strategy
auto_test_all_categories_v2() {
    local auto_mode=0

    # Check --auto flag
    if [ "$1" = "--auto" ]; then
        auto_mode=1
    fi

    if [ ! -f "${STRATEGIES_CONF:-${CONFIG_DIR}/strategies.conf}" ]; then
        print_error "Strategies file not found: ${STRATEGIES_CONF:-${CONFIG_DIR}/strategies.conf}"
        return 1
    fi

    print_header "Automatic selection of strategies by category (Z4R method)"

    print_info "Strategies for each category will be tested:"
    print_info "  - YouTube TCP (youtube.com)"
    print_info "  - YouTube GV (googlevideo CDN)"
    print_info "  - RKN (meduza.io, facebook.com, rutracker.org)"
    print_info "It will take about 8-10 minutes"
    printf "\n"

    if [ "$auto_mode" -eq 0 ]; then
        if ! confirm "Start testing?"; then
            print_info "Self test cancelled"
            return 0
        fi
    fi

    local config_file="${CONFIG_DIR}/category_strategies.conf"
    mkdir -p "$CONFIG_DIR"

    # Test each category
    # We use temporary files instead of subshell so that utils.sh functions are available
    local result_file_tcp="/tmp/z2k_yt_tcp_result.txt"
    local result_file_gv="/tmp/z2k_yt_gv_result.txt"
    local result_file_rkn="/tmp/z2k_rkn_result.txt"

    print_separator
    print_info "Testing YouTube TCP..."
    local strategies_list
    strategies_list=$(get_all_strategies_list)
    auto_test_youtube_tcp "$strategies_list" > "$result_file_tcp"
    local yt_tcp_result=$?
    local yt_tcp_strategy=$(tail -1 "$result_file_tcp" 2>/dev/null | tr -d '\n' || echo "1")

    printf "\n"
    print_separator
    print_info "Testing YouTube GV..."
    auto_test_youtube_gv "$strategies_list" > "$result_file_gv"
    local yt_gv_result=$?
    local yt_gv_strategy=$(tail -1 "$result_file_gv" 2>/dev/null | tr -d '\n' || echo "1")

    printf "\n"
    print_separator
    print_info "Testing RKN..."
    auto_test_rkn "$strategies_list" > "$result_file_rkn"
    local rkn_result=$?
    local rkn_strategy=$(tail -1 "$result_file_rkn" 2>/dev/null | tr -d '\n' || echo "1")

    # Clear temporary files
    rm -f "$result_file_tcp" "$result_file_gv" "$result_file_rkn"

    # Show summary table
    printf "\n"
    print_separator
    print_success "Autotest completed"
    print_separator
    printf "\nResults:\n"
    printf "%-15s | %-10s | %s\n" "Category" "Strategy" "Status"
    print_separator
    printf "%-15s | #%-9s | %s\n" "YouTube TCP" "$yt_tcp_strategy" "$([ $yt_tcp_result -eq 0 ] && echo 'OK' || echo 'ДЕФОЛТ')"
    printf "%-15s | #%-9s | %s\n" "YouTube GV" "$yt_gv_strategy" "$([ $yt_gv_result -eq 0 ] && echo 'OK' || echo 'ДЕФОЛТ')"
    printf "%-15s | #%-9s | %s\n" "RKN" "$rkn_strategy" "$([ $rkn_result -eq 0 ] && echo 'OK' || echo 'DEFAULT')"
    print_separator

    # Apply strategies (in auto and interactive mode the same)
    if [ "$auto_mode" -eq 0 ]; then
        # Interactively ask for confirmation
        printf "\nApply these strategies? [Y/n]:"
        read -r answer </dev/tty

        case "$answer" in
            [Nn]|[Nn][Oo])
                print_info "No strategies applied"
                print_info "Use menu for manual selection"
                return 0
                ;;
        esac
    fi

    # Apply the selected strategies (autotest and default work the same)
    printf "\n"
    apply_category_strategies_v2 "$yt_tcp_strategy" "$yt_gv_strategy" "$rkn_strategy"
    return 0
}

# Alias ​​for backwards compatibility
auto_test_categories() {
    auto_test_all_categories_v2 "$@"
}

# ==============================================================================
# TESTING A RANGE OF STRATEGIES
# ==============================================================================

# Strategy Range Test
test_strategy_range() {
    local start=$1
    local end=$2

    if [ -z "$start" ] || [ -z "$end" ]; then
        print_error "Specify the start and end of the range"
        return 1
    fi

    if [ "$start" -gt "$end" ]; then
        print_error "The beginning of the range is greater than the end"
        return 1
    fi

    local total=$((end - start + 1))
    print_header "Test of strategies #$start-#$end"
    print_info "Total strategies for the test: $total"

    if ! confirm "Start testing?"; then
        return 0
    fi

    local best_score=0
    local best_strategy=0
    local tested=0

    local num=$start
    while [ "$num" -le "$end" ]; do
        tested=$((tested + 1))

        printf "\n[%d/%d] Testing strategy #%s...\n" "$tested" "$total" "$num"

        # Apply strategy
        apply_strategy "$num" >/dev/null 2>&1 || {
            print_warning "Failed to apply #$num strategy"
            num=$((num + 1))
            continue
        }

        sleep 3

        # Test
        local score
        score=$(test_strategy_score)

        printf "Rating: %s/5\n" "$score"

        if [ "$score" -gt "$best_score" ]; then
            best_score=$score
            best_strategy=$num
            print_success "New leader: #$num ($score/5)"
        fi

        num=$((num + 1))
    done

    printf "\n"
    print_separator
    print_success "Testing completed"
    printf "Best strategy: #%s (score: %s/5)\n" "$best_strategy" "$best_score"
    print_separator

    if [ "$best_strategy" -ne 0 ]; then
        printf "\nApply strategy #%s? [Y/n]:" "$best_strategy"
        read -r answer </dev/tty </dev/tty

        case "$answer" in
            [Nn]|[Nn][Oo])
                print_info "Strategy not applied"
                ;;
            *)
                apply_strategy "$best_strategy"
                ;;
        esac
    fi
}

# ==============================================================================
# APPLYING STRATEGIES BY CATEGORIES
# ==============================================================================

# Apply different strategies for different categories
# Parameter: string like "youtube:4:5 discord:7:4 custom:11:3"
apply_category_strategies() {
    local category_strategies=$1
    local init_script="${INIT_SCRIPT:-/opt/etc/init.d/S99zapret2}"

    if [ -z "$category_strategies" ]; then
        print_error "Not specified strategy for category"
        return 1
    fi

    if [ ! -f "$init_script" ]; then
        print_error "Init script not found: $init_script"
        return 1
    fi

    print_info "Applying strategies by category..."

    # Process each category
    for entry in $category_strategies; do
        local category=$(echo "$entry" | cut -d: -f1)
        local strategy_num=$(echo "$entry" | cut -d: -f2)
        local score=$(echo "$entry" | cut -d: -f3)

        print_info "$category -> strategy #$strategy_num (score: $score/5)"

        # Get strategy parameters
        local params
        params=$(get_strategy "$strategy_num")

        if [ -z "$params" ]; then
            print_warning "Strategy #$strategy_num not found, skip $category"
            continue
        fi

        # Convert profiles to TCP/UDP
        local tcp_params
        local udp_params

        # Determine the type of strategy
        local type
        type=$(get_strategy_type "$strategy_num")

        if [ "$type" = "https" ]; then
            tcp_params="--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello ${params}"
            udp_params=""
        else
            tcp_params="--filter-tcp=80,443 --filter-l7=http ${params}"
            udp_params=""
        fi

        # Update markers in init script
        case "$category" in
            youtube)
                update_init_section "YOUTUBE" "$tcp_params" "$udp_params" "$init_script"
                ;;
            discord)
                update_init_section "DISCORD" "$tcp_params" "$udp_params" "$init_script"
                ;;
            custom)
                update_init_section "CUSTOM" "$tcp_params" "$udp_params" "$init_script"
                ;;
        esac
    done

    print_success "Strategies applied to init script"

    # Restart service
    print_info "Restarting the service..."
    "$init_script" restart >/dev/null 2>&1

    sleep 2

    if is_zapret2_running; then
        print_success "The service has been relaunched with new strategies"
        return 0
    else
        print_warning "The service did not start, check the logs"
        return 1
    fi
}

# Update a section in the init script for a specific category
update_init_section() {
    local marker=$1
    local tcp_params=$2
    local udp_params=$3
    local init_script=$4

    local start_marker="${marker}_MARKER_START"
    local end_marker="${marker}_MARKER_END"

    # Create temporary file
    local temp_file="${init_script}.tmp"

    # Flag - are we inside the section to be replaced?
    local inside_section=0
    local found_section=0

    while IFS= read -r line; do
        if echo "$line" | grep -q "# ${start_marker}"; then
            # Beginning of the section - write down the marker and new parameters
            echo "$line"
            echo "${marker}_TCP=\"${tcp_params}\""
            echo "${marker}_UDP=\"${udp_params}\""
            inside_section=1
            found_section=1
        elif echo "$line" | grep -q "# ${end_marker}"; then
            # End of section - write down the marker and exit the mode
            echo "$line"
            inside_section=0
        elif [ "$inside_section" -eq 0 ]; then
            # Outside the section - just copy
            echo "$line"
        fi
        # Inside a section - skip old lines (except for markers)
    done < "$init_script" > "$temp_file"

    # If the section was not in the file, add it to the end
    if [ "$found_section" -eq 0 ]; then
        {
            echo ""
            echo "# ${start_marker}"
            echo "${marker}_TCP=\"${tcp_params}\""
            echo "${marker}_UDP=\"${udp_params}\""
            echo "# ${end_marker}"
        } >> "$temp_file"
    fi

    # Replace init script
    mv "$temp_file" "$init_script" || {
        print_error "Failed to update init script"
        return 1
    }

    chmod +x "$init_script"
}

# ==============================================================================
# AUTO TEST OF QUIC STRATEGIES
# ==============================================================================

auto_test_quic() {
    local auto_mode=0

    if [ "$1" = "--auto" ]; then
        auto_mode=1
    fi

    if ! curl_supports_http3; then
        print_warning "curl does not support HTTP/3, QUIC autotest is not available"
        return 1
    fi

    if [ ! -f "${QUIC_STRATEGIES_CONF:-${CONFIG_DIR}/quic_strategies.conf}" ]; then
        print_error "QUIC strategies file not found: ${QUIC_STRATEGIES_CONF:-${CONFIG_DIR}/quic_strategies.conf}"
        return 1
    fi

    print_header "Autotest QUIC strategies (UDP 443)"
    print_info "QUIC strategies will be tested"
    print_info "Domain(s): rutracker.org, static.rutracker.cc"
    print_info "Score: 0-2 points"
    printf "\n"

    if [ "$auto_mode" -eq 0 ]; then
        if ! confirm "Start testing?" "Y"; then
            print_info "Self test cancelled"
            return 0
        fi
    fi

    local strategies_list
    strategies_list=$(get_all_quic_strategies_list)
    local best_score=0
    local best_strategy=0
    local tested=0
    local total=0

    for _ in $strategies_list; do
        total=$((total + 1))
    done

    if [ "$total" -eq 0 ]; then
        print_error "No QUIC strategies found to test"
        return 1
    fi

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

    local original_quic
    original_quic=$(get_current_quic_strategy)

    for num in $strategies_list; do
        tested=$((tested + 1))

        printf "\n[%d/%d] Testing QUIC strategy #%s...\n" "$tested" "$total" "$num"

        set_current_quic_strategy "$num"
        apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn" >/dev/null 2>&1 || {
            print_warning "Failed to apply QUIC strategy #$num"
            continue
        }

        sleep 3

        local score=0
        if test_strategy_quic "youtube.com" 5; then
            score=$((score + 1))
        fi
        if test_strategy_quic "googlevideo.com" 5; then
            score=$((score + 1))
        fi

        printf "Rating: %s/2\n" "$score"

        if [ "$score" -gt "$best_score" ]; then
            best_score=$score
            best_strategy=$num
            print_success "New leader: #$num ($score/2)"
        fi
    done

    if [ -n "$original_quic" ]; then
        set_current_quic_strategy "$original_quic"
        apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn" >/dev/null 2>&1 || true
    fi

    printf "\n"
    print_separator
    print_success "QUIC autotest completed"
    printf "Best QUIC strategy: #%s (score: %s/2)\n" "$best_strategy" "$best_score"
    print_separator

    if [ "$best_strategy" -eq 0 ]; then
        print_error "No working QUIC strategies found"
        return 1
    fi

    if [ "$auto_mode" -eq 1 ]; then
        set_current_quic_strategy "$best_strategy"
        apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
        print_success "QUIC strategy #$best_strategy applied automatically"
        return 0
    fi

    printf "\nApply QUIC strategy #%s? [Y/n]:" "$best_strategy"
    read -r answer </dev/tty

    case "$answer" in
        [Nn]|[Nn][Oo])
            print_info "QUIC strategy not applied"
            return 0
            ;;
        *)
            set_current_quic_strategy "$best_strategy"
            apply_category_strategies_v2 "$current_yt_tcp" "$current_yt_gv" "$current_rkn"
            print_success "QUIC strategy applied"
            return 0
            ;;
    esac
}

# Get current TCP parameters from the init script for the section
get_init_tcp_params() {
    local marker=$1
    local init_script=$2

    if [ ! -f "$init_script" ]; then
        return 1
    fi

    local line
    line=$(grep "^${marker}_TCP=" "$init_script" 2>/dev/null | head -n 1)
    echo "$line" | sed "s/^${marker}_TCP=\"//" | sed 's/\"$//'
}

# Get current UDP parameters from the init script for a section
get_init_udp_params() {
    local marker=$1
    local init_script=$2

    if [ ! -f "$init_script" ]; then
        return 1
    fi

    local line
    line=$(grep "^${marker}_UDP=" "$init_script" 2>/dev/null | head -n 1)
    echo "$line" | sed "s/^${marker}_UDP=\"//" | sed 's/\"$//'
}

# Apply different strategies for YouTube TCP, YouTube GV, RKN (Z4R method)
# Parameters: strategy for each category
apply_category_strategies_v2() {
    local yt_tcp_strategy=$1
    local yt_gv_strategy=$2
    local rkn_strategy=$3

    local zapret_config="${ZAPRET2_DIR:-/opt/zapret2}/config"
    local init_script="${INIT_SCRIPT:-/opt/etc/init.d/S99zapret2}"

    print_info "Applying strategies by category..."
    print_info "YouTube TCP -> strategy #$yt_tcp_strategy"
    print_info "YouTube GV -> strategy #$yt_gv_strategy"
    print_info "RKN -> strategy #$rkn_strategy"

    # Get parameters for each strategy
    local yt_tcp_params
    yt_tcp_params=$(get_strategy "$yt_tcp_strategy")
    if [ -z "$yt_tcp_params" ]; then
        print_warning "Стратегия #$yt_tcp_strategy not found, default is used"
        yt_tcp_params="--lua-desync=fake:blob=fake_default_tls:repeats=6"
    fi

    local yt_gv_params
    yt_gv_params=$(get_strategy "$yt_gv_strategy")
    if [ -z "$yt_gv_params" ]; then
        print_warning "Стратегия #$yt_gv_strategy not found, default is used"
        yt_gv_params="--lua-desync=fake:blob=fake_default_tls:repeats=6"
    fi

    local rkn_params
    rkn_params=$(get_strategy "$rkn_strategy")
    if [ -z "$rkn_params" ]; then
        print_warning "Стратегия #$rkn_strategy not found, default is used"
        rkn_params="--lua-desync=fake:blob=fake_default_tls:repeats=6"
    fi

    # Generate full TCP parameters for each category
    local yt_tcp_full
    local yt_gv_full
    local rkn_full
    yt_tcp_full=$(build_tls_profile_params "$yt_tcp_params")
    yt_gv_full=$(build_tls_profile_params "$yt_gv_params")
    rkn_full=$(build_tls_profile_params "$rkn_params")

    # QUIC parameters (single profile)
    local udp_quic
    udp_quic=$(get_current_quic_profile_params)

    # Save strategies to category files (config-driven)
    print_info "Saving strategies to category files..."
    save_strategy_to_category "YT" "TCP" "$yt_tcp_full" || return 1
    save_strategy_to_category "YT_GV" "TCP" "$yt_gv_full" || return 1
    save_strategy_to_category "RKN" "TCP" "$rkn_full" || return 1
    save_strategy_to_category "YT" "UDP" "$udp_quic" || return 1
    save_strategy_to_category "RUTRACKER" "UDP" "$udp_quic" || return 1

    # Update config file (NFQWS2_OPT section)
    print_info "Updating config file..."
    . "${LIB_DIR}/config_official.sh" || {
        print_error "Failed to load config_official.sh"
        return 1
    }

    update_nfqws2_opt_in_config "$zapret_config" || {
        print_error "Failed to update config file"
        return 1
    }

    # Save selected strategies to configuration
    save_category_strategies "$yt_tcp_strategy" "$yt_gv_strategy" "$rkn_strategy"

    print_success "Strategies applied"

    # Restart service
    print_info "Restarting the service..."
    "$init_script" restart >/dev/null 2>&1

    sleep 2

    if ! is_zapret2_running; then
        # Sometimes nfqws2 starts with a delay
        sleep 2
    fi

    if is_zapret2_running; then
        print_success "The service has been relaunched with new strategies"
        return 0
    else
        print_error "The service did not start, check the logs"
        return 1
    fi
}

# Save strategies by category (YouTube TCP/GV/RKN)
save_category_strategies() {
    local yt_tcp_strategy=$1
    local yt_gv_strategy=$2
    local rkn_strategy=$3
    local config_file="${CONFIG_DIR}/category_strategies.conf"

    mkdir -p "$CONFIG_DIR" 2>/dev/null

    cat > "$config_file" <<EOF
# Category Strategies Configuration (Z4R format)
# Format: CATEGORY:STRATEGY_NUM
# Updated: $(date)

youtube_tcp:${yt_tcp_strategy}
youtube_gv:${yt_gv_strategy}
rkn:${rkn_strategy}
EOF
}

# ==============================================================================
# APPLICATION OF DEFAULT STRATEGIES
# ==============================================================================

# Apply a set of strategies by level (soft/medium/aggressive)
apply_tiered_strategies() {
    local tier="$1"
    local auto_mode=0

    if [ "$2" = "--auto" ]; then
        auto_mode=1
    fi

    local yt_tcp=""
    local yt_gv=""
    local rkn=""
    local quic=""

    case "$tier" in
        soft)
            yt_tcp=1; yt_gv=4; rkn=7; quic=1
            print_header "Application of soft strategies"
            ;;
        medium)
            yt_tcp=2; yt_gv=5; rkn=8; quic=2
            print_header "Applying Medium Strategies"
            ;;
        aggressive)
            yt_tcp=3; yt_gv=6; rkn=9; quic=3
            print_header "Using Aggressive Strategies"
            ;;
        *)
            print_error "Unknown level: $tier"
            return 1
            ;;
    esac

    print_info "The following strategies will be applied:"
    print_info "  YouTube TCP: #$yt_tcp"
    print_info "  YouTube GV:  #$yt_gv"
    print_info "  RKN:         #$rkn"
    print_info "  YouTube QUIC: #$quic"
    printf "\n"

    if [ "$auto_mode" -eq 0 ]; then
        if ! confirm "Apply the selected set of strategies?"; then
            print_info "Cancelled"
            return 0
        fi
    fi

    if ! strategy_exists "$yt_tcp"; then
        print_warning "Strategy #$yt_tcp not found, using #1"
        yt_tcp=1
    fi
    if ! strategy_exists "$yt_gv"; then
        print_warning "Strategy #$yt_gv not found, using #1"
        yt_gv=1
    fi
    if ! strategy_exists "$rkn"; then
        print_warning "Strategy #$rkn not found, using #1"
        rkn=1
    fi

    apply_category_strategies_v2 "$yt_tcp" "$yt_gv" "$rkn"

    if quic_strategy_exists "$quic"; then
        set_current_quic_strategy "$quic"
    else
        print_warning "QUIC стратегия #$quic not found, leave the current one"
    fi

    return 0
}

# Apply soft strategies (default)
apply_default_strategies() {
    apply_tiered_strategies soft "$@"
}

# Apply average strategies
apply_medium_strategies() {
    apply_tiered_strategies medium "$@"
}

# Apply aggressive strategies (compatibility)
apply_new_default_strategies() {
    apply_tiered_strategies aggressive "$@"
}

# Apply autocircular strategies (auto-search inside the profile)
apply_autocircular_strategies() {
    local auto_mode=0

    if [ "$1" = "--auto" ]; then
        auto_mode=1
    fi

    local yt_tcp=10
    local yt_gv=11
    local rkn=12
    local quic=7

    print_header "Application of autocircular strategies"
    print_info "The following strategies will be applied:"
    print_info "  YouTube TCP: #$yt_tcp"
    print_info "  YouTube GV:  #$yt_gv"
    print_info "  RKN:         #$rkn"
    print_info "  YouTube QUIC: #$quic"
    printf "\n"

    if [ "$auto_mode" -eq 0 ]; then
        if ! confirm "Apply autocircular strategy?"; then
            print_info "Cancelled"
            return 0
        fi
    fi

    if ! strategy_exists "$yt_tcp"; then
        print_warning "Strategy #$yt_tcp not found, using #1"
        yt_tcp=1
    fi
    if ! strategy_exists "$yt_gv"; then
        print_warning "Strategy #$yt_gv not found, using #1"
        yt_gv=1
    fi
    if ! strategy_exists "$rkn"; then
        print_warning "Strategy #$rkn not found, using #1"
        rkn=1
    fi

    apply_category_strategies_v2 "$yt_tcp" "$yt_gv" "$rkn"

    if quic_strategy_exists "$quic"; then
        set_current_quic_strategy "$quic"
    else
        print_warning "QUIC стратегия #$quic not found, leave the current one"
    fi

    return 0
}
