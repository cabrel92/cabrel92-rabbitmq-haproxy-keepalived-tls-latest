#!/bin/bash


# Vérifie que le port est ouvert (par défaut 5672 pour AMQP ou 15672 pour HTTP)
PORT_OK=$(ss -lntp | grep -q ':5672' && echo "1" || echo "0")

# Vérifie que le service RabbitMQ répond via la CLI (vérifie que le cluster est up)
RABBIT_OK=$(rabbitmqctl status 2>/dev/null | grep -q '{pid,' && echo "1" || echo "0")

if [ "$PORT_OK" -eq 1 ] && [ "$RABBIT_OK" -eq 1 ]; then
  exit 0
else
  exit 1
fi
