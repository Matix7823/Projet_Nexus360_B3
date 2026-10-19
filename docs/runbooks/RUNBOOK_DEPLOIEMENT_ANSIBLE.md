# Runbook : Procédure de Déploiement & Automatisation Ansible

| Réf Doc | RB-ANS-001 |
| :--- | :--- |
| **Périmètre** | Serveurs Linux & Nœuds d'Infrastructure Nexus360 |
| **Fréquence** | À chaque provisionnement ou mise à jour de socle |
| **Responsable** | Ingénieur Automatisation / DevOps |

---

## 1. Contexte & Prérequis

Ce runbook détaille les étapes d'exécution des playbooks Ansible pour standardiser les machines virtuelles déployées sur les 5 sites de l'infrastructure.

### Prérequis Techniques
1. Clé SSH privée configurée sur le contrôleur Ansible (`NX-OPS-SRV01`) : `~/.ssh/id_rsa_nexus360`.
2. Utilisateur `ansible` créé sur chaque hôte cible avec droits sudo sans mot de passe :
   ```bash
   echo "ansible ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible
   chmod 0440 /etc/sudoers.d/ansible
   ```
3. Python 3 installé sur chaque cible.

---

## 2. Procédure Pas-à-Pas

### Étape 1 : Vérification de la connectivité réseau et SSH
Depuis le répertoire `ansible/` :
```bash
cd ansible
ansible -i inventory/hosts.ini all -m ping
```
*Critère de succès* : Tous les nœuds doivent répondre par `"ping": "pong"` en vert.

### Étape 2 : Exécution à blanc (Check Mode / Dry-Run)
Valider la syntaxe et les changements sans modification effective :
```bash
ansible-playbook -i inventory/hosts.ini site.yml --check --diff
```

### Étape 3 : Déploiement Global du Playbook Maître
```bash
ansible-playbook -i inventory/hosts.ini site.yml
```

### Étape 4 : Déploiement Ciblé par Tags
Si une intervention ne concerne qu'un rôle spécifique :
- **Uniquement le socle commun (mises à jour & SSH)** :
  ```bash
  ansible-playbook -i inventory/hosts.ini site.yml --tags "base"
  ```
- **Uniquement le serveur Web Nginx** :
  ```bash
  ansible-playbook -i inventory/hosts.ini site.yml --tags "web"
  ```
- **Uniquement la passerelle et le routage** :
  ```bash
  ansible-playbook -i inventory/hosts.ini site.yml --tags "gw"
  ```

---

## 3. Gestion des Erreurs et Dépannage

| Symptôme | Cause Probable | Action Corrective |
| :--- | :--- | :--- |
| `UNREACHABLE: Permission denied (publickey)` | Clé SSH absente du `authorized_keys` | Redéployer la clé publique avec `ssh-copy-id ansible@<IP>` |
| `Failed to lock apt for exclusive access` | Un processus apt/dpkg tourne déjà | Tuer le processus bloquant (`fuser -vki /var/lib/dpkg/lock-frontend`) |
| `Timeout connecting to host` | Routage Subnet Tailscale interrompu | Vérifier le statut de `tailscale status` sur la passerelle du site |
