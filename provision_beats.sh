#!/bin/bash


# Filebeat
wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.14.0-amd64.deb

# Metricbeat
wget https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-8.14.0-amd64.deb


# Installation de Filebeat et Metricbeat
sudo dpkg -i filebeat-8.14.0-amd64.deb
sudo dpkg -i metricbeat-8.14.0-amd64.deb

# fixer les dependances manquantes 
sudo apt-get install -f

#  enable Filebeat and Metricbeat
sudo systemctl enable filebeat
sudo systemctl start filebeat

sudo systemctl enable metricbeat
sudo systemctl start metricbeat
