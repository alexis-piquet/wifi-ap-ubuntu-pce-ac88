PREFIX=/etc/wifi-ap
SYSTEMD_DIR=/etc/systemd/system

requirements:
	@echo "📦 Installation des paquets requis..."
	@if command -v dnf >/dev/null; then \
		echo "🔧 DNF détecté" && \
		sudo dnf install -y hostapd dhcp iproute iptables iptables-services util-linux; \
	elif command -v apt >/dev/null; then \
		echo "🔧 APT détecté" && \
		sudo apt update && \
		sudo apt install -y hostapd isc-dhcp-server iproute2 iptables net-tools netfilter-persistent; \
	elif command -v pacman >/dev/null; then \
		echo "🔧 Pacman détecté" && \
		sudo pacman -Sy --noconfirm hostapd dhcp iproute2 iptables; \
	else \
		echo "❌ Gestionnaire de paquets non pris en charge."; \
		exit 1; \
	fi

	@echo "✅ Paquets installés ou déjà présents."

install:
	@echo "🔍 Recherche des interfaces réseau disponibles..."
	@ls /sys/class/net | grep -v lo
	@echo ""
	@read -p "📡 Interface LAN (Wi-Fi AP) : " LAN_IFACE; \
	read -p "🌐 Interface WAN (accès Internet) : " WAN_IFACE; \
	echo ""; \
	echo "🛠️  Installation avec LAN=$$LAN_IFACE et WAN=$$WAN_IFACE"; \
	\
	echo "🧪 Vérification du chargement du module..."; \
	dmesg | grep brcmfmac | tail -n 5; \
	\
	echo "📝 Génération des fichiers de configuration..."; \
	sudo mkdir -p $(PREFIX); \
	sed "s/{{IFACE}}/$$LAN_IFACE/g" conf/hostapd.conf.in | sudo tee $(PREFIX)/hostapd.conf > /dev/null; \
	[ -f conf/dhcpd.conf ] && sudo cp -v conf/dhcpd.conf $(PREFIX) || echo "⚠️  Fichier conf/dhcpd.conf manquant, DHCP pourrait ne pas fonctionner."; \
	echo "🚀 Installation des scripts dans /usr/local/bin..."; \
	sudo mkdir -p /usr/local/bin; \
	sed "s|{{LAN_IFACE}}|$$LAN_IFACE|g" scripts/start-wifi-ap.sh.in | sudo tee /usr/local/bin/start-wifi-ap.sh > /dev/null; \
	sudo chmod +x /usr/local/bin/start-wifi-ap.sh; \
	sed "s|{{LAN_IFACE}}|$$LAN_IFACE|g; s|{{WAN_IFACE}}|$$WAN_IFACE|g" scripts/wifi-iptables.sh.in | sudo tee /usr/local/bin/wifi-iptables.sh > /dev/null; \
	sudo chmod +x /usr/local/bin/wifi-iptables.sh; \
	sudo cp -v scripts/wifi-ap-status.sh /usr/local/bin/; \
	sudo chmod +x /usr/local/bin/wifi-ap-status.sh; \
	[ -f scripts/wifi-dhcp.sh ] && sudo cp -v scripts/wifi-dhcp.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/wifi-dhcp.sh || true; \
	for f in scripts/*.sh; do \
	    case "$$f" in \
	        scripts/start-wifi-ap.sh.in|scripts/wifi-iptables.sh.in) continue ;; \
	        *) sudo cp -v "$$f" /usr/local/bin/ && sudo chmod +x /usr/local/bin/"$$(basename $$f)" ;; \
	    esac \
	done; \
	\
	echo "📂 Installation des services systemd..."; \
	sudo cp -v services/*.service $(SYSTEMD_DIR); \
	sudo systemctl daemon-reexec; \
	echo "📡 Activation et démarrage des services..."; \
	for svc in wifi-iptables wifi-hostapd wifi-dhcp wifi-ap; do \
		sudo systemctl enable $$svc.service; \
		sudo systemctl start $$svc.service; \
	done; \
	\
	echo "✅ Installation terminée avec succès !"

clean:
	@echo "🧹 Suppression de l'installation..."
	-@sudo systemctl stop wifi-{ap,hostapd,dhcp,iptables}.service
	-@sudo systemctl disable wifi-{ap,hostapd,dhcp,iptables}.service
	@sudo rm -rf $(PREFIX)
	@sudo rm -f $(SYSTEMD_DIR)/wifi-*.service
	@sudo rm -f /usr/local/bin/start-wifi-ap.sh /usr/local/bin/wifi-iptables.sh /usr/local/bin/wifi-ap-status.sh /usr/local/bin/wifi-dhcp.sh
	@sudo systemctl daemon-reexec
	@sudo rm -rf /lib/firmware/brcm/brcmfmac4366c-pcie.*
	@sudo apt update
	@sudo apt install --reinstall linux-firmware
	@sudo modprobe -r brcmfmac
	@sudo modprobe brcmfmac
	@echo "🧼 Nettoyage terminé."

status:
	@echo "📊 État des services Wi-Fi :"
	@systemctl status wifi-iptables.service
	@systemctl status wifi-hostapd.service
	@systemctl status wifi-dhcp.service
	@systemctl status wifi-ap.service

select-iface:
	@echo "📡 Interfaces sans fil disponibles :"
	@ls /sys/class/net | grep -E '^wl'
	@echo ""
	@echo "💡 Pour forcer une interface manuellement :"
	@echo "make install IFACE=wlan0"
