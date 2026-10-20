<#
.SYNOPSIS
    04-Setup-DHCP-Failover.ps1 - Configuration du scope DHCP local et mise en place du basculement (Failover LoadBalance 50/50).
.DESCRIPTION
    Projet : Nexus360 (B3 - Mission T01 / Site 1 Paris)
    Domaine : ad.nexus360.test
    Ce script :
    1. Installe et verifie le role DHCP Server sur SRV-DC01 (10.36.11.10).
    2. Cree et active le scope DHCP du Site 1 (10.36.11.0/24 : 10.36.11.100 a 10.36.11.200).
    3. Configure les options DHCP critiques (Router 10.36.11.1, DNS 10.36.11.10 / 10.36.12.11, Domaine ad.nexus360.test).
    4. Initialise ou prepare l'association de basculement DHCP Failover en mode 'LoadBalance' (50% / 50%)
       avec le controleur de domaine secondaire SRV-DC02 (10.36.12.11) sur le Site 2.
.NOTES
    Auteur  : Equipe DevOps / SysAdmin Nexus360
    Version : 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ScopeId = "10.36.11.0",

    [Parameter(Mandatory = $false)]
    [string]$SubnetMask = "255.255.255.0",

    [Parameter(Mandatory = $false)]
    [string]$ScopeName = "Scope-Site1-Clients",

    [Parameter(Mandatory = $false)]
    [string]$StartRange = "10.36.11.100",

    [Parameter(Mandatory = $false)]
    [string]$EndRange = "10.36.11.200",

    [Parameter(Mandatory = $false)]
    [string]$RouterIp = "10.36.11.1",

    [Parameter(Mandatory = $false)]
    [string[]]$DnsServers = @("10.36.11.10", "10.36.12.11"),

    [Parameter(Mandatory = $false)]
    [string]$DomainName = "ad.nexus360.test",

    [Parameter(Mandatory = $false)]
    [string]$PartnerServer = "10.36.12.11",

    [Parameter(Mandatory = $false)]
    [string]$RelationshipName = "Nexus360-DHCP-Failover",

    [Parameter(Mandatory = $false)]
    [string]$SharedSecret = "NexusDhcpSecret2026!"
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

# Verifier et importer le module DhcpServer
if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
    Write-Log -Level "ERROR" -Message "Le module DhcpServer n'est pas installe. Installez la fonctionnalite DHCP."
    exit 1
}
Import-Module DhcpServer

Write-Log -Level "INFO" -Message "Initialisation de la configuration DHCP et de la haute disponibilite..."

# 1. Creation du Scope DHCP Site 1
try {
    $existingScope = Get-DhcpServerv4Scope -ScopeId $ScopeId -ErrorAction SilentlyContinue
    if ($null -eq $existingScope) {
        Write-Log -Level "INFO" -Message "Creation de l'etendue DHCP $ScopeId ($StartRange - $EndRange)..."
        Add-DhcpServerv4Scope -ScopeId $ScopeId `
                              -SubnetMask $SubnetMask `
                              -Name $ScopeName `
                              -StartRange $StartRange `
                              -EndRange $EndRange `
                              -Description "Etendue DHCP des postes clients Site 1 (Paris)" `
                              -State Active
        Write-Log -Level "SUCCESS" -Message "Etendue DHCP $ScopeId creee et activee."
    } else {
        Write-Log -Level "INFO" -Message "Etendue DHCP $ScopeId deja existante (idempotent)."
    }
} catch {
    Write-Log -Level "ERROR" -Message "Erreur lors de la creation du scope DHCP : $_"
}

# 2. Configuration des Options du Scope DHCP
try {
    Write-Log -Level "INFO" -Message "Configuration des options de l'etendue (Router, DNS, Domain)..."
    
    # Option 003 : Router / Passerelle par defaut
    Set-DhcpServerv4OptionValue -ScopeId $ScopeId -OptionId 3 -Value $RouterIp -Force
    Write-Log -Level "SUCCESS" -Message "Option 003 (Router) definie sur $RouterIp"

    # Option 006 : Serveurs DNS
    Set-DhcpServerv4OptionValue -ScopeId $ScopeId -OptionId 6 -Value $DnsServers -Force
    Write-Log -Level "SUCCESS" -Message "Option 006 (DNS Servers) definie sur $($DnsServers -join ', ')"

    # Option 015 : Nom de Domaine DNS
    Set-DhcpServerv4OptionValue -ScopeId $ScopeId -OptionId 15 -Value $DomainName -Force
    Write-Log -Level "SUCCESS" -Message "Option 015 (Domain Name) definie sur $DomainName"

} catch {
    Write-Log -Level "ERROR" -Message "Erreur lors de la configuration des options DHCP : $_"
}

# 3. Activation du Basculement DHCP Failover (Load Balance 50/50)
Write-Log -Level "INFO" -Message "Verification du partenaire DHCP Failover : $PartnerServer..."

$isPartnerReachable = Test-Connection -ComputerName $PartnerServer -Count 1 -Quiet -ErrorAction SilentlyContinue

try {
    $existingRelationship = Get-DhcpServerv4Failover -Name $RelationshipName -ErrorAction SilentlyContinue
    if ($null -eq $existingRelationship) {
        if ($isPartnerReachable) {
            Write-Log -Level "INFO" -Message "Partenaire $PartnerServer joignable. Creation de la relation de failover $RelationshipName..."
            Add-DhcpServerv4Failover -Name $RelationshipName `
                                     -ScopeId $ScopeId `
                                     -PartnerServer $PartnerServer `
                                     -Mode LoadBalance `
                                     -Percentage 50 `
                                     -SharedSecret $SharedSecret `
                                     -MaxClientLeadTime (New-TimeSpan -Hours 1) `
                                     -StateSwitchInterval (New-TimeSpan -Hours 1) `
                                     -AutoStateTransition $true
            Write-Log -Level "SUCCESS" -Message "Association DHCP Failover creee avec succes en LoadBalance 50/50 avec $PartnerServer."
        } else {
            Write-Log -Level "WARNING" -Message "Le partenaire $PartnerServer (SRV-DC02) n'est pas encore joignable sur le reseau."
            Write-Log -Level "INFO" -Message "Le scope local est pret. Des que SRV-DC02 sera instancie sur le Site 2, rejouez ce script ou executez :"
            Write-Log -Level "INFO" -Message "Add-DhcpServerv4Failover -Name '$RelationshipName' -ScopeId '$ScopeId' -PartnerServer '$PartnerServer' -Mode LoadBalance -Percentage 50 -SharedSecret '***'"
        }
    } else {
        Write-Log -Level "INFO" -Message "Relation de failover '$RelationshipName' deja existante (idempotent)."
    }
} catch {
    Write-Log -Level "ERROR" -Message "Erreur lors de la mise en place du Failover DHCP : $_"
}

Write-Log -Level "SUCCESS" -Message "Configuration DHCP pour le Site 1 terminee."
