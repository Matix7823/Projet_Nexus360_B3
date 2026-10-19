# Fiche Post-Mortem d'Incident : [ID_INCIDENT] - [Titre Court]

| Champ | Information |
| :--- | :--- |
| **Identifiant Incident** | `INC-YYYY-XXX` |
| **Gravité** | P1 (Critique) / P2 (Majeur) / P3 (Mineur) |
| **Date et Heure de Début** | YYYY-MM-DD HH:MM UTC |
| **Date et Heure de Résolution** | YYYY-MM-DD HH:MM UTC |
| **Durée d'Indisponibilité** | XX minutes |
| **Composant(s) Impacté(s)** | Ex: Routage Site 2, Contrôleur AD DS, Serveur Web |
| **Pilote d'Incident** | [Nom / Rôle] |

---

## 1. Résumé Exécutif
Brève description (2 à 3 phrases) compréhensible par la direction : ce qui s'est produit, l'impact sur l'activité métier et comment la situation a été rétablie.

---

## 2. Chronologie des Événements
* **HH:MM** : Première alerte Prometheus / Ticket utilisateur.
* **HH:MM** : Prise en charge par l'équipe d'astreinte.
* **HH:MM** : Identification de la cause racine.
* **HH:MM** : Application du correctif / contournement.
* **HH:MM** : Validation de la reprise du trafic et clôture de l'incident.

---

## 3. Cause Racine (Root Cause Analysis - RCA)
Explication technique détaillée de l'origine de l'incident (ex: mauvaise règle de pare-feu, expiration de certificat, surcharge processeur).

---

## 4. Mesures Correctives & Plan d'Action Préventif

| Action | Description | Responsable | Échéance | Statut |
| :--- | :--- | :--- | :--- | :--- |
| **AC-01** | Ajout d'une alerte proactive sur la passerelle | Ingénieur Monitoring | J+3 | À faire |
| **AC-02** | Mise à jour du script de déploiement Ansible | Ingénieur DevOps | J+5 | À faire |
