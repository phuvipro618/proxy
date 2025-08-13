#!/bin/bash

IPV4=$(curl -4 -s ifconfig.me)
USER="user"
PASS="pass"
START_PORT=30000
NUM_PROXIES=500
CONFIG_FILE="/home/ubuntu/3proxy/3proxy.cfg"
OUTPUT_FILE="/root/proxy.txt"

# Lấy interface thực tế (AWS thường là enX0)
IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n 1)

# Lấy IPv6 prefix /64
IPV6_PREFIX=$(ip -6 addr show dev "$IFACE" scope global | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=/64)')
if [[ -z "$IPV6_PREFIX" ]]; then
    echo "❌ Không tìm thấy IPv6 prefix trên $IFACE!"
    exit 1
fi

echo "🔧 Đang cài đặt 3proxy..."
sudo apt update -y > /dev/null 2>&1
sudo apt install gcc make git -y > /dev/null 2>&1

git clone https://github.com/z3APA3A/3proxy.git /tmp/3proxy
cd /tmp/3proxy
make -f Makefile.Linux
sudo mkdir -p /home/ubuntu/3proxy
sudo cp src/3proxy /home/ubuntu/3proxy/

echo "⚙️ Đang tạo file cấu hình 3proxy..."
cat <<EOF | sudo tee $CONFIG_FILE > /dev/null
daemon
maxconn 500
nserver 1.1.1.1
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
users $USER:CL:$PASS
auth strong
EOF

sudo rm -f $OUTPUT_FILE

for ((i=0; i<$NUM_PROXIES; i++)); do
    PORT=$((START_PORT + i))
    IPV6=$(printf "%s:%x:%x:%x:%x" "$IPV6_PREFIX" $RANDOM $RANDOM $RANDOM $RANDOM)
    echo "proxy -6 -n -a -p$PORT -i$IPV4 -e$IPV6" | sudo tee -a $CONFIG_FILE > /dev/null
    echo "$IPV4:$PORT:$USER:$PASS" | sudo tee -a $OUTPUT_FILE > /dev/null
done

echo "✅ Hoàn tất! Đã tạo $NUM_PROXIES IPv6 proxy từ cổng $START_PORT."
echo "📂 Danh sách proxy lưu tại: $OUTPUT_FILE"

sudo pkill 3proxy || true
sudo /home/ubuntu/3proxy/3proxy $CONFIG_FILE
