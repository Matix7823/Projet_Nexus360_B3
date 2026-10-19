# Journal d'Exploitation & Suivi de Projet - Nexus360 (T01)

Ce document retrace l'historique chronologique des séances, les décisions techniques prises, les difficultés rencontrées et l'état d'avancement des livrables.

---

## Modèle de Fiche de Séance

```markdown
### [YYYY-MM-DD] - Séance N°X : Titre de la séance
* **Membres présents** : [Noms / Équipe T01]
* **Objectifs planifiés** :
  - [ ] Objectif 1
  - [ ] Objectif 2
* **Réalisations & Actions techniques** :
  - Action A : détails et commandes / playbooks exécutés
  - Action B : modifications d'architecture
* **Difficultés & Incidents rencontrés** :
  - Problème : description
  - Résolution : solution apportée ou contournement
* **Statut des tests & validations** :
  - Test X : Réussi / Échec
* **Reste à faire / Prochaine séance** :
  - [ ] Tâche à initier
```

---

## Historique des Séances

### [2026-10-19] - Séance 1 : Initialisation du Dépôt, Définition de l'Architecture & Socle Git
* **Membres présents** : Équipe T01 au complet
* **Objectifs planifiés** :
  - [x] Initialiser le dépôt Git local et configurer le remote GitHub officiel
  - [x] Formaliser la structure arborescente du projet (Ansible, PowerShell, Réseau, Documentation)
  - [x] Rédiger le Dossier d'Architecture Technique (`DAT.md`) et le `README.md`
  - [x] Concevoir le plan d'adressage IP `10.36.0.0/16` et la matrice AGDLP
  - [x] Rédiger la politique de sécurité Tailnet (`tailnet-policy.hujson`)
* **Réalisations & Actions techniques** :
  - Initialisation du dépôt Git sur la branche `main` et configuration du remote `https://github.com/Matix7823/Projet_Nexus360_B3.git`.
  - Établissement du fichier `.gitignore` couvrant Ansible, PowerShell, Python, clés SSH et fichiers de secrets.
  - Définition complète des 5 rôles Ansible : `base`, `web`, `ops`, `mon`, `gw`.
  - Création des jeux de données d'utilisateurs (`users.csv`), de groupes (`groups.json`) et de partages avec quotas FSRM (`shares.json`).
  - Écriture des scripts d'automatisation PowerShell pour l'Active Directory.
* **Difficultés & Incidents rencontrés** :
  - *Sujet* : Harmonisation des identifiants et des formats JSON pour les scripts PowerShell.
  - *Résolution* : Normalisation stricte de la nomenclature AGDLP (`GG_<METIER>` et `GDL_<RESSOURCE>_<DROIT>`).
* **Statut des tests & validations** :
  - Arborescence Git validée et conforme aux exigences B3.
  - Politiques HUJSON vérifiées et sans erreur de syntaxe.
* **Reste à faire / Prochaine séance** :
  - [ ] Déploiement du premier contrôleur de domaine Windows Server (`NX-AD-DC01`).
  - [ ] Exécution du script de création d'OU et provisionnement des comptes utilisateurs.
  - [ ] Validation de l'authentification SSH et test du ping Ansible sur les nœuds de test.

---

### [Séance 2 - Planifiée] : Déploiement du Contrôleur AD DS & Automatisation PowerShell
* **Membres prévus** : Équipe T01
* **Objectifs prévisionnels** :
  - Déployer le rôle AD DS sur Windows Server 2022 (`nexus360.local`).
  - Exécuter `01_Deploy-ActiveDirectoryBase.ps1` et `02_Provision-UsersAndAGDLP.ps1`.
  - Mettre en place les partages et quotas avec `03_Configure-FSRMQuotasAndShares.ps1`.
  - Valider l'application des droits NTFS effectifs sur un poste client de test.

---

### [Séance 3 - Planifiée] : Interconnexion Réseau Tailscale & Subnet Routers
* **Membres prévus** : Équipe T01
* **Objectifs prévisionnels** :
  - Déployer les passerelles Linux (`gw`) sur chaque site.
  - Activer l'IP forwarding et annoncer les routes `10.36.x.0/24`.
  - Appliquer les ACLs Tailnet et valider la matrice des flux réseau.

---

### [Séance 4 - Planifiée] : Industrialisation Ansible & Services Applicatifs
* **Membres prévus** : Équipe T01
* **Objectifs prévisionnels** :
  - Exécuter le playbook `ansible/site.yml`.
  - Valider le bon déploiement du rôle `web` (reverse proxy Nginx) et `ops`.
  - Configurer les sauvegardes automatiques.

---

### [Séance 5 - Planifiée] : Observabilité, Recette Finale & Soutenance
* **Membres prévus** : Équipe T01
* **Objectifs prévisionnels** :
  - Déployer la stack de métriques `roles/mon` (Prometheus & Grafana).
  - Importer les tableaux de bord de supervision des 5 sites.
  - Effectuer les tests de bascule et rédiger les fiches d'incidents post-mortem.
  - Finaliser la documentation technique pour la soutenance.
