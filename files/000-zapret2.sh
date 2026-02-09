#!/bin/sh
# Keenetic NDM netfilter hook for automatic recovery of zapret2 rules
# Устанавливается в: /opt/etc/ndm/netfilter.d/000-zapret2.sh
#
# This script is called by the Keenetic system when there are changes in netfilter (iptables).
# When you reconnect to the Internet, change network settings, or
# other events - iptables rules are reset and this hook restores them.

# Environment variables from NDM:
# $table - iptables table name (filter, nat, mangle, raw)
# $type - event type (add, del, etc)

INIT_SCRIPT="/opt/etc/init.d/S99zapret2"

# We process only changes in the mangle table
# (zapret2 uses mangle table for NFQUEUE)
[ "$table" != "mangle" ] && exit 0

# Check that the init script exists
[ ! -f "$INIT_SCRIPT" ] && exit 0

# Check that zapret2 is enabled
if ! grep -q "^ENABLED=yes" "$INIT_SCRIPT" 2>/dev/null; then
    exit 0
fi

# Logging (optional, uncomment for debugging)
# logger -t zapret2-hook "Netfilter hook triggered: table=$table, type=$type"

# Slight delay for stability
sleep 2

# Restart zapret2 rules
"$INIT_SCRIPT" restart >/dev/null 2>&1 &

exit 0
