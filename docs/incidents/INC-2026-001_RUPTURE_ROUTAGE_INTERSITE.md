# Fiche Post-Mortem d'Incident : INC-2026-001 - Perte de Connectivité Subnet Site 2 (Usine)

| Champ | Information |
| :--- | :--- |
| **Identifiant Incident** | `INC-2026-001` |
| **Gravité** | P2 (Majeur) |
| **Date et Heure de Début** | 2026-10-18 14:15 UTC |
| **Date et Heure de Résolution** | 2026-10-18 14:48 UTC |
| **Durée d'Indisponibilité** | 33 minutes |
| **Composant(s) Impacté(s)** | Passerelle `NX-GW-PROD01`, Routage sous-réseau `10.36.20.0/24` |
| **Pilote d'Incident** | Ingénieur Réseau Équipe T01 |

---

## 1. Résumé Exécutif
À la suite d'un redémarrage système imprévu de la passerelle `NX-GW-PROD01`, le transfert de paquets IPv4 (`net.ipv4.ip_forward`) n'a pas été rétabli automatiquement au boot, entraînant l'isolement du sous-réseau usine vis-à-vis des contrôleurs de domaine centraux.

---

## 2. Chronologie des Événements
* **14:15** : Alerte Prometheus `InstanceDown` pour les collecteurs IoT du Site 2.
* **14:18** : Constat de l'impossibilité d'accéder au contrôleur RODC02 depuis le siège.
* **14:25** : Connexion SSH de secours via IP Tailscale directe sur `NX-GW-PROD01`.
* **14:32** : Détection du flag noyau `net.ipv4.ip_forward = 0`.
* **14:36** : Rétablissement immédiat via commande `sysctl -w net.ipv4.ip_forward=1`.
* **14:48** : Persistance de la configuration dans `/etc/sysctl.d/99-nexus360.conf` et validation de la reprise des flux.

---

## 3. Cause Racine (RCA)
La modification de configuration initiale avait été effectuée temporairement en ligne de commande sans être inscrite dans `/etc/sysctl.conf` ou prise en charge par Ansible.

---

## 4. Mesures Correctives & Plan d'Action Préventif

| Action | Description | Responsable | Échéance | Statut |
| :--- | :--- | :--- | :--- | :--- |
| **AC-01** | Intégration de la tâche sysctl idempotente dans le rôle Ansible `gw` | Ingénieur DevOps | Immédiat | **Terminé** |
| **AC-02** | Ajout d'une alerte Prometheus sur la métrique `node_network_flags` | Ingénieur Monitoring | J+2 | En cours |
| **AC-03** | Test de redémarrage complet simulé sur toutes les passerelles | Ingénieur Réseau | J+4 | Planifié |
