#!/bin/bash

echo "Stopping services..."
sudo systemctl stop wifi-dhcp.service
sudo systemctl stop wifi-hostapd.service
sudo systemctl stop wifi-ap.service
sudo systemctl stop wifi-iptables.service

echo "Waiting for interfaces to settle..."
sleep 2

echo "Starting Wi-Fi iptables..."
sudo systemctl start wifi-iptables.service

echo "Starting Wi-Fi Access Point (IP setup)..."
sudo systemctl start wifi-ap.service

echo "Starting hostapd..."
sudo systemctl start wifi-hostapd.service

echo "Starting DHCP server..."
sudo systemctl start wifi-dhcp.service

echo
echo "===== Services Status ====="
systemctl is-active wifi-iptables.service wifi-ap.service wifi-hostapd.service wifi-dhcp.service

