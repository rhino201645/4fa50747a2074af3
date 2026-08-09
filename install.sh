#!/bin/sh

apk update
apk add xray-core kmod-nft-tproxy nano wget

mkdir -p /etc/xray
> /etc/xray/config.json

wget -O /usr/bin/geoip.dat https://cdn.jsdelivr.net/gh/rhino201645/0d60353968493be0@main/geoip.dat

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

ip rule add fwmark 1 table 100 2>/dev/null
ip route add local default dev lo table 100 2>/dev/null
fw4 reload
/etc/init.d/xray enable
/etc/init.d/xray restart

cat << 'EOF' > /etc/init.d/xray
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/xray run -c /etc/xray/config.json
    procd_set_param respawn
    procd_set_param file /etc/xray/config.json
    procd_close_instance
}
EOF

chmod +x /etc/init.d/xray
/etc/init.d/xray enable

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
    procd_set_param env GOMEMLIMIT=70MiB GOGC=40
    procd_set_param respawn
    procd_set_param file /etc/xray/config.json
    procd_close_instance
}
EOF
fi

chmod +x /etc/init.d/xray
/etc/init.d/xray restart

printf "configure your inbound? ( y / n ): "
read CONF_ANS

if [ "$CONF_ANS" = "y" ]; then
    nano /etc/xray/config.json
fi

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
    echo "To use the commands below, please log out and log back in, or type: source /etc/profile"
    echo ""
    echo "Available commands:"
    echo "  xray start   - Starts the core service"
    echo "  xray stop    - Stops the core service"
    echo "  xray restart - Restarts the core service"
    echo "  xray enable  - Enables core autostart on system boot"
    echo "  xray disable - Disables core autostart"
    echo "  xray status  - Shows current core status"
else
    echo "error!"
    exit 1
fi
