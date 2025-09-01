#!/bin/bash
# install_rabbitmq.sh

IP=$(hostname -I | awk '{print $1}')
VERSION="3.13.7"
echo "START -install rabbitmq "$IP

#############################################################
 

#############################################################

echo "START -install rabbitmq and erlang using official repository file "$IP
echo " [1]:  install Modern Erlang/OTP release repository  | Provides modern RabbitMQ releases"
apt-get update -q -y >/dev/null
sudo apt-get install curl gnupg apt-transport-https -y
curl -1sLf "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" | sudo gpg --dearmor | sudo tee /usr/share/keyrings/com.rabbitmq.team.gpg > /dev/null


sudo tee /etc/apt/sources.list.d/rabbitmq.list <<EOF
## Modern Erlang/OTP release repository  

deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-erlang/debian/bookworm bookworm main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-erlang/debian/bookworm bookworm main

## Provides modern RabbitMQ releases

deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb1.rabbitmq.com/rabbitmq-server/debian/bookworm bookworm main
deb [arch=amd64 signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://deb2.rabbitmq.com/rabbitmq-server/debian/bookworm bookworm main

EOF
echo "[2]: install erlang and rabbitmq-server"

sudo apt-get update -q -y >/dev/null

## Install Erlang packages
sudo apt-get install -y erlang-base \
                        erlang-asn1 erlang-crypto erlang-eldap erlang-ftp erlang-inets \
                        erlang-mnesia erlang-os-mon erlang-parsetools erlang-public-key \
                        erlang-runtime-tools erlang-snmp erlang-ssl \
                        erlang-syntax-tools erlang-tftp erlang-tools erlang-xmerl

## Install rabbitmq-server and its dependencies
sudo apt-get install rabbitmq-server -y --fix-missing

# Install HAPRoxy
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
sudo cp /vagrant/haproxy.cfg /etc/haproxy/haproxy.cfg
sudo cp /vagrant/chk_rabbitmq.sh /etc/keepalived/chk_rabbitmq.sh
sudo cp /vagrant/chk_haproxy.sh /etc/keepalived/chk_haproxy.sh
sudo systemctl enable haproxy
sudo systemctl restart haproxy

# Installation de keepalived
echo "START [keepalived] - install keepalived on $IP"
sudo apt-get install -y keepalived
sudo systemctl enable keepalived

if [[ "$1" == "leader" && "$2" == "192.168.59.40" ]]; then
    echo "START [*] - Configuration keepalived on $IP"
    sudo cp /vagrant/keepalived-master.conf /etc/keepalived/keepalived.conf
    sudo cp /vagrant/chk_haproxy.sh /etc/keepalived/chk_haproxy.sh
    sudo chmod +x /etc/keepalived/chk_haproxy.sh
    sudo systemctl restart keepalived

elif [[ "$1" == "follower" && "$2" == "192.168.59.41" ]]; then
    echo "START [*] - Configuration keepalived on $IP"
    sudo cp /vagrant/keepalived-backup1.conf /etc/keepalived/keepalived.conf
    sudo cp /vagrant/chk_haproxy.sh /etc/keepalived/chk_haproxy.sh
    sudo chmod +x /etc/keepalived/chk_haproxy.sh
    sudo systemctl restart keepalived

elif [[ "$1" == "follower" && "$2" == "192.168.59.42" ]]; then
    echo "START [*] - Configuration keepalived on $IP"
    sudo cp /vagrant/keepalived-backup2.conf /etc/keepalived/keepalived.conf
    sudo cp /vagrant/chk_haproxy.sh /etc/keepalived/chk_haproxy.sh
    sudo chmod +x /etc/keepalived/chk_haproxy.sh
    sudo systemctl restart keepalived
fi

# Installation de Filebeat et de Metricbeat sur les noeuds du cluster RabbitMQ
echo "START [Filebeat] - install Filebeat on $IP"
sudo apt-get install -y filebeat
sudo systemctl enable filebeat
sudo systemctl start filebeat 

# Installation de Metricbeat sur les noeuds du cluster RabbitMQ
echo "START [Metricbeat] - install Metricbeat on $IP"
sudo apt-get install -y metricbeat
sudo systemctl enable metricbeat
sudo systemctl start metricbeat


# configuration minimale de rabbitmq sur tous les serveurs: management + cookie
echo "[3]: configuration minimale de rabbitmq sur tous les serveurs: management + cookie"
rabbitmq-plugins enable rabbitmq_management
rabbitmq-plugins enable rabbitmq_consistent_hash_exchange
rabbitmq-plugins enable rabbitmq_prometheus
echo "NZHINUSOFTCMRFRANCE" | sudo tee /var/lib/rabbitmq/.erlang.cookie
echo "listeners.tcp.1 = 0.0.0.0:5672" | sudo tee -a /etc/rabbitmq/rabbitmq.conf
echo "management.tcp.port = 15672" | sudo tee -a /etc/rabbitmq/rabbitmq.conf
systemctl restart rabbitmq-server

if [[ "$1" == "leader" ]]; then
    echo "[4]: definir l'utilisateur par defaut"
    rabbitmqctl add_user nzhinusoft nzhinusoft
    #rabbitmctl 
    rabbitmqctl set_permissions -p / nzhinusoft ".*" ".*" ".*"
    rabbitmqctl set_user_tags nzhinusoft administrator
    rabbitmqctl delete_user guest
fi

# check and add follower
if [[ "$1" == "follower" ]]; then
echo "[5]: join leader"
    rabbitmqctl stop_app
    rabbitmqctl join_cluster rabbit@rabbit-node1
    rabbitmqctl start_app
fi

