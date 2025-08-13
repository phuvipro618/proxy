#!/bin/bash
set -e

WORKDIR="/home/cloudfly"
mkdir -p $WORKDIR
cd $WORKDIR

# 1️⃣ Cài phụ thuộc
sudo apt update
sudo apt install -y wget curl gcc-9 g++-9 make build-essential net-tools iproute2 iptables iptables-persistent libarchive-tools zip

# 2️⃣ Tải và build 3proxy mới nhất
echo "[INFO] Downloading 3proxy..."
wget -qO- https://github.com/3proxy/3proxy/archive/refs/heads/master.zip | bsdtar -xf-
cd 3proxy-master
echo "[INFO] Building 3proxy..."
make -f Makefile.Linux CC=gcc-9 CXX=g++-9

# Copy binary
sudo mkdir -p /usr/local/etc/3proxy/bin
sudo cp src/3proxy /usr/local/etc/3proxy/bin/

# 3️⃣ Tạo config 3proxy
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d:)

PROXY_START_PORT=21000
PROXY_END_PORT=21010
USER_PASS="user1:CL:pass1"

sudo tee /usr/local/etc/3proxy/3proxy.cfg > /dev/null <<EOF
daemon
maxconn 2000
nserver 1.1.1.1
nserver 8.8.8.8
nserver 2001:4860:4860::8888
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456
flush
auth strong
users $USER_PASS
EOF

# Thêm các proxy ports
for port in $(seq $PROXY_START_PORT $PROXY_END_PORT); do
    echo "proxy -n -a -p$port -i$IP4 -e$IP6" | sudo tee -a /usr/local/etc/3proxy/3proxy.cfg > /dev/null
done

# 4️⃣ Tạo systemd service
sudo tee /etc/systemd/system/3proxy.service > /dev/null <<EOF
[Unit]
Description=3Proxy Proxy Server
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
LimitNOFILE=65535
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable 3proxy

# 5️⃣ Mở firewall cho các cổng proxy
for port in $(seq $PROXY_START_PORT $PROXY_END_PORT); do
    sudo iptables -I INPUT -p tcp --dport $port -j ACCEPT
    sudo ip6tables -I INPUT -p tcp --dport $port -j ACCEPT
done
sudo netfilter-persistent save

# 6️⃣ Chạy 3proxy
echo "[INFO] Starting 3proxy..."
sudo systemctl restart 3proxy
sudo systemctl status 3proxy --no-pager

echo "[DONE] 3proxy setup complete. IPv4: $IP4, IPv6 prefix: $IP6, ports: $PROXY_START_PORT-$PROXY_END_PORT"
