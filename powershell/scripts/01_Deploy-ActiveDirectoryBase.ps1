<#
.SYNOPSIS
    Nexus360 - Initialisation de la structure Active Directory (Unités d'Organisation).
.DESCRIPTION
    Crée l'arbre d'Unité d'Organisation (OU) hiérarchique pour l'entreprise Nexus360
    selon les meilleures pratiques Microsoft et les préconisations du projet B3.
.NOTES
    Projet : Nexus360 (T01)
    Prérequis : Module ActiveDirectory (RSAT / Contrôleur de Domaine)
#>

[CmdletBinding()]
param (
    [string]$DomainDN = "DC=nexus360,DC=local"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Nexus360 : Déploiement de l'arborescence Active Directory " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Vérification de la disponibilité du module ActiveDirectory
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Warning "Le module PowerShell ActiveDirectory n'est pas installé sur cette machine."
    Write-Warning "Exécutez ce script sur un contrôleur de domaine ou avec RSAT installé."
    return
}
Import-Module ActiveDirectory

# Définition des Unités d'Organisation hiérarchiques
$OUHierarchy = @(
    @{ Name = "Nexus360"; Path = $DomainDN; Description = "Racine de l'organisation Nexus360" },
    @{ Name = "Users"; Path = "OU=Nexus360,$DomainDN"; Description = "Comptes utilisateurs par département" },
    @{ Name = "Groups"; Path = "OU=Nexus360,$DomainDN"; Description = "Groupes de sécurité AGDLP" },
    @{ Name = "Computers"; Path = "OU=Nexus360,$DomainDN"; Description = "Postes de travail et serveurs" },
    @{ Name = "ServiceAccounts"; Path = "OU=Nexus360,$DomainDN"; Description = "Comptes de service managés (gMSA)" },
    
    # Sous-OU pour les Départements utilisateurs
    @{ Name = "Direction"; Path = "OU=Users,OU=Nexus360,$DomainDN"; Description = "Direction Générale" },
    @{ Name = "RH"; Path = "OU=Users,OU=Nexus360,$DomainDN"; Description = "Ressources Humaines" },
    @{ Name = "Finance"; Path = "OU=Users,OU=Nexus360,$DomainDN"; Description = "Finance et Comptabilité" },
    @{ Name = "Informatique"; Path = "OU=Users,OU=Nexus360,$DomainDN"; Description = "Direction des Systèmes d'Information" },
    @{ Name = "Ventes"; Path = "OU=Users,OU=Nexus360,$DomainDN"; Description = "Équipes Commerciales" },
    @{ Name = "Production"; Path = "OU=Users,OU=Nexus360,$DomainDN"; Description = "Équipes Usine et Ateliers" },
    
    # Sous-OU pour les Machines
    @{ Name = "Workstations"; Path = "OU=Computers,OU=Nexus360,$DomainDN"; Description = "Postes clients des agences" },
    @{ Name = "Servers"; Path = "OU=Computers,OU=Nexus360,$DomainDN"; Description = "Serveurs membres du domaine" }
)

foreach ($ou in $OUHierarchy) {
    $targetDN = "OU=$($ou.Name),$($ou.Path)"
    try {
        [void](Get-ADOrganizationalUnit -Identity $targetDN)
        Write-Host "[EXISTS] L'OU existe déjà : $targetDN" -ForegroundColor Yellow
    }
    catch {
        New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path -Description $ou.Description -ProtectedFromAccidentalDeletion $true
        Write-Host "[CREATED] OU créée avec succès : $targetDN" -ForegroundColor Green
    }
}

Write-Host "`n[SUCCÈS] Arborescence Active Directory initialisée avec succès !" -ForegroundColor Green
