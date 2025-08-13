#!/bin/bash
# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Script này cần quyền root. Vui lòng chạy với sudo."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
set -e
sleep 1
echo "🔧 Đang cài đặt 3proxy, vui lòng đợi..."

# Cập nhật và cài đặt gói cần thiết
apt update -qq
apt install -y git make gcc curl > /dev/null 2>&1 || true
sleep 1

# Clone 3proxy
cd /opt || exit
git clone https://github.com/z3APA3A/3proxy.git 2>/dev/null || true
cd 3proxy || exit

make -f Makefile.Linux > /dev/null 2>&1

mkdir -p /etc/3proxy/logs
cp ./bin/3proxy /usr/local/bin/
chmod +x /usr/local/bin/3proxy

# Tắt firewall để tránh chặn port proxy
ufw disable > /dev/null 2>&1
systemctl stop ufw > /dev/null 2>&1
systemctl mask ufw > /dev/null 2>&1

# Cấu hình 3proxy
CONFIG_FILE="/etc/3proxy/3proxy.cfg"
echo "⚙️ Đang tạo file cấu hình 3proxy..."
sleep 1

# Interface AWS EC2 mặc định
NET_IF=$(ip route | grep '^default' | awk '{print $5}')

# Lấy prefix IPv6 (4 block đầu)
IPV6_PREFIX=$(ip -6 addr show dev $NET_IF | grep 'scope global' | awk '{print $2}' | head -n1 | cut -d'/' -f1 | awk -F: '{print $1":"$2":"$3":"$4}')

if [ -z "$IPV6_PREFIX" ]; then
  echo "❌ Không tìm thấy IPv6 prefix trên $NET_IF!"
  exit 1
fi

# Hàm sinh IPv6 ngẫu nhiên
randhex() { printf "%04x" $((RANDOM%65536)); }
gen_ipv6() { echo "${IPV6_PREFIX}:$(randhex):$(randhex):$(randhex):$(randhex)"; }

# Cấu hình cơ bản
cat <<EOF > $CONFIG_FILE
nserver 8.8.8.8
nserver 1.1.1.1
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log /var/log/3proxy/3proxy.log D
auth strong
users admin123:CL:pas123456
allow admin123
EOF

# Chọn loại proxy: "http" hoặc "socks5"
PROXY_TYPE="http"

# Sinh proxy port 22000-22050
for port in {22000..22050}; do
  ip6=$(gen_ipv6)
  ip -6 addr add "$ip6/64" dev $NET_IF 2>/dev/null || true
  if [ "$PROXY_TYPE" = "socks5" ]; then
    echo "socks -6 -n -a -p$port -i0.0.0.0 -e$ip6" >> $CONFIG_FILE
  else
    echo "proxy -6 -n -a -p$port -i0.0.0.0 -e$ip6" >> $CONFIG_FILE
  fi
done

echo "flush" >> $CONFIG_FILE

# Tạo systemd service
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
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable 3proxy
systemctl restart 3proxy

echo "✅ Cài đặt hoàn tất!"
echo "🔹 Proxy chạy trên port 22000-22050 với IPv6 trên interface $NET_IF"
