<#
.SYNOPSIS
    vSphere 8.0.3U Infrastructure Deployment Orchestrator
.DESCRIPTION
    Main script that orchestrates the deployment of vSphere infrastructure
    by calling modular scripts in the correct order.
.PARAMETER ConfigPath
    Path to the JSON configuration file (default: .\config.json)
.PARAMETER SkipVCSA
    Skip VCSA deployment (use existing vCenter)
.PARAMETER SkipNetworking
    Skip VDS and port group configuration
.PARAMETER SkipStorage
    Skip vSAN configuration
.PARAMETER WhatIf
    Show what would be done without making changes
.EXAMPLE
    .\Deploy-Infrastructure.ps1 -ConfigPath .\config.json
.EXAMPLE
    .\Deploy-Infrastructure.ps1 -SkipVCSA -SkipStorage
.NOTES
    Author: John Pedro
    Version: 1.0.0
    Requires: VMware.PowerCLI 13.0+
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$ConfigPath = ".\config.json",
    
    [Parameter()]
    [switch]$SkipVCSA,
    
    [Parameter()]
    [switch]$SkipNetworking,
    
    [Parameter()]
    [switch]$SkipStorage,
    
    [Parameter()]
    [switch]$SkipConfiguration
)

#region Script Configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"
$ScriptRoot = $PSScriptRoot
$ModulesPath = Join-Path $ScriptRoot "modules"
$LogPath = Join-Path $ScriptRoot "logs"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
#endregion

#region Logging Functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $LogFile = Join-Path $LogPath "deployment-$Timestamp.log"
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$TimeStamp] [$Level] $Message"
    
    # Console output with colors
    switch ($Level) {
        "INFO"    { Write-Host $LogMessage -ForegroundColor Cyan }
        "WARN"    { Write-Host $LogMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $LogMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $LogMessage -ForegroundColor Green }
    }
    
    # File output
    Add-Content -Path $LogFile -Value $LogMessage
}

function Write-Banner {
    param([string]$Title)
    $border = "=" * 60
    Write-Host ""
    Write-Host $border -ForegroundColor Magenta
    Write-Host "  $Title" -ForegroundColor White
    Write-Host $border -ForegroundColor Magenta
    Write-Host ""
}
#endregion

#region Main Execution
try {
    # Create log directory
    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }
    
    Write-Banner "vSphere 8.0.3U Infrastructure Deployment"
    Write-Log "Starting deployment orchestration..."
    Write-Log "Configuration file: $ConfigPath"
    
    # Validate configuration file exists
    if (!(Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    
    # Load configuration
    Write-Log "Loading configuration..."
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    Write-Log "Environment: $($Config.environment.name)" -Level SUCCESS
    
    # Validate PowerCLI module
    Write-Log "Checking PowerCLI installation..."
    if (!(Get-Module -ListAvailable -Name VMware.PowerCLI)) {
        throw "VMware.PowerCLI module not found. Install with: Install-Module VMware.PowerCLI -Scope CurrentUser"
    }
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    Write-Log "PowerCLI loaded successfully" -Level SUCCESS
    
    # Get credentials
    Write-Log "Requesting credentials..."
    $vCenterCred = Get-Credential -Message "Enter vCenter Administrator Credentials"
    $ESXiCred = Get-Credential -Message "Enter ESXi Root Credentials" -UserName "root"
    
    # Store credentials in script scope for modules
    $Script:vCenterCredential = $vCenterCred
    $Script:ESXiCredential = $ESXiCred
    $Script:Configuration = $Config
    
    #region Step 1: VCSA Deployment (Optional)
    if (!$SkipVCSA -and $Config.vcenter.deployNew) {
        Write-Banner "Step 1: Deploying VCSA"
        $vcsaScript = Join-Path $ScriptRoot "Deploy-VCSA.ps1"
        if (Test-Path $vcsaScript) {
            & $vcsaScript -Config $Config -Credential $vCenterCred
            Write-Log "VCSA deployment completed" -Level SUCCESS
        } else {
            Write-Log "VCSA deployment script not found, skipping..." -Level WARN
        }
    } else {
        Write-Log "Skipping VCSA deployment (using existing vCenter)" -Level INFO
    }
    #endregion
    
    #region Step 2: Connect to vCenter
    Write-Banner "Step 2: Connecting to vCenter"
    $connectScript = Join-Path $ModulesPath "01-Connect.ps1"
    . $connectScript
    Connect-VCenterServer -Server $Config.vcenter.server -Credential $vCenterCred
    Write-Log "Connected to vCenter: $($Config.vcenter.server)" -Level SUCCESS
    #endregion
    
    #region Step 3: Create Datacenter and Cluster
    Write-Banner "Step 3: Creating Datacenter and Cluster"
    $dcScript = Join-Path $ModulesPath "02-Datacenter.ps1"
    . $dcScript
    New-VsphereDatacenter -Config $Config
    New-VsphereCluster -Config $Config
    Write-Log "Datacenter and Cluster created" -Level SUCCESS
    #endregion
    
    #region Step 4: Add ESXi Hosts
    Write-Banner "Step 4: Adding ESXi Hosts"
    $hostsScript = Join-Path $ModulesPath "03-Hosts.ps1"
    . $hostsScript
    Add-ESXiHostsToCluster -Config $Config -Credential $ESXiCred
    Write-Log "ESXi hosts added to cluster" -Level SUCCESS
    #endregion
    
    #region Step 5: Configure Networking
    if (!$SkipNetworking) {
        Write-Banner "Step 5: Configuring Networking"
        $networkScript = Join-Path $ModulesPath "04-Networking.ps1"
        . $networkScript
        New-VsphereVDS -Config $Config
        New-VspherePortGroups -Config $Config
        Add-HostsToVDS -Config $Config
        Configure-VMotionStack -Config $Config
        Write-Log "Networking configuration completed" -Level SUCCESS
    } else {
        Write-Log "Skipping networking configuration" -Level INFO
    }
    #endregion
    
    #region Step 6: Configure Storage (vSAN)
    if (!$SkipStorage) {
        Write-Banner "Step 6: Configuring vSAN Storage"
        $storageScript = Join-Path $ModulesPath "05-Storage.ps1"
        . $storageScript
        Enable-VsanCluster -Config $Config
        Configure-VsanDiskGroups -Config $Config -AutoClaim
        Write-Log "vSAN storage configuration completed" -Level SUCCESS
    } else {
        Write-Log "Skipping storage configuration" -Level INFO
    }
    #endregion
    
    #region Step 7: Host Configuration (NTP, DNS, Syslog)
    if (!$SkipConfiguration) {
        Write-Banner "Step 7: Applying Host Configuration"
        $configScript = Join-Path $ModulesPath "06-Configuration.ps1"
        . $configScript
        Set-HostNtpConfiguration -Config $Config
        Set-HostDnsConfiguration -Config $Config
        Set-HostSyslogConfiguration -Config $Config
        Set-HostSecurityConfiguration -Config $Config
        Write-Log "Host configuration completed" -Level SUCCESS
    } else {
        Write-Log "Skipping host configuration" -Level INFO
    }
    #endregion
    
    #region Deployment Summary
    Write-Banner "Deployment Complete"
    $summary = @"
Environment:     $($Config.environment.name)
vCenter:         $($Config.vcenter.server)
Datacenter:      $($Config.datacenter.name)
Cluster:         $($Config.cluster.name)
Hosts Added:     $($Config.esxiHosts.Count)
VDS:             $($Config.networking.vds.name)
vSAN Enabled:    $($Config.storage.vsan.enabled)
"@
    Write-Host $summary -ForegroundColor Green
    Write-Log "Deployment completed successfully!" -Level SUCCESS
    #endregion
    
} catch {
    Write-Log "DEPLOYMENT FAILED: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
    throw
} finally {
    # Disconnect from vCenter if connected
    if ($global:DefaultVIServer) {
        Write-Log "Disconnecting from vCenter..."
        Disconnect-VIServer -Server * -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
}
#endregion
