# Baseline de Durcissement de Sécurité Hybride (ANSSI / CIS Level 2)
## Projet Nexus360 - Promotion B3 - Mission T01 (Exigence B5)

| Métadonnée | Valeur |
| :--- | :--- |
| **Projet** | Nexus360 - Infrastructure Multi-Sites Résiliente |
| **Référence Exigence** | **Exigence B5** - Durcissement de sécurité de niveau élevé |
| **Cadres de référence** | **ANSSI** (Recommandations GNU/Linux, Guide de sécurisation Active Directory) <br/> **CIS Benchmarks** (Rocky Linux 9/10 v1.0, Windows Server 2022/2025 v2.0) |
| **Version** | v1.0.0 |
| **Statut** | Validé / En vigueur |
| **Dernière révision** | 20 octobre 2026 |

---

## 1. Contexte & Périmètre d'Application

Dans le cadre du déploiement de l'infrastructure d'entreprise **Nexus360**, l'Exigence B5 impose un durcissement approfondi de tous les nœuds hybrides (Linux et Windows Server) afin d'annihiler les vecteurs d'attaque courants : mouvements latéraux, attaques par rebond, relais NTLM, empoisonnement LLMNR/NBT-NS et compromission des accès distants.

Le durcissement s'applique à :
- **Passerelle & Routeur de sous-réseau** : `LNXGW01` (`10.36.11.1` / VIP Tailscale `10.36.10.1`, Rocky Linux 10)
- **Contrôleur de Domaine Principal** : `SRV-DC01` (`10.36.11.10`, Windows Server 2025 Datacenter)
- **Serveurs d'Infrastructure Linux** :
  - `LNX-OPS01` / `nx-ops-srv01` (`10.36.11.25` / `10.36.10.20`, Bastion & Contrôleur Ansible)
  - `LNX-WEB01` / `nx-web-srv01` (`10.36.11.20` / `10.36.30.20`, Serveur Web applicatif)
  - `LNX-MON01` / `nx-mon-srv01` (`10.36.11.30` / `10.36.10.30`, Supervision Prometheus/Grafana)
- **Postes et Serveurs Membres** : `CLI-WIN01` et serveurs Tier 1 du domaine `ad.nexus360.test`.

---

## 2. Durcissement & PKI SSH sur les Serveurs Linux

### 2.1. Architecture PKI SSH & Bastion d'Administration
L'administration des hôtes Linux est exclusivement autorisée depuis le bastion dédié `LNX-OPS01`.
- **Type de clé** : Algorithme à clé publique **Ed25519** (courbe d'Edwards Curve25519, conforme aux recommandations ANSSI RGS B1/B2 et OpenSSH standard).
- **Emplacement clé privée** : `~/.ssh/id_ed25519_admin` sur `LNX-OPS01` (droits `0600`, non exportable).
- **Emplacement clé publique** : Distribuée automatiquement dans `~/.ssh/authorized_keys` des comptes autorisés sur `LNXGW01`, `LNX-WEB01`, `LNX-MON01`.
- **Authentification par mot de passe** : Totalement interdite au niveau du démon `sshd`.

### 2.2. Configuration OpenSSH Durcie (`/etc/ssh/sshd_config.d/99-hardening.conf`)
Le rôle Ansible `hardening_ssh` déploie le fichier de configuration modulaire suivant :

```sshconfig
# ==============================================================================
# Nexus360 - SSH Daemon Hardening Configuration (ANSSI / CIS Level 2)
# Exigence B5 - Deploiement Securise du Site 1 & Infrastructure Globale
# ==============================================================================

# 1. Controle d'acces et restrictions d'authentification
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
X11Forwarding no
MaxAuthTries 3
AllowGroups g_ssh_admins g_exploitation

# 2. Cryptographie durcie (KEX, Ciphers, MACs conformes ANSSI)
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.org
MACs hmac-sha2-512-etm@openssh.com

# 3. Parametres de robustesse et d'audit de session
LogLevel VERBOSE
ClientAliveInterval 300
ClientAliveCountMax 2
MaxSessions 5
IgnoreRhosts yes
HostbasedAuthentication no
PermitEmptyPasswords no
PermitUserEnvironment no
```

### 2.3. Choix Cryptographiques SSH Justifiés

| Composant Cryptographique | Algorithmes Retenus | Justification Sécurité (ANSSI / CIS) |
| :--- | :--- | :--- |
| **Signature & Clé d'hôte** | `ssh-ed25519` | Résistance maximale aux attaques par canaux auxiliaires, signature rapide, pas de constantes faibles. |
| **Échange de clés (KEX)** | `curve25519-sha256`, `curve25519-sha256@libssh.org`, `diffie-hellman-group16-sha512` | Élimination de SHA-1 et des groupes DH inférieurs à 2048 bits (DH group 1 et group 14 obsolètes). |
| **Chiffrement symétrique (Ciphers)** | `chacha20-poly1305@openssh.com`, `aes256-gcm@openssh.org` | Chiffrement authentifié (AEAD). Élimination totale de CBC (vulnérable aux attaques Padding Oracle) et de Blowfish/3DES. |
| **Codes d'authentification (MACs)** | `hmac-sha2-512-etm@openssh.com` | Encrypt-then-MAC évitant toute attaque d'intégrité avant déchiffrement. |

---

## 3. Hardening Système Linux (Noyau, SELinux & Pare-feu)

### 3.1. SELinux en mode `Enforcing`
Conformément aux recommandations ANSSI pour les distributions de la famille Red Hat / Rocky Linux :
- `/etc/selinux/config` configuré avec :
  ```ini
  SELINUX=enforcing
  SELINUXTYPE=targeted
  ```
- Vérification au runtime : `getenforce` doit impérativement retourner `Enforcing`.
- Confinement strict des processus exposés (démons `sshd`, `nginx`, `tailscaled`).

### 3.2. Pare-feu Restrictif (`firewalld` / `ufw`)
La politique par défaut applique le principe du moindre privilège (*Default Deny*) :
- **SSH (Port 22/tcp)** : Interdit à tout le réseau, accessible **uniquement depuis les adresses IP du bastion** (`10.36.11.25/32` et `10.36.10.20/32`) via des règles riches (`rich-rules`) :
  ```xml
  rule family="ipv4" source address="10.36.11.25/32" service name="ssh" accept
  rule family="ipv4" source address="10.36.10.20/32" service name="ssh" accept
  ```
- **Flux applicatifs autorisés** :
  - `LNX-WEB01` : Ports `80/tcp` (HTTP) et `443/tcp` (HTTPS).
  - Partages de fichiers / AD : Port `445/tcp` (SMB).
  - `LNXGW01` : Port `41641/udp` (tunnel WireGuard Tailscale) et translation NAT.
  - Tout autre port non sollicité est immédiatement rejeté/supprimé (`DROP`).

### 3.3. Paramètres Noyau Sysctl (`/etc/sysctl.d/99-security.conf`)

```ini
# ==============================================================================
# Nexus360 - Kernel Sysctl Hardening Configuration (ANSSI / CIS Level 2)
# ==============================================================================

# 1. Routage et Forwarding IP
# net.ipv4.ip_forward = 1 uniquement sur la passerelle LNXGW01
# net.ipv4.ip_forward = 0 sur tous les serveurs membres et applicatifs
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# 2. Protection contre le IP Spoofing (Reverse Path Filtering RFC 3704)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 3. Protection contre les attaques SYN Flood (SYN Cookies)
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2

# 4. Rejet strict des redirections ICMP (Accept Redirects)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# 5. Desactivation de l'emission de redirections ICMP (Send Redirects)
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# 6. Rejet du routage par la source (Source Routing)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# 7. Protection contre le Ping Broadcast (Smurf Attacks) et reponses ICMP erronnees
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# 8. Journalisation des paquets anormaux (Martian Packets)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# 9. Durcissement memoire du noyau et protection contre les liens symboliques
kernel.randomize_va_space = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
```

---

## 4. Hardening Windows Server 2025 (`SRV-DC01` & Membres)

Le script automatisé et idempotent `scripts/windows/05-Security-Hardening.ps1` configure le système local et déploie la stratégie de groupe centrale **`GPO_Security_Hardening_Baseline`**.

### 4.1. Protocoles & Chiffrement (Schannel)
- **Protocoles désactivés** :
  - `SSL 2.0` (Client & Server) : Désactivé (`Enabled = 0`, `DisabledByDefault = 1`)
  - `SSL 3.0` (Client & Server) : Désactivé (`Enabled = 0`, `DisabledByDefault = 1`)
  - `TLS 1.0` (Client & Server) : Désactivé (`Enabled = 0`, `DisabledByDefault = 1`)
  - `TLS 1.1` (Client & Server) : Désactivé (`Enabled = 0`, `DisabledByDefault = 1`)
- **Protocoles autorisés & imposés** :
  - `TLS 1.2` (Client & Server) : Actif (`Enabled = 1`, `DisabledByDefault = 0`)
  - `TLS 1.3` (Client & Server) : Actif (`Enabled = 1`, `DisabledByDefault = 0`)
- **Élimination des protocoles de résolution de nom vulnérables** :
  - **LLMNR** (Link-Local Multicast Name Resolution) : Désactivé via `EnableMulticast = 0` dans `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient`.
  - **NBT-NS** (NetBIOS over TCP/IP) : Désactivé sur toutes les interfaces réseau via CIM (`SetTcpipNetbios(2)`) et nœud configuré en point-à-point (`NodeType = 2`).

### 4.2. Protection SMB (Server Message Block)
- **Signature SMB obligatoire** :
  - `Set-SmbServerConfiguration -RequireSecuritySignature $true -EnableSecuritySignature $true -Force`
  - `Set-SmbClientConfiguration -RequireSecuritySignature $true -EnableSecuritySignature $true -Force`
  - Protection active contre le vol et le rejeu de sessions NTLM (SMB Relay).
- **Désactivation totale de SMBv1** :
  - Clé de registre `HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters\SMB1 = 0`.
  - Pilote système `mrxsmb10` désactivé (`Start = 4`).
  - Suppression de la fonctionnalité facultative Windows `SMB1Protocol`.

### 4.3. Gestion des Comptes et Mots de Passe
- **Renommage du compte Administrateur local intégré** :
  - Le compte à SID se terminant par `-500` est renommé en **`NexusLocalAdmin`** pour déjouer les attaques de force brute ciblant le compte par défaut.
- **Désactivation du compte Invité (`Guest`)** :
  - Le compte à SID se terminant par `-501` est désactivé et verrouillé au niveau local et dans l'annuaire Active Directory.

### 4.4. Stratégie de Groupe `GPO_Security_Hardening_Baseline`
La GPO est créée de manière idempotente et liée avec statut **Enforced** (Pas de substitution possible par une OU enfant) sur :
1. `OU=Nexus360,DC=ad,DC=nexus360,DC=test` (Racine de tous les objets d'entreprise)
2. `OU=Serveurs-T1,OU=Services,OU=Nexus360,DC=ad,DC=nexus360,DC=test`
3. `OU=Postes,OU=Nexus360,DC=ad,DC=nexus360,DC=test`

---

## 5. Matrice de Conformité ANSSI & CIS Benchmark

| Identifiant Référence | Intitulé de la Mesure | Implémentation Technique Nexus360 | Statut |
| :--- | :--- | :--- | :---: |
| **ANSSI Linux R1** | Confinement des services avec SELinux | Mode `Enforcing` (`targeted`) configuré sur tous les hôtes Rocky Linux | **CONFORME** |
| **ANSSI Linux R2** | Filtrage réseau d'entrée restrictif | `firewalld` avec suppression de l'accès SSH mondial, rich-rules bastion | **CONFORME** |
| **ANSSI Linux R8** | Filtrage Reverse Path (Anti-Spoofing) | `net.ipv4.conf.all.rp_filter = 1` | **CONFORME** |
| **ANSSI Linux R9** | Protection SYN Flood | `net.ipv4.tcp_syncookies = 1` | **CONFORME** |
| **ANSSI Linux R10**| Rejet des redirections ICMP | `net.ipv4.conf.all.accept_redirects = 0` | **CONFORME** |
| **ANSSI Linux R11**| Désactivation du routage IP sur nœuds finaux | `net.ipv4.ip_forward = 0` (sauf passerelle `LNXGW01`) | **CONFORME** |
| **ANSSI SSH R1** | Interdiction de connexion root directe | `PermitRootLogin no` dans `/etc/ssh/sshd_config.d/99-hardening.conf` | **CONFORME** |
| **ANSSI SSH R2** | Authentification exclusive par clé publique | `PasswordAuthentication no` & `PubkeyAuthentication yes` | **CONFORME** |
| **ANSSI SSH R3** | Cryptographie moderne Curve25519 / AEAD | Clés Ed25519, `curve25519-sha256`, `chacha20-poly1305`, `aes256-gcm` | **CONFORME** |
| **ANSSI SSH R5** | Limitation des groupes autorisés | `AllowGroups g_ssh_admins g_exploitation` | **CONFORME** |
| **CIS WinSrv 1.1** | Renommage du compte Administrateur local | Renommé en `NexusLocalAdmin` (Script & Template INF) | **CONFORME** |
| **CIS WinSrv 1.2** | Désactivation du compte Invité | Désactivation confirmée sur SID `-501` et compte Guest AD | **CONFORME** |
| **CIS WinSrv 2.3** | Signature SMB obligatoire (Client/Server) | `RequireSecuritySignature = $true` enforce par GPO & Registre | **CONFORME** |
| **CIS WinSrv 2.3** | Désactivation définitive de SMBv1 | `SMB1 = 0`, pilote `mrxsmb10` désactivé (Start=4) | **CONFORME** |
| **CIS WinSrv 9.3** | Désactivation de LLMNR et NBT-NS | `EnableMulticast = 0` et `SetTcpipNetbios(2)` sur toutes interfaces | **CONFORME** |
| **CIS WinSrv 9.1** | Maintien exclusif de TLS 1.2 et TLS 1.3 | SSL 2.0/3.0 et TLS 1.0/1.1 désactivés dans Schannel | **CONFORME** |

---

## 6. Procédures de Vérification et d'Audit

### 6.1. Audit des Hôtes Linux
```bash
# 1. Vérification du statut SELinux
getenforce
# Attendu : Enforcing

# 2. Vérification des règles de filtrage SSH dans firewalld
firewall-cmd --list-rich-rules
# Attendu : rule family="ipv4" source address="10.36.11.25/32" service name="ssh" accept

# 3. Vérification des paramètres du noyau sysctl
sysctl net.ipv4.ip_forward net.ipv4.conf.all.rp_filter net.ipv4.tcp_syncookies
# Attendu :
# Sur serveurs applicatifs : net.ipv4.ip_forward = 0
# Sur LNXGW01 : net.ipv4.ip_forward = 1
# net.ipv4.conf.all.rp_filter = 1
# net.ipv4.tcp_syncookies = 1

# 4. Vérification de la configuration SSH active
sshd -T | grep -E "permitrootlogin|passwordauthentication|pubkeyauthentication|kexalgorithms"
# Attendu :
# permitrootlogin no
# passwordauthentication no
# pubkeyauthentication yes
```

### 6.2. Audit de `SRV-DC01` (Windows Server)
```powershell
# 1. Vérification de la signature SMB
Get-SmbServerConfiguration | Select-Object RequireSecuritySignature, EnableSMB1Protocol
# Attendu : RequireSecuritySignature = True, EnableSMB1Protocol = False

# 2. Vérification de l'état des protocoles TLS dans Schannel
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" -Name Enabled
# Attendu : Enabled = 0
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" -Name Enabled
# Attendu : Enabled = 1

# 3. Vérification du statut des comptes locaux
Get-LocalUser | Select-Object Name, Enabled, SID
# Attendu : NexusLocalAdmin (Enabled: True, SID: *-500), Guest (Enabled: False, SID: *-501)

# 4. Vérification des liens de la GPO Baseline
Get-GPOReport -Name "GPO_Security_Hardening_Baseline" -ReportType Xml | Select-String -Pattern "LinksTo"
```
