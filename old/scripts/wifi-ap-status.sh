#!/bin/bash

# Fonction pour afficher le statut avec couleurs et emojis
status_output() {
    local service=$1
    local service_name=$2
    local emoji=$3

    # Titre du service avec emoji
    echo -e "\n\033[1;34m$emoji ===== $service_name ($service) ===== $emoji\033[0m"

    # Statut du service avec couleurs
    systemctl status --no-pager $service | \
    sed -e 's/\(Active:.*\)/\033[1;32m\1\033[0m/' -e 's/\(Loaded:.*\)/\033[1;33m\1\033[0m/' | \
    head -n 10
}

# Afficher les statuts des services avec couleur et emojis
status_output "wifi-ap.service" "Wi-Fi IP Setup" "🌐"
status_output "wifi-hostapd.service" "Hostapd" "📡"
status_output "wifi-dhcp.service" "DHCP Server" "🖧"
status_output "wifi-iptables.service" "IPTables Rules" "🔒"

