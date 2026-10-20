# Runbook d'Exploitation : Importation & Provisionnement des Utilisateurs AD
## Projet Nexus360 - Mission T01 / Site 1 Paris

---

## 1. Contexte & Objectif

Ce runbook décrit la procédure opérationnelle standardisée (SOP) pour :
1. Déployer l'arborescence des Unités Organisationnelles (OU) et les groupes AGDLP.
2. Importer de manière idempotente les 15 utilisateurs de l'entreprise répartis dans 4 départements (`Comptabilite`, `Direction`, `Exploitation`, `Informatique`).
3. Provisionner les 3 comptes d'administration de Tiering (`adm-t0-mathis`, `adm-t1-mathis`, `adm-t2-mathis`).
4. Vérifier la conformité de l'annuaire.
5. Exécuter un plan de retour arrière (Rollback) maîtrisé en cas d'anomalie.

---

## 2. Prérequis Opérationnels

- **Serveur d'exécution** : `SRV-DC01` (Windows Server 2025) ou station d'administration RSAT connectée au domaine `ad.nexus360.test`.
- **Privilèges requis** : Compte membre du groupe `Domain Admins` (ou `adm-t0-mathis`).
- **Composants logiciels** :
  - PowerShell 5.1 ou PowerShell 7+
  - Module `ActiveDirectory` installé (`RSAT-AD-PowerShell`)
- **Fichiers requis** :
  - `config/utilisateurs.csv`
  - `config/ad_structure.json`
  - `scripts/windows/01-Create-OU-and-AGDLP.ps1`
  - `scripts/windows/02-Import-Users.ps1`

---

## 3. Procédure d'Exécution Pas-à-Pas

### Étape 3.1 : Clonage / Accès au Répertoire du Projet
Ouvrir une invite de commande PowerShell en mode Administrateur :
```powershell
# Positionnement dans le dossier racine du projet
cd C:\Users\mathi\Desktop\Projet_Nexus360_B3
```

### Étape 3.2 : Validation de l'Intégrité du Fichier CSV
Vérifier la présence et la structure du fichier source :
```powershell
# Vérification du nombre de lignes (1 entête + 15 utilisateurs = 16 lignes)
$csvData = Import-Csv -Path ".\config\utilisateurs.csv" -Encoding UTF8
$csvData | Format-Table -AutoSize
Write-Host "Total utilisateurs détectés : $($csvData.Count)" -ForegroundColor Green
```
*Critère de succès* : Exactement 15 lignes de comptes valides affichées avec les colonnes `FirstName`, `LastName`, `SamAccountName`, `Department`.

### Étape 3.3 : Création de l'Arborescence OU et des Groupes AGDLP
Exécuter le script `01-Create-OU-and-AGDLP.ps1` :
```powershell
& ".\scripts\windows\01-Create-OU-and-AGDLP.ps1" -DomainDN "DC=ad,DC=nexus360,DC=test"
```
*Sortie attendue* :
- Création confirmée de `Nexus360`, `Administration`, `T0-Admins`, `T1-Admins`, `T2-Admins`, `Services`, `Serveurs-T1`, `Postes`, `Utilisateurs`, `Groupes`.
- Création des groupes `GG_Comptabilite`, `GG_Direction`, `GG_Exploitation`, `GG_Informatique`, `GG_Admins_T0`, `GG_Admins_T1`, `GG_Admins_T2`.
- Création des groupes `DL_Compta_Share_RW`, `DL_Direction_Share_RW`, `DL_Exploitation_Share_RW`, `DL_Informatique_Share_RW`.
- Imbrication réussie des `GG_*` dans les `DL_*`.

### Étape 3.4 : Importation des Utilisateurs et Comptes de Tiering
Exécuter le script `02-Import-Users.ps1` :
```powershell
& ".\scripts\windows\02-Import-Users.ps1" `
    -CsvPath ".\config\utilisateurs.csv" `
    -DomainName "ad.nexus360.test" `
    -DomainDN "DC=ad,DC=nexus360,DC=test"
```

---

## 4. Recette & Contrôles Post-Déploiement

Exécuter les requêtes de contrôle suivantes pour valider le déploiement :

### 4.1. Vérification du décompte des utilisateurs standard
```powershell
$users = Get-ADUser -SearchBase "OU=Utilisateurs,OU=Nexus360,DC=ad,DC=nexus360,DC=test" -Filter * -Properties Department
Write-Host "Nombre d'utilisateurs dans Nexus360/Utilisateurs : $($users.Count)"
$users | Select-Object SamAccountName, Name, Department, Enabled | Format-Table -AutoSize
```
*Critère de validation* : 15 comptes actifs (`Enabled: True`).

### 4.2. Vérification de l'affectation aux groupes globaux
```powershell
"GG_Comptabilite", "GG_Direction", "GG_Exploitation", "GG_Informatique" | ForEach-Object {
    $grp = $_
    $members = Get-ADGroupMember -Identity $grp | Select-Object -ExpandProperty SamAccountName
    Write-Host "Groupe $grp ($($members.Count) membres) : $($members -join ', ')" -ForegroundColor Cyan
}
```

### 4.3. Vérification des comptes de Tiering
```powershell
$tiering = @("adm-t0-mathis", "adm-t1-mathis", "adm-t2-mathis")
foreach ($acc in $tiering) {
    $u = Get-ADUser -Identity $acc -Properties MemberOf, DistinguishedName
    Write-Host "Compte : $($u.SamAccountName)" -ForegroundColor Yellow
    Write-Host "  DN : $($u.DistinguishedName)"
    Write-Host "  Groupes : $($u.MemberOf -join ' | ')"
}
```
*Critères de validation* :
- `adm-t0-mathis` réside dans `OU=T0-Admins` et est membre de `GG_Admins_T0` et `Domain Admins`.
- `adm-t1-mathis` réside dans `OU=T1-Admins` et est membre de `GG_Admins_T1`.
- `adm-t2-mathis` réside dans `OU=T2-Admins` et est membre de `GG_Admins_T2`.

---

## 5. Procédure de Retour Arrière (Rollback)

En cas d'anomalie critique (mauvaise structure importée, corruption d'identifiants), la procédure ci-dessous restaure l'état antérieur sans impacter les comptes systèmes ou le compte `Administrator` natif.

```powershell
<#
    === SCRIPT DE ROLLBACK AUTOMATISE ===
#>
$DomainDN = "DC=ad,DC=nexus360,DC=test"
$csvPath = ".\config\utilisateurs.csv"

Write-Warning "INITIALISATION DU ROLLBACK - Annuaire ad.nexus360.test"

# 1. Suppression des 15 utilisateurs importes
if (Test-Path $csvPath) {
    $importedUsers = Import-Csv -Path $csvPath
    foreach ($usr in $importedUsers) {
        $sam = $usr.SamAccountName.Trim()
        if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
            Remove-ADUser -Identity $sam -Confirm:$false
            Write-Host "[-] Utilisateur supprime : $sam" -ForegroundColor Yellow
        }
    }
}

# 2. Suppression des comptes de Tiering
@("adm-t0-mathis", "adm-t1-mathis", "adm-t2-mathis") | ForEach-Object {
    if (Get-ADUser -Filter "SamAccountName -eq '$_'" -ErrorAction SilentlyContinue) {
        Remove-ADUser -Identity $_ -Confirm:$false
        Write-Host "[-] Compte Tiering supprime : $_" -ForegroundColor Yellow
    }
}

# 3. Suppression des groupes AGDLP
$groupsToDelete = @(
    "GG_Comptabilite", "GG_Direction", "GG_Exploitation", "GG_Informatique",
    "GG_Admins_T0", "GG_Admins_T1", "GG_Admins_T2",
    "DL_Compta_Share_RW", "DL_Direction_Share_RW", "DL_Exploitation_Share_RW", "DL_Informatique_Share_RW"
)
foreach ($grp in $groupsToDelete) {
    if (Get-ADGroup -Filter "SamAccountName -eq '$grp'" -ErrorAction SilentlyContinue) {
        Remove-ADGroup -Identity $grp -Confirm:$false
        Write-Host "[-] Groupe supprime : $grp" -ForegroundColor Yellow
    }
}

# 4. Suppression de l'arborescence OU (deverrouillage prealable de la protection contre suppression accidentelle)
$ousToDelete = @(
    "OU=T0-Admins,OU=Administration,OU=Nexus360,$DomainDN",
    "OU=T1-Admins,OU=Administration,OU=Nexus360,$DomainDN",
    "OU=T2-Admins,OU=Administration,OU=Nexus360,$DomainDN",
    "OU=Administration,OU=Nexus360,$DomainDN",
    "OU=Serveurs-T1,OU=Services,OU=Nexus360,$DomainDN",
    "OU=Services,OU=Nexus360,$DomainDN",
    "OU=Postes,OU=Nexus360,$DomainDN",
    "OU=Utilisateurs,OU=Nexus360,$DomainDN",
    "OU=Groupes,OU=Nexus360,$DomainDN",
    "OU=Nexus360,$DomainDN"
)

foreach ($ou in $ousToDelete) {
    $existing = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ou'" -ErrorAction SilentlyContinue
    if ($existing) {
        Set-ADOrganizationalUnit -Identity $ou -ProtectedFromAccidentalDeletion $false
        Remove-ADOrganizationalUnit -Identity $ou -Recursive -Confirm:$false
        Write-Host "[-] OU supprimee : $ou" -ForegroundColor Red
    }
}

Write-Host "Rollback termine avec succes. L'annuaire a ete purge des elements Nexus360." -ForegroundColor Green
```
