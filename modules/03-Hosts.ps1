<#
.SYNOPSIS
    ESXi Host Addition Module
.DESCRIPTION
    Adds ESXi hosts to the vSphere cluster with validation and error handling.
#>

function Add-ESXiHostsToCluster {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory)]
        [PSCredential]$Credential,
        
        [Parameter()]
        [switch]$Force
    )
    
    $clusterName = $Config.cluster.name
    $hosts = $Config.esxiHosts
    
    Write-Host "Adding $($hosts.Count) ESXi hosts to cluster: $clusterName" -ForegroundColor Cyan
    
    $cluster = Get-Cluster -Name $clusterName -ErrorAction Stop
    
    $results = @{
        Success = @()
        Failed  = @()
        Skipped = @()
    }
    
    foreach ($esxiHost in $hosts) {
        $hostname = $esxiHost.hostname
        
        Write-Host "Processing host: $hostname" -ForegroundColor Cyan
        
        try {
            # Check if host is already in the cluster
            $existingHost = Get-VMHost -Name $hostname -ErrorAction SilentlyContinue
            
            if ($existingHost) {
                $currentCluster = Get-Cluster -VMHost $existingHost -ErrorAction SilentlyContinue
                
                if ($currentCluster.Name -eq $clusterName) {
                    Write-Host "  Host '$hostname' already in cluster '$clusterName', skipping" -ForegroundColor Yellow
                    $results.Skipped += $hostname
                    continue
                } elseif (!$Force) {
                    Write-Host "  Host '$hostname' is in different cluster '$($currentCluster.Name)', use -Force to move" -ForegroundColor Yellow
                    $results.Skipped += $hostname
                    continue
                }
            }
            
            # Test connectivity to host
            Write-Host "  Testing connectivity to $hostname..." -ForegroundColor Gray
            $pingResult = Test-Connection -ComputerName $hostname -Count 1 -Quiet -ErrorAction SilentlyContinue
            
            if (!$pingResult) {
                Write-Host "  Warning: Cannot ping $hostname, attempting to add anyway..." -ForegroundColor Yellow
            }
            
            # Add host to cluster
            Write-Host "  Adding host to cluster..." -ForegroundColor Gray
            $vmHost = Add-VMHost -Name $hostname `
                -Location $cluster `
                -Credential $Credential `
                -Force:$Force `
                -Confirm:$false `
                -ErrorAction Stop
            
            Write-Host "  Host '$hostname' added successfully" -ForegroundColor Green
            $results.Success += $hostname
            
            # Set host to maintenance mode briefly for initial configuration
            # Write-Host "  Entering maintenance mode for configuration..." -ForegroundColor Gray
            # Set-VMHost -VMHost $vmHost -State Maintenance -Confirm:$false | Out-Null
            
        }
        catch {
            Write-Host "  Failed to add host '$hostname': $($_.Exception.Message)" -ForegroundColor Red
            $results.Failed += @{
                Host  = $hostname
                Error = $_.Exception.Message
            }
        }
    }
    
    # Summary
    Write-Host "`nHost Addition Summary:" -ForegroundColor Cyan
    Write-Host "  Successful: $($results.Success.Count)" -ForegroundColor Green
    Write-Host "  Skipped:    $($results.Skipped.Count)" -ForegroundColor Yellow
    Write-Host "  Failed:     $($results.Failed.Count)" -ForegroundColor Red
    
    if ($results.Failed.Count -gt 0) {
        Write-Host "`nFailed hosts:" -ForegroundColor Red
        foreach ($failed in $results.Failed) {
            Write-Host "  $($failed.Host): $($failed.Error)" -ForegroundColor Red
        }
    }
    
    return $results
}

function Remove-ESXiHostFromCluster {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HostName,
        
        [Parameter()]
        [switch]$Force
    )
    
    Write-Host "Removing host: $HostName" -ForegroundColor Cyan
    
    try {
        $vmHost = Get-VMHost -Name $HostName -ErrorAction Stop
        
        # Check for running VMs
        $runningVMs = Get-VM -Location $vmHost | Where-Object { $_.PowerState -eq "PoweredOn" }
        
        if ($runningVMs -and !$Force) {
            throw "Host has $($runningVMs.Count) running VMs. Use -Force to proceed or migrate VMs first."
        }
        
        # Put host in maintenance mode
        Write-Host "  Entering maintenance mode..." -ForegroundColor Gray
        Set-VMHost -VMHost $vmHost -State Maintenance -Confirm:$false -ErrorAction Stop | Out-Null
        
        # Remove from vCenter
        Write-Host "  Removing from vCenter..." -ForegroundColor Gray
        Remove-VMHost -VMHost $vmHost -Confirm:$false -ErrorAction Stop
        
        Write-Host "  Host '$HostName' removed successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  Failed to remove host: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Set-ESXiHostMaintenanceMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HostName,
        
        [Parameter(Mandatory)]
        [ValidateSet("Enter", "Exit")]
        [string]$Action,
        
        [Parameter()]
        [switch]$EvacuatePoweredOffVms
    )
    
    try {
        $vmHost = Get-VMHost -Name $HostName -ErrorAction Stop
        
        if ($Action -eq "Enter") {
            Write-Host "Entering maintenance mode: $HostName" -ForegroundColor Cyan
            Set-VMHost -VMHost $vmHost -State Maintenance -EvacuatePoweredOffVms:$EvacuatePoweredOffVms -Confirm:$false | Out-Null
        } else {
            Write-Host "Exiting maintenance mode: $HostName" -ForegroundColor Cyan
            Set-VMHost -VMHost $vmHost -State Connected -Confirm:$false | Out-Null
        }
        
        Write-Host "  $Action maintenance mode completed for $HostName" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  Failed to $Action maintenance mode: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-ESXiHostStatus {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ClusterName
    )
    
    $hosts = if ($ClusterName) {
        Get-Cluster -Name $ClusterName | Get-VMHost
    } else {
        Get-VMHost
    }
    
    $hostInfo = foreach ($h in $hosts) {
        @{
            Name              = $h.Name
            ConnectionState   = $h.ConnectionState
            PowerState        = $h.PowerState
            Version           = $h.Version
            Build             = $h.Build
            CpuTotalMhz       = $h.CpuTotalMhz
            MemoryTotalGB     = [math]::Round($h.MemoryTotalGB, 2)
            NumCpu            = $h.NumCpu
            VMCount           = (Get-VM -Location $h).Count
        }
    }
    
    return $hostInfo
}

# Export functions
Export-ModuleMember -Function Add-ESXiHostsToCluster, Remove-ESXiHostFromCluster, Set-ESXiHostMaintenanceMode, Get-ESXiHostStatus -ErrorAction SilentlyContinue
