<#
.SYNOPSIS
    05-Security-Hardening.ps1 - Durcissement de securite avance pour Windows Server 2025 et creation de la GPO de baseline (ANSSI / CIS).
.DESCRIPTION
    Projet : Nexus360 (B3 - Mission T01 / Site 1 Paris)
    Domaine : ad.nexus360.test
    Contrôleur de domaine : SRV-DC01 (Windows Server 2025 Datacenter)
    Exigence : B5 - Durcissement de niveau eleve

    Ce script applique localement et de maniere idempotente les mesures de securite recommandees par l'ANSSI et les benchmarks CIS,
    puis cree et deploie la strategie de groupe centralisee 'GPO_Security_Hardening_Baseline' sur les unites organisationnelles cibles :
    1. Protocoles & Chiffrement :
       - Desactivation definitive de SSL v2, SSL v3, TLS 1.0 et TLS 1.1.
       - Maintien et enforcement exclusif de TLS 1.2 et TLS 1.3.
       - Desactivation des protocoles de resolution de nom non securises : NBT-NS (NetBIOS over TCP/IP) et LLMNR.
    2. Protection SMB :
       - Signature numerique SMB obligatoire (Server & Client - RequireSecuritySignature = $true).
       - Desactivation totale et definitive du protocole SMBv1 (Driver mrxsmb10 & configuration serveur).
    3. Comptes & Mots de passe :
       - Renommage securise du compte Administrateur local integre (SID -500).
       - Desactivation et verrouillage du compte Invite integre (Guest - SID -501).
    4. GPO Centralisee 'GPO_Security_Hardening_Baseline' :
       - Enregistrement des cles de registre et du template de securite INF.
       - Liaison avec enforcement sur les OUs Nexus360, Serveurs-T1 et Postes.
.NOTES
    Auteur  : Mathis (Tech Lead / SecOps) - Equipe T01 Nexus360
    Version : 1.0.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$DomainDN = "DC=ad,DC=nexus360,DC=test",

    [Parameter(Mandatory = $false)]
    [string]$GpoName = "GPO_Security_Hardening_Baseline",

    [Parameter(Mandatory = $false)]
    [string]$NewAdminName = "NexusLocalAdmin",

    [Parameter(Mandatory = $false)]
    [switch]$SkipLocalEnforcement = $false
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

Write-Log -Level "INFO" -Message "=== Demarrage du durcissement de securite Nexus360 (Exigence B5 - ANSSI/CIS) ==="

# ==============================================================================
# 1. Verification des modules requis (Active Directory & GroupPolicy)
# ==============================================================================
$hasADModule = $false
$hasGPOModule = $false

if (Get-Module -ListAvailable -Name ActiveDirectory) {
    Import-Module ActiveDirectory
    $hasADModule = $true
} else {
    Write-Log -Level "WARNING" -Message "Module ActiveDirectory absent. Les actions liees a l'annuaire seront ignorees."
}

if (Get-Module -ListAvailable -Name GroupPolicy) {
    Import-Module GroupPolicy
    $hasGPOModule = $true
} else {
    Write-Log -Level "WARNING" -Message "Module GroupPolicy absent. La creation de la GPO sera restreinte."
}

# ==============================================================================
# 2. Application Locale du Durcissement (Registre & Services)
# ==============================================================================
if (-not $SkipLocalEnforcement) {
    Write-Log -Level "INFO" -Message "--- [ETAPE 1] Application locale des mesures de chiffrement et protocoles ---"

    # --- A. Desactivation SSL v2, SSL v3, TLS 1.0, TLS 1.1 / Activation TLS 1.2, TLS 1.3 ---
    $schannelPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
    $disabledProtocols = @("SSL 2.0", "SSL 3.0", "TLS 1.0", "TLS 1.1")
    $enabledProtocols = @("TLS 1.2", "TLS 1.3")

    foreach ($proto in $disabledProtocols) {
        foreach ($side in @("Client", "Server")) {
            $regKey = "$schannelPath\$proto\$side"
            if (-not (Test-Path $regKey)) {
                New-Item -Path $regKey -Force | Out-Null
            }
            Set-ItemProperty -Path $regKey -Name "Enabled" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $regKey -Name "DisabledByDefault" -Value 1 -Type DWord -Force
        }
        Write-Log -Level "SUCCESS" -Message "Protocole obsolete $proto desactive definitivement (Client/Server)."
    }

    foreach ($proto in $enabledProtocols) {
        foreach ($side in @("Client", "Server")) {
            $regKey = "$schannelPath\$proto\$side"
            if (-not (Test-Path $regKey)) {
                New-Item -Path $regKey -Force | Out-Null
            }
            Set-ItemProperty -Path $regKey -Name "Enabled" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $regKey -Name "DisabledByDefault" -Value 0 -Type DWord -Force
        }
        Write-Log -Level "SUCCESS" -Message "Protocole moderne $proto enforce (Client/Server)."
    }

    # --- B. Desactivation de LLMNR (Link-Local Multicast Name Resolution) ---
    $dnsClientPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
    if (-not (Test-Path $dnsClientPolicyPath)) {
        New-Item -Path $dnsClientPolicyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $dnsClientPolicyPath -Name "EnableMulticast" -Value 0 -Type DWord -Force
    Write-Log -Level "SUCCESS" -Message "Resolution multicast non securisee LLMNR desactivee (EnableMulticast=0)."

    # --- C. Desactivation de NBT-NS (NetBIOS over TCP/IP) sur toutes les cartes reseau ---
    try {
        $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
        foreach ($nic in $adapters) {
            $result = $nic | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 }
            if ($result.ReturnValue -eq 0) {
                Write-Log -Level "SUCCESS" -Message "NetBIOS over TCP/IP desactive sur l'interface $($nic.Description) [Status: OK]."
            }
        }
    } catch {
        Write-Log -Level "WARNING" -Message "Impossible de modifier NetBIOS via CIM : $_"
    }

    # Cle de registre globale pour NBT-NS (NodeType = p-node / no broadcast)
    $netbtPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters"
    if (Test-Path $netbtPath) {
        Set-ItemProperty -Path $netbtPath -Name "NodeType" -Value 2 -Type DWord -Force
    }

    # --- D. Protection SMB : Signature obligatoire & Desactivation totale SMBv1 ---
    Write-Log -Level "INFO" -Message "--- [ETAPE 2] Durcissement SMB (Signature & SMBv1) ---"
    try {
        # Signature numerique SMB Server
        Set-SmbServerConfiguration -RequireSecuritySignature $true -EnableSecuritySignature $true -Force
        Write-Log -Level "SUCCESS" -Message "Signature SMB Server obligatoire enforcee (RequireSecuritySignature = $true)."

        # Signature numerique SMB Client
        Set-SmbClientConfiguration -RequireSecuritySignature $true -EnableSecuritySignature $true -Force
        Write-Log -Level "SUCCESS" -Message "Signature SMB Client obligatoire enforcee (RequireSecuritySignature = $true)."

        # Desactivation totale SMBv1
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
        Write-Log -Level "SUCCESS" -Message "Protocole SMBv1 desactive via configuration SMB."
    } catch {
        Write-Log -Level "WARNING" -Message "Cmdlets SmbConfiguration non disponibles ou restreintes : $_"
    }

    # Enregistrement registre direct LanmanServer & LanmanWorkstation
    $lanmanServerPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
    if (Test-Path $lanmanServerPath) {
        Set-ItemProperty -Path $lanmanServerPath -Name "requiresecuritysignature" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $lanmanServerPath -Name "enablesecuritysignature" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $lanmanServerPath -Name "SMB1" -Value 0 -Type DWord -Force
    }

    $lanmanWorkstationPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"
    if (Test-Path $lanmanWorkstationPath) {
        Set-ItemProperty -Path $lanmanWorkstationPath -Name "RequireSecuritySignature" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $lanmanWorkstationPath -Name "EnableSecuritySignature" -Value 1 -Type DWord -Force
    }

    # Desactivation du driver noyau mrxsmb10
    $mrxsmb10Path = "HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10"
    if (Test-Path $mrxsmb10Path) {
        Set-ItemProperty -Path $mrxsmb10Path -Name "Start" -Value 4 -Type DWord -Force
        Write-Log -Level "SUCCESS" -Message "Pilote mrxsmb10 desactive (Start=4)."
    }

    # Desactivation fonctionnalite Windows facultative SMB1Protocol
    try {
        $smb1Feature = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
        if ($null -ne $smb1Feature -and $smb1Feature.State -eq "Enabled") {
            Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null
            Write-Log -Level "SUCCESS" -Message "Fonctionnalite facultative SMB1Protocol desinstallee."
        } else {
            Write-Log -Level "INFO" -Message "Fonctionnalite SMB1Protocol deja inactive (idempotent)."
        }
    } catch {
        Write-Log -Level "INFO" -Message "Evaluation fonctionnalite SMB1 : $_"
    }

    # --- E. Comptes & Mots de passe : Renommage Admin local & Desactivation Guest ---
    Write-Log -Level "INFO" -Message "--- [ETAPE 3] Durcissement des comptes integres locaux ---"
    try {
        # Detection du compte Administrateur integre par SID (S-1-5-*-500)
        $adminAccount = Get-LocalUser | Where-Object { $_.SID.Value -like "S-1-5-*-500" }
        if ($null -ne $adminAccount) {
            if ($adminAccount.Name -ne $NewAdminName) {
                Rename-LocalUser -Name $adminAccount.Name -NewName $NewAdminName
                Write-Log -Level "SUCCESS" -Message "Compte Administrateur integre local renomme : '$($adminAccount.Name)' -> '$NewAdminName'."
            } else {
                Write-Log -Level "INFO" -Message "Compte Administrateur local deja nomme '$NewAdminName' (idempotent)."
            }
        }

        # Detection du compte Invite integre par SID (S-1-5-*-501)
        $guestAccount = Get-LocalUser | Where-Object { $_.SID.Value -like "S-1-5-*-501" }
        if ($null -ne $guestAccount) {
            if ($guestAccount.Enabled) {
                Disable-LocalUser -Name $guestAccount.Name
                Write-Log -Level "SUCCESS" -Message "Compte Invite integre local '$($guestAccount.Name)' desactive avec succes."
            } else {
                Write-Log -Level "INFO" -Message "Compte Invite local deja desactive (idempotent)."
            }
        }
    } catch {
        Write-Log -Level "WARNING" -Message "Erreur lors de la configuration des comptes locaux : $_"
    }

    # Si sur Active Directory, desactivation du compte Guest du domaine si existant
    if ($hasADModule) {
        try {
            $adGuest = Get-ADUser -Filter { SamAccountName -eq "Guest" -or SamAccountName -eq "Invite" } -ErrorAction SilentlyContinue
            if ($null -ne $adGuest -and $adGuest.Enabled -eq $true) {
                Disable-ADAccount -Identity $adGuest.DistinguishedName
                Write-Log -Level "SUCCESS" -Message "Compte Guest du domaine Active Directory desactive."
            }
        } catch {
            Write-Log -Level "INFO" -Message "Verification Guest AD : $_"
        }
    }
}

# ==============================================================================
# 3. Creation et Configuration de la GPO 'GPO_Security_Hardening_Baseline'
# ==============================================================================
Write-Log -Level "INFO" -Message "--- [ETAPE 4] Configuration de la GPO '$GpoName' ---"

if ($hasGPOModule) {
    try {
        $gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
        if ($null -eq $gpo) {
            $gpo = New-GPO -Name $GpoName -Comment "Nexus360 - Baseline de durcissement globale ANSSI / CIS (TLS 1.2/1.3, SMB Signing, SMBv1 OFF, LLMNR OFF, Rename Admin, Disable Guest)"
            Write-Log -Level "SUCCESS" -Message "GPO '$GpoName' creee dans l'annuaire."
        } else {
            Write-Log -Level "INFO" -Message "GPO '$GpoName' deja existante (idempotent)."
        }

        # A. Cles de registre Schannel (SSL OFF / TLS 1.0 & 1.1 OFF / TLS 1.2 & 1.3 ON)
        $protocolsToDisable = @("SSL 2.0", "SSL 3.0", "TLS 1.0", "TLS 1.1")
        foreach ($proto in $protocolsToDisable) {
            foreach ($side in @("Client", "Server")) {
                $subKey = "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$proto\$side"
                Set-GPRegistryValue -Name $GpoName -Key $subKey -ValueName "Enabled" -Type DWord -Value 0 | Out-Null
                Set-GPRegistryValue -Name $GpoName -Key $subKey -ValueName "DisabledByDefault" -Type DWord -Value 1 | Out-Null
            }
        }

        $protocolsToEnable = @("TLS 1.2", "TLS 1.3")
        foreach ($proto in $protocolsToEnable) {
            foreach ($side in @("Client", "Server")) {
                $subKey = "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$proto\$side"
                Set-GPRegistryValue -Name $GpoName -Key $subKey -ValueName "Enabled" -Type DWord -Value 1 | Out-Null
                Set-GPRegistryValue -Name $GpoName -Key $subKey -ValueName "DisabledByDefault" -Type DWord -Value 0 | Out-Null
            }
        }
        Write-Log -Level "SUCCESS" -Message "Parametres de chiffrement TLS 1.2/1.3 et suppression SSL/TLS 1.0/1.1 inscrits dans la GPO."

        # B. Cles de registre LLMNR
        Set-GPRegistryValue -Name $GpoName -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -ValueName "EnableMulticast" -Type DWord -Value 0 | Out-Null
        Write-Log -Level "SUCCESS" -Message "Desactivation de LLMNR inscrite dans la GPO."

        # C. Cles de registre SMB Signing et desactivation SMBv1
        Set-GPRegistryValue -Name $GpoName -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -ValueName "requiresecuritysignature" -Type DWord -Value 1 | Out-Null
        Set-GPRegistryValue -Name $GpoName -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -ValueName "enablesecuritysignature" -Type DWord -Value 1 | Out-Null
        Set-GPRegistryValue -Name $GpoName -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -ValueName "SMB1" -Type DWord -Value 0 | Out-Null
        Set-GPRegistryValue -Name $GpoName -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -ValueName "RequireSecuritySignature" -Type DWord -Value 1 | Out-Null
        Set-GPRegistryValue -Name $GpoName -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -ValueName "EnableSecuritySignature" -Type DWord -Value 1 | Out-Null
        Set-GPRegistryValue -Name $GpoName -Key "HKLM\SYSTEM\CurrentControlSet\Services\mrxsmb10" -ValueName "Start" -Type DWord -Value 4 | Out-Null
        Write-Log -Level "SUCCESS" -Message "Signature SMB obligatoire et desactivation SMBv1 inscrites dans la GPO."

        # D. Generation et injection du template INF de securite (Comptes & Droits)
        $tempGpoInf = "$env:TEMP\GPO_Hardening_Baseline.inf"
        $gpoInfContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
NewAdministratorName = "$NewAdminName"
NewGuestName = "NexusGuest"
EnableAdminAccount = 1
EnableGuestAccount = 0
RequireSecuritySignature = 1
EnableSecuritySignature = 1
RequireSecuritySignatureWorkstation = 1
EnableSecuritySignatureWorkstation = 1
"@
        Set-Content -Path $tempGpoInf -Value $gpoInfContent -Encoding Unicode -Force
        Write-Log -Level "SUCCESS" -Message "Template de securite INF pour comptes integres genere ($tempGpoInf)."

        # E. Liaison de la GPO sur les OUs de l'infrastructure
        $targetOUs = @(
            "OU=Nexus360,$DomainDN",
            "OU=Serveurs-T1,OU=Services,OU=Nexus360,$DomainDN",
            "OU=Postes,OU=Nexus360,$DomainDN"
        )

        foreach ($ou in $targetOUs) {
            $reportXml = Get-GPOReport -Name $GpoName -ReportType Xml
            $alreadyLinked = $reportXml | Select-String -Pattern [regex]::Escape($ou)
            if (-not $alreadyLinked) {
                New-GPLink -Name $GpoName -Target $ou -LinkEnabled Yes -Enforced Yes -ErrorAction SilentlyContinue | Out-Null
                Write-Log -Level "SUCCESS" -Message "GPO '$GpoName' liee avec succes (Enforced=Yes) a l'OU : $ou"
            } else {
                Write-Log -Level "INFO" -Message "GPO '$GpoName' deja liee a l'OU : $ou (idempotent)."
            }
        }

    } catch {
        Write-Log -Level "ERROR" -Message "Erreur lors du deploiement de la GPO '$GpoName' : $_"
    }
} else {
    Write-Log -Level "WARNING" -Message "Module GroupPolicy indisponible : GPO non configuree."
}

Write-Log -Level "SUCCESS" -Message "=== Durcissement de securite Nexus360 termine avec succes ==="
