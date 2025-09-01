#!/bin/bash
# provision-elk.sh


set -e


echo "[1]: Installation ELK Stack pour l'environnement de développement"
RABBITMQ_NODES=("192.168.1.10" "192.168.1.11" "192.168.1.12")  # Nodes RabbitMQ
ELK_SERVER_IP="192.168.59.43"  # IP du serveur ELK

wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt-get update
sudo apt-get install -y elasticsearch logstash kibana

echo "[2]: Configuration simplifiée d'Elasticsearch "
cat > /etc/elasticsearch/elasticsearch.yml << EOF
cluster.name: rabbitmq-cluster-dev
node.name: elk-dev-node
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
xpack.security.enabled: false  # Désactivé pour simplifier le dev
EOF

echo " [3]: Configuration JVM pour environnement de dev (moins de RAM)"
echo "-Xms1g" > /etc/elasticsearch/jvm.options.d/heap.options # in production think of using 8 GB or more
echo "-Xmx1g" >> /etc/elasticsearch/jvm.options.d/heap.options

echo " [4]: Configuration Kibana"
cat > /etc/kibana/kibana.yml << EOF
server.host: "0.0.0.0"
server.port: 5601
elasticsearch.hosts: ["http://localhost:9200"]
EOF

echo "[5]: Démarrage des services"
sudo systemctl enable elasticsearch logstash kibana
sudo systemctl start elasticsearch

# Attendre qu'Elasticsearch soit prêt
sleep 30

sudo systemctl start logstash kibana

echo "ELK Stack installé et configuré pour le développement"
echo "Kibana accessible sur : http://$ELK_SERVER_IP:5601"
