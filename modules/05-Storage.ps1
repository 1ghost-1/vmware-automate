<#
.SYNOPSIS
    vSAN Storage Configuration Module
.DESCRIPTION
    Enables and configures vSAN on the cluster including disk groups and storage policies.
#>

function Enable-VsanCluster {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    if (!$Config.storage.vsan.enabled) {
        Write-Host "vSAN is not enabled in configuration, skipping" -ForegroundColor Yellow
        return $true
    }
    
    $clusterName = $Config.cluster.name
    $vsanConfig = $Config.storage.vsan
    
    Write-Host "Enabling vSAN on cluster: $clusterName" -ForegroundColor Cyan
    
    try {
        $cluster = Get-Cluster -Name $clusterName -ErrorAction Stop
        
        # Check if vSAN is already enabled
        $vsanClusterConfig = Get-VsanClusterConfiguration -Cluster $cluster -ErrorAction SilentlyContinue
        
        if ($vsanClusterConfig -and $vsanClusterConfig.VsanEnabled) {
            Write-Host "vSAN is already enabled on cluster '$clusterName'" -ForegroundColor Yellow
            
            # Update vSAN configuration
            Write-Host "Updating vSAN configuration..." -ForegroundColor Cyan
        } else {
            # Enable vSAN
            Write-Host "Enabling vSAN cluster..." -ForegroundColor Cyan
            
            $vsanParams = @{
                Cluster = $cluster
                Confirm = $false
                ErrorAction = "Stop"
            }
            
            Enable-VsanCluster @vsanParams | Out-Null
        }
        
        # Configure vSAN settings
        Set-VsanClusterConfiguration -Cluster $cluster `
            -SpaceEfficiencyEnabled:$vsanConfig.deduplicationEnabled `
            -Confirm:$false `
            -ErrorAction SilentlyContinue | Out-Null
        
        Write-Host "vSAN enabled successfully on cluster" -ForegroundColor Green
        Write-Host "  Deduplication: $($vsanConfig.deduplicationEnabled)" -ForegroundColor Gray
        Write-Host "  Compression: $($vsanConfig.compressionEnabled)" -ForegroundColor Gray
        
        # Create vSAN VMkernel adapters if not already done
        . "$PSScriptRoot\04-Networking.ps1"
        New-VsanVMkernel -Config $Config
        
        return $true
    }
    catch {
        throw "Failed to enable vSAN: $($_.Exception.Message)"
    }
}

function Configure-VsanDiskGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,
        
        [Parameter()]
        [switch]$AutoClaim
    )
    
    if (!$Config.storage.vsan.enabled) {
        Write-Host "vSAN is not enabled, skipping disk group configuration" -ForegroundColor Yellow
        return $true
    }
    
    $clusterName = $Config.cluster.name
    $diskConfig = $Config.storage.vsan.diskGroups
    $claimMode = $Config.storage.vsan.claimMode
    
    Write-Host "Configuring vSAN Disk Groups" -ForegroundColor Cyan
    
    # Force auto-claim if switch is provided
    if ($AutoClaim) {
        $claimMode = "Automatic"
    }
    
    try {
        $cluster = Get-Cluster -Name $clusterName -ErrorAction Stop
        $hosts = Get-VMHost -Location $cluster
        
        foreach ($vmHost in $hosts) {
            Write-Host "  Processing host: $($vmHost.Name)" -ForegroundColor Gray
            
            # Check existing disk groups
            $existingDiskGroups = Get-VsanDiskGroup -VMHost $vmHost -ErrorAction SilentlyContinue
            
            if ($existingDiskGroups) {
                Write-Host "    Host already has $($existingDiskGroups.Count) disk group(s), skipping" -ForegroundColor Yellow
                continue
            }
            
            # Discover eligible disks
            Write-Host "    Discovering eligible disks..." -ForegroundColor Gray
            $discoveredDisks = Get-VsanEligibleDisk -VMHost $vmHost -ErrorAction SilentlyContinue
            
            if (!$discoveredDisks -or $discoveredDisks.Count -eq 0) {
                Write-Host "    No eligible disks found on host" -ForegroundColor Yellow
                continue
            }
            
            # Categorize disks
            $allFlash = $true
            $cacheDisks = @()
            $capacityDisks = @()
            
            foreach ($disk in $discoveredDisks) {
                $diskInfo = Get-DiskInfo -Disk $disk
                Write-Host "      Found: $($disk.CanonicalName) | $($diskInfo.SizeGB) GB | $($diskInfo.Type)" -ForegroundColor Gray
                
                if (!$disk.IsSsd) {
                    $allFlash = $false
                }
            }
            
            # Auto-discovery logic for disk group creation
            if ($claimMode -eq "Automatic" -or $AutoClaim) {
                $diskGroupResult = New-AutoDiscoveredDiskGroup -VMHost $vmHost -EligibleDisks $discoveredDisks -AllFlash $allFlash
                
                if ($diskGroupResult) {
                    Write-Host "    Disk group created successfully via auto-discovery" -ForegroundColor Green
                }
            } else {
                Write-Host "    Manual claim mode - run with -AutoClaim to auto-configure" -ForegroundColor Yellow
                Write-Host "    Or use: New-VsanDiskGroup -VMHost '$($vmHost.Name)' -SsdCanonicalName '<cache>' -DataDiskCanonicalName '<capacity>'" -ForegroundColor Gray
            }
        }
        
        return $true
    }
    catch {
        throw "Failed to configure vSAN disk groups: $($_.Exception.Message)"
    }
}

function Get-DiskInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Disk
    )
    
    $sizeGB = [math]::Round($Disk.CapacityGB, 2)
    $type = if ($Disk.IsSsd) { "SSD" } else { "HDD" }
    
    return @{
        CanonicalName = $Disk.CanonicalName
        SizeGB        = $sizeGB
        Type          = $type
        IsSsd         = $Disk.IsSsd
        IsCapacityFlash = $Disk.IsCapacityFlash
    }
}

function New-AutoDiscoveredDiskGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $VMHost,
        
        [Parameter(Mandatory)]
        $EligibleDisks,
        
        [Parameter()]
        [bool]$AllFlash = $false
    )
    
    Write-Host "    Running auto-discovery for disk group creation..." -ForegroundColor Cyan
    
    try {
        # Separate cache and capacity candidates
        $ssds = @($EligibleDisks | Where-Object { $_.IsSsd -eq $true })
        $hdds = @($EligibleDisks | Where-Object { $_.IsSsd -eq $false })
        
        if ($AllFlash) {
            # All-flash configuration: smallest SSD as cache, rest as capacity
            Write-Host "    Detected All-Flash configuration" -ForegroundColor Gray
            
            if ($ssds.Count -lt 2) {
                Write-Host "    Warning: Need at least 2 SSDs for all-flash vSAN" -ForegroundColor Yellow
                return $false
            }
            
            # Sort by size - smallest for cache
            $sortedSsds = $ssds | Sort-Object -Property CapacityGB
            
            # Use smallest SSD for cache (or one marked as cache tier)
            $cacheCandidate = $sortedSsds | Select-Object -First 1
            
            # Rest are capacity
            $capacityCandidates = $sortedSsds | Where-Object { $_.CanonicalName -ne $cacheCandidate.CanonicalName }
            
            if ($capacityCandidates.Count -eq 0) {
                Write-Host "    Warning: No capacity disks available after cache selection" -ForegroundColor Yellow
                return $false
            }
            
            Write-Host "      Cache disk: $($cacheCandidate.CanonicalName) ($([math]::Round($cacheCandidate.CapacityGB, 0)) GB)" -ForegroundColor Gray
            Write-Host "      Capacity disks: $($capacityCandidates.Count) x SSD" -ForegroundColor Gray
            
            New-VsanDiskGroup -VMHost $VMHost `
                -SsdCanonicalName $cacheCandidate.CanonicalName `
                -DataDiskCanonicalName ($capacityCandidates.CanonicalName) `
                -ErrorAction Stop | Out-Null
            
            return $true
        }
        else {
            # Hybrid configuration: SSD for cache, HDDs for capacity
            Write-Host "    Detected Hybrid configuration (SSD cache + HDD capacity)" -ForegroundColor Gray
            
            if ($ssds.Count -eq 0) {
                Write-Host "    Warning: No SSDs found for cache tier" -ForegroundColor Yellow
                return $false
            }
            
            if ($hdds.Count -eq 0) {
                Write-Host "    Warning: No HDDs found for capacity tier (use all-flash?)" -ForegroundColor Yellow
                return $false
            }
            
            $cacheDisk = $ssds | Select-Object -First 1
            
            Write-Host "      Cache disk: $($cacheDisk.CanonicalName) ($([math]::Round($cacheDisk.CapacityGB, 0)) GB SSD)" -ForegroundColor Gray
            Write-Host "      Capacity disks: $($hdds.Count) x HDD" -ForegroundColor Gray
            
            New-VsanDiskGroup -VMHost $VMHost `
                -SsdCanonicalName $cacheDisk.CanonicalName `
                -DataDiskCanonicalName ($hdds.CanonicalName) `
                -ErrorAction Stop | Out-Null
            
            return $true
        }
    }
    catch {
        Write-Host "    Failed to create disk group: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-VsanDiskInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClusterName
    )
    
    Write-Host "Discovering vSAN-eligible disks across cluster: $ClusterName" -ForegroundColor Cyan
    
    try {
        $cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop
        $hosts = Get-VMHost -Location $cluster
        
        $inventory = @()
        
        foreach ($vmHost in $hosts) {
            Write-Host "  Scanning: $($vmHost.Name)" -ForegroundColor Gray
            
            # Get eligible disks
            $eligibleDisks = Get-VsanEligibleDisk -VMHost $vmHost -ErrorAction SilentlyContinue
            
            # Get disks already in use
            $claimedDisks = @()
            $diskGroups = Get-VsanDiskGroup -VMHost $vmHost -ErrorAction SilentlyContinue
            if ($diskGroups) {
                foreach ($dg in $diskGroups) {
                    $dgDisks = $dg | Get-VsanDisk
                    $claimedDisks += $dgDisks
                }
            }
            
            foreach ($disk in $eligibleDisks) {
                $inventory += [PSCustomObject]@{
                    Host          = $vmHost.Name
                    CanonicalName = $disk.CanonicalName
                    CapacityGB    = [math]::Round($disk.CapacityGB, 2)
                    IsSsd         = $disk.IsSsd
                    Type          = if ($disk.IsSsd) { "SSD" } else { "HDD" }
                    Status        = "Eligible"
                }
            }
            
            foreach ($disk in $claimedDisks) {
                $inventory += [PSCustomObject]@{
                    Host          = $vmHost.Name
                    CanonicalName = $disk.CanonicalName
                    CapacityGB    = [math]::Round($disk.CapacityGB, 2)
                    IsSsd         = $disk.IsSsd
                    Type          = if ($disk.IsSsd) { "SSD" } else { "HDD" }
                    Status        = if ($disk.IsCacheDisk) { "Cache (In Use)" } else { "Capacity (In Use)" }
                }
            }
        }
        
        return $inventory
    }
    catch {
        throw "Failed to get disk inventory: $($_.Exception.Message)"
    }
}

function Get-VsanClusterStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClusterName
    )
    
    try {
        $cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop
        $vsanConfig = Get-VsanClusterConfiguration -Cluster $cluster -ErrorAction Stop
        
        if (!$vsanConfig.VsanEnabled) {
            return @{
                ClusterName = $ClusterName
                VsanEnabled = $false
            }
        }
        
        $hosts = Get-VMHost -Location $cluster
        $diskGroupInfo = @()
        
        foreach ($vmHost in $hosts) {
            $diskGroups = Get-VsanDiskGroup -VMHost $vmHost -ErrorAction SilentlyContinue
            
            foreach ($dg in $diskGroups) {
                $diskGroupInfo += @{
                    Host           = $vmHost.Name
                    DiskGroupUuid  = $dg.Uuid
                    CacheDisks     = ($dg | Get-VsanDisk | Where-Object { $_.IsCacheDisk }).Count
                    CapacityDisks  = ($dg | Get-VsanDisk | Where-Object { !$_.IsCacheDisk }).Count
                }
            }
        }
        
        # Get vSAN datastore info
        $vsanDatastore = Get-Datastore | Where-Object { $_.Type -eq "vsan" } | Select-Object -First 1
        
        return @{
            ClusterName          = $ClusterName
            VsanEnabled          = $vsanConfig.VsanEnabled
            SpaceEfficiencyEnabled = $vsanConfig.SpaceEfficiencyEnabled
            HostCount            = $hosts.Count
            DiskGroups           = $diskGroupInfo
            DatastoreName        = $vsanDatastore.Name
            DatastoreCapacityGB  = if ($vsanDatastore) { [math]::Round($vsanDatastore.CapacityGB, 2) } else { 0 }
            DatastoreFreeGB      = if ($vsanDatastore) { [math]::Round($vsanDatastore.FreeSpaceGB, 2) } else { 0 }
        }
    }
    catch {
        throw "Failed to get vSAN status: $($_.Exception.Message)"
    }
}

function New-VsanStoragePolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    $policyConfig = $Config.storage.vsan.storagePolicy
    
    if (!$policyConfig) {
        Write-Host "No vSAN storage policy defined, using defaults" -ForegroundColor Yellow
        return $null
    }
    
    Write-Host "Creating vSAN Storage Policy: $($policyConfig.name)" -ForegroundColor Cyan
    
    try {
        # Check if policy exists
        $existingPolicy = Get-SpbmStoragePolicy -Name $policyConfig.name -ErrorAction SilentlyContinue
        
        if ($existingPolicy) {
            Write-Host "Storage policy '$($policyConfig.name)' already exists" -ForegroundColor Yellow
            return $existingPolicy
        }
        
        # Create storage policy rules
        $rules = @()
        
        # Failures to tolerate
        $fttRule = New-SpbmRule -Capability (Get-SpbmCapability -Name "VSAN.hostFailuresToTolerate") `
            -Value $policyConfig.failuresToTolerate
        $rules += $fttRule
        
        # Create the policy
        $ruleSet = New-SpbmRuleSet -AllOfRules $rules
        $policy = New-SpbmStoragePolicy -Name $policyConfig.name `
            -Description "vSAN storage policy - FTT: $($policyConfig.failuresToTolerate), $($policyConfig.raidType)" `
            -AnyOfRuleSets $ruleSet
        
        Write-Host "Storage policy created successfully" -ForegroundColor Green
        return $policy
    }
    catch {
        Write-Host "Warning: Could not create storage policy: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

function Remove-VsanDiskGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HostName,
        
        [Parameter()]
        [switch]$Force
    )
    
    try {
        $vmHost = Get-VMHost -Name $HostName -ErrorAction Stop
        $diskGroups = Get-VsanDiskGroup -VMHost $vmHost -ErrorAction Stop
        
        if ($diskGroups.Count -eq 0) {
            Write-Host "No disk groups found on host: $HostName" -ForegroundColor Yellow
            return $true
        }
        
        foreach ($dg in $diskGroups) {
            Write-Host "Removing disk group from: $HostName" -ForegroundColor Cyan
            
            if ($Force) {
                Remove-VsanDiskGroup -VsanDiskGroup $dg -DataMigrationMode "NoDataMigration" -Confirm:$false | Out-Null
            } else {
                Remove-VsanDiskGroup -VsanDiskGroup $dg -Confirm:$false | Out-Null
            }
            
            Write-Host "Disk group removed" -ForegroundColor Green
        }
        
        return $true
    }
    catch {
        throw "Failed to remove disk group: $($_.Exception.Message)"
    }
}

# Export functions
Export-ModuleMember -Function Enable-VsanCluster, Configure-VsanDiskGroups, Get-VsanClusterStatus, New-VsanStoragePolicy, Remove-VsanDiskGroup, Get-DiskInfo, New-AutoDiscoveredDiskGroup, Get-VsanDiskInventory -ErrorAction SilentlyContinue
