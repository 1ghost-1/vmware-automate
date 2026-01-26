<#
.SYNOPSIS
    Datacenter and Cluster Creation Module
.DESCRIPTION
    Creates vSphere Datacenter and Cluster with HA/DRS configuration.
#>

function New-VsphereDatacenter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    $dcName = $Config.datacenter.name
    
    Write-Host "Checking for existing Datacenter: $dcName" -ForegroundColor Cyan
    
    $existingDC = Get-Datacenter -Name $dcName -ErrorAction SilentlyContinue
    
    if ($existingDC) {
        Write-Host "Datacenter '$dcName' already exists, skipping creation" -ForegroundColor Yellow
        return $existingDC
    }
    
    Write-Host "Creating Datacenter: $dcName" -ForegroundColor Cyan
    
    try {
        $folder = Get-Folder -Type Datacenter -Name "Datacenters" -ErrorAction SilentlyContinue
        
        if ($folder) {
            $dc = New-Datacenter -Name $dcName -Location $folder -ErrorAction Stop
        } else {
            $dc = New-Datacenter -Name $dcName -ErrorAction Stop
        }
        
        Write-Host "Datacenter '$dcName' created successfully" -ForegroundColor Green
        return $dc
    }
    catch {
        throw "Failed to create Datacenter: $($_.Exception.Message)"
    }
}

function New-VsphereCluster {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    $dcName = $Config.datacenter.name
    $clusterName = $Config.cluster.name
    $haConfig = $Config.cluster.ha
    $drsConfig = $Config.cluster.drs
    
    Write-Host "Checking for existing Cluster: $clusterName" -ForegroundColor Cyan
    
    $existingCluster = Get-Cluster -Name $clusterName -ErrorAction SilentlyContinue
    
    if ($existingCluster) {
        Write-Host "Cluster '$clusterName' already exists" -ForegroundColor Yellow
        
        # Update cluster configuration if needed
        Write-Host "Updating cluster configuration..." -ForegroundColor Cyan
        Set-ClusterConfiguration -Cluster $existingCluster -Config $Config
        
        return $existingCluster
    }
    
    Write-Host "Creating Cluster: $clusterName in Datacenter: $dcName" -ForegroundColor Cyan
    
    try {
        $dc = Get-Datacenter -Name $dcName -ErrorAction Stop
        
        # Create cluster with basic settings
        $cluster = New-Cluster -Name $clusterName `
            -Location $dc `
            -HAEnabled:$haConfig.enabled `
            -DrsEnabled:$drsConfig.enabled `
            -DrsAutomationLevel $drsConfig.automationLevel `
            -ErrorAction Stop
        
        Write-Host "Cluster '$clusterName' created successfully" -ForegroundColor Green
        
        # Configure advanced HA settings
        Set-ClusterConfiguration -Cluster $cluster -Config $Config
        
        return $cluster
    }
    catch {
        throw "Failed to create Cluster: $($_.Exception.Message)"
    }
}

function Set-ClusterConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Cluster,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    $haConfig = $Config.cluster.ha
    $drsConfig = $Config.cluster.drs
    
    Write-Host "Configuring HA and DRS settings for cluster: $($Cluster.Name)" -ForegroundColor Cyan
    
    try {
        # Configure HA settings
        if ($haConfig.enabled) {
            $haParams = @{
                Cluster = $Cluster
                HAEnabled = $true
                HAAdmissionControlEnabled = $true
                ErrorAction = "Stop"
            }
            
            # Set HA admission control based on type
            if ($haConfig.admissionControl.type -eq "ResourcePercentage") {
                $haParams.Add("HAFailoverResourcesPercent", $haConfig.admissionControl.cpuPercent)
            }
            
            Set-Cluster @haParams -Confirm:$false | Out-Null
            
            Write-Host "  HA Admission Control: $($haConfig.admissionControl.cpuPercent)% CPU/Memory reserved" -ForegroundColor Gray
        }
        
        # Configure DRS settings
        if ($drsConfig.enabled) {
            Set-Cluster -Cluster $Cluster `
                -DrsEnabled $true `
                -DrsAutomationLevel $drsConfig.automationLevel `
                -Confirm:$false `
                -ErrorAction Stop | Out-Null
            
            Write-Host "  DRS Automation Level: $($drsConfig.automationLevel)" -ForegroundColor Gray
        }
        
        # Configure EVC if specified
        if ($Config.cluster.evc.enabled -and $Config.cluster.evc.mode) {
            Set-Cluster -Cluster $Cluster `
                -EVCMode $Config.cluster.evc.mode `
                -Confirm:$false `
                -ErrorAction Stop | Out-Null
            
            Write-Host "  EVC Mode: $($Config.cluster.evc.mode)" -ForegroundColor Gray
        }
        
        Write-Host "Cluster configuration completed" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Some cluster settings could not be applied: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Get-ClusterStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClusterName
    )
    
    $cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop
    
    return @{
        Name              = $cluster.Name
        HAEnabled         = $cluster.HAEnabled
        DrsEnabled        = $cluster.DrsEnabled
        DrsAutomationLevel = $cluster.DrsAutomationLevel
        EVCMode           = $cluster.EVCMode
        NumHosts          = ($cluster | Get-VMHost).Count
        NumVMs            = ($cluster | Get-VM).Count
    }
}

# Export functions
Export-ModuleMember -Function New-VsphereDatacenter, New-VsphereCluster, Set-ClusterConfiguration, Get-ClusterStatus -ErrorAction SilentlyContinue
