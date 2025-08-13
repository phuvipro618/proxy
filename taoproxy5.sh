#!/bin/bash
# ==========================
# Script tạo proxy IPv6 AWS
# ==========================

INSTANCE_ID="i-xxxxxxxxxxxxxxxxx" # thay bằng ID thật
IPV6_COUNT=500
PORT_START=30000

echo "[INFO] Đang gán $IPV6_COUNT IPv6 cho instance $INSTANCE_ID..."

# Chạy Python để gán IPv6
python3 <<EOF
import boto3

INSTANCE_ID = "$INSTANCE_ID"
IPV6_COUNT = $IPV6_COUNT

ec2 = boto3.client('ec2')
res = ec2.describe_instances(InstanceIds=[INSTANCE_ID])
eni_id = res['Reservations'][0]['Instances'][0]['NetworkInterfaces'][0]['NetworkInterfaceId']

assign = ec2.assign_ipv6_addresses(
    NetworkInterfaceId=eni_id,
    Ipv6AddressCount=IPV6_COUNT
)

with open("/root/proxy_ipv6.txt", "w") as f:
    port = $PORT_START
    for ip in assign['AssignedIpv6Addresses']:
        f.write(f"{ip}:{port}\n")
        port += 1

print(f"[OK] Đã lưu danh sách IPv6 vào /root/proxy_ipv6.txt")
EOF

# Sau bước này /root/proxy_ipv6.txt có dạng:
# 2406:da18:2ed:c800::1234:30000
# 2406:da18:2ed:c800::abcd:30001
