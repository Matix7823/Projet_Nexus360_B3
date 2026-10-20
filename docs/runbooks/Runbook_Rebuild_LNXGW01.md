# Runbook d'Exploitation : Reconstruction de la Passerelle LNXGW01
## Projet Nexus360 - Mission T01 / Site 1 Paris

---

## 1. Contexte & Objectif

La machine **`LNXGW01`** est le nœud d'infrastructure central assurant le routage, le masquerading NAT vers Internet et l'interconnexion chiffrée WireGuard via le Subnet Router Tailscale pour l'ensemble du Site 1 (`10.36.11.0/24`).

Ce runbook fournit la procédure intégrale de reconstruction automatisée / manuelle *from scratch* (Bare Metal ou machine virtuelle) sous **Rocky Linux 10**.

---

## 2. Spécifications Techniques

- **Hostname** : `lnxgw01.ad.nexus360.test`
- **Distribution** : Rocky Linux 10 (ou Rocky Linux 9.x minimal x86_64)
- **Interfaces réseau** :
  - `eth0` (WAN) : Connectée au réseau externe / NAT hyperviseur (DHCP ou IP statique d'accès WAN)
  - `eth1` (LAN) : `10.36.11.1/24` (Passerelle par défaut pour les hôtes du Site 1)
- **Adresse Overlay Tailscale** : `10.36.10.1` (VIP Tailnet)
- **Rôles assurés** :
  - Passerelle par défaut LAN (`10.36.11.1`)
  - Routeur IPv4 (`net.ipv4.ip_forward = 1`)
  - Traduction d'adresses réseau (NAT Masquerade via `firewalld`)
  - Routeur de sous-réseau Tailscale (Subnet Router annonçant `10.36.11.0/24`)

---

## 3. Procédure de Déploiement & Configuration Pas-à-Pas

### Étape 3.1 : Définition du Hostname et Mise à Jour Système
Se connecter en `root` sur la console de la machine :
```bash
# Définition du FQDN
hostnamectl set-hostname lnxgw01.ad.nexus360.test

# Mise à jour des paquets de base
dnf upgrade -y

# Installation des utilitaires réseau et de diagnostic
dnf install -y epel-release
dnf install -y vim curl wget git net-tools bind-utils iptables tcpdump iproute firewalld
```

---

### Étape 3.2 : Configuration des Interfaces Réseau via NetworkManager (`nmcli`)

Identifier les noms des interfaces (`ip link`) puis configurer les connexions :

```bash
# 1. Interface WAN (eth0) - Attribution DHCP
nmcli connection modify eth0 \
    connection.autoconnect yes \
    ipv4.method auto

# 2. Interface LAN Site 1 (eth1) - IP Statique 10.36.11.1/24 (SANS passerelle sur le LAN !)
nmcli connection modify eth1 \
    connection.autoconnect yes \
    ipv4.method manual \
    ipv4.addresses 10.36.11.1/24 \
    ipv4.gateway "" \
    ipv4.dns ""

# 3. Réactivation des interfaces pour appliquer les changements
nmcli connection up eth0
nmcli connection up eth1

# 4. Vérification de la configuration
ip addr show
ip route show
```
*Vérification* : La route par défaut (`default via ...`) doit impérativement pointer vers la passerelle de l'interface WAN `eth0`.

---

### Étape 3.3 : Activation du Routage Kernel IPv4 (IP Forwarding)

Activer de manière permanente le routage de paquets entre interfaces :

```bash
cat << 'EOF' > /etc/sysctl.d/99-ipforward.conf
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv6.conf.all.forwarding = 0
EOF

# Application immédiate des paramètres sysctl
sysctl --system

# Vérification
sysctl net.ipv4.ip_forward
# Doit renvoyer : net.ipv4.ip_forward = 1
```

---

### Étape 3.4 : Configuration du Pare-Feu et du NAT Masquerading (`firewalld`)

Configurer les zones de confiance et le masquerading NAT :

```bash
# Démarrage et activation au boot de firewalld
systemctl enable --now firewalld

# Affectation de l'interface WAN (eth0) à la zone external (masquerade automatique)
firewall-cmd --permanent --zone=external --add-interface=eth0

# Affectation de l'interface LAN (eth1) à la zone internal
firewall-cmd --permanent --zone=internal --add-interface=eth1

# Activation explicite du NAT Masquerade sur la zone external
firewall-cmd --permanent --zone=external --add-masquerade

# Autorisation du routage entre la zone internal et external
firewall-cmd --permanent --zone=internal --add-forward

# Autorisation du trafic SSH d'administration sur le LAN
firewall-cmd --permanent --zone=internal --add-service=ssh

# Rechargement des règles de filtrage
firewall-cmd --reload

# Contrôle des zones actives
firewall-cmd --get-active-zones
firewall-cmd --zone=external --query-masquerade
# Doit renvoyer : yes
```

---

### Étape 3.5 : Installation & Configuration du Subnet Router Tailscale

Installer le client officiel Tailscale pour Rocky Linux / RHEL :

```bash
# Ajout du dépôt officiel Tailscale
dnf config-manager --add-repo https://pkgs.tailscale.com/stable/rhel/9/tailscale.repo

# Installation du paquet
dnf install -y tailscale

# Activation du service d'arrière-plan
systemctl enable --now tailscaled

# Optimisation UDP et déchargement réseau pour Tailscale WireGuard
NETDEV=$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")
ethtool -K $NETDEV rx-udp-gro-forwarding on rx-gro-list off || true
```

Démarrer l'agent Tailscale en publiant la route du Site 1 :
```bash
# Authentification et annonce de route vers le Tailnet d'entreprise
tailscale up \
    --advertise-routes=10.36.11.0/24 \
    --snat-subnet-routes=false \
    --accept-routes
```
*Note* : Se connecter sur l'URL affichée par le CLI ou utiliser une Auth Key d'administration. Sur la console Tailscale Admin, approuver la route `10.36.11.0/24` pour la machine `lnxgw01`.

---

## 4. Tests & Validation du Rétablissement

Depuis la passerelle `LNXGW01` :
```bash
# 1. Test de la connectivité Internet
ping -c 3 1.1.1.1

# 2. Test de la résolution DNS publique
nslookup google.com

# 3. Test de ping vers le contrôleur de domaine SRV-DC01
ping -c 3 10.36.11.10

# 4. Statut du démon Tailscale et des routes annoncées
tailscale status
tailscale ip -4
```

Depuis le client de test Windows 11 (`CLI-WIN01`) ou le contrôleur (`SRV-DC01`) :
```powershell
# 1. Vérification de la passerelle par défaut
Get-NetRoute -DestinationPrefix "0.0.0.0/0"
# NextHop doit être 10.36.11.1

# 2. Test du ping vers la passerelle
Test-Connection -ComputerName 10.36.11.1 -Count 2

# 3. Test de sortie Internet via NAT
Test-Connection -ComputerName 8.8.8.8 -Count 2
Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing | Select-Object StatusCode

# 4. Test d'interconnexion vers le Site 2 à travers Tailscale
Test-Connection -ComputerName 10.36.12.11 -Count 2
```

---

## 5. Résolution d'Incidents Fréquents (Troubleshooting)

| Symptôme | Cause Probable | Action Corrective |
| :--- | :--- | :--- |
| **Les clients LAN n'accèdent pas à Internet** | IP Forwarding désactivé ou masquerade non actif | Vérifier `sysctl net.ipv4.ip_forward` (= 1). Vérifier `firewall-cmd --zone=external --query-masquerade`. |
| **Passerelle injoignable sur le LAN** | L'interface `eth1` est éteinte ou a récupéré une IP DHCP | Vérifier `nmcli con show eth1` et forcer `nmcli con up eth1`. |
| **Le Site 2 n'atteint pas les machines du Site 1** | Route de sous-réseau non approuvée dans Tailscale Admin | Ouvrir `https://login.tailscale.com/admin/machines`, localiser `lnxgw01`, cliquer sur *Edit route settings* et activer `10.36.11.0/24`. |
| **Conflit de route par défaut** | `eth1` a été configurée par erreur avec une passerelle | Retirer le gateway sur `eth1` via `nmcli con mod eth1 ipv4.gateway ""`. Seule `eth0` doit avoir une passerelle. |
