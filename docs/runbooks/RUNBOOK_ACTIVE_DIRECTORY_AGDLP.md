# Runbook : Exploitation Active Directory, Modèle AGDLP & Quotas FSRM

| Réf Doc | RB-AD-002 |
| :--- | :--- |
| **Périmètre** | Contrôleurs de domaine (`NX-AD-DC01`, `NX-AD-RODC01`), Serveurs de fichiers (`NX-FS-*`) |
| **Responsable** | Administrateur Système Windows / Sécurité |

---

## 1. Vue d'Ensemble du Modèle AGDLP Nexus360

La gestion des droits d'accès suit scrupuleusement la règle :
1. **A**ccounts : Les comptes utilisateurs sont créés dans `OU=<Service>,OU=Users,OU=Nexus360,DC=nexus360,DC=local`.
2. **G**lobal Groups : Les utilisateurs sont affectés à leur groupe métier (`GG_Direction`, `GG_RH`, etc.).
3. **D**omain **L**ocal Groups : Les groupes métiers sont membres des groupes de domaine local régissant la ressource (`GDL_PARTAGE_DIRECTION_RW`).
4. **P**ermissions : Seuls les groupes `GDL_*` sont positionnés sur les listes de contrôle d'accès NTFS.

---

## 2. Déploiement Initial de l'Annuaire

Exécuter les scripts PowerShell séquentiellement dans une session avec privilèges élevés :

```powershell
# 1. Création de l'arborescence des OUs
cd powershell\scripts
.\01_Deploy-ActiveDirectoryBase.ps1

# 2. Création des groupes AGDLP et provisionnement des comptes utilisateurs
.\02_Provision-UsersAndAGDLP.ps1
```

---

## 3. Configuration des Serveurs de Fichiers & Quotas FSRM

Sur le serveur de fichiers cible (`NX-FS-NORD01` ou `NX-FS-SUD01`) :

```powershell
cd powershell\scripts
.\03_Configure-FSRMQuotasAndShares.ps1
```

### Vérification des Droits Effectifs
Pour contrôler qu'un utilisateur a bien les accès escomptés :
```powershell
# Exemple pour Marie Durand sur le partage RH
(Get-Acl "D:\Shares\RH").Access | Where-Object { $_.IdentityReference -like "*GDL_PARTAGE_RH*" }
```

---

## 4. Procédures d'Exploitation Courante (Toolbox D2)

Exécuter la boîte à outils pour les contrôles de routine :
```powershell
# Bilan de santé global
.\Toolbox-D2.ps1 -Action All

# Audit des comptes verrouillés ou inactifs
.\Toolbox-D2.ps1 -Action AuditUsers

# Vérification du remplissage des quotas disques
.\Toolbox-D2.ps1 -Action CheckQuotas
```
