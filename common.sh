#!/bin/bash


set -e


# Install HAProxy script
IP=$(hostname -I | awk '{print $1}')
echo "START [HAProxy] - install haproxy on $IP"
sudo apt update && sudo apt install -y gnupg ca-certificates lsb-release software-properties-common

# Ajouter la clé GPG
sudo mkdir -p /usr/share/keyrings
curl -fsSL https://haproxy.debian.net/bernat.debian.org.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/haproxy.debian.net.gpg > /dev/null

# Ajouter le dépôt HAProxy 2.8 pour Debian Bookworm
echo "deb [signed-by=/usr/share/keyrings/haproxy.debian.net.gpg] http://haproxy.debian.net bookworm-backports-2.8 main" | sudo tee /etc/apt/sources.list.d/haproxy.list

sudo apt update

echo "[INFO] === Versions HAProxy disponibles ==="
apt-cache madison haproxy

# Installer HAProxy version 2.8.x exacte
sudo apt install -y haproxy=2.8.5-1~bpo12+1
sudo systemctl enable haproxy
sudo systemctl restart haproxy

echo "[INFO] === HAProxy installé avec succès ==="
haproxy -v

echo "START [*] - Configuration HAProxy on $IP"
sudo cp provision/haproxy.cfg /etc/haproxy/haproxy.cfg
sudo cp provision/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg
sudo systemctl enable haproxy
sudo systemctl restart haproxy

echo "START [keepalived] - install keepalived on $IP"
sudo apt-get install -y keepalived 
sudo systemctl enable keepalived

echo "START [*] - Configuration keepalived on $IP"
sudo cp provision/keepalived/keepalived-master.conf /etc/keepalived/keepalived.conf
sudo cp provision/keepalived/chk_haproxy.sh /etc/keepalived/chk_haproxy.sh