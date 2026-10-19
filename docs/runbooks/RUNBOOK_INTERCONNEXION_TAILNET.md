# Runbook : Interconnexion Réseau Maillé & Passerelles Tailscale

| Réf Doc | RB-NET-003 |
| :--- | :--- |
| **Périmètre** | Passerelles de routage des 5 sites (`NX-GW-*`), Contrôleur ACL |
| **Responsable** | Ingénieur Réseau & Sécurité |

---

## 1. Objectif du Maillage

Chaque site dispose d'une passerelle Linux annonçant son sous-réseau local respectif (`10.36.10.0/24`, `10.36.20.0/24`, etc.) à l'ensemble du Tailnet, permettant ainsi un routage transparent et chiffré sans nécessiter de concentrateur VPN central unique (SPOF).

---

## 2. Configuration d'une Passerelle de Site (Subnet Router)

### Étape 1 : Activation du transfert de paquets au niveau du noyau
```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=1
```

### Étape 2 : Démarrage du client Tailscale avec annonce de sous-réseau
Exemple pour le Site 3 (Agence Nord) :
```bash
sudo tailscale up \
  --advertise-routes=10.36.30.0/24 \
  --accept-routes \
  --advertise-tags=tag:gateway \
  --reset
```

### Étape 3 : Validation du statut et de la table de routage
```bash
# Vérifier la connectivité au Tailnet
tailscale status

# Vérifier les pairs connectés
tailscale ping 10.36.10.1
```

---

## 3. Mise à Jour de la Politique de Sécurité ACL

1. Éditer le fichier [`reseau/tailnet-policy.hujson`](file:///reseau/tailnet-policy.hujson).
2. Vérifier les syntaxes des groupes et des blocs d'autorisations.
3. Téléverser ou appliquer la politique dans la console d'administration Tailscale via API ou GitOps.
