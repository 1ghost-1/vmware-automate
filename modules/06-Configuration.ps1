<#
.SYNOPSIS
    Host Configuration Module
.DESCRIPTION
    Configures NTP, DNS, Syslog, and security settings on ESXi hosts.
#>

function Set-HostNtpConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    $clusterName = $Config.cluster.name
    $ntpConfig = $Config.services.ntp
    
    Write-Host "Configuring NTP on all hosts" -ForegroundColor Cyan
    
    try {
        $cluster = Get-Cluster -Name $clusterName -ErrorAction Stop
        $hosts = Get-VMHost -Location $cluster
        
        foreach ($vmHost in $hosts) {
            Write-Host "  Configuring NTP on: $($vmHost.Name)" -ForegroundColor Gray
            
            try {
                # Remove existing NTP servers
                $existingNtp = Get-VMHostNtpServer -VMHost $vmHost
                if ($existingNtp) {
                    Remove-VMHostNtpServer -VMHost $vmHost -NtpServer $existingNtp -Confirm:$false -ErrorAction SilentlyContinue
                }
                
                # Add new NTP servers
                foreach ($ntpServer in $ntpConfig.servers) {
                    Add-VMHostNtpServer -VMHost $vmHost -NtpServer $ntpServer -ErrorAction Stop | Out-Null
                }
                
                # Configure NTP service
                $ntpService = Get-VMHostService -VMHost $vmHost | Where-Object { $_.Key -eq "ntpd" }
                
                # Set service policy
                Set-VMHostService -HostService $ntpService -Policy $ntpConfig.policy -Confirm:$false | Out-Null
                
                # Start NTP service if not running
                if ($ntpService.Running -eq $false) {
                    Start-VMHostService -HostService $ntpService -Confirm:$false | Out-Null
                }
                
                Write-Host "    NTP configured: $($ntpConfig.servers -join ', ')" -ForegroundColor Green
            }
            catch {
                Write-Host "    Warning: Failed to configure NTP: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        return $true
    }
    catch {
        throw "Failed to configure NTP: $($_.Exception.Message)"
    }
}

function Set-HostDnsConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    $clusterName = $Config.cluster.name
    $dnsConfig = $Config.services.dns
    
    Write-Host "Configuring DNS on all hosts" -ForegroundColor Cyan
    
    try {
        $cluster = Get-Cluster -Name $clusterName -ErrorAction Stop
        $hosts = Get-VMHost -Location $cluster
        
        foreach ($vmHost in $hosts) {
            Write-Host "  Configuring DNS on: $($vmHost.Name)" -ForegroundColor Gray
            
            try {
                # Get current network config
                $networkConfig = Get-VMHostNetwork -VMHost $vmHost
                
                # Update DNS settings
                Set-VMHostNetwork -Network $networkConfig `
                    -DnsAddress $dnsConfig.servers `
                    -SearchDomain $dnsConfig.searchDomains `
                    -Confirm:$false `
                    -ErrorAction Stop | Out-Null
                
                Write-Host "    DNS configured: $($dnsConfig.servers -join ', ')" -ForegroundColor Green
            }
            catch {
                Write-Host "    Warning: Failed to configure DNS: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        return $true
    }
    catch {
        throw "Failed to configure DNS: $($_.Exception.Message)"
    }
}

function Set-HostSyslogConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    $clusterName = $Config.cluster.name
    $syslogConfig = $Config.services.syslog
    
    Write-Host "Configuring Syslog on all hosts" -ForegroundColor Cyan
    
    try {
        $cluster = Get-Cluster -Name $clusterName -ErrorAction Stop
        $hosts = Get-VMHost -Location $cluster
        
        foreach ($vmHost in $hosts) {
            Write-Host "  Configuring Syslog on: $($vmHost.Name)" -ForegroundColor Gray
            
            try {
                # Build syslog URI
                $syslogUri = "$($syslogConfig.protocol)://$($syslogConfig.server):$($syslogConfig.port)"
                
                # Get ESXCLI
                $esxcli = Get-EsxCli -VMHost $vmHost -V2
                
                # Set syslog remote host
                $esxcli.system.syslog.config.set.Invoke(@{
                    loghost = $syslogUri
                }) | Out-Null
                
                # Reload syslog
                $esxcli.system.syslog.reload.Invoke() | Out-Null
                
                # Enable syslog firewall rule
                $firewallRule = Get-VMHostFirewallException -VMHost $vmHost -Name "syslog" -ErrorAction SilentlyContinue
                if ($firewallRule) {
                    Set-VMHostFirewallException -Exception $firewallRule -Enabled $true -Confirm:$false | Out-Null
                }
                
                Write-Host "    Syslog configured: $syslogUri" -ForegroundColor Green
            }
            catch {
                Write-Host "    Warning: Failed to configure Syslog: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        return $true
    }
    catch {
        throw "Failed to configure Syslog: $($_.Exception.Message)"
    }
}

function Set-HostSecurityConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    $clusterName = $Config.cluster.name
    $securityConfig = $Config.security
    
    Write-Host "Applying security configuration on all hosts" -ForegroundColor Cyan
    
    try {
        $cluster = Get-Cluster -Name $clusterName -ErrorAction Stop
        $hosts = Get-VMHost -Location $cluster
        
        foreach ($vmHost in $hosts) {
            Write-Host "  Applying security on: $($vmHost.Name)" -ForegroundColor Gray
            
            try {
                # Configure SSH
                $sshService = Get-VMHostService -VMHost $vmHost | Where-Object { $_.Key -eq "TSM-SSH" }
                
                if ($securityConfig.sshEnabled) {
                    if (!$sshService.Running) {
                        Start-VMHostService -HostService $sshService -Confirm:$false | Out-Null
                    }
                    Set-VMHostService -HostService $sshService -Policy "on" -Confirm:$false | Out-Null
                    Write-Host "    SSH: Enabled" -ForegroundColor Yellow
                } else {
                    if ($sshService.Running) {
                        Stop-VMHostService -HostService $sshService -Confirm:$false | Out-Null
                    }
                    Set-VMHostService -HostService $sshService -Policy "off" -Confirm:$false | Out-Null
                    Write-Host "    SSH: Disabled" -ForegroundColor Green
                }
                
                # Configure Shell Timeout
                $esxcli = Get-EsxCli -VMHost $vmHost -V2
                
                try {
                    $esxcli.system.settings.advanced.set.Invoke(@{
                        option = "/UserVars/ESXiShellTimeOut"
                        intvalue = $securityConfig.shellTimeout
                    }) | Out-Null
                    Write-Host "    Shell Timeout: $($securityConfig.shellTimeout) seconds" -ForegroundColor Gray
                }
                catch {
                    Write-Host "    Note: Could not set shell timeout" -ForegroundColor Yellow
                }
                
                # Configure Lockdown Mode
                if ($securityConfig.lockdownMode -ne "disabled") {
                    $lockdownLevel = switch ($securityConfig.lockdownMode) {
                        "normal" { "lockdownNormal" }
                        "strict" { "lockdownStrict" }
                        default { "lockdownDisabled" }
                    }
                    
                    try {
                        $hostView = Get-View $vmHost -Property ConfigManager.HostAccessManager
                        $accessManager = Get-View $hostView.ConfigManager.HostAccessManager
                        $accessManager.ChangeLockdownMode($lockdownLevel)
                        Write-Host "    Lockdown Mode: $($securityConfig.lockdownMode)" -ForegroundColor Gray
                    }
                    catch {
                        Write-Host "    Note: Could not set lockdown mode" -ForegroundColor Yellow
                    }
                }
                
                # Enable required firewall rulesets
                foreach ($ruleset in $securityConfig.firewallRulesetsEnabled) {
                    try {
                        $rule = Get-VMHostFirewallException -VMHost $vmHost -Name $ruleset -ErrorAction SilentlyContinue
                        if ($rule) {
                            Set-VMHostFirewallException -Exception $rule -Enabled $true -Confirm:$false | Out-Null
                        }
                    }
                    catch {
                        # Silently continue if ruleset doesn't exist
                    }
                }
                
                Write-Host "    Security configuration applied" -ForegroundColor Green
            }
            catch {
                Write-Host "    Warning: Failed to apply security config: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        return $true
    }
    catch {
        throw "Failed to apply security configuration: $($_.Exception.Message)"
    }
}

function Get-HostConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HostName
    )
    
    try {
        $vmHost = Get-VMHost -Name $HostName -ErrorAction Stop
        
        # Get NTP
        $ntpServers = Get-VMHostNtpServer -VMHost $vmHost
        $ntpService = Get-VMHostService -VMHost $vmHost | Where-Object { $_.Key -eq "ntpd" }
        
        # Get DNS
        $network = Get-VMHostNetwork -VMHost $vmHost
        
        # Get SSH
        $sshService = Get-VMHostService -VMHost $vmHost | Where-Object { $_.Key -eq "TSM-SSH" }
        
        return @{
            HostName      = $HostName
            NtpServers    = $ntpServers
            NtpRunning    = $ntpService.Running
            NtpPolicy     = $ntpService.Policy
            DnsServers    = $network.DnsAddress
            SearchDomains = $network.SearchDomain
            SshEnabled    = $sshService.Running
        }
    }
    catch {
        throw "Failed to get host configuration: $($_.Exception.Message)"
    }
}

function Set-HostAdvancedSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HostName,
        
        [Parameter(Mandatory)]
        [string]$SettingName,
        
        [Parameter(Mandatory)]
        $Value
    )
    
    try {
        $vmHost = Get-VMHost -Name $HostName -ErrorAction Stop
        
        Get-AdvancedSetting -Entity $vmHost -Name $SettingName | 
            Set-AdvancedSetting -Value $Value -Confirm:$false | Out-Null
        
        Write-Host "Set $SettingName = $Value on $HostName" -ForegroundColor Green
        return $true
    }
    catch {
        throw "Failed to set advanced setting: $($_.Exception.Message)"
    }
}

# Export functions
Export-ModuleMember -Function Set-HostNtpConfiguration, Set-HostDnsConfiguration, Set-HostSyslogConfiguration, Set-HostSecurityConfiguration, Get-HostConfiguration, Set-HostAdvancedSetting -ErrorAction SilentlyContinue
