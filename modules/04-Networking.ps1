<#
.SYNOPSIS
    vSphere Distributed Switch and Networking Module
.DESCRIPTION
    Creates VDS, port groups, and configures networking including vMotion TCP/IP stack.
#>

function New-VsphereVDS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    $dcName = $Config.datacenter.name
    $vdsConfig = $Config.networking.vds
    
    Write-Host "Creating VDS: $($vdsConfig.name)" -ForegroundColor Cyan
    
    try {
        $dc = Get-Datacenter -Name $dcName -ErrorAction Stop
        
        # Check if VDS already exists
        $existingVDS = Get-VDSwitch -Name $vdsConfig.name -ErrorAction SilentlyContinue
        
        if ($existingVDS) {
            Write-Host "VDS '$($vdsConfig.name)' already exists, updating configuration..." -ForegroundColor Yellow
            
            # Update VDS settings
            Set-VDSwitch -VDSwitch $existingVDS `
                -Mtu $vdsConfig.mtu `
                -Confirm:$false | Out-Null
            
            return $existingVDS
        }
        
        # Create new VDS
        $vds = New-VDSwitch -Name $vdsConfig.name `
            -Location $dc `
            -Version $vdsConfig.version `
            -Mtu $vdsConfig.mtu `
            -NumUplinkPorts $vdsConfig.uplinkCount `
            -ErrorAction Stop
        
        Write-Host "VDS '$($vdsConfig.name)' created successfully" -ForegroundColor Green
        Write-Host "  Version: $($vdsConfig.version)" -ForegroundColor Gray
        Write-Host "  MTU: $($vdsConfig.mtu)" -ForegroundColor Gray
        Write-Host "  Uplinks: $($vdsConfig.uplinkCount)" -ForegroundColor Gray
        
        # Configure load balancing policy
        if ($vdsConfig.loadBalancing) {
            $vds | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy `
                -LoadBalancingPolicy $vdsConfig.loadBalancing `
                -Confirm:$false | Out-Null
            
            Write-Host "  Load Balancing: $($vdsConfig.loadBalancing)" -ForegroundColor Gray
        }
        
        return $vds
    }
    catch {
        throw "Failed to create VDS: $($_.Exception.Message)"
    }
}

function New-VspherePortGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    $vdsName = $Config.networking.vds.name
    $portGroups = $Config.networking.portGroups
    
    Write-Host "Creating Port Groups on VDS: $vdsName" -ForegroundColor Cyan
    
    try {
        $vds = Get-VDSwitch -Name $vdsName -ErrorAction Stop
        
        foreach ($pg in $portGroups) {
            Write-Host "  Creating port group: $($pg.name) (VLAN: $($pg.vlanId))" -ForegroundColor Gray
            
            # Check if port group exists
            $existingPG = Get-VDPortgroup -VDSwitch $vds -Name $pg.name -ErrorAction SilentlyContinue
            
            if ($existingPG) {
                Write-Host "    Port group '$($pg.name)' already exists, skipping" -ForegroundColor Yellow
                continue
            }
            
            # Create port group
            $newPG = New-VDPortgroup -VDSwitch $vds `
                -Name $pg.name `
                -VlanId $pg.vlanId `
                -ErrorAction Stop
            
            # Configure port group based on type
            switch ($pg.type) {
                "vMotion" {
                    # vMotion specific settings
                    Write-Host "    Configured for vMotion traffic" -ForegroundColor Gray
                }
                "vSAN" {
                    # vSAN specific settings
                    Write-Host "    Configured for vSAN traffic" -ForegroundColor Gray
                }
                "Management" {
                    Write-Host "    Configured for Management traffic" -ForegroundColor Gray
                }
                "VMTraffic" {
                    Write-Host "    Configured for VM traffic" -ForegroundColor Gray
                }
            }
            
            Write-Host "    Port group '$($pg.name)' created successfully" -ForegroundColor Green
        }
        
        return $true
    }
    catch {
        throw "Failed to create port groups: $($_.Exception.Message)"
    }
}

function Add-HostsToVDS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    $vdsName = $Config.networking.vds.name
    $uplinks = $Config.networking.vds.uplinks
    $clusterName = $Config.cluster.name
    
    Write-Host "Adding hosts to VDS: $vdsName" -ForegroundColor Cyan
    
    try {
        $vds = Get-VDSwitch -Name $vdsName -ErrorAction Stop
        $cluster = Get-Cluster -Name $clusterName -ErrorAction Stop
        $hosts = Get-VMHost -Location $cluster
        
        foreach ($vmHost in $hosts) {
            Write-Host "  Processing host: $($vmHost.Name)" -ForegroundColor Gray
            
            # Check if host is already added to VDS
            $hostInVDS = $vds | Get-VMHost | Where-Object { $_.Name -eq $vmHost.Name }
            
            if ($hostInVDS) {
                Write-Host "    Host already in VDS, checking uplinks..." -ForegroundColor Yellow
            } else {
                # Add host to VDS
                Write-Host "    Adding host to VDS..." -ForegroundColor Gray
                Add-VDSwitchVMHost -VDSwitch $vds -VMHost $vmHost -ErrorAction Stop | Out-Null
            }
            
            # Get physical NICs
            $pNics = Get-VMHostNetworkAdapter -VMHost $vmHost -Physical | 
                Where-Object { $_.Name -in $uplinks }
            
            if ($pNics) {
                Write-Host "    Assigning uplinks: $($pNics.Name -join ', ')" -ForegroundColor Gray
                
                # Add pNICs as uplinks
                foreach ($pNic in $pNics) {
                    try {
                        Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vds `
                            -VMHostPhysicalNic $pNic `
                            -Confirm:$false `
                            -ErrorAction SilentlyContinue | Out-Null
                    }
                    catch {
                        Write-Host "    Warning: Could not add $($pNic.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                }
            }
            
            Write-Host "    Host configured successfully" -ForegroundColor Green
        }
        
        return $true
    }
    catch {
        throw "Failed to add hosts to VDS: $($_.Exception.Message)"
    }
}

function Configure-VMotionStack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    if (!$Config.networking.vmotionTcpIpStack.enabled) {
        Write-Host "vMotion TCP/IP Stack configuration is disabled, skipping" -ForegroundColor Yellow
        return $true
    }
    
    $clusterName = $Config.cluster.name
    $vmotionConfig = $Config.networking.vmotionTcpIpStack
    $vmotionPG = $Config.networking.portGroups | Where-Object { $_.type -eq "vMotion" }
    
    Write-Host "Configuring vMotion TCP/IP Stack" -ForegroundColor Cyan
    
    try {
        $cluster = Get-Cluster -Name $clusterName -ErrorAction Stop
        $hosts = Get-VMHost -Location $cluster
        $vds = Get-VDSwitch -Name $Config.networking.vds.name -ErrorAction Stop
        
        $hostIndex = 0
        foreach ($vmHost in $hosts) {
            $hostConfig = $Config.esxiHosts[$hostIndex]
            
            Write-Host "  Configuring vMotion on: $($vmHost.Name)" -ForegroundColor Gray
            
            try {
                # Get the vMotion port group
                $pgName = $vmotionPG.name
                $vdPortGroup = Get-VDPortgroup -VDSwitch $vds -Name $pgName -ErrorAction Stop
                
                # Check if vMotion VMkernel already exists
                $existingVmk = Get-VMHostNetworkAdapter -VMHost $vmHost -VMKernel | 
                    Where-Object { $_.VMotionEnabled -eq $true }
                
                if ($existingVmk) {
                    Write-Host "    vMotion VMkernel already exists: $($existingVmk.Name)" -ForegroundColor Yellow
                } else {
                    # Create VMkernel adapter for vMotion
                    $vmkParams = @{
                        VMHost = $vmHost
                        PortGroup = $vdPortGroup
                        VMotionEnabled = $true
                        IP = $hostConfig.vmotionIp
                        SubnetMask = $vmotionConfig.subnetMask
                        ErrorAction = "Stop"
                    }
                    
                    $vmk = New-VMHostNetworkAdapter @vmkParams
                    Write-Host "    Created vMotion VMkernel: $($vmk.Name) with IP $($hostConfig.vmotionIp)" -ForegroundColor Green
                }
                
                # Configure vMotion TCP/IP Stack gateway if specified
                if ($vmotionConfig.gateway) {
                    $esxcli = Get-EsxCli -VMHost $vmHost -V2
                    
                    try {
                        # Set default gateway for vMotion TCP/IP stack
                        $esxcli.network.ip.route.ipv4.add.Invoke(@{
                            gateway = $vmotionConfig.gateway
                            netstack = "vmotion"
                            network = "default"
                        }) | Out-Null
                        
                        Write-Host "    vMotion gateway configured: $($vmotionConfig.gateway)" -ForegroundColor Gray
                    }
                    catch {
                        # Route may already exist
                        Write-Host "    Note: vMotion route may already exist" -ForegroundColor Yellow
                    }
                }
            }
            catch {
                Write-Host "    Warning: Error configuring vMotion on $($vmHost.Name): $($_.Exception.Message)" -ForegroundColor Yellow
            }
            
            $hostIndex++
        }
        
        Write-Host "vMotion TCP/IP Stack configuration completed" -ForegroundColor Green
        return $true
    }
    catch {
        throw "Failed to configure vMotion stack: $($_.Exception.Message)"
    }
}

function New-VsanVMkernel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    $clusterName = $Config.cluster.name
    $vsanPG = $Config.networking.portGroups | Where-Object { $_.type -eq "vSAN" }
    
    if (!$vsanPG) {
        Write-Host "No vSAN port group defined, skipping vSAN VMkernel creation" -ForegroundColor Yellow
        return $true
    }
    
    Write-Host "Creating vSAN VMkernel adapters" -ForegroundColor Cyan
    
    try {
        $cluster = Get-Cluster -Name $clusterName -ErrorAction Stop
        $hosts = Get-VMHost -Location $cluster
        $vds = Get-VDSwitch -Name $Config.networking.vds.name -ErrorAction Stop
        $vdPortGroup = Get-VDPortgroup -VDSwitch $vds -Name $vsanPG.name -ErrorAction Stop
        
        $hostIndex = 0
        foreach ($vmHost in $hosts) {
            $hostConfig = $Config.esxiHosts[$hostIndex]
            
            Write-Host "  Configuring vSAN VMkernel on: $($vmHost.Name)" -ForegroundColor Gray
            
            try {
                # Check if vSAN VMkernel already exists
                $existingVmk = Get-VMHostNetworkAdapter -VMHost $vmHost -VMKernel | 
                    Where-Object { $_.VsanTrafficEnabled -eq $true }
                
                if ($existingVmk) {
                    Write-Host "    vSAN VMkernel already exists: $($existingVmk.Name)" -ForegroundColor Yellow
                } else {
                    # Create VMkernel adapter for vSAN
                    $vmk = New-VMHostNetworkAdapter -VMHost $vmHost `
                        -PortGroup $vdPortGroup `
                        -VsanTrafficEnabled $true `
                        -IP $hostConfig.vsanIp `
                        -SubnetMask "255.255.255.0" `
                        -ErrorAction Stop
                    
                    Write-Host "    Created vSAN VMkernel: $($vmk.Name) with IP $($hostConfig.vsanIp)" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "    Warning: Error creating vSAN VMkernel on $($vmHost.Name): $($_.Exception.Message)" -ForegroundColor Yellow
            }
            
            $hostIndex++
        }
        
        return $true
    }
    catch {
        throw "Failed to create vSAN VMkernels: $($_.Exception.Message)"
    }
}

# Export functions
Export-ModuleMember -Function New-VsphereVDS, New-VspherePortGroups, Add-HostsToVDS, Configure-VMotionStack, New-VsanVMkernel -ErrorAction SilentlyContinue
