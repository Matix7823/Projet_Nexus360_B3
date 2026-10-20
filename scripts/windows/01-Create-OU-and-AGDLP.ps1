<#
.SYNOPSIS
    01-Create-OU-and-AGDLP.ps1 - Creation idempotente de la structure d'Unites Organisationnelles (OU) et des groupes AGDLP.
.DESCRIPTION
    Projet : Nexus360 (B3 - Mission T01 / Site 1 Paris)
    Domaine : ad.nexus360.test
    Ce script cree l'arborescence Active Directory selon le modele d'administration Tiering (T0/T1/T2),
    ainsi que les Groupes Globaux (GG) et Groupes Locaux de Domaine (DL) requis pour le modele AGDLP.
.NOTES
    Auteur  : Equipe DevOps / SysAdmin Nexus360
    Version : 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$DomainDN = "DC=ad,DC=nexus360,DC=test",

    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "$PSScriptRoot/../../config/ad_structure.json"
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

# Verifier la presence du module ActiveDirectory
Write-Log -Level "INFO" -Message "Verification du module Active Directory..."
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Log -Level "ERROR" -Message "Le module ActiveDirectory n'est pas installe sur ce serveur. Veuillez installer les outils RSAT / AD DS."
    exit 1
}
Import-Module ActiveDirectory

Write-Log -Level "INFO" -Message "Initialisation du deploielement OU et AGDLP sur $DomainDN"

# 1. Structure hierarchique des OU (ordre respecte pour eviter les dependances parent/enfant)
$ouHierarchy = @(
    @{ Name = "Nexus360"; Path = "$DomainDN"; Description = "Racine organisationnelle Nexus360" },
    @{ Name = "Administration"; Path = "OU=Nexus360,$DomainDN"; Description = "Comptes d'administration et modeles de Tiering" },
    @{ Name = "T0-Admins"; Path = "OU=Administration,OU=Nexus360,$DomainDN"; Description = "Tier 0 - Administrateurs Controleurs de Domaine et PKI" },
    @{ Name = "T1-Admins"; Path = "OU=Administration,OU=Nexus360,$DomainDN"; Description = "Tier 1 - Administrateurs Serveurs et Services Applicatifs" },
    @{ Name = "T2-Admins"; Path = "OU=Administration,OU=Nexus360,$DomainDN"; Description = "Tier 2 - Techniciens Support et Postes de Travail" },
    @{ Name = "Services"; Path = "OU=Nexus360,$DomainDN"; Description = "Serveurs membres et services reseau" },
    @{ Name = "Serveurs-T1"; Path = "OU=Services,OU=Nexus360,$DomainDN"; Description = "Serveurs Tier 1 (Fichiers, Web, BDD)" },
    @{ Name = "Postes"; Path = "OU=Nexus360,$DomainDN"; Description = "Postes de travail clients Windows 11" },
    @{ Name = "Utilisateurs"; Path = "OU=Nexus360,$DomainDN"; Description = "Comptes utilisateurs standards Nexus360" },
    @{ Name = "Groupes"; Path = "OU=Nexus360,$DomainDN"; Description = "Groupes de securite globaux et locaux de domaine (AGDLP)" }
)

foreach ($ou in $ouHierarchy) {
    $targetOUPath = "OU=$($ou.Name),$($ou.Path)"
    try {
        $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$targetOUPath'" -ErrorAction SilentlyContinue
        if ($null -eq $existingOU) {
            New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path -Description $ou.Description -ProtectedFromAccidentalDeletion $true
            Write-Log -Level "SUCCESS" -Message "OU creee : $targetOUPath"
        } else {
            Write-Log -Level "INFO" -Message "OU deja existante (idempotent) : $targetOUPath"
        }
    } catch {
        Write-Log -Level "ERROR" -Message "Erreur lors de la creation de l'OU $targetOUPath : $_"
    }
}

# 2. Creation des Groupes de Securite AGDLP
$groupsTargetOU = "OU=Groupes,OU=Nexus360,$DomainDN"

$adGroups = @(
    # Groupes Globaux Metier (GG)
    @{ Name = "GG_Comptabilite"; Scope = "Global"; Category = "Security"; Description = "Groupe Global - Equipe Comptabilite" },
    @{ Name = "GG_Direction"; Scope = "Global"; Category = "Security"; Description = "Groupe Global - Direction Generale" },
    @{ Name = "GG_Exploitation"; Scope = "Global"; Category = "Security"; Description = "Groupe Global - Equipe Exploitation & Maintenance" },
    @{ Name = "GG_Informatique"; Scope = "Global"; Category = "Security"; Description = "Groupe Global - Service Informatique & DevOps" },
    
    # Groupes d'Administration de Tiering
    @{ Name = "GG_Admins_T0"; Scope = "Global"; Category = "Security"; Description = "Groupe Global - Administrateurs Tier 0 (Controleurs de domaine)" },
    @{ Name = "GG_Admins_T1"; Scope = "Global"; Category = "Security"; Description = "Groupe Global - Administrateurs Tier 1 (Serveurs membres)" },
    @{ Name = "GG_Admins_T2"; Scope = "Global"; Category = "Security"; Description = "Groupe Global - Administrateurs Tier 2 (Postes clients)" },

    # Groupes Locaux de Domaine de Ressource (DL)
    @{ Name = "DL_Compta_Share_RW"; Scope = "DomainLocal"; Category = "Security"; Description = "Domain Local - Acces Lecture/Ecriture partage Comptabilite" },
    @{ Name = "DL_Direction_Share_RW"; Scope = "DomainLocal"; Category = "Security"; Description = "Domain Local - Acces Lecture/Ecriture partage Direction" },
    @{ Name = "DL_Exploitation_Share_RW"; Scope = "DomainLocal"; Category = "Security"; Description = "Domain Local - Acces Lecture/Ecriture partage Exploitation" },
    @{ Name = "DL_Informatique_Share_RW"; Scope = "DomainLocal"; Category = "Security"; Description = "Domain Local - Acces Lecture/Ecriture partage Informatique" }
)

foreach ($grp in $adGroups) {
    try {
        $existingGrp = Get-ADGroup -Filter "SamAccountName -eq '$($grp.Name)'" -ErrorAction SilentlyContinue
        if ($null -eq $existingGrp) {
            New-ADGroup -Name $grp.Name `
                        -SamAccountName $grp.Name `
                        -GroupScope $grp.Scope `
                        -GroupCategory $grp.Category `
                        -Path $groupsTargetOU `
                        -Description $grp.Description
            Write-Log -Level "SUCCESS" -Message "Groupe de securite cree : $($grp.Name) ($($grp.Scope)) dans $groupsTargetOU"
        } else {
            Write-Log -Level "INFO" -Message "Groupe deja existant (idempotent) : $($grp.Name)"
        }
    } catch {
        Write-Log -Level "ERROR" -Message "Erreur lors de la creation du groupe $($grp.Name) : $_"
    }
}

# 3. Imbrication AGDLP : Affectation des Groupes Globaux (GG) dans les Groupes Locaux (DL)
$groupNesting = @(
    @{ Member = "GG_Comptabilite"; TargetDL = "DL_Compta_Share_RW" },
    @{ Member = "GG_Direction";    TargetDL = "DL_Direction_Share_RW" },
    @{ Member = "GG_Exploitation"; TargetDL = "DL_Exploitation_Share_RW" },
    @{ Member = "GG_Informatique"; TargetDL = "DL_Informatique_Share_RW" }
)

foreach ($nest in $groupNesting) {
    try {
        $members = Get-ADGroupMember -Identity $nest.TargetDL -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SamAccountName
        if ($members -notcontains $nest.Member) {
            Add-ADGroupMember -Identity $nest.TargetDL -Members $nest.Member
            Write-Log -Level "SUCCESS" -Message "Imbrication AGDLP realisee : $($nest.Member) ajoute a $($nest.TargetDL)"
        } else {
            Write-Log -Level "INFO" -Message "Imbrication deja presente (idempotent) : $($nest.Member) dans $($nest.TargetDL)"
        }
    } catch {
        Write-Log -Level "ERROR" -Message "Erreur lors de l'imbrication de $($nest.Member) dans $($nest.TargetDL) : $_"
    }
}

Write-Log -Level "SUCCESS" -Message "Deploiement de l'arborescence OU et des groupes AGDLP termine avec succes."
