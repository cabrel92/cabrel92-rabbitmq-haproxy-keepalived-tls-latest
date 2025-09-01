#!/bin/bash


if systemctl is-active --quiet haproxy; then
    exit 0
else
    exit 1
fi
