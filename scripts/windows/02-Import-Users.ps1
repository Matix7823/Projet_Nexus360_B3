<#
.SYNOPSIS
    02-Import-Users.ps1 - Importation automatique des utilisateurs AD et provisionnement des comptes de Tiering.
.DESCRIPTION
    Projet : Nexus360 (B3 - Mission T01 / Site 1 Paris)
    Domaine : ad.nexus360.test
    Ce script lit le fichier CSV `config/utilisateurs.csv` (15 comptes), les provisionne de facon
    idempotente dans l'OU 'Nexus360/Utilisateurs', les affecte a leurs groupes globaux respectifs,
    et cree les 3 comptes d'administration securises du modele de Tiering (adm-t0-mathis, adm-t1-mathis, adm-t2-mathis).
.NOTES
    Auteur  : Equipe DevOps / SysAdmin Nexus360
    Version : 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$CsvPath = "$PSScriptRoot/../../config/utilisateurs.csv",

    [Parameter(Mandatory = $false)]
    [string]$DomainName = "ad.nexus360.test",

    [Parameter(Mandatory = $false)]
    [string]$DomainDN = "DC=ad,DC=nexus360,DC=test",

    [Parameter(Mandatory = $false)]
    [string]$DefaultUserPassword = "NexusPassword2026!",

    [Parameter(Mandatory = $false)]
    [string]$DefaultAdminPassword = "AdminSecurePassword2026!"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param (
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO",
        [string]$Message
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $colors = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

# Verifier ActiveDirectory
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Log -Level "ERROR" -Message "Le module ActiveDirectory n'est pas installe."
    exit 1
}
Import-Module ActiveDirectory

# Verification du fichier CSV
$resolvedCsvPath = Resolve-Path -Path $CsvPath -ErrorAction SilentlyContinue
if (-not $resolvedCsvPath -or -not (Test-Path -Path $resolvedCsvPath)) {
    # Tenter un chemin alternatif
    $altPath = Join-Path -Path $PSScriptRoot -ChildPath "..\..\config\utilisateurs.csv"
    if (Test-Path -Path $altPath) {
        $resolvedCsvPath = (Resolve-Path -Path $altPath).Path
    } else {
        Write-Log -Level "ERROR" -Message "Fichier CSV introuvable a l'emplacement : $CsvPath"
        exit 1
    }
}

Write-Log -Level "INFO" -Message "Lecture du fichier CSV : $resolvedCsvPath"
$usersList = Import-Csv -Path $resolvedCsvPath -Encoding UTF8

$usersOU = "OU=Utilisateurs,OU=Nexus360,$DomainDN"
$deptGroupMapping = @{
    "Comptabilite" = "GG_Comptabilite"
    "Direction"    = "GG_Direction"
    "Exploitation" = "GG_Exploitation"
    "Informatique" = "GG_Informatique"
}

$secureUserPass = ConvertTo-SecureString $DefaultUserPassword -AsPlainText -Force
$secureAdminPass = ConvertTo-SecureString $DefaultAdminPassword -AsPlainText -Force

Write-Log -Level "INFO" -Message "Traitement des utilisateurs standards ($($usersList.Count) utilisateurs detectes)..."

foreach ($u in $usersList) {
    $sam = $u.SamAccountName.Trim().ToLower()
    $fn = $u.FirstName.Trim()
    $ln = $u.LastName.Trim()
    $displayName = "$fn $ln"
    $dept = $u.Department.Trim()
    $upn = "$sam@$DomainName"

    try {
        $existing = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
        if ($null -eq $existing) {
            New-ADUser -Name $displayName `
                       -GivenName $fn `
                       -Surname $ln `
                       -DisplayName $displayName `
                       -SamAccountName $sam `
                       -UserPrincipalName $upn `
                       -Department $dept `
                       -Path $usersOU `
                       -AccountPassword $secureUserPass `
                       -Enabled $true `
                       -ChangePasswordAtLogon $false `
                       -PasswordNeverExpires $false
            Write-Log -Level "SUCCESS" -Message "Utilisateur cree : $sam ($displayName) dans $usersOU"
        } else {
            Write-Log -Level "INFO" -Message "Utilisateur deja existant (idempotent) : $sam"
        }

        # Affectation au Groupe Global selon le departement
        if ($deptGroupMapping.ContainsKey($dept)) {
            $targetGroup = $deptGroupMapping[$dept]
            $isMember = Get-ADGroupMember -Identity $targetGroup -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $sam }
            if (-not $isMember) {
                Add-ADGroupMember -Identity $targetGroup -Members $sam
                Write-Log -Level "SUCCESS" -Message "Utilisateur $sam ajoute au groupe $targetGroup"
            } else {
                Write-Log -Level "INFO" -Message "Utilisateur $sam est deja membre de $targetGroup"
            }
        } else {
            Write-Log -Level "WARNING" -Message "Departement '$dept' non reconnu pour l'utilisateur $sam"
        }
    } catch {
        Write-Log -Level "ERROR" -Message "Erreur lors du traitement de l'utilisateur $sam : $_"
    }
}

# Provisionnement des Comptes d'Administration Tiering (T0 / T1 / T2)
Write-Log -Level "INFO" -Message "Provisionnement des comptes de Tiering (T0, T1, T2)..."

$tieringAccounts = @(
    @{
        SamAccountName = "adm-t0-mathis"
        DisplayName    = "Admin Tier 0 - Mathis"
        FirstName      = "Mathis"
        LastName       = "Admin-T0"
        TargetOU       = "OU=T0-Admins,OU=Administration,OU=Nexus360,$DomainDN"
        PrimaryGroup   = "GG_Admins_T0"
        BuiltInGroups  = @("Domain Admins")
        Description    = "Compte d'administration Tier 0 (Controleurs de domaine AD DS, PKI)"
    },
    @{
        SamAccountName = "adm-t1-mathis"
        DisplayName    = "Admin Tier 1 - Mathis"
        FirstName      = "Mathis"
        LastName       = "Admin-T1"
        TargetOU       = "OU=T1-Admins,OU=Administration,OU=Nexus360,$DomainDN"
        PrimaryGroup   = "GG_Admins_T1"
        BuiltInGroups  = @()
        Description    = "Compte d'administration Tier 1 (Serveurs membres, services d'infrastructure)"
    },
    @{
        SamAccountName = "adm-t2-mathis"
        DisplayName    = "Admin Tier 2 - Mathis"
        FirstName      = "Mathis"
        LastName       = "Admin-T2"
        TargetOU       = "OU=T2-Admins,OU=Administration,OU=Nexus360,$DomainDN"
        PrimaryGroup   = "GG_Admins_T2"
        BuiltInGroups  = @()
        Description    = "Compte d'administration Tier 2 (Postes de travail, assistance support)"
    }
)

foreach ($adm in $tieringAccounts) {
    $sam = $adm.SamAccountName
    $upn = "$sam@$DomainName"

    try {
        $existing = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
        if ($null -eq $existing) {
            New-ADUser -Name $adm.DisplayName `
                       -GivenName $adm.FirstName `
                       -Surname $adm.LastName `
                       -DisplayName $adm.DisplayName `
                       -SamAccountName $sam `
                       -UserPrincipalName $upn `
                       -Description $adm.Description `
                       -Path $adm.TargetOU `
                       -AccountPassword $secureAdminPass `
                       -Enabled $true `
                       -PasswordNeverExpires $true `
                       -ChangePasswordAtLogon $false
            Write-Log -Level "SUCCESS" -Message "Compte de Tiering cree : $sam dans $($adm.TargetOU)"
        } else {
            Write-Log -Level "INFO" -Message "Compte de Tiering deja existant (idempotent) : $sam"
        }

        # Affectation au groupe global Tiering specifique
        if ($adm.PrimaryGroup) {
            $isMember = Get-ADGroupMember -Identity $adm.PrimaryGroup -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $sam }
            if (-not $isMember) {
                Add-ADGroupMember -Identity $adm.PrimaryGroup -Members $sam
                Write-Log -Level "SUCCESS" -Message "Compte $sam ajoute a $($adm.PrimaryGroup)"
            }
        }

        # Affectation aux groupes built-in le cas echeant (ex: Domain Admins pour T0)
        foreach ($bGrp in $adm.BuiltInGroups) {
            $isBmember = Get-ADGroupMember -Identity $bGrp -ErrorAction SilentlyContinue | Where-Object { $_.SamAccountName -eq $sam }
            if (-not $isBmember) {
                Add-ADGroupMember -Identity $bGrp -Members $sam
                Write-Log -Level "SUCCESS" -Message "Compte $sam ajoute au groupe delegue $bGrp"
            }
        }
    } catch {
        Write-Log -Level "ERROR" -Message "Erreur lors de la creation du compte Tiering $sam : $_"
    }
}

Write-Log -Level "SUCCESS" -Message "Importation des utilisateurs et provisionnement du Tiering termines avec succes."
