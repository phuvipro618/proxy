#!/bin/bash

TOTAL_IP=500  # Số lượng IPv6 muốn tạo

echo "🔧 Đang cài đặt 3proxy, vui lòng đợi..."
sudo apt update -y && sudo apt install -y gcc make git curl

# Clone 3proxy nếu chưa có
if [ ! -d "/home/ubuntu/3proxy" ]; then
    git clone https://github.com/z3APA3A/3proxy.git /home/ubuntu/3proxy
fi
cd /home/ubuntu/3proxy && make -f Makefile.Linux

# Tìm interface
IFACE=$(ip route | grep '^default' | awk '{print $5}')
echo "🌐 Interface: $IFACE"

# Lấy IPv6 prefix (4 block đầu)
IPV6_FULL=$(ip -6 addr show dev "$IFACE" scope global | grep -v "temporary" | awk '/inet6/ {print $2}' | head -n 1)
if [ -z "$IPV6_FULL" ]; then
    echo "❌ Không tìm thấy IPv6 trên $IFACE!"
    exit 1
fi
PREFIX=$(echo $IPV6_FULL | cut -d':' -f1-4)
echo "✅ IPv6 prefix: $PREFIX::/64"

# Hàm tạo chuỗi hex ngẫu nhiên 4 block
rand_hex() {
    for i in {1..4}; do
        printf "%x" $((RANDOM%65536))
        if [ $i -lt 4 ]; then printf ":"; fi
    done
}

# Xóa IPv6 cũ để tránh trùng
sudo ip -6 addr flush dev $IFACE

# Tạo file cấu hình 3proxy
cat <<EOL > /home/ubuntu/3proxy/3proxy.cfg
daemon
maxconn 200
nserver 1.1.1.1
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush

auth none
allow * * * *
EOL

# Tạo danh sách proxy + add IPv6 vào interface
PORT_START=30000
MY_IPV4=$(curl -s ipv4.icanhazip.com)

for i in $(seq 1 $TOTAL_IP); do
    IP6="${PREFIX}:$(rand_hex)"
    PORT=$((PORT_START + i))
    sudo ip -6 addr add "$IP6/64" dev $IFACE
    echo "proxy -6 -n -a -p$PORT -i$MY_IPV4 -e$IP6" >> /home/ubuntu/3proxy/3proxy.cfg
done

# Tạo service
cat <<EOL | sudo tee /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/home/ubuntu/3proxy/bin/3proxy /home/ubuntu/3proxy/3proxy.cfg
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Khởi động dịch vụ
sudo systemctl daemon-reload
sudo systemctl enable 3proxy
sudo systemctl restart 3proxy

echo "🎉 Hoàn tất! Đã tạo $TOTAL_IP IPv6 proxy từ cổng $PORT_START."
