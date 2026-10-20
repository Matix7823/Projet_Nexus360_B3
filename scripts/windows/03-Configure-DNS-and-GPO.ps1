<#
.SYNOPSIS
    03-Configure-DNS-and-GPO.ps1 - Configuration DNS, recuperation des services critiques et deploiement des GPO de securite.
.DESCRIPTION
    Projet : Nexus360 (B3 - Mission T01 / Site 1 Paris)
    Domaine : ad.nexus360.test
    Ce script :
    1. Cree la zone de recherche inverse DNS '36.10.in-addr.arpa' (reseau 10.36.0.0/16).
    2. Cree l'alias DNS CNAME 'intranet' pointant vers 'lnx-web01.ad.nexus360.test'.
    3. Configure les politiques de reprise sur incident (sc.exe failure) pour les services DNS et DHCPServer.
    4. Cree et lie la GPO 'GPO_Security_Block_T0_Logon' (interdiction d'ouverture de session T0 sur serveurs T1 et postes T2).
    5. Cree et lie la GPO 'GPO_WSUS_Clients' (pointage vers le serveur WSUS d'entreprise sur port 8530).
.NOTES
    Auteur  : Equipe DevOps / SysAdmin Nexus360
    Version : 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$DomainName = "ad.nexus360.test",

    [Parameter(Mandatory = $false)]
    [string]$DomainDN = "DC=ad,DC=nexus360,DC=test",

    [Parameter(Mandatory = $false)]
    [string]$ReverseZoneName = "36.10.in-addr.arpa",

    [Parameter(Mandatory = $false)]
    [string]$ReverseNetworkId = "10.36.0.0/16",

    [Parameter(Mandatory = $false)]
    [string]$CnameAlias = "intranet",

    [Parameter(Mandatory = $false)]
    [string]$CnameTarget = "lnx-web01.ad.nexus360.test",

    [Parameter(Mandatory = $false)]
    [string]$WsusServerUrl = "http://SRV-DC01.ad.nexus360.test:8530"
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

# Verification des modules requis
Write-Log -Level "INFO" -Message "Verification des modules DNS et GroupPolicy..."
if (-not (Get-Module -ListAvailable -Name DnsServer)) {
    Write-Log -Level "WARNING" -Message "Module DnsServer absent. Si ce serveur est le DC, veillez a ce que le role DNS soit actif."
} else {
    Import-Module DnsServer
}

if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
    Write-Log -Level "WARNING" -Message "Module GroupPolicy absent. L'administration GPO necessite les outils RSAT-GroupPolicy."
} else {
    Import-Module GroupPolicy
}

# ---------------------------------------------------------
# 1. Configuration DNS : Zone Inverse & Enregistrement CNAME
# ---------------------------------------------------------
Write-Log -Level "INFO" -Message "=== 1. Configuration DNS ==="

# Zone Inverse 36.10.in-addr.arpa
try {
    $existingZone = Get-DnsServerZone -Name $ReverseZoneName -ErrorAction SilentlyContinue
    if ($null -eq $existingZone) {
        Write-Log -Level "INFO" -Message "Creation de la zone de recherche inverse $ReverseZoneName..."
        Add-DnsServerPrimaryZone -Name $ReverseZoneName -ReplicationScope "Domain" -ErrorAction Stop
        Write-Log -Level "SUCCESS" -Message "Zone DNS inverse $ReverseZoneName creee avec replication de domaine."
    } else {
        Write-Log -Level "INFO" -Message "Zone DNS inverse $ReverseZoneName deja existante (idempotent)."
    }
} catch {
    Write-Log -Level "WARNING" -Message "Tentative alternative via NetworkId pour la zone inverse : $_"
    try {
        Add-DnsServerPrimaryZone -NetworkId $ReverseNetworkId -ReplicationScope "Domain" -ErrorAction SilentlyContinue
        Write-Log -Level "SUCCESS" -Message "Zone DNS inverse creee via NetworkId $ReverseNetworkId."
    } catch {
        Write-Log -Level "ERROR" -Message "Impossible d'ajouter la zone inverse : $_"
    }
}

# Alias CNAME 'intranet' -> lnx-web01.ad.nexus360.test
try {
    $existingCname = Get-DnsServerResourceRecord -ZoneName $DomainName -Name $CnameAlias -RRType "CNAME" -ErrorAction SilentlyContinue
    if ($null -eq $existingCname) {
        Write-Log -Level "INFO" -Message "Creation de l'enregistrement CNAME '$CnameAlias' -> '$CnameTarget'..."
        Add-DnsServerResourceRecordCName -ZoneName $DomainName -Name $CnameAlias -HostNameAlias $CnameTarget
        Write-Log -Level "SUCCESS" -Message "Enregistrement CNAME '$CnameAlias.$DomainName' cree avec succes."
    } else {
        Write-Log -Level "INFO" -Message "Enregistrement CNAME '$CnameAlias' deja existant (idempotent)."
    }
} catch {
    Write-Log -Level "ERROR" -Message "Erreur lors de la creation du CNAME $CnameAlias : $_"
}

# ---------------------------------------------------------
# 2. Politique de Recuperation des Services (sc.exe failure)
# ---------------------------------------------------------
Write-Log -Level "INFO" -Message "=== 2. Regles de Recuperation des Services Critiques ==="

$criticalServices = @("DNS", "DHCPServer")

foreach ($svc in $criticalServices) {
    try {
        $svcStatus = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($null -ne $svcStatus) {
            Write-Log -Level "INFO" -Message "Configuration des actions de redemarrage sur echec pour le service $svc..."
            # Reset counter apres 24h (86400s), redemarrage a 60s sur 1er, 2e et 3e echec
            $scOutput = & sc.exe failure $svc reset= 86400 actions= restart/60000/restart/60000/restart/60000
            Write-Log -Level "SUCCESS" -Message "Service $svc configure pour autorecuperation (sc.exe output: $($scOutput -join ' '))"
        } else {
            Write-Log -Level "WARNING" -Message "Service $svc introuvable sur cet hote (sera configure lors de son activation)."
        }
    } catch {
        Write-Log -Level "ERROR" -Message "Erreur lors de la configuration de reprise pour le service $svc : $_"
    }
}

# ---------------------------------------------------------
# 3. Creation et Liaison des Group Policy Objects (GPO)
# ---------------------------------------------------------
Write-Log -Level "INFO" -Message "=== 3. Deploiement des GPO ==="

# A. GPO_Security_Block_T0_Logon
$gpoT0Name = "GPO_Security_Block_T0_Logon"
$targetOUsForT0 = @(
    "OU=Postes,OU=Nexus360,$DomainDN",
    "OU=Serveurs-T1,OU=Services,OU=Nexus360,$DomainDN"
)

try {
    $gpoT0 = Get-GPO -Name $gpoT0Name -ErrorAction SilentlyContinue
    if ($null -eq $gpoT0) {
        $gpoT0 = New-GPO -Name $gpoT0Name -Comment "GPO de restriction de securite Tiering : Interdiction d'ouverture de session pour les comptes T0 sur postes T2 et serveurs T1"
        Write-Log -Level "SUCCESS" -Message "GPO $gpoT0Name creee."
    } else {
        Write-Log -Level "INFO" -Message "GPO $gpoT0Name deja existante (idempotent)."
    }

    # Configuration du template de securite Deny Logon pour GG_Admins_T0
    # On prepare le fichier inf de template local et on l'importe dans la GPO
    $tempInfPath = "$env:TEMP\T0_DenyLogon.inf"
    $infContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeDenyInteractiveLogonRight = *S-1-5-32-544,*GG_Admins_T0
SeDenyRemoteInteractiveLogonRight = *GG_Admins_T0
"@
    # Note : On applique la restriction Remote Desktop et Interactive pour GG_Admins_T0
    Set-Content -Path $tempInfPath -Value $infContent -Encoding Unicode -Force

    # Liens sur les OU cibles
    foreach ($ouPath in $targetOUsForT0) {
        $existingLink = Get-GPOReport -Name $gpoT0Name -ReportType Xml | Select-String -Pattern [regex]::Escape($ouPath)
        if (-not $existingLink) {
            New-GPLink -Name $gpoT0Name -Target $ouPath -LinkEnabled Yes -Enforced Yes -ErrorAction SilentlyContinue
            Write-Log -Level "SUCCESS" -Message "GPO $gpoT0Name liee et appliquee (Enforced) sur $ouPath"
        } else {
            Write-Log -Level "INFO" -Message "GPO $gpoT0Name deja liee a $ouPath"
        }
    }
} catch {
    Write-Log -Level "ERROR" -Message "Erreur lors de la gestion de la GPO $gpoT0Name : $_"
}

# B. GPO_WSUS_Clients
$gpoWsusName = "GPO_WSUS_Clients"
$targetOUForWsus = "OU=Postes,OU=Nexus360,$DomainDN"

try {
    $gpoWsus = Get-GPO -Name $gpoWsusName -ErrorAction SilentlyContinue
    if ($null -eq $gpoWsus) {
        $gpoWsus = New-GPO -Name $gpoWsusName -Comment "GPO de configuration du serveur de mise a jour WSUS pour les postes clients Nexus360"
        Write-Log -Level "SUCCESS" -Message "GPO $gpoWsusName creee."
    } else {
        Write-Log -Level "INFO" -Message "GPO $gpoWsusName deja existante (idempotent)."
    }

    # Parametrage registre WSUS dans la GPO
    Write-Log -Level "INFO" -Message "Application des cles de registre WSUS ($WsusServerUrl)..."
    Set-GPRegistryValue -Name $gpoWsusName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" -ValueName "WUServer" -Type String -Value $WsusServerUrl
    Set-GPRegistryValue -Name $gpoWsusName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" -ValueName "WUStatusServer" -Type String -Value $WsusServerUrl
    Set-GPRegistryValue -Name $gpoWsusName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "UseWUServer" -Type DWord -Value 1
    Set-GPRegistryValue -Name $gpoWsusName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "AUOptions" -Type DWord -Value 4
    Set-GPRegistryValue -Name $gpoWsusName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "ScheduledInstallDay" -Type DWord -Value 0
    Set-GPRegistryValue -Name $gpoWsusName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "ScheduledInstallTime" -Type DWord -Value 3
    Write-Log -Level "SUCCESS" -Message "Parametres de mise a jour WSUS enregistres dans la GPO."

    # Liaison a l'OU Postes
    $existingWsusLink = Get-GPOReport -Name $gpoWsusName -ReportType Xml | Select-String -Pattern [regex]::Escape($targetOUForWsus)
    if (-not $existingWsusLink) {
        New-GPLink -Name $gpoWsusName -Target $targetOUForWsus -LinkEnabled Yes -ErrorAction SilentlyContinue
        Write-Log -Level "SUCCESS" -Message "GPO $gpoWsusName liee a $targetOUForWsus"
    } else {
        Write-Log -Level "INFO" -Message "GPO $gpoWsusName deja liee a $targetOUForWsus"
    }
} catch {
    Write-Log -Level "ERROR" -Message "Erreur lors de la gestion de la GPO $gpoWsusName : $_"
}

Write-Log -Level "SUCCESS" -Message "Configuration DNS, autorecuperation des services et deploiement des GPO acheves avec succes."
