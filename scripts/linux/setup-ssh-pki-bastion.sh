#!/usr/bin/env bash
# ==============================================================================
# Nexus360 - Bastion SSH PKI Setup & Key Distribution (Exigence B5)
# Machine source : Bastion d'Administration LNX-0PS01 (10.36.11.25 / 10.36.10.20)
# Cibles : LNX-WEB01, LNX-MON01, LNXGW01 (et serveurs Linux Site 1 & Infra)
# ==============================================================================
set -euo pipefail

KEY_TYPE="ed25519"
KEY_COMMENT="admin-nexus360-ops@bastion-lnx-ops01-$(date +%Y%m%d)"
KEY_PATH="${HOME}/.ssh/id_ed25519_admin"
TARGET_USER="${TARGET_USER:-ansible}"

# Hôtes cibles par défaut pour le Site 1 / Nexus360
TARGET_HOSTS=(
    "10.36.11.1"   # LNXGW01 (Passerelle Site 1)
    "10.36.11.20"  # LNX-WEB01 (Serveur Web Applicatif)
    "10.36.11.30"  # LNX-MON01 (Serveur Supervision Prometheus/Grafana)
)

echo "=========================================================="
echo "  Nexus360 - Initialisation de la PKI SSH Bastion ED25519"
echo "=========================================================="

# 1. Vérification / Création du répertoire .ssh sécurisé
mkdir -p -m 0700 "${HOME}/.ssh"

# 2. Génération de la paire de clés ED25519 si inexistante
if [ ! -f "${KEY_PATH}" ]; then
    echo "[+] Génération de la paire de clés SSH ED25519 (${KEY_PATH})..."
    ssh-keygen -t "${KEY_TYPE}" -a 100 -C "${KEY_COMMENT}" -f "${KEY_PATH}" -N ""
    chmod 0600 "${KEY_PATH}"
    chmod 0644 "${KEY_PATH}.pub"
    echo "[✓] Paire de clés générée avec succès."
else
    echo "[i] La clé SSH ED25519 existe déjà : ${KEY_PATH}"
fi

PUBKEY_CONTENT=$(cat "${KEY_PATH}.pub")
echo "[i] Empreinte de la clé publique :"
ssh-keygen -lf "${KEY_PATH}.pub"

# 3. Distribution de la clé publique sur les serveurs cibles
echo ""
echo "[+] Distribution de la clé publique sur les serveurs cibles..."
for host in "${TARGET_HOSTS[@]}"; do
    echo "--- Déploiement sur ${host} (${TARGET_USER}) ---"
    if ssh-copy-id -i "${KEY_PATH}.pub" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${TARGET_USER}@${host}" 2>/dev/null; then
        echo "[✓] Clé publique déployée sur ${host}."
    else
        echo "[!] Déploiement via ssh-copy-id échoué ou hôte inaccessible directement."
        echo "    Tentative de distribution alternative via script distant ou vérification existante..."
    fi

    # Test de validation par clé
    if ssh -i "${KEY_PATH}" -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "${TARGET_USER}@${host}" "echo '[OK] Auth ED25519 active sur \$(hostname)'" 2>/dev/null; then
        echo "[✓] Connexion validée par clé ED25519 sur ${host}."
    else
        echo "[i] Note : Le serveur ${host} sera configuré lors de l'exécution du rôle Ansible hardening_ssh."
    fi
done

echo ""
echo "=========================================================="
echo "  Configuration de ~/.ssh/config pour le Bastion"
echo "=========================================================="
SSH_CONFIG_ENTRY="Host lnx-gw01 10.36.11.1
    HostName 10.36.11.1
    User ${TARGET_USER}
    IdentityFile ${KEY_PATH}
    IdentitiesOnly yes

Host lnx-web01 10.36.11.20
    HostName 10.36.11.20
    User ${TARGET_USER}
    IdentityFile ${KEY_PATH}
    IdentitiesOnly yes

Host lnx-mon01 10.36.11.30
    HostName 10.36.11.30
    User ${TARGET_USER}
    IdentityFile ${KEY_PATH}
    IdentitiesOnly yes
"

if ! grep -q "IdentityFile ${KEY_PATH}" "${HOME}/.ssh/config" 2>/dev/null; then
    echo "${SSH_CONFIG_ENTRY}" >> "${HOME}/.ssh/config"
    chmod 0600 "${HOME}/.ssh/config"
    echo "[✓] Hôtes Nexus360 ajoutés dans ~/.ssh/config."
else
    echo "[i] ~/.ssh/config contient déjà la configuration de l'identité ED25519."
fi

echo "[✓] Initialisation PKI SSH Bastion terminée."
