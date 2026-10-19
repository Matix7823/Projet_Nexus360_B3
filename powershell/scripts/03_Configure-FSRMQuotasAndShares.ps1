<#
.SYNOPSIS
    Nexus360 - Configuration des Partages SMB, Permissions NTFS et Quotas FSRM.
.DESCRIPTION
    Lit le fichier shares.json pour :
    1. Créer les dossiers de stockage locaux
    2. Configurer les partages SMB Windows
    3. Poser les ACLs NTFS précises en utilisant les groupes GDL
    4. Configurer les quotas FSRM (File Server Resource Manager).
.NOTES
    Projet : Nexus360 (T01)
    Exécuter sur les serveurs de fichiers (ex: NX-FS-NORD01 / NX-FS-SUD01).
#>

[CmdletBinding()]
param (
    [string]$ConfigFolder = "$PSScriptRoot\..\config"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Nexus360 : Configuration Partages, NTFS & Quotas FSRM   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$sharesFile = Join-Path $ConfigFolder "shares.json"
if (-not (Test-Path $sharesFile)) {
    throw "Le fichier $sharesFile est introuvable."
}

$sharesConfig = Get-Content -Raw -Path $sharesFile | ConvertFrom-Json
$rootPath = $sharesConfig.shares_root

# Création du dossier racine des partages si inexistant
if (-not (Test-Path $rootPath)) {
    New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
    Write-Host "[CREATED] Dossier racine créé : $rootPath" -ForegroundColor Green
}

# Vérification du rôle FSRM
$fsrmInstalled = (Get-WindowsFeature -Name FS-Resource-Manager -ErrorAction SilentlyContinue).Installed
if (-not $fsrmInstalled) {
    Write-Warning "Le rôle FSRM (File Server Resource Manager) n'est pas actif."
    Write-Warning "Pour l'installer : Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools"
}

foreach ($share in $sharesConfig.shares) {
    $folderPath = Join-Path $rootPath $share.folder_name
    
    # 1. Création du dossier local
    if (-not (Test-Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        Write-Host "`n[FOLDER] Dossier créé : $folderPath" -ForegroundColor Green
    } else {
        Write-Host "`n[FOLDER] Dossier existant : $folderPath" -ForegroundColor Yellow
    }

    # 2. Création ou mise à jour du partage SMB
    $existingShare = Get-SmbShare -Name $share.name -ErrorAction SilentlyContinue
    if (-not $existingShare) {
        New-SmbShare -Name $share.name -Path $folderPath -Description $share.description -FullAccess "Administrateurs","Domain Admins" -ChangeAccess "Authenticated Users" | Out-Null
        Write-Host "  -> [SMB] Partage SMB créé : \\$env:COMPUTERNAME\$($share.name)" -ForegroundColor Cyan
    } else {
        Write-Host "  -> [SMB] Partage SMB déjà existant : $($share.name)" -ForegroundColor Gray
    }

    # 3. Application des Permissions NTFS basées sur le groupe GDL
    try {
        $acl = Get-Acl -Path $folderPath
        # Désactiver l'héritage et copier les droits existants pour isoler chaque partage
        $acl.SetAccessRuleProtection($true, $true)
        
        $rights = [System.Security.AccessControl.FileSystemRights]::$($share.ntfs_permission)
        $inherit = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
        $prop = [System.Security.AccessControl.PropagationFlags]"None"
        $access = [System.Security.AccessControl.AccessControlType]::Allow

        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($share.assigned_group, $rights, $inherit, $prop, $access)
        $acl.AddAccessRule($rule)
        Set-Acl -Path $folderPath -AclObject $acl
        Write-Host "  -> [NTFS] Règle NTFS appliquée pour $($share.assigned_group) ($($share.ntfs_permission))" -ForegroundColor Green
    }
    catch {
        Write-Warning "  -> [NTFS WARNING] Impossible d'appliquer l'ACL pour $($share.assigned_group) : $($_.Exception.Message)"
    }

    # 4. Configuration du Quota FSRM
    if (Get-Command -Name New-FsrmQuota -ErrorAction SilentlyContinue) {
        try {
            $quotaSize = $share.quota_size_gb * 1GB
            $quotaFlags = if ($share.quota_type -eq "Hard") { 0 } else { 1 }
            
            $existingQuota = Get-FsrmQuota -Path $folderPath -ErrorAction SilentlyContinue
            if (-not $existingQuota) {
                New-FsrmQuota -Path $folderPath -Size $quotaSize -Description "Quota Nexus360 $($share.quota_type)" -SoftLimit:($share.quota_type -eq "Soft") | Out-Null
                Write-Host "  -> [FSRM] Quota configuré : $($share.quota_size_gb) Go ($($share.quota_type))" -ForegroundColor Cyan
            } else {
                Write-Host "  -> [FSRM] Quota déjà présent pour $folderPath" -ForegroundColor Gray
            }
        }
        catch {
            Write-Warning "  -> [FSRM WARNING] Erreur quota : $($_.Exception.Message)"
        }
    }
}

Write-Host "`n[SUCCÈS] Configuration des partages et quotas FSRM terminée !" -ForegroundColor Green
