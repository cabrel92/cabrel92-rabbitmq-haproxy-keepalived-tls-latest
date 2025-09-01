### Ce projet met en place un cluster RabbitMQ en haute disponibilité sur des VMs provisionnées avec Vagrant et configurées via Ansible.
L’architecture comprend :

RabbitMQ (3 nœuds en cluster, stockage distribué)

HAProxy (équilibrage de charge des connexions AMQP et Management UI)

Keepalived (VIP pour la tolérance aux pannes du load balancer)

Metricbeat (collecte de métriques RabbitMQ et OS vers Elastic ou Prometheus)

Filebeat (collecte et envoi des logs vers ELK)

Ce dépôt fournit l’infrastructure et les configurations nécessaires pour un déploiement reproductible.

###



### configuration de filebeat
#### Après installation de filebeat activer le module dans rabbitmq
``` bash
    sudo filebeat modules enable rabbitmq
```


