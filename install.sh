#!/bin/sh

apk update
apk add xray-core kmod-nft-tproxy nano wget

mkdir -p /etc/xray
> /etc/xray/config.json

cat << 'EOF' > /etc/hotplug.d/iface/99-xray-route
#!/bin/sh
if [ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "lan" ]; then
    ip rule del fwmark 1 table 100 2>/dev/null
    ip route del local default dev lo table 100 2>/dev/null
    
    ip rule add fwmark 1 table 100
    ip route add local default dev lo table 100
fi
EOF

chmod +x /etc/hotplug.d/iface/99-xray-route

cat << 'EOF' > /etc/nftables.d/xray.nft
chain xray_prerouting {
    type filter hook prerouting priority mangle; policy accept;
    ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32 } return
    meta mark 255 return
    meta l4proto { tcp, udp } tproxy to :12345 meta mark set 1 accept
}
EOF

ip rule add fwmark 1 table 100 2>/dev/null
ip route add local default dev lo table 100 2>/dev/null
fw4 reload

printf "configure your inbound? ( y / n ): "
read CONF_ANS

if [ "$CONF_ANS" = "y" ]; then
    nano /etc/xray/config.json
fi

printf "low-ram? ( y / n ): "
read RAM_ANS

if [ "$RAM_ANS" = "y" ]; then
    cat << 'EOF' > /etc/init.d/xray
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/xray run -c /etc/xray/config.json
    procd_set_param env GOMEMLIMIT=55MiB GOGC=20
    procd_set_param respawn
    procd_set_param file /etc/xray/config.json
    procd_close_instance
}
EOF
else
    cat << 'EOF' > /etc/init.d/xray
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/xray run -c /etc/xray/config.json
    procd_set_param env GOMEMLIMIT=65MiB GOGC=40
    procd_set_param respawn
    procd_set_param file /etc/xray/config.json
    procd_close_instance
}
EOF
fi

chmod +x /etc/init.d/xray
/etc/init.d/xray enable
/etc/init.d/xray restart

sleep 2
STATUS_OUT=$(/etc/init.d/xray status 2>&1)

grep -q "xray()" /etc/profile || cat << 'EOF' >> /etc/profile
xray() {
    if [ -n "$1" ]; then
        /etc/init.d/xray "$1"
    else
        echo "Usage: xray {start|stop|restart|enable|disable|status}"
    fi
}
EOF

echo "$STATUS_OUT" | grep -q "running"

if [ $? -eq 0 ]; then
    echo "xray running!"
    echo ""
    echo "Setup is complete."
    echo "To use the commands below, please log out and log back in, or type: source /etc/profile"
    echo ""
    echo "Available commands:"
    echo "  xray start   - Starts the proxy service"
    echo "  xray stop    - Stops the proxy service"
    echo "  xray restart - Restarts the proxy service"
    echo "  xray enable  - Enables proxy autostart on system boot"
    echo "  xray disable - Disables proxy autostart"
    echo "  xray status  - Shows current service status"
else
    echo "error!"
    exit 1
fi
