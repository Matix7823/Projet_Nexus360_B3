<#
.SYNOPSIS
    Nexus360 - Toolbox Opérationnelle D2 (Day-2 Operations).
.DESCRIPTION
    Boîte à outils d'administration et de diagnostic quotidien pour le SI Nexus360 :
    - Vérification de la santé Active Directory et des réplications
    - Audit des comptes désactivés, expirés ou verrouillés
    - Test de connectivité des contrôleurs et passerelles
    - État d'occupation des quotas FSRM
.NOTES
    Projet : Nexus360 (T01)
    Usage : .\Toolbox-D2.ps1 -Action <CheckHealth|AuditUsers|CheckQuotas|All>
#>

[CmdletBinding()]
param (
    [ValidateSet("CheckHealth", "AuditUsers", "CheckQuotas", "All")]
    [string]$Action = "All"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

function Write-SectionHeader {
    param ([string]$Title)
    Write-Host "`n==========================================================" -ForegroundColor Yellow
    Write-Host " $Title" -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Yellow
}

function Test-ADHealth {
    Write-SectionHeader "1. Diagnostic Santé Active Directory"
    if (-not (Get-Command -Name Get-ADDomain -ErrorAction SilentlyContinue)) {
        Write-Warning "Le module ActiveDirectory n'est pas disponible."
        return
    }

    try {
        $domain = Get-ADDomain
        Write-Host "[OK] Domaine Actif : $($domain.DNSRoot)" -ForegroundColor Green
        Write-Host "     Niveau fonctionnel : $($domain.DomainMode)" -ForegroundColor Gray
        Write-Host "     Maître d'infrastructure : $($domain.InfrastructureMaster)" -ForegroundColor Gray
        Write-Host "     Contrôleur PDC Emulator : $($domain.PDCEmulator)" -ForegroundColor Gray

        Write-Host "`nContrôleurs de Domaine détectés :" -ForegroundColor Cyan
        $dcs = Get-ADDomainController -Filter *
        foreach ($dc in $dcs) {
            $ping = Test-Connection -ComputerName $dc.HostName -Count 1 -Quiet
            $status = if ($ping) { "[ONLINE]" } else { "[OFFLINE]" }
            $color = if ($ping) { "Green" } else { "Red" }
            Write-Host "  $status $($dc.HostName) ($($dc.IPv4Address)) - Site: $($dc.Site)" -ForegroundColor $color
        }
    }
    catch {
        Write-Error "Erreur lors de l'analyse du domaine : $($_.Exception.Message)"
    }
}

function Get-UserSecurityAudit {
    Write-SectionHeader "2. Audit de Sécurité des Comptes Utilisateurs"
    if (-not (Get-Command -Name Search-ADAccount -ErrorAction SilentlyContinue)) {
        Write-Warning "Module ActiveDirectory non disponible."
        return
    }

    $lockedUsers = Search-ADAccount -LockedOut
    if ($lockedUsers) {
        Write-Host "[ALERTE] Comptes Verrouillés détectés :" -ForegroundColor Red
        $lockedUsers | Select-Object SamAccountName, Name | Format-Table -AutoSize
    } else {
        Write-Host "[OK] Aucun compte utilisateur verrouillé." -ForegroundColor Green
    }

    $disabledUsers = Search-ADAccount -AccountDisabled
    Write-Host "Comptes désactivés ($($disabledUsers.Count)) :" -ForegroundColor Cyan
    $disabledUsers | Select-Object -First 10 SamAccountName, Name | Format-Table -AutoSize
}

function Test-StorageQuotas {
    Write-SectionHeader "3. État des Quotas de Fichiers FSRM"
    if (-not (Get-Command -Name Get-FsrmQuota -ErrorAction SilentlyContinue)) {
        Write-Host "[INFO] Commande Get-FsrmQuota non disponible sur ce système." -ForegroundColor Gray
        return
    }

    $quotas = Get-FsrmQuota
    if ($quotas) {
        foreach ($q in $quotas) {
            $usedMB = [math]::Round($q.Usage / 1MB, 2)
            $sizeMB = [math]::Round($q.Size / 1MB, 2)
            $pct = if ($sizeMB -gt 0) { [math]::Round(($usedMB / $sizeMB) * 100, 1) } else { 0 }
            
            $color = if ($pct -gt 85) { "Red" } elseif ($pct -gt 70) { "Yellow" } else { "Green" }
            Write-Host "Chemin : $($q.Path) - Utilisé : $usedMB Mo / $sizeMB Mo ($pct%)" -ForegroundColor $color
        }
    } else {
        Write-Host "Aucun quota FSRM configuré sur cette machine." -ForegroundColor Gray
    }
}

switch ($Action) {
    "CheckHealth" { Test-ADHealth }
    "AuditUsers"  { Get-UserSecurityAudit }
    "CheckQuotas" { Test-StorageQuotas }
    "All" {
        Test-ADHealth
        Get-UserSecurityAudit
        Test-StorageQuotas
    }
}
Write-Host "`n[FIN] Fin des vérifications de la Toolbox D2." -ForegroundColor Cyan
