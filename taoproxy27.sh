#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
set -e

echo "🔧 Cài đặt 3proxy..."

apt update -y >/dev/null 2>&1
apt install -y git make gcc ufw curl >/dev/null 2>&1

cd /opt
[ ! -d 3proxy ] && git clone https://github.com/z3APA3A/3proxy.git
cd 3proxy
make -f Makefile.Linux >/dev/null 2>&1

mkdir -p /etc/3proxy/logs
cp ./bin/3proxy /usr/local/bin/
chmod +x /usr/local/bin/3proxy

# Lấy IPv4 public
IPV4=$(curl -4 -s ifconfig.me)

# Lấy interface mạng
IFACE=$(ip route | grep default | awk '{print $5}')

# Lấy prefix IPv6
IPV6_PREFIX=$(ip -6 addr show dev $IFACE | grep 'inet6' | grep -v 'fe80' \
    | awk '{print $2}' | head -n1 | cut -d'/' -f1 | awk -F: '{print $1":"$2":"$3":"$4}')

if [ -z "$IPV6_PREFIX" ]; then
    echo "❌ Không tìm thấy IPv6 prefix."
    exit 1
fi

# Hàm random IPv6
randhex() { printf "%04x" $((RANDOM%65536)); }
gen_ipv6() { echo "${IPV6_PREFIX}:$(randhex):$(randhex):$(randhex):$(randhex)"; }

CONFIG_FILE="/etc/3proxy/3proxy.cfg"
PROXY_TXT="/root/proxy.txt"

cat <<EOF > $CONFIG_FILE
nserver 8.8.8.8
nserver 1.1.1.1
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log /var/log/3proxy/3proxy.log D
auth strong
users admin123:CL:admin123
allow admin123
EOF

> $PROXY_TXT

# Tạo 100 proxy
for port in $(seq 21000 21099); do
    ip6=$(gen_ipv6)
    ip -6 addr add "$ip6/64" dev $IFACE || true
    echo "proxy -6 -n -a -p$port -i$IPV4 -e$ip6" >> $CONFIG_FILE
    echo "$IPV4:$port:admin123:admin123" >> $PROXY_TXT
done

echo "flush" >> $CONFIG_FILE

# Mở port
for port in $(seq 21000 21099); do
    ufw allow $port/tcp >/dev/null 2>&1 || true
done

# Tạo service
cat <<EOF > /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always

[Install]
WantedBy=multi-
