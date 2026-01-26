<#
.SYNOPSIS
    VCSA Deployment Script
.DESCRIPTION
    Deploys a new vCenter Server Appliance (VCSA) using the VMware CLI installer.
.PARAMETER ConfigPath
    Path to the JSON configuration file
.NOTES
    Requires the VCSA ISO to be mounted or extracted.
    The vcsa-deploy CLI tool must be accessible.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath = ".\config.json",
    
    [Parameter()]
    [PSCredential]$Credential
)

function Deploy-VCSA {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,
        
        [Parameter()]
        [PSCredential]$Credential
    )
    
    $vcsaConfig = $Config.vcenter.vcsa
    
    Write-Host "Preparing VCSA Deployment" -ForegroundColor Cyan
    Write-Host "  Target ESXi Host: $($vcsaConfig.targetEsxiHost)" -ForegroundColor Gray
    Write-Host "  VCSA Hostname: $($vcsaConfig.hostname)" -ForegroundColor Gray
    Write-Host "  VCSA IP: $($vcsaConfig.ip)" -ForegroundColor Gray
    Write-Host "  Deployment Size: $($vcsaConfig.deploymentSize)" -ForegroundColor Gray
    
    # Create VCSA deployment JSON template
    $deploymentJson = @{
        "__version" = "2.13.0"
        "__comments" = "vSphere 8.0.3U VCSA Deployment Template"
        "new_vcsa" = @{
            "esxi" = @{
                "hostname" = $vcsaConfig.targetEsxiHost
                "username" = "root"
                "password" = if ($Credential) { $Credential.GetNetworkCredential().Password } else { "__ESXi_ROOT_PASSWORD__" }
                "deployment_network" = $vcsaConfig.targetNetwork
                "datastore" = $vcsaConfig.targetDatastore
            }
            "appliance" = @{
                "__comments" = @(
                    "Deployment sizes: tiny, small, medium, large, xlarge"
                    "tiny: up to 10 hosts, 100 VMs"
                    "small: up to 100 hosts, 1000 VMs"
                    "medium: up to 400 hosts, 4000 VMs"
                    "large: up to 1000 hosts, 10000 VMs"
                    "xlarge: up to 2500 hosts, 45000 VMs"
                )
                "thin_disk_mode" = $true
                "deployment_option" = $vcsaConfig.deploymentSize
                "name" = ($vcsaConfig.hostname -split '\.')[0]
            }
            "network" = @{
                "ip_family" = "ipv4"
                "mode" = "static"
                "system_name" = $vcsaConfig.hostname
                "ip" = $vcsaConfig.ip
                "prefix" = $vcsaConfig.prefix
                "gateway" = $vcsaConfig.gateway
                "dns_servers" = $vcsaConfig.dns
            }
            "os" = @{
                "password" = if ($vcsaConfig.ssoPassword) { $vcsaConfig.ssoPassword } else { "__VCSA_ROOT_PASSWORD__" }
                "ntp_servers" = $Config.services.ntp.servers
                "ssh_enable" = $false
            }
            "sso" = @{
                "password" = if ($vcsaConfig.ssoPassword) { $vcsaConfig.ssoPassword } else { "__SSO_ADMIN_PASSWORD__" }
                "domain_name" = $vcsaConfig.ssoDomain
            }
        }
        "ceip" = @{
            "settings" = @{
                "ceip_enabled" = $false
            }
        }
    }
    
    # Create deployment JSON file
    $jsonPath = Join-Path $PSScriptRoot "vcsa-deploy-config.json"
    $deploymentJson | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8
    
    Write-Host "`nDeployment configuration saved to: $jsonPath" -ForegroundColor Green
    Write-Host "`nIMPORTANT: Before running the deployment:" -ForegroundColor Yellow
    Write-Host "  1. Edit $jsonPath and replace placeholder passwords" -ForegroundColor Yellow
    Write-Host "  2. Mount the VCSA ISO: $($vcsaConfig.iso)" -ForegroundColor Yellow
    Write-Host "  3. Run the vcsa-deploy command below" -ForegroundColor Yellow
    
    # Generate deployment command
    $isoPath = $vcsaConfig.iso
    $deployCommand = @"

# VCSA Deployment Command
# -----------------------
# 1. Mount the VCSA ISO or extract it
# 2. Navigate to the vcsa-cli-installer\win32 folder
# 3. Run the following command:

.\vcsa-deploy.exe install --accept-eula --acknowledge-ceip --no-ssl-certificate-verification "$jsonPath"

# To verify the deployment template first:
.\vcsa-deploy.exe install --accept-eula --verify-template-only "$jsonPath"

# For a pre-check without actual deployment:
.\vcsa-deploy.exe install --accept-eula --precheck-only "$jsonPath"

"@
    
    Write-Host $deployCommand -ForegroundColor Cyan
    
    # Save deployment instructions
    $instructionsPath = Join-Path $PSScriptRoot "vcsa-deploy-instructions.txt"
    $deployCommand | Set-Content -Path $instructionsPath
    Write-Host "`nInstructions saved to: $instructionsPath" -ForegroundColor Green
    
    return @{
        ConfigPath       = $jsonPath
        InstructionsPath = $instructionsPath
        VcsaHostname     = $vcsaConfig.hostname
        VcsaIp           = $vcsaConfig.ip
    }
}

function Wait-VCSADeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VCenterServer,
        
        [Parameter()]
        [int]$TimeoutMinutes = 60,
        
        [Parameter()]
        [int]$CheckIntervalSeconds = 30
    )
    
    Write-Host "Waiting for VCSA to become available: $VCenterServer" -ForegroundColor Cyan
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $maxWait = [TimeSpan]::FromMinutes($TimeoutMinutes)
    $vcAvailable = $false
    
    while ($stopwatch.Elapsed -lt $maxWait) {
        try {
            $response = Invoke-WebRequest -Uri "https://$VCenterServer/ui" -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
            
            if ($response.StatusCode -eq 200) {
                Write-Host "`nvCenter is now available!" -ForegroundColor Green
                $vcAvailable = $true
                break
            }
        }
        catch {
            $elapsed = $stopwatch.Elapsed.ToString("mm\:ss")
            Write-Host "  [$elapsed] Waiting for vCenter to start..." -ForegroundColor Gray
        }
        
        Start-Sleep -Seconds $CheckIntervalSeconds
    }
    
    $stopwatch.Stop()
    
    if (!$vcAvailable) {
        Write-Host "Timeout waiting for vCenter after $TimeoutMinutes minutes" -ForegroundColor Red
        return $false
    }
    
    return $true
}

function New-VCSADeploymentTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [Parameter()]
        [ValidateSet("tiny", "small", "medium", "large", "xlarge")]
        [string]$Size = "small"
    )
    
    $template = @{
        vcsa = @{
            iso                 = "C:\ISO\VMware-VCSA-all-8.0.3-xxxxx.iso"
            deploymentSize      = $Size
            targetEsxiHost      = "esxi01.domain.local"
            targetDatastore     = "local-datastore"
            targetNetwork       = "VM Network"
            hostname            = "vcenter.domain.local"
            ip                  = "192.168.1.10"
            prefix              = "24"
            gateway             = "192.168.1.1"
            dns                 = @("192.168.1.5", "192.168.1.6")
            ssoPassword         = ""
            ssoDomain           = "vsphere.local"
        }
    }
    
    $template | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "Template saved to: $OutputPath" -ForegroundColor Green
}

#region Main execution when run directly
if ($MyInvocation.InvocationName -ne '.') {
    # Load configuration
    if (!(Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    
    if (!$config.vcenter.deployNew) {
        Write-Host "VCSA deployment is not enabled in configuration (vcenter.deployNew = false)" -ForegroundColor Yellow
        exit 0
    }
    
    # Deploy VCSA
    $result = Deploy-VCSA -Config $config -Credential $Credential
    
    Write-Host "`nVCSA Deployment preparation complete!" -ForegroundColor Green
    Write-Host "Follow the instructions in: $($result.InstructionsPath)" -ForegroundColor Cyan
}
#endregion

# Export functions
Export-ModuleMember -Function Deploy-VCSA, Wait-VCSADeployment, New-VCSADeploymentTemplate -ErrorAction SilentlyContinue
