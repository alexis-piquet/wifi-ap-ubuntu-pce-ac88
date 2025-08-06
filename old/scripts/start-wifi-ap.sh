#!/bin/bash
set -e

# Ensure interface exists
if ! ip link show wls16 &>/dev/null; then
    echo "❌ Interface {{LAN_IFACE}}wls16 does not exist"
    exit 1
fi

# Bring interface up
ip link set wls16 up

# Wait until UP
for i in {1..10}; do
    if ip link show wls16 | grep -q "state UP"; then
        echo "✅ Interface wls16 is UP"
        break
    fi
    echo "⏳ Waiting for wls16 to be UP ($i/10)..."
    sleep 1
done

# Configure IP
ip addr flush dev wls16
ip addr add 192.168.0.1/24 dev wls16

echo "🎉 Interface wls16 configured with IP 192.168.0.1/24"
