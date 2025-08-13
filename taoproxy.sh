#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
set -e

sleep 1
echo "🔧 Đang cài đặt 3proxy, vui lòng đợi..."

# Cài đặt gói cần thiết
sudo apt update > /dev/null 2>&1
sudo apt install -y git make gcc ufw curl > /dev/null 2>&1

# Clone và build 3proxy
WORKDIR="/tmp/3proxy"
rm -rf "$WORKDIR"
git clone https://github.com/z3APA3A/3proxy.git "$WORKDIR" > /dev/null 2>&1
cd "$WORKDIR"

make -f Makefile.Linux > /dev/null 2>&1

# Tạo thư mục logs và copy binary
sudo mkdir -p /etc/3proxy/logs
sudo cp ./bin/3proxy /usr/local/bin/
sudo chmod +x /usr/local/bin/3proxy

# Mở port firewall
for port in {25000..25499}; do
  sudo ufw allow $port/tcp > /dev/null 2>&1 || true
done

CONFIG_FILE="/etc/3proxy/3proxy.cfg"

echo "⚙️ Đang tạo file cấu hình 3proxy..."
sleep 1

# Lấy prefix IPv6 (4 block đầu)
IPV6_PREFIX=$(ip -6 addr show dev eth0 | grep 'inet6' | grep -v 'fe80' | awk '{print $2}' | head -n1 | cut -d'/' -f1 | awk -F: '{print $1":"$2":"$3":"$4}')
if [ -z "$IPV6_PREFIX" ]; then
  echo "❌ Không tìm thấy IPv6 prefix trên eth0!"
  exit 1
fi

# Hàm random IPv6
randhex() { printf "%04x" $((RANDOM%65536)); }
gen_ipv6() { echo "${IPV6_PREFIX}:$(randhex):$(randhex):$(randhex):$(randhex)"; }

# Ghi file cấu hình
sudo tee $CONFIG_FILE > /dev/null <<EOF
nserver 8.8.8.8
nserver 1.1.1.1
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log /var/log/3proxy/3proxy.log D
auth strong
users admin1:CL:123456
allow admin1
EOF

for port in {25000..254
