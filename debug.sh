#!/bin/sh
# debug.sh - Diagnostics of kernel modules for z2k on Keenetic

echo "+==================================================+"
echo "|  z2k - Kernel module diagnostics |"
echo "+==================================================+"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. SYSTEM INFORMATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Architecture: $(uname -m)"
echo "Kernel: $(uname -r)"
echo "В#rowsρ really jeanet: $(cat /test 2>/ve/vell |'не определена')"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. DIRECTORIES WITH MODULES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "System modules:"
ls -la /lib/modules/ 2>/dev/null || echo "Directory does not exist"
echo ""

echo "Entware Modules:"
ls -la /opt/lib/modules/ 2>/dev/null || echo "Directory does not exist"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. AVAILABILITY OF MODULE FILES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for mod in xt_NFQUEUE xt_multiport xt_connbytes nfnetlink_queue; do
    echo "Module: $mod"
    find /lib/modules/ -name "${mod}.ko" 2>/dev/null || echo "File not found"
done
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. LOADED MODULES (lsmod)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All netfilter modules:"
lsmod | grep -E 'nf|xt_' | head -20
echo ""
echo "Modules we are interested in:"
for mod in xt_NFQUEUE xt_multiport xt_connbytes nfnetlink_queue; do
    if lsmod | grep -q "^${mod} "; then
        echo "[OK] $mod loaded"
    else
        echo "[FAIL] $mod NOT loaded"
    fi
done
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. MODPROBE VERSIONS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "System modprobe:"
which /sbin/modprobe && /sbin/modprobe --version 2>&1 | head -3
echo ""
echo "Entware modprobe:"
which /opt/sbin/modprobe && /opt/sbin/modprobe --version 2>&1 | head -3
echo ""
echo "Default modprobe:"
which modprobe && modprobe --version 2>&1 | head -3
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. ATTEMPT TO LOAD VIA /sbin/modprobe"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for mod in xt_NFQUEUE xt_multiport xt_connbytes; do
    echo "Load attempt: $mod"
    /sbin/modprobe "$mod" 2>&1
    echo "Exit code: $?"
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7. ATTEMPTING TO LOAD VIA insmod"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kernel_ver=$(uname -r)
mod_path="/lib/modules/${kernel_ver}"

echo "Path to modules: $mod_path"
echo ""

for mod in xt_NFQUEUE.ko xt_multiport.ko xt_connbytes.ko; do
    mod_file=$(find "$mod_path" -name "$mod" 2>/dev/null | head -1)
    if [ -n "$mod_file" ]; then
        echo "Load attempt: $mod_file"
        /sbin/insmod "$mod_file" 2>&1
        echo "Exit code: $?"
    else
        echo "$mod file not found"
    fi
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "8. DMESG (last 30 lines)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
dmesg | tail -30
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "9. CHECKING DEPENDENCIES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ip_tables:"
lsmod | grep ip_tables
echo ""
echo "x_tables:"
lsmod | grep x_tables
echo ""
echo "nfnetlink:"
lsmod | grep nfnetlink
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "10. ПОПЫТКА ЗАГРУЗКИ ЧЕРЕЗ /opt/sbin/insmod (с полным путём)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kernel_ver=$(uname -r)
for mod in xt_NFQUEUE xt_multiport xt_connbytes; do
    mod_file="/lib/modules/${kernel_ver}/${mod}.ko"
    echo "Попытка: /opt/sbin/insmod $mod_file"
    /opt/sbin/insmod "$mod_file" 2>&1
    exitcode=$?
    echo "Exit code: $exitcode"

    # Check if it has loaded
    if lsmod | grep -q "^${mod} "; then
        echo "[OK] Module $mod loaded successfully!"
    else
        echo "[FAIL] Module $mod NOT loaded"
        # Show last lines of dmesg
        echo "Latest kernel messages:"
        dmesg | tail -5
    fi
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "11. ПОПЫТКА ЗАГРУЗКИ ЧЕРЕЗ /opt/sbin/modprobe -d"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kernel_ver=$(uname -r)
mod_dir="/lib/modules/${kernel_ver}"
echo "Modules directory: $mod_dir"
echo ""

for mod in xt_NFQUEUE xt_multiport xt_connbytes; do
    echo "Попытка: /opt/sbin/modprobe -d $mod_dir $mod"
    /opt/sbin/modprobe -d "$mod_dir" "$mod" 2>&1
    exitcode=$?
    echo "Exit code: $exitcode"

    # Check if it has loaded
    if lsmod | grep -q "^${mod} "; then
        echo "[OK] Module $mod loaded successfully!"
    else
        echo "[FAIL] Module $mod NOT loaded"
    fi
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "12. FINAL STATE OF MODULES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Loaded modules:"
lsmod | grep -E 'xt_NFQUEUE|xt_multiport|xt_connbytes|nfnetlink_queue'
echo ""

echo "Checking each module:"
for mod in xt_NFQUEUE xt_multiport xt_connbytes nfnetlink_queue; do
    if lsmod | grep -q "^${mod} "; then
        echo "[OK] $mod loaded"
    else
        echo "[FAIL] $mod NOT loaded"
    fi
done
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "13. LATEST DMESG POSTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
dmesg | tail -20
echo ""

echo "+==================================================+"
echo "|  Diagnostics completed |"
echo "+==================================================+"
