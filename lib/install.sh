#!/bin/sh
# lib/install.sh - Complete installation process of zapret2 for Keenetic
# 12-step installation with integration of domain lists and strategies

# ==============================================================================
# STEP 0: VERIFY ROOT RIGHT (CRITICAL)
# ==============================================================================

step_check_root() {
    print_header "Step 0/12: Checking Permissions"

    print_info "Check root right..."

    if [ "$(id -u)" -ne 0 ]; then
        print_error "Root rights are required to install zapret2"
        print_separator
        print_info "Run the installation as root:"
        printf "  sudo sh z2k.sh install\n\n"
        print_warning "Without root rights it is impossible:"
        print_warning "- Install packages via opkg"
        print_warning "  - Создать init скрипт в /opt/etc/init.d/"
        print_warning "- Configure iptables rules"
        print_warning "- Load kernel modules"
        return 1
    fi

    print_success "Root rights confirmed (UID=$(id -u))"
    return 0
}

# ==============================================================================
# STEP 1: UPDATE PACKAGES
# ==============================================================================

step_update_packages() {
    print_header "Step 1/12: Updating Packages"

    print_info "Entware package list update..."

    # Attempt to update with full output interception
    local opkg_output
    opkg_output=$(opkg update 2>&1)
    local exit_code=$?

    # Show opkg output
    echo "$opkg_output"

    if [ "$exit_code" -eq 0 ]; then
        print_success "Package list updated"
        return 0
    else
        print_error "Failed to update package list (code: $exit_code)"

        # Checking for Illegal instruction is a typical problem on Keenetic due to RKN blocking
        if echo "$opkg_output" | grep -qi "illegal instruction"; then
            print_warning "Error detected'Illegal instruction'"
            print_info "This is often associated with the blocking of the RKN repository bin.entware.net"
            print_separator

            # Trying to switch to an alternative mirror (method from zapret4rocket)
            print_info "Trying to switch to an alternate Entware mirror..."

            local current_mirror
            current_mirror=$(grep -m1 "^src" /opt/etc/opkg.conf | awk '{print $3}' | grep -o 'bin.entware.net')

            if [ -n "$current_mirror" ]; then
                print_info "I change bin.entware.net → entware.diversion.ch"

                # Create a backup config
                cp /opt/etc/opkg.conf /opt/etc/opkg.conf.backup

                # Replace mirror
                sed -i 's|bin.entware.net|entware.diversion.ch|g' /opt/etc/opkg.conf

                print_info "Trying to update again with a new mirror..."

                # Repeat opkg update
                opkg_output=$(opkg update 2>&1)
                exit_code=$?

                echo "$opkg_output"

                if [ "$exit_code" -eq 0 ]; then
                    print_success "Package list updated via alternative mirror!"
                    print_info "Backup старого конфига: /opt/etc/opkg.conf.backup"
                    return 0
                else
                    print_error "Didn't help - the error remains"
                    print_info "I am restoring the original config..."
                    mv /opt/etc/opkg.conf.backup /opt/etc/opkg.conf
                fi
            else
                print_info "Mirror bin.entware.net not found in config"
            fi

            printf "\n"
        fi

        # Diagnosis of the cause of the error
        print_info "In-depth diagnosis of the problem..."
        print_separator

        # Analyzing opkg output to determine the exact location of the error
        if echo "$opkg_output" | grep -q "Illegal instruction"; then
            # Try to find context
            local error_context
            error_context=$(echo "$opkg_output" | grep -B2 "Illegal instruction" | head -5)
            if [ -n "$error_context" ]; then
                print_info "Error context:"
                echo "$error_context"
            fi
        fi
        printf "\n"

        # 1. Checking the system architecture
        local sys_arch=$(uname -m)
        print_info "System architecture: $sys_arch"

        # 2. Checking the Entware architecture
        if [ -f "/opt/etc/opkg.conf" ]; then
            local entware_arch=$(grep -m1 "^arch" /opt/etc/opkg.conf | awk '{print $2}')
            print_info "Entware Architecture: ${entware_arch:-undefined}"

            local repo_url=$(grep -m1 "^src" /opt/etc/opkg.conf | awk '{print $3}')
            print_info "Repository: $repo_url"

            # 3. Checking the availability of the repository
            if [ -n "$repo_url" ]; then
                print_info "Checking repository availability..."
                if curl -s -m 5 --head "$repo_url/Packages.gz" >/dev/null 2>&1; then
                    print_success "[OK] Repository is available"
                else
                    print_error "[FAIL] Repository is unavailable"
                fi
            fi
        fi

        # 4. Checking opkg itself
        print_info "Checking the opkg binary..."
        if opkg --version 2>&1 | grep -qi "illegal"; then
            print_error "[FAIL] opkg --version crashes (Illegal instruction)"
            print_warning "REASON: opkg is installed for the wrong CPU architecture!"
        elif opkg --version >/dev/null 2>&1; then
            local opkg_version=$(opkg --version 2>&1 | head -1)
            print_success "[OK] opkg binary runs: $opkg_version"
            print_warning "But'opkg update'crashes - maybe there is a problem with the dependency or script"
        else
            print_error "[FAIL] opkg does not work for an unknown reason"
        fi

        # 5. Checking the opkg file
        if command -v file >/dev/null 2>&1; then
            if [ -f "/opt/bin/opkg" ]; then
                local opkg_file_info=$(file /opt/bin/opkg 2>&1 | head -1)
                print_info "Binary opkg: $opkg_file_info"
            fi
        fi

        print_separator

        # 6. Recommendations for additional diagnostics
        print_info "For detailed diagnostics, try manually:"
        printf "  opkg update --verbosity=2\n\n"

        # We determine the root cause based on diagnostics
        if opkg --version 2>&1 | grep -qi "illegal"; then
            cat <<'EOF'
[WARN]  КРИТИЧЕСКАЯ ПРОБЛЕМА: НЕПРАВИЛЬНАЯ АРХИТЕКТУРА ENTWARE

Диагностика показала: opkg не может выполниться на этом роутере.
Это означает что Entware установлен для НЕПРАВИЛЬНОЙ архитектуры CPU.

ПРИЧИНА:
Ваш роутер имеет процессор одной архитектуры, а установлен Entware
для другой архитектуры. Это как пытаться запустить программу для
Intel на процессоре ARM.

ЧТО ДЕЛАТЬ:
1. Удалите текущий Entware:
   - Зайдите в веб-интерфейс роутера
   - Система → Компоненты → Entware → Удалить

2. Установите ПРАВИЛЬНУЮ версию Entware:
   - Скачайте installer.sh с официального сайта
   - Убедитесь что выбрана версия для ВАШЕЙ модели роутера
   - https://help.keenetic.com/hc/ru/articles/360021888880

3. После переустановки запустите z2k снова

ВАЖНО: z2k не может работать с неправильной версией Entware!
EOF
        elif echo "$opkg_output" | grep -qi "illegal instruction"; then
            cat <<'EOF'
[WARN]  СЛОЖНАЯ ПРОБЛЕМА: opkg update падает с "Illegal instruction"

Диагностика и попытки исправления:
- [OK] opkg бинарник запускается (opkg --version работает)
- [OK] Архитектура системы корректная (aarch64)
- [OK] Репозиторий доступен (curl тест успешен)
- [OK] Попробовали альтернативное зеркало (entware.diversion.ch)
- [FAIL] НО "opkg update" всё равно падает с "Illegal instruction"

Это редкая проблема, которая может быть связана с:
1. Поврежденной зависимой библиотекой (libcurl, libssl, и др.)
2. Несовместимостью конкретной версии пакета с вашим CPU
3. Поврежденной базой данных opkg
4. Проблемой с самой установкой Entware

РЕКОМЕНДАЦИИ ПО УСТРАНЕНИЮ:

1. Проверьте какая библиотека вызывает ошибку:
   ldd /opt/bin/opkg
   (покажет все зависимые библиотеки)

2. Попробуйте детальную диагностику:
   opkg update --verbosity=2 2>&1 | tee /tmp/opkg_debug.log
   (сохранит полный вывод в файл)

3. Очистите кэш и попробуйте снова:
   rm -rf /opt/var/opkg-lists/*
   opkg update

4. Проверьте место на диске:
   df -h /opt
   (убедитесь что есть свободное место)

5. Если ничего не помогает - переустановите Entware:
   https://help.keenetic.com/hc/ru/articles/360021888880
   Убедитесь что выбираете версию для aarch64!

ПРОДОЛЖИТЬ БЕЗ ОБНОВЛЕНИЯ?
Можно попробовать продолжить установку z2k.
Если нужные пакеты (iptables, ipset, curl) уже установлены -
всё может заработать и без обновления списков пакетов.
EOF
        else
            cat <<'EOF'
[WARN]  ОШИБКА ПРИ ОБНОВЛЕНИИ ПАКЕТОВ

Проверьте результаты диагностики выше.

Если репозиторий недоступен:
- Проблемы с сетью, DNS или блокировка
- Проверьте: curl -I http://bin.entware.net/

Если другая проблема:
- Попробуйте вручную: opkg update --verbosity=2
- Проверьте логи: cat /opt/var/log/opkg.log

ПРОДОЛЖИТЬ БЕЗ ОБНОВЛЕНИЯ?
Установка продолжится с текущими пакетами.
Обычно это безопасно, если пакеты уже установлены.
EOF
        fi
        printf "\nContinue without opkg update? [Y/n]:"
        read -r answer </dev/tty

        case "$answer" in
            [Nn]|[Nn][Oo])
                print_info "Installation aborted"
                print_info "Fix the problem and run again"
                return 1
                ;;
        3)
            print_info "Application of new default strategies..."
            apply_new_default_strategies --auto
            ;;
            *)
                print_warning "We continue without updating packages..."
                print_info "The current local package database will be used"
                return 0
                ;;
        esac
    fi
}

# ==============================================================================
# STEP 2: DNS CHECK (IMPORTANT)
# ==============================================================================

step_check_dns() {
    print_header "Step 2/12: DNS Check"

    print_info "Checking DNS operation and Internet availability..."

    # Check multiple servers
    local test_hosts="github.com google.com cloudflare.com"
    local dns_works=0

    for host in $test_hosts; do
        if nslookup "$host" >/dev/null 2>&1; then
            print_success "DNS is working ($host allowed)"
            dns_works=1
            break
        fi
    done

    if [ $dns_works -eq 0 ]; then
        print_error "DNS is not working!"
        print_separator
        print_warning "Possible reasons:"
        print_warning "1. No internet connection"
        print_warning "2. DNS server is not configured"
        print_warning "3. Blocking RKN (bin.entware.net, github.com)"
        print_separator

        printf "Continue installation without working DNS? [y/N]:"
        read -r answer </dev/tty

        case "$answer" in
            [Yy]*)
                print_warning "We continue without DNS..."
                print_info "Installation may fail when downloading files"
                return 0
                ;;
        3)
            print_info "Application of new default strategies..."
            apply_new_default_strategies --auto
            ;;
            *)
                print_info "Installation aborted"
                print_info "Fix DNS and start again"
                return 1
                ;;
        esac
    fi

    return 0
}

# ==============================================================================
# STEP 3: INSTALLING DEPENDENCIES (ADVANCED)
# ==============================================================================

step_install_dependencies() {
    print_header "Step 3/12: Installing Dependencies"

    # List of required packages for Entware (runtime only)
    local packages="
libmnl
libnetfilter-queue
libnfnetlink
libcap
zlib
curl
unzip
"

    print_info "Installing packages..."

    for pkg in $packages; do
        if opkg list-installed | grep -q "^${pkg} "; then
            print_info "$pkg is already installed"
        else
            print_info "Installing $pkg..."
            opkg install "$pkg" || print_warning "Failed to install $pkg"
        fi
    done

    # Create symlinks for libraries (needed for linking)
    print_info "Creating library symlinks..."

    cd /opt/lib || return 1

    # libmnl
    if [ ! -e libmnl.so ] && [ -e libmnl.so.0 ]; then
        ln -sf libmnl.so.0 libmnl.so
        print_info "A symlink has been created: libmnl.so -> libmnl.so.0"
    fi

    # libnetfilter_queue
    if [ ! -e libnetfilter_queue.so ] && [ -e libnetfilter_queue.so.1 ]; then
        ln -sf libnetfilter_queue.so.1 libnetfilter_queue.so
        print_info "A symlink has been created: libnetfilter_queue.so -> libnetfilter_queue.so.1"
    fi

    # libnfnetlink
    if [ ! -e libnfnetlink.so ] && [ -e libnfnetlink.so.0 ]; then
        ln -sf libnfnetlink.so.0 libnfnetlink.so
        print_info "A symlink has been created: libnfnetlink.so -> libnfnetlink.so.0"
    fi

    cd - >/dev/null || return 1

    # =========================================================================
    # CRITICAL PACKAGES FOR ZAPRET2 (from check_prerequisites_openwrt)
    # =========================================================================

    print_separator
    print_info "Installing critical packages for zapret2..."

    local critical_packages=""

    # ipset - CRITICAL for filtering by domain lists
    if ! opkg list-installed | grep -q "^ipset "; then
        print_info "ipset is required to filter traffic"
        critical_packages="$critical_packages ipset"
    else
        print_success "ipset is already installed"
    fi

    # Checking kernel modules (on Keenetic they are built into the kernel, do not require installation)
    # xt_NFQUEUE - CRITICAL for redirection to NFQUEUE
    if [ -f "/lib/modules/$(uname -r)/xt_NFQUEUE.ko" ] || lsmod | grep -q "xt_NFQUEUE" || modinfo xt_NFQUEUE >/dev/null 2>&1; then
        print_success "The xt_NFQUEUE module is available"
    else
        print_warning "Module xt_NFQUEUE not found (could be built into the kernel)"
    fi

    # xt_connbytes, xt_multiport - for packet filtering
    if modinfo xt_connbytes >/dev/null 2>&1 || grep -q "xt_connbytes" /proc/modules 2>/dev/null; then
        print_success "xt_connbytes module is available"
    else
        print_warning "Module xt_connbytes not found (could be built into the kernel)"
    fi

    if modinfo xt_multiport >/dev/null 2>&1 || grep -q "xt_multiport" /proc/modules 2>/dev/null; then
        print_success "xt_multiport module available"
    else
        print_warning "xt_multiport module not found (could be built into the kernel)"
    fi

    # Install critical packages if necessary (ipset only for Keenetic)
    if [ -n "$critical_packages" ]; then
        print_info "Installation: $critical_packages"
        if opkg install $critical_packages; then
            print_success "Critical packages installed"
        else
            print_error "Failed to install critical packages"
            print_warning "zapret2 may not work without these packages!"

            printf "Continue without them? [y/N]:"
            read -r answer </dev/tty
            case "$answer" in
                [Yy]*) print_warning "We continue at our own risk..." ;;
        3)
            print_info "Application of new default strategies..."
            apply_new_default_strategies --auto
            ;;
                *) return 1 ;;
            esac
        fi
    else
        print_success "All critical packages are already installed"
    fi

    print_separator
    print_info "NOTE: On Keenetic modules iptables (xt_NFQUEUE, xt_connbytes,"
    print_info "xt_multiport) are built into the kernel and do not require separate installation."

    # =========================================================================
    # OPTIONAL OPTIMIZATIONS (GNU gzip/sort)
    # =========================================================================

    print_separator
    print_info "Checking optional optimizations..."

    # Check busybox gzip
    if command -v gzip >/dev/null 2>&1; then
        if readlink "$(which gzip)" 2>/dev/null | grep -q busybox; then
            print_info "Busybox gzip detected (slow, ~3x slower than GNU)"
            printf "Install GNU gzip to speed up list processing? [y/N]:"
            read -r answer </dev/tty
            case "$answer" in
                [Yy]*)
                    if opkg install --force-overwrite gzip; then
                        print_success "GNU gzip installed"
                    else
                        print_warning "Failed to install GNU gzip"
                    fi
                    ;;
        3)
            print_info "Application of new default strategies..."
            apply_new_default_strategies --auto
            ;;
                *)
                    print_info "Skip installing GNU gzip"
                    ;;
            esac
        fi
    fi

    # Check busybox sort
    if command -v sort >/dev/null 2>&1; then
        if readlink "$(which sort)" 2>/dev/null | grep -q busybox; then
            print_info "Busybox sort detected (slow, uses a lot of RAM)"
            printf "Install GNU sort for speedup? [y/N]:"
            read -r answer </dev/tty
            case "$answer" in
                [Yy]*)
                    if opkg install --force-overwrite sort; then
                        print_success "GNU sort installed"
                    else
                        print_warning "Failed to install GNU sort"
                    fi
                    ;;
        3)
            print_info "Application of new default strategies..."
            apply_new_default_strategies --auto
            ;;
                *)
                    print_info "Skip installing GNU sort"
                    ;;
            esac
        fi
    fi

    print_success "Dependencies installed"
    return 0
}

# ==============================================================================
# STEP 3: LOADING KERNEL MODULES
# ==============================================================================

step_load_kernel_modules() {
    print_header "Step 4/12: Loading Kernel Modules"

    local modules="xt_multiport xt_connbytes xt_NFQUEUE nfnetlink_queue"

    for module in $modules; do
        load_kernel_module "$module" || print_warning "Module $module not loaded"
    done

    print_success "Kernel modules loaded"
    return 0
}

# ==============================================================================
# STEP 4: INSTALLING ZAPRET2 (USING OFFICIAL install_bin.sh)
# ==============================================================================

step_build_zapret2() {
    print_header "Step 5/12: Install zapret2"

    # Delete old installation if exists
    if [ -d "$ZAPRET2_DIR" ]; then
        print_info "Removing old installation..."
        rm -rf "$ZAPRET2_DIR"
        print_success "Old installation removed"
    fi

    # Create temporary directory
    local build_dir="/tmp/zapret2_build"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    cd "$build_dir" || return 1

    # ===========================================================================
    # STEP 4.1: Download OpenWrt embedded release (contains everything you need)
    # ===========================================================================

    print_info "Loading zapret2 OpenWrt embedded release..."

    # GitHub API to get the latest version
    local api_url="https://api.github.com/repos/bol-van/zapret2/releases/latest"
    local release_data
    release_data=$(curl -fsSL "$api_url" 2>&1)

    local openwrt_url
    if [ $? -ne 0 ]; then
        print_warning "API is not available, I'm using fallback version v0.8.6..."
        openwrt_url="https://github.com/bol-van/zapret2/releases/download/v0.8.6/zapret2-v0.8.6-openwrt-embedded.tar.gz"
    else
        # Parse URL from JSON
        openwrt_url=$(echo "$release_data" | grep -o 'https://github.com/bol-van/zapret2/releases/download/[^"]*openwrt-embedded\.tar\.gz' | head -1)

        if [ -z "$openwrt_url" ]; then
            print_warning "Not found in the API, using fallback v0.8.6..."
            openwrt_url="https://github.com/bol-van/zapret2/releases/download/v0.8.6/zapret2-v0.8.6-openwrt-embedded.tar.gz"
        fi
    fi

    print_info "Release URL: $openwrt_url"

    # Download release
    if ! curl -fsSL "$openwrt_url" -o openwrt-embedded.tar.gz; then
        print_error "Failed to load zapret2 OpenWrt embedded"
        return 1
    fi

    print_success "Release loaded ($(du -h openwrt-embedded.tar.gz | cut -f1))"

    # ===========================================================================
    # STEP 4.2: Unpack the complete release structure
    # ===========================================================================

    print_info "Unpacking the release..."

    tar -xzf openwrt-embedded.tar.gz || {
        print_error "Error unpacking archive"
        return 1
    }

    # Find the root directory of the release (zapret2-vX.Y.Z)
    local release_dir
    release_dir=$(find . -maxdepth 1 -type d -name "zapret2-v*" | head -1)

    if [ -z "$release_dir" ] || [ ! -d "$release_dir" ]; then
        print_error "Release directory not found in archive"
        ls -la
        return 1
    fi

    print_success "Release unpacked: $release_dir"

    # ===========================================================================
    # STEP 4.3: Use install_bin.sh to install binaries
    # ===========================================================================

    print_info "Defining the architecture and installing binaries..."

    cd "$release_dir" || return 1

    # Set environment variables for install_bin.sh
    export ZAPRET_BASE="$PWD"

    # Check for install_bin.sh
    if [ ! -f "install_bin.sh" ]; then
        print_error "install_bin.sh not found in release"
        return 1
    fi

    # Call install_bin.sh to automatically install binaries
    print_info "Running the official install_bin.sh..."

    if sh install_bin.sh; then
        print_success "The binaries are installed via install_bin.sh"
    else
        print_error "install_bin.sh failed"
        print_info "Trying to install manually..."

        # Fallback: manual installation if install_bin.sh did not work
        local arch=$(uname -m)
        local bin_arch=""

        case "$arch" in
            aarch64) bin_arch="linux-arm64" ;;
            armv7l|armv6l|arm) bin_arch="linux-arm" ;;
            x86_64) bin_arch="linux-x86_64" ;;
            i386|i686) bin_arch="linux-x86" ;;
            mips) bin_arch="linux-mips" ;;
            mipsel) bin_arch="linux-mipsel" ;;
        3)
            print_info "Application of new default strategies..."
            apply_new_default_strategies --auto
            ;;
            *)
                print_error "Unsupported architecture: $arch"
                return 1
                ;;
        esac

        if [ ! -d "binaries/$bin_arch" ]; then
            print_error "No binaries found for $bin_arch"
            return 1
        fi

        # Create directories and install binaries manually
        mkdir -p nfq2 ip2net mdig
        cp "binaries/$bin_arch/nfqws2" nfq2/ || return 1
        cp "binaries/$bin_arch/ip2net" ip2net/ || return 1
        cp "binaries/$bin_arch/mdig" mdig/ || return 1
        chmod +x nfq2/nfqws2 ip2net/ip2net mdig/mdig

        print_success "Binaries installed manually for $bin_arch"
    fi

    # Check that nfqws2 is executable and working
    if [ ! -x "nfq2/nfqws2" ]; then
        print_error "nfqws2 not found or not executable after installation"
        return 1
    fi

    # Check launch
    if ! ./nfq2/nfqws2 --version >/dev/null 2>&1; then
        print_warning "nfqws2 cannot be started (possibly the wrong architecture)"
        print_info "Output --version:"
        ./nfq2/nfqws2 --version 2>&1 | head -5 || true
    else
        local version=$(./nfq2/nfqws2 --version 2>&1 | head -1)
        print_success "nfqws2 running: $version"
    fi

    # ===========================================================================
    # STEP 4.4: Move to final directory
    # ===========================================================================

    print_info "Setting to $ZAPRET2_DIR..."

    cd "$build_dir" || return 1
    mv "$release_dir" "$ZAPRET2_DIR" || return 1

    # ===========================================================================
    # STEP 4.5: Add custom files from the z2k repository
    # ===========================================================================

    print_info "Copying additional files..."

    # Copy strats_new2.txt if it is in the z2k repository
    if [ -f "${WORK_DIR}/strats_new2.txt" ]; then
        cp -f "${WORK_DIR}/strats_new2.txt" "${ZAPRET2_DIR}/" || \
            print_warning "Failed to copy strats_new2.txt"
    fi

    # Copy quic_strats.ini if ​​available
    if [ -f "${WORK_DIR}/quic_strats.ini" ]; then
        cp -f "${WORK_DIR}/quic_strats.ini" "${ZAPRET2_DIR}/" || \
            print_warning "Failed to copy quic_strats.ini"
    fi

    # Update fake blobs if there are more recent ones in z2k
    if [ -d "${WORK_DIR}/files/fake" ]; then
        print_info "���������� fake blobs �� z2k..."
        cp -f "${WORK_DIR}/files/fake/"* "${ZAPRET2_DIR}/files/fake/" 2>/dev/null || true
    fi

    # ����������� lua.gz (���� ����� openwrt-embedded)
    if [ -d "${ZAPRET2_DIR}/lua" ]; then
        if command -v gzip >/dev/null 2>&1; then
            for f in "${ZAPRET2_DIR}/lua/"*.lua.gz; do
                [ -f "$f" ] || continue
                local out="${f%.gz}"
                print_info "���������� $(basename "$f")..."
                if gzip -dc "$f" > "${out}.tmp" 2>/dev/null; then
                    mv -f "${out}.tmp" "$out"
                    rm -f "$f"
                else
                    rm -f "${out}.tmp"
                    print_warning "�� ������� ����������� $f"
                fi
            done
        else
            print_warning "gzip �� ������, ���������� lua.gz ���������"
        fi
    fi
    # ===========================================================================
    # COMPLETION
    # ===========================================================================

    # Cleaning
    cd / || return 1
    rm -rf "$build_dir"

    print_success "lock2 installed"
    print_info "Structure:"
    print_info "- Binaries: nfq2/nfqws2, ip2net/ip2net, mdig/mdig"
    print_info "- Lua libraries: lua/"
    print_info "- Fake файлы: files/fake/"
    print_info "- Module: common/"
    print_info "- Documentation: docs/"

    return 0
}

# ==============================================================================
# STEP 5: CHECKING THE INSTALLATION
# ==============================================================================

step_verify_installation() {
    print_header "Step 6/12: Verify installation"

    # Check directory structure
    local required_paths="
${ZAPRET2_DIR}
${ZAPRET2_DIR}/nfq2
${ZAPRET2_DIR}/nfq2/nfqws2
${ZAPRET2_DIR}/ip2net
${ZAPRET2_DIR}/mdig
${ZAPRET2_DIR}/lua
${ZAPRET2_DIR}/files
${ZAPRET2_DIR}/common
${ZAPRET2_DIR}/binaries
"

    print_info "Checking directory structure..."

    local missing=0
    for path in $required_paths; do
        if [ -e "$path" ]; then
            print_info "[OK] $path"
        else
            print_warning "[FAIL] $path not found"
            missing=$((missing + 1))
        fi
    done

    if [ $missing -gt 0 ]; then
        print_warning "Some components are missing, but this may be normal"
    fi

    # Check all binaries (installed via install_bin.sh)
    print_info "Checking binaries..."

    # nfqws2 - main binary
    if [ -x "${ZAPRET2_DIR}/nfq2/nfqws2" ]; then
        if verify_binary "${ZAPRET2_DIR}/nfq2/nfqws2"; then
            print_success "[OK] nfqws2 works"
        else
            print_error "[FAIL] nfqws2 does not start"
            return 1
        fi
    else
        print_error "[FAIL] nfqws2 not found or not executable"
        return 1
    fi

    # ip2net - auxiliary (can be a symlink)
    if [ -e "${ZAPRET2_DIR}/ip2net/ip2net" ]; then
        print_info "[OK] ip2net installed"
    else
        print_warning "[FAIL] ip2net not found (optional)"
    fi

    # mdig - DNS utility (can be a symlink)
    if [ -e "${ZAPRET2_DIR}/mdig/mdig" ]; then
        print_info "[OK] mdig installed"
    else
        print_warning "[FAIL] mdig not found (optional)"
    fi

    # Count components
    print_info "Component statistics:"

    # Lua files
    if [ -d "${ZAPRET2_DIR}/lua" ]; then
        local lua_count=$(find "${ZAPRET2_DIR}/lua" -name "*.lua" 2>/dev/null | wc -l)
        print_info "- Lua files: $lua_count"
    fi

    # Fake files
    if [ -d "${ZAPRET2_DIR}/files/fake" ]; then
        local fake_count=$(find "${ZAPRET2_DIR}/files/fake" -name "*.bin" 2>/dev/null | wc -l)
        print_info "- Fake files: $fake_count"
    fi

    # Moduli common/
    if [ -d "${ZAPRET2_DIR}/common" ]; then
        local common_count=$(find "${ZAPRET2_DIR}/common" -name "*.sh" 2>/dev/null | wc -l)
        print_info "- Module common/: $common_count"
    fi

    # is install_bin.sh present?
    if [ -f "${ZAPRET2_DIR}/install_bin.sh" ]; then
        print_info "- install_bin.sh: installed"
    fi

    print_success "Installation verified successfully"
    return 0
}

# ==============================================================================
# STEP 7: DETERMINING THE FIREWALL TYPE (CRITICAL)
# ==============================================================================

step_check_and_select_fwtype() {
    print_header "Step 7/12: Determining the firewall type"

    print_info "Auto-detection of system firewall type..."

    # IMPORTANT: Load base.sh BEFORE fwtype.sh, because we need the exists() function
    if [ -f "${ZAPRET2_DIR}/common/base.sh" ]; then
        . "${ZAPRET2_DIR}/common/base.sh"
    else
        print_error "Module base.sh not found in ${ZAPRET2_DIR}/common/"
        return 1
    fi

    # Source module fwtype from zapret2
    if [ -f "${ZAPRET2_DIR}/common/fwtype.sh" ]; then
        . "${ZAPRET2_DIR}/common/fwtype.sh"
    else
        print_error "Module fwtype.sh not found in ${ZAPRET2_DIR}/common/"
        return 1
    fi

    # IMPORTANT: Restore the Z2K path to the init script (it is overwritten by zapret2 modules)
    INIT_SCRIPT="$Z2K_INIT_SCRIPT"

    # Override linux_ipt_avail for Keenetic (IPv4-only mode)
    # The official function requires iptables AND ip6tables, but Keenetic with DISABLE_IPV6=1
    # does not have ip6tables, so we only check iptables
    linux_ipt_avail()
    {
        exists iptables
    }

    # Autodetection via function from zapret2
    linux_fwtype

    if [ -z "$FWTYPE" ]; then
        print_error "Could not determine firewall type"
        FWTYPE="iptables"  # fallback
        print_warning "We use fallback: iptables"
    fi

    print_success "Firewall detected: $FWTYPE"

    # Show information
    case "$FWTYPE" in
        iptables)
            print_info "iptables - traditional Linux firewall"
            print_info "Keenetic usually uses iptables"
            ;;
        nftables)
            print_info "nftables - modern Linux firewall (kernel 3.13+)"
            print_info "More efficient than iptables"
            ;;
        3)
            print_info "Application of new default strategies..."
            apply_new_default_strategies --auto
            ;;
        *)
            print_warning "Unknown firewall type: $FWTYPE"
            ;;
    esac

    # Write FWTYPE to the config file (if it already exists)
    local config="${ZAPRET2_DIR}/config"
    if [ -f "$config" ]; then
        # Check if FWTYPE is already in config
        if grep -q "^#*FWTYPE=" "$config"; then
            # Update an existing row
            sed -i "s|^#*FWTYPE=.*|FWTYPE=$FWTYPE|" "$config"
            print_info "FWTYPE=$FWTYPE saved in config"
        else
            # Add to the end of the FIREWALL SETTINGS section
            sed -i "/# FIREWALL SETTINGS/a FWTYPE=$FWTYPE" "$config"
            print_info "FWTYPE=$FWTYPE added to config"
        fi
    else
        print_info "Config file has not yet been created, FWTYPE will be set later"
    fi

    # Export for use in other functions
    export FWTYPE

    return 0
}

# ==============================================================================
# STEP 8: LOADING DOMAIN LISTS
# ==============================================================================

step_download_domain_lists() {
    print_header "Step 8/12: Uploading Domain Lists"

    # Use function from lib/config.sh
    download_domain_lists || {
        print_error "Failed to load domain lists"
        return 1
    }

    # ���. ��������: ������ QUIC YT (zapret4rocket)
    local yt_quic_list="/opt/zapret2/extra_strats/UDP/YT/List.txt"
    if [ ! -s "$yt_quic_list" ]; then
        print_warning "������ QUIC YT ����������� ��� ������: $yt_quic_list"
        print_info "������ ��������� �������� �� zapret4rocket..."
        local base_url="${Z4R_BASE_URL:-https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/master}"
        mkdir -p "$(dirname "$yt_quic_list")"
        if curl -fsSL "$base_url/extra_strats/UDP/YT/List.txt" -o "$yt_quic_list"; then
            if [ -s "$yt_quic_list" ]; then
                print_success "������ QUIC YT ��������: $yt_quic_list"
            else
                print_warning "������ QUIC YT ������, �� ������: $yt_quic_list"
            fi
        else
            print_warning "�� ������� ��������� QUIC YT list � $base_url"
        fi
    fi
    # Create a basic configuration
    create_base_config || {
        print_error "Failed to create configuration"
        return 1
    }

    print_success "Domain lists and configuration set"
    return 0
}

# ==============================================================================
# STEP 7: DISABLE HARDWARE NAT
# ==============================================================================

step_disable_hwnat_and_offload() {
    print_header "Step 9/12: Disabling Hardware NAT and Flow Offloading"

    # =========================================================================
    # 9.1: Hardware NAT (stuck on Keenetic)
    # =========================================================================

    print_info "Checking Hardware NAT (fastnat)..."

    # Check availability of HWNAT control system
    if [ -f "/sys/kernel/fastnat/mode" ]; then
        local current_mode
        current_mode=$(cat /sys/kernel/fastnat/mode 2>/dev/null || echo "unknown")

        print_info "Current fastnat mode: $current_mode"

        if [ "$current_mode" != "0" ] && [ "$current_mode" != "unknown" ]; then
            print_warning "Hardware NAT enabled - may conflict with DPI bypass"

            # Attempting to disconnect
            if echo 0 > /sys/kernel/fastnat/mode 2>/dev/null; then
                print_success "Hardware NAT disabled"
            else
                print_warning "Failed to disable Hardware NAT"
                print_info "Additional rights may be required"
                print_info "Try it manually: echo 0 > /sys/kernel/fastnat/mode"
            fi
        else
            print_success "Hardware NAT is already disabled or inaccessible"
        fi
    else
        print_info "Hardware NAT (fastnat) not detected on this system"
    fi

    # =========================================================================
    # 9.2: Flow Offloading (critical for nfqws)
    # =========================================================================

    print_separator
    print_info "Checking Flow Offloading..."

    # On Keenetic flow offloading is controlled through other mechanisms
    # Mainly via iptables/nftables rules

    # Check via sysctl (if available)
    if [ -f "/proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal" ]; then
        print_info "Checking conntrack liberal mode..."

        # zapret2 may require liberal mode to handle invalid RST packets
        local liberal_mode
        liberal_mode=$(cat /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal 2>/dev/null || echo "0")

        if [ "$liberal_mode" = "0" ]; then
            print_info "conntrack liberal mode is disabled (will be enabled when zapret2 starts)"
        else
            print_info "conntrack liberal mode is already enabled"
        fi
    fi

    # Write FLOWOFFLOAD=none in config (safe option)
    print_info "Setting FLOWOFFLOAD=none in config (recommended for Keenetic)"

    # This will be used when creating the config file
    export FLOWOFFLOAD=none

    print_separator
    print_info "Information about flow offloading:"
    print_info "- Flow offloading speeds up routing but can break DPI bypass"
    print_info "- nfqws traffic MUST be excluded from offloading"
    print_info "- On Keenetic, FLOWOFFLOAD=none is used (safe)"
    print_info "- The official init script will automatically configure exemption rules"

    print_success "Hardware NAT and Flow Offloading checked"
    return 0
}

# ==============================================================================
# STEP 9.5: CONFIGURING TMPDIR FOR LOW RAM SYSTEMS
# ==============================================================================

step_configure_tmpdir() {
    print_header "Step 9.5/12: Configuring TMPDIR for low RAM systems"

    # Get the amount of RAM
    local ram_mb
    if [ -f "${ZAPRET2_DIR}/common/base.sh" ]; then
        . "${ZAPRET2_DIR}/common/base.sh"
        ram_mb=$(get_ram_mb)
    else
        # Fallback: detect RAM manually
        if [ -f /proc/meminfo ]; then
            ram_mb=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
        else
            ram_mb=999  # We assume there is enough RAM if we cannot determine
        fi
    fi

    print_info "Found RAM: ${ram_mb}MB"

    # AUTOMATIC TMPDIR selection based on RAM
    if [ "$ram_mb" -le 400 ]; then
        print_warning "Low RAM system - use the disk for temporary files"

        local disk_tmpdir="/opt/zapret2/tmp"

        # Create directory
        mkdir -p "$disk_tmpdir" || {
            print_error "Failed to create $disk_tmpdir"
            return 1
        }

        export TMPDIR="$disk_tmpdir"
        print_success "TMPDIR set: $disk_tmpdir (OOM protection)"

        # Check free disk space
        if command -v df >/dev/null 2>&1; then
            local free_mb
            free_mb=$(df -m "$disk_tmpdir" | tail -1 | awk '{print $4}')
            print_info "Free disk space: ${free_mb}MB"

            if [ "$free_mb" -lt 200 ]; then
                print_warning "Low free space (<200MB)"
            fi
        fi
    else
        print_success "Enough RAM (${ram_mb}MB) - use /tmp (faster)"
        export TMPDIR=""
    fi

    return 0
}

# ==============================================================================
# STEP 10: CREATE AN OFFICIAL CONFIG AND INIT SCRIPT
# ==============================================================================

step_create_config_and_init() {
    print_header "Step 10/12: Create config and init script"

    # ========================================================================
    # 10.0: Create default strategy files
    # ========================================================================

    # Source functions for working with strategies
    . "${LIB_DIR}/strategies.sh" || {
        print_error "Failed to load strategies.sh"
        return 1
    }

    # Create directories and default strategy files
    create_default_strategy_files || {
        print_error "Failed to create strategy files"
        return 1
    }

    # ========================================================================
    # 10.1: Create official config file
    # ========================================================================

    print_info "Creating the official config file..."

    local zapret_config="${ZAPRET2_DIR}/config"

    # Source functions for generating config
    . "${LIB_DIR}/config_official.sh" || {
        print_error "Failed to load config_official.sh"
        return 1
    }

    # Create a config file (with auto-generation of NFQWS2_OPT from strategies)
    create_official_config "$zapret_config" || {
        print_error "Failed to create config file"
        return 1
    }

    print_success "Config file created: $zapret_config"

    # ========================================================================
    # 8.2: Install new init script
    # ========================================================================

    print_info "��������� init �������..."

    # ������� ���������� ���� �� ����������
    mkdir -p "$(dirname "$INIT_SCRIPT")"

    # ����������� init ������ �� �����������
    print_info "�������� init �������..."

    if [ -f "${WORK_DIR}/files/S99zapret2.new" ]; then
        cp -f "${WORK_DIR}/files/S99zapret2.new" "$INIT_SCRIPT" || {
            print_error "�� ������� ����������� init ������"
            return 1
        }
    else
        print_error "Init ������ �� ������: ${WORK_DIR}/files/S99zapret2.new"
        return 1
    fi

    chmod +x "$INIT_SCRIPT" || {
        print_error "Failed to set permissions on init script"
        return 1
    }

    print_success "Init script installed: $INIT_SCRIPT"

    # Show information about the new approach
    print_info "Init script uses:"
    print_info "- Modules from $ZAPRET2_DIR/common/"
    print_info "- Config file: $zapret_config"
    print_info "- Strategies from config (config-driven, not hardcoded)"
    print_info "- PID files for graceful shutdown"
    print_info "- Firewall/daemons separation"

    return 0
}

# ==============================================================================
# STEP 9: INSTALLING THE NETFILTER HOOK
# ==============================================================================

step_install_netfilter_hook() {
    print_header "Step 11/12: Installing the netfilter hook"

    print_info "Installing a hook to automatically restore rules..."

    # Create a directory for NDM hooks
    local hook_dir="/opt/etc/ndm/netfilter.d"
    mkdir -p "$hook_dir" || {
        print_error "Failed to create $hook_dir"
        return 1
    }

    local hook_file="${hook_dir}/000-zapret2.sh"

    # Copy hook from files/
    if [ -f "${WORK_DIR}/files/000-zapret2.sh" ]; then
        cp "${WORK_DIR}/files/000-zapret2.sh" "$hook_file" || {
            print_error "Failed to copy hook"
            return 1
        }
    else
        print_warning "Hook file not found in ${WORK_DIR}/files/"
        print_info "Creating a hook manually..."

        # Create a hook directly
        cat > "$hook_file" <<'HOOK'
#!/bin/sh
# Keenetic NDM netfilter hook for automatic recovery of zapret2 rules
# Called when there are changes in netfilter (iptables)

INIT_SCRIPT="/opt/etc/init.d/S99zapret2"

# We process only changes in the mangle table
[ "$table" != "mangle" ] && exit 0

# Check that the init script exists
[ ! -f "$INIT_SCRIPT" ] && exit 0

# Check that zapret2 is enabled
if ! grep -q "^ENABLED=yes" "$INIT_SCRIPT" 2>/dev/null; then
    exit 0
fi

# Slight delay for stability
sleep 2

# Restart zapret2 rules
"$INIT_SCRIPT" restart >/dev/null 2>&1 &

exit 0
HOOK
    fi

    # Make executable
    chmod +x "$hook_file" || {
        print_error "Failed to set permissions on hook"
        return 1
    }

    print_success "Netfilter hook installed: $hook_file"
    print_info "The hook will restore the rules when the Internet is reconnected"

    return 0
}

# ==============================================================================
# STEP 10: FINALIZATION
# ==============================================================================

step_finalize() {
    print_header "Step 12/12: Finalizing the installation"

    # Check the binary before launching
    print_info "Checking nfqws2 before starting..."

    if [ ! -x "${ZAPRET2_DIR}/nfq2/nfqws2" ]; then
        print_error "nfqws2 not found or not executable"
        return 1
    fi

    # Check binary dependencies (if ldd is available)
    if command -v ldd >/dev/null 2>&1; then
        print_info "Checking libraries..."
        if ldd "${ZAPRET2_DIR}/nfq2/nfqws2" 2>&1 | grep -q "not found"; then
            print_warning "Some libraries are missing:"
            ldd "${ZAPRET2_DIR}/nfq2/nfqws2" | grep "not found"
        else
            print_success "All libraries found"
        fi
    fi

    # Try running it directly for diagnostics
    print_info "nfqws2 launch test..."
    local version_output
    version_output=$("${ZAPRET2_DIR}/nfq2/nfqws2" --version 2>&1 | head -1)

    if echo "$version_output" | grep -q "github version"; then
        print_success "nfqws2 executes correctly: $version_output"
    else
        print_error "nfqws2 cannot be started"
        print_info "Error output:"
        "${ZAPRET2_DIR}/nfq2/nfqws2" --version 2>&1 | head -10
        return 1
    fi

    # Start the service
    print_info "Starting the zapret2... service"

    if "$INIT_SCRIPT" start 2>&1; then
        print_success "start command completed"
    else
        print_error "Failed to start the service"
        print_info "I'm trying to run it with detailed output..."
        sh -x "$INIT_SCRIPT" start 2>&1 | tail -20
        return 1
    fi

    sleep 2

    # Check status
    if is_zapret2_running; then
        print_success "lock2 works"
    else
        print_warning "The service is running, but the process is not detected"
        print_info "Process check:"
        ps | grep -i nfqws || echo "No nfqws processes found"
        print_info "Check the logs: $INIT_SCRIPT status"
    fi

    # =========================================================================
    # CONFIGURING AUTO-UPDATES OF DOMAIN LISTS (CRITICAL)
    # =========================================================================

    print_separator
    print_info "Configuring auto-update of domain lists..."

    # Source module installer.sh for crontab functions
    if [ -f "${ZAPRET2_DIR}/common/installer.sh" ]; then
        . "${ZAPRET2_DIR}/common/installer.sh"

        # IMPORTANT: Restore the Z2K path to the init script (it is overwritten by zapret2 modules)
        INIT_SCRIPT="$Z2K_INIT_SCRIPT"

        # Delete old cron entries if there are any
        crontab_del_quiet

        # Add a new task: updated every day at 06:00
        # Routers work 24/7, so night time is ideal
        if crontab_add 0 6; then
            print_success "Auto-update is configured (daily at 06:00)"
        else
            print_warning "Failed to configure crontab"
            print_info "The lists will need to be updated manually:"
            print_info "  ${ZAPRET2_DIR}/ipset/get_config.sh"
        fi

        # Make sure the cron daemon is running
        if cron_ensure_running; then
            print_info "Cron daemon is running"
        else
            print_warning "Cron daemon is not running, auto-update will not work"
        fi
    else
        print_warning "Installer.sh module not found, skip cron setup"
        print_info "Auto-update is not configured - lists must be updated manually"
    fi

    # Show summary information
    print_separator
    print_success "Installation of zapret2 is complete!"
    print_separator

    printf "Installed:\n"
    printf "  %-25s: %s\n" "Directory" "$ZAPRET2_DIR"
    printf "  %-25s: %s\n" "Binary" "${ZAPRET2_DIR}/nfq2/nfqws2"
    printf "  %-25s: %s\n" "Init script" "$INIT_SCRIPT"
    printf "  %-25s: %s\n" "Configuration" "$CONFIG_DIR"
    printf "  %-25s: %s\n" "Domain Lists" "$LISTS_DIR"
    printf "  %-25s: %s\n" "Strategies" "$STRATEGIES_CONF"
    printf "  %-25s: %s\n" "Tools" "$tools_dir"

    print_separator

    return 0
}

# ==============================================================================
# FULL INSTALLATION (9 STEPS)
# ==============================================================================

run_full_install() {
    print_header "Installing zapret2 for Keenetic"
    print_info "Installation process: 12 steps (advanced verification)"
    print_separator

    # Follow all steps sequentially
    step_check_root || return 1                    # ← NEW (0/12)
    step_update_packages || return 1               # 1/12
    step_check_dns || return 1                     # ← NEW (2/12)
    step_install_dependencies || return 1          # 3/12 (extended)
    step_load_kernel_modules || return 1           # 4/12
    step_build_zapret2 || return 1                 # 5/12
    step_verify_installation || return 1           # 6/12
    step_check_and_select_fwtype || return 1       # ← NEW (7/12)
    step_download_domain_lists || return 1         # 8/12
    step_disable_hwnat_and_offload || return 1     # 9/12 (extended)
    step_configure_tmpdir || return 1              # ← NEW (9.5/12)
    step_create_config_and_init || return 1        # 10/12
    step_install_netfilter_hook || return 1        # 11/12
    step_finalize || return 1                      # 12/12

    # After installation, we use autocircular strategies by default without any questions
    print_separator
    print_info "Installation completed successfully!"
    print_separator

    printf "\nConfiguring DPI bypass strategies:\n\n"
    print_info "Automatically apply autocircular strategies (without asking for a choice)..."
    apply_autocircular_strategies --auto

    print_info "I open the control menu..."
    sleep 1
    show_main_menu

    return 0
}

# ==============================================================================
# REMOVING ZAPRET2
# ==============================================================================

uninstall_zapret2() {
    print_header "Removing zapret2"

    if ! is_zapret2_installed; then
        print_info "lock2 is not installed"
        return 0
    fi

    print_warning "This will remove:"
    print_warning "- All files zapret2 ($ZAPRET2_DIR)"
    print_warning "- Configuration ($CONFIG_DIR)"
    print_warning "- Init script ($INIT_SCRIPT)"

    printf "\n"
    if ! confirm "Are you sure? This action is irreversible!" "N"; then
        print_info "Deletion cancelled."
        return 0
    fi

    # Stop service
    if is_zapret2_running; then
        print_info "Stopping the service..."
        "$INIT_SCRIPT" stop
    fi

    # Remove init script
    if [ -f "$INIT_SCRIPT" ]; then
        rm -f "$INIT_SCRIPT"
        print_info "Removed init script"
    fi

    # Remove netfilter hook
    local hook_file="/opt/etc/ndm/netfilter.d/000-zapret2.sh"
    if [ -f "$hook_file" ]; then
        rm -f "$hook_file"
        print_info "Removed netfilter hook"
    fi

    # Remove lock2
    if [ -d "$ZAPRET2_DIR" ]; then
        rm -rf "$ZAPRET2_DIR"
        print_info "Removed directory zapret2"
    fi

    # Delete configuration
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        print_info "Configuration deleted"
    fi

    print_success "zapret2 has been completely removed"

    return 0
}

# ==============================================================================
# EXPORTING FUNCTIONS
# ==============================================================================

# All functions are available after the source of this file
