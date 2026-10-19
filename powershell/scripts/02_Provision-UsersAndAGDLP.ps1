<#
.SYNOPSIS
    Nexus360 - Provisionnement des Groupes AGDLP et des Utilisateurs.
.DESCRIPTION
    Lit les fichiers config/groups.json et config/users.csv pour :
    1. Créer les groupes globaux (GG_*)
    2. Créer les groupes domaine local (GDL_*)
    3. Imbriquer les GG_* dans les GDL_* (AGDLP)
    4. Créer les utilisateurs et les ajouter à leur groupe GG métier respectif.
.NOTES
    Projet : Nexus360 (T01)
#>

[CmdletBinding()]
param (
    [string]$ConfigFolder = "$PSScriptRoot\..\config"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Nexus360 : Provisionnement Utilisateurs & Modèle AGDLP   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Warning "Module ActiveDirectory non disponible. Exécution en mode simulation."
}

$groupsFile = Join-Path $ConfigFolder "groups.json"
$usersFile  = Join-Path $ConfigFolder "users.csv"

if (-not (Test-Path $groupsFile) -or -not (Test-Path $usersFile)) {
    throw "Les fichiers de configuration ($groupsFile ou $usersFile) sont introuvables."
}

$groupsConfig = Get-Content -Raw -Path $groupsFile | ConvertFrom-Json

# --- 1. Création des Groupes Globaux (GG) ---
Write-Host "`n--- 1. Création des Groupes Globaux (GG) ---" -ForegroundColor Magenta
foreach ($gg in $groupsConfig.global_groups) {
    try {
        [void](Get-ADGroup -Identity $gg.name)
        Write-Host "[EXISTS] Groupe Global : $($gg.name)" -ForegroundColor Yellow
    }
    catch {
        New-ADGroup -Name $gg.name -GroupScope $gg.scope -GroupCategory $gg.category -Path $gg.ou -Description $gg.description
        Write-Host "[CREATED] Groupe Global : $($gg.name)" -ForegroundColor Green
    }
}

# --- 2. Création des Groupes Domaine Local (GDL) & Imbrication ---
Write-Host "`n--- 2. Création des Groupes Domaine Local (GDL) ---" -ForegroundColor Magenta
foreach ($gdl in $groupsConfig.domain_local_groups) {
    try {
        [void](Get-ADGroup -Identity $gdl.name)
        Write-Host "[EXISTS] Groupe Domaine Local : $($gdl.name)" -ForegroundColor Yellow
    }
    catch {
        New-ADGroup -Name $gdl.name -GroupScope $gdl.scope -GroupCategory $gdl.category -Path $gdl.ou -Description $gdl.description
        Write-Host "[CREATED] Groupe Domaine Local : $($gdl.name)" -ForegroundColor Green
    }

    # Imbrication des GG dans le GDL
    if ($gdl.members) {
        foreach ($member in $gdl.members) {
            try {
                Add-ADGroupMember -Identity $gdl.name -Members $member -ErrorAction SilentlyContinue
                Write-Host "  -> [LINKED] Membre $member imbriqué dans $($gdl.name)" -ForegroundColor Cyan
            }
            catch {
                Write-Host "  -> [INFO] $member est déjà membre de $($gdl.name)" -ForegroundColor Gray
            }
        }
    }
}

# --- 3. Provisionnement des Utilisateurs ---
Write-Host "`n--- 3. Provisionnement des Utilisateurs ---" -ForegroundColor Magenta
$users = Import-Csv -Path $usersFile -Delimiter ','

foreach ($user in $users) {
    $sam = $user.SamAccountName
    try {
        [void](Get-ADUser -Identity $sam)
        Write-Host "[EXISTS] Utilisateur : $sam ($($user.FirstName) $($user.LastName))" -ForegroundColor Yellow
    }
    catch {
        $secPassword = ConvertTo-SecureString $user.Password -AsPlainText -Force
        New-ADUser -SamAccountName $sam `
                   -UserPrincipalName "$sam@nexus360.local" `
                   -Name "$($user.FirstName) $($user.LastName)" `
                   -GivenName $user.FirstName `
                   -Surname $user.LastName `
                   -Department $user.Department `
                   -Title $user.Title `
                   -EmailAddress $user.Email `
                   -Path $user.OU `
                   -AccountPassword $secPassword `
                   -Enabled $true `
                   -ChangePasswordAtLogon $false

        Write-Host "[CREATED] Utilisateur : $sam ($($user.Department))" -ForegroundColor Green
    }

    # Affectation de l'utilisateur à son groupe métier (GG_<Department>)
    $departmentGroup = "GG_$($user.Department.Replace(' ', ''))"
    try {
        Add-ADGroupMember -Identity $departmentGroup -Members $sam -ErrorAction SilentlyContinue
        Write-Host "  -> [ASSIGNED] $sam ajouté au groupe métier $departmentGroup" -ForegroundColor DarkCyan
    }
    catch {
        Write-Host "  -> [WARNING] Impossible d'ajouter $sam à $departmentGroup (Groupe inexistant ou déjà membre)" -ForegroundColor DarkYellow
    }
}

Write-Host "`n[SUCCÈS] Provisionnement AGDLP et des utilisateurs terminé !" -ForegroundColor Green
