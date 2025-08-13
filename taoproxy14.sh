#!/bin/bash
set -e
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

WORKDIR="/home/cloudfly"
WORKDATA="${WORKDIR}/data.txt"
sudo mkdir -p "$WORKDIR"
sudo chown $USER:$USER "$WORKDIR"
cd "$WORKDIR"

# -----------------------------
# Hàm sinh password ngẫu nhiên
# -----------------------------
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c12
    echo
}

# -----------------------------
# Hàm sinh IPv6
# -----------------------------
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# -----------------------------
# Cài dependencies
# -----------------------------
sudo apt update -y
sudo apt install -y wget zip curl net-tools libarchive-tools build-essential gcc make

# -----------------------------
# Lấy IP
# -----------------------------
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
echo "Internal IP = ${IP4}, External subnet for IPv6 = ${IP6}"

# -----------------------------
# Nhập FIRST_PORT
# -----------------------------
while :; do
  read -p "Enter FIRST_PORT between 21000 and 61000: " FIRST_PORT
  [[ $FIRST_PORT =~ ^[0-9]+$ ]] || { echo "Enter a valid number"; continue; }
  if ((FIRST_PORT >= 21000 && FIRST_PORT <= 61000)); then
    break
  else
    echo "Number out of range, try again"
  fi
done
LAST_PORT=$(($FIRST_PORT + 750))
echo "LAST_PORT is $LAST_PORT. Continue..."

# -----------------------------
# Sinh dữ liệu proxy
# -----------------------------
seq $FIRST_PORT $LAST_PORT | while read port; do
    echo "user$port/$(random)/$IP4/$port/$(gen64 $IP6)"
done >"$WORKDATA"

# -----------------------------
# Tạo script ifconfig IPv6
# -----------------------------
awk -F "/" '{print "sudo ip -6 addr add "$5"/64 dev eth0"}' "$WORKDATA" >"$WORKDIR/boot_ifconfig.sh"
chmod +x "$WORKDIR/boot_ifconfig.sh"

# -----------------------------
# Tải và build 3proxy mới
# -----------------------------
echo "Downloading latest 3proxy..."
URL="https://github.com/z3APA3A/3proxy/archive/refs/heads/master.tar.gz"
wget -qO- $URL | bsdtar -xvf-

cd 3proxy-master
make -f Makefile.Linux
sudo mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
sudo cp bin/* /usr/local/etc/3proxy/bin/
cd "$WORKDIR"

# -----------------------------
# Tạo config 3proxy
# -----------------------------
awk -F "/" 'BEGIN{print "daemon\nmaxconn 2000\nauth strong"} {print "users "$1":CL:"$2"\nproxy -6 -n -a -p"$4" -i"$3" -e"$5"\nflush"}' "$WORKDATA" \
    > /usr/local/etc/3proxy/3proxy.cfg
sudo chmod 644 /usr/local/etc/3proxy/3proxy.cfg

# -----------------------------
# Chạy IPv6 ifconfig và 3proxy
# -----------------------------
bash "$WORKDIR/boot_ifconfig.sh"
sudo /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &

# -----------------------------
# Tạo file proxy.txt
# -----------------------------
cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF

# -----------------------------
# Upload proxy.txt
# -----------------------------
if [[ -f proxy.txt ]]; then
    curl -F "file=@proxy.txt" https://file.io
else
    echo "proxy.txt not found!"
fi

echo "3proxy setup completed successfully!"
