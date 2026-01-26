<#
.SYNOPSIS
    vCenter Connection Module
.DESCRIPTION
    Handles connection to vCenter Server with validation and error handling.
#>

function Connect-VCenterServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server,
        
        [Parameter(Mandatory)]
        [PSCredential]$Credential,
        
        [Parameter()]
        [int]$MaxRetries = 3,
        
        [Parameter()]
        [int]$RetryDelaySeconds = 10
    )
    
    Write-Host "Connecting to vCenter: $Server" -ForegroundColor Cyan
    
    $retryCount = 0
    $connected = $false
    
    while (!$connected -and $retryCount -lt $MaxRetries) {
        try {
            $retryCount++
            
            # Check if already connected
            if ($global:DefaultVIServer -and $global:DefaultVIServer.Name -eq $Server) {
                Write-Host "Already connected to $Server" -ForegroundColor Green
                return $global:DefaultVIServer
            }
            
            # Disconnect any existing connections
            if ($global:DefaultVIServer) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -ErrorAction SilentlyContinue
            }
            
            # Connect to vCenter
            $connection = Connect-VIServer -Server $Server -Credential $Credential -ErrorAction Stop
            
            # Validate connection
            if ($connection) {
                Write-Host "Successfully connected to vCenter: $($connection.Name)" -ForegroundColor Green
                Write-Host "  Version: $($connection.Version)" -ForegroundColor Gray
                Write-Host "  Build: $($connection.Build)" -ForegroundColor Gray
                $connected = $true
                return $connection
            }
        }
        catch {
            Write-Host "Connection attempt $retryCount failed: $($_.Exception.Message)" -ForegroundColor Yellow
            
            if ($retryCount -lt $MaxRetries) {
                Write-Host "Retrying in $RetryDelaySeconds seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }
    
    if (!$connected) {
        throw "Failed to connect to vCenter after $MaxRetries attempts"
    }
}

function Test-VCenterConnection {
    [CmdletBinding()]
    param()
    
    if ($global:DefaultVIServer -and $global:DefaultVIServer.IsConnected) {
        return $true
    }
    return $false
}

function Get-VCenterVersion {
    [CmdletBinding()]
    param()
    
    if (Test-VCenterConnection) {
        return @{
            Name    = $global:DefaultVIServer.Name
            Version = $global:DefaultVIServer.Version
            Build   = $global:DefaultVIServer.Build
        }
    }
    return $null
}

# Export functions
Export-ModuleMember -Function Connect-VCenterServer, Test-VCenterConnection, Get-VCenterVersion -ErrorAction SilentlyContinue
