================================================================================
               vSphere 8.0.3U Infrastructure Automation Toolkit
================================================================================

OVERVIEW
--------
This toolkit provides modular PowerCLI scripts for automated deployment and 
configuration of VMware vSphere 8.0.3U infrastructure. It supports both new 
deployments and rebuilding existing environments using Infrastructure as Code 
(IaC) principles.

Features:
  - Deploy new VCSA (vCenter Server Appliance)
  - Create Datacenters and Clusters with HA/DRS
  - Add ESXi hosts to cluster
  - Configure VDS (vSphere Distributed Switch) with port groups
  - Enable and configure vSAN storage with auto-discovery
  - Apply host configuration (NTP, DNS, Syslog, Security)
  - vMotion TCP/IP stack configuration
  - Idempotent design - safe to re-run without duplicating resources


================================================================================
REQUIREMENTS
================================================================================

Software:
  - PowerShell 5.1+ or PowerShell 7.x
  - VMware PowerCLI 13.0 or later
  - Windows, macOS, or Linux

VMware Environment:
  - vSphere 8.0.3U license
  - ESXi 8.0.3U hosts (9 hosts configured by default)
  - Network connectivity to vCenter and ESXi hosts
  - VCSA ISO (for new vCenter deployments)

Install PowerCLI:
  Install-Module VMware.PowerCLI -Scope CurrentUser
  Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false


================================================================================
FILE STRUCTURE
================================================================================

vmware-automate/
|
|-- config.json                 Configuration file (EDIT THIS FIRST)
|-- Deploy-Infrastructure.ps1   Main orchestrator script
|-- Deploy-VCSA.ps1             VCSA deployment script
|-- README.txt                  This file
|
+-- modules/
    |-- 01-Connect.ps1          vCenter connection module
    |-- 02-Datacenter.ps1       Datacenter and Cluster creation
    |-- 03-Hosts.ps1            ESXi host addition
    |-- 04-Networking.ps1       VDS and port group configuration
    |-- 05-Storage.ps1          vSAN storage configuration
    +-- 06-Configuration.ps1    Host services (NTP, DNS, Syslog)

+-- logs/                       Created automatically for deployment logs


================================================================================
QUICK START
================================================================================

Step 1: Configure Your Environment
-----------------------------------
Edit config.json and replace ALL placeholder values:

  - vCenter server FQDN and credentials
  - ESXi host FQDNs and IP addresses
  - Network settings (VLANs, subnets, gateways)
  - NTP, DNS, and Syslog servers
  - vSAN disk configuration

Step 2: Run the Deployment
--------------------------
Open PowerShell and navigate to the project directory:

  cd "G:\My Drive\Github\vmware-automate"
  .\Deploy-Infrastructure.ps1 -ConfigPath .\config.json

Step 3: Enter Credentials When Prompted
---------------------------------------
You will be prompted for:
  - vCenter Administrator credentials
  - ESXi root credentials


================================================================================
CONFIGURATION FILE (config.json)
================================================================================

The config.json file contains all environment parameters. Key sections:

ENVIRONMENT
-----------
  "environment": {
    "name": "Production",
    "description": "vSphere 8.0.3U Production Environment"
  }

VCENTER
-------
  "vcenter": {
    "server": "vcenter.domain.local",    <- Your vCenter FQDN
    "deployNew": false,                   <- Set true for new VCSA
    "vcsa": { ... }                       <- VCSA deployment settings
  }

DATACENTER & CLUSTER
--------------------
  "datacenter": {
    "name": "DC-01"                       <- Datacenter name
  },
  "cluster": {
    "name": "Cluster-01",                 <- Cluster name
    "ha": {
      "enabled": true,
      "admissionControl": {
        "cpuPercent": 12,                 <- 12% CPU reserved for HA
        "memoryPercent": 12               <- 12% Memory reserved for HA
      }
    },
    "drs": {
      "enabled": true,
      "automationLevel": "FullyAutomated"
    }
  }

ESXI HOSTS
----------
  "esxiHosts": [
    {
      "hostname": "esxi01.domain.local",  <- Host FQDN
      "managementIp": "192.168.1.21",     <- Management IP
      "vmotionIp": "10.10.10.21",         <- vMotion IP
      "vsanIp": "10.10.20.21"             <- vSAN IP
    },
    ...                                    <- 9 hosts total
  ]

NETWORKING
----------
  "networking": {
    "vds": {
      "name": "VDS-Core",
      "version": "8.0.0",
      "mtu": 9000,                        <- Jumbo frames
      "uplinks": ["vmnic0", "vmnic1"]
    },
    "portGroups": [
      { "name": "PG-Management", "vlanId": 0,  "type": "Management" },
      { "name": "PG-vMotion",    "vlanId": 10, "type": "vMotion" },
      { "name": "PG-VMTraffic",  "vlanId": 20, "type": "VMTraffic" },
      { "name": "PG-vSAN",       "vlanId": 30, "type": "vSAN" }
    ]
  }

VSAN STORAGE
------------
  "storage": {
    "vsan": {
      "enabled": true,
      "claimMode": "Automatic",           <- Auto-discover disks
      "deduplicationEnabled": true,
      "compressionEnabled": true
    }
  }

SERVICES
--------
  "services": {
    "ntp": {
      "servers": ["ntp1.domain.local", "ntp2.domain.local"]
    },
    "dns": {
      "servers": ["192.168.1.5", "192.168.1.6"],
      "searchDomains": ["domain.local"]
    },
    "syslog": {
      "server": "syslog.domain.local",
      "port": 514,
      "protocol": "udp"
    }
  }


================================================================================
USAGE EXAMPLES
================================================================================

FULL DEPLOYMENT (All Steps)
---------------------------
  .\Deploy-Infrastructure.ps1 -ConfigPath .\config.json

SKIP SPECIFIC STEPS
-------------------
Skip VCSA deployment (use existing vCenter):
  .\Deploy-Infrastructure.ps1 -SkipVCSA

Skip networking configuration:
  .\Deploy-Infrastructure.ps1 -SkipNetworking

Skip vSAN storage configuration:
  .\Deploy-Infrastructure.ps1 -SkipStorage

Skip host configuration (NTP, DNS, Syslog):
  .\Deploy-Infrastructure.ps1 -SkipConfiguration

Combine multiple skips:
  .\Deploy-Infrastructure.ps1 -SkipVCSA -SkipStorage

DRY RUN (WhatIf)
----------------
  .\Deploy-Infrastructure.ps1 -WhatIf

DEPLOY NEW VCSA ONLY
--------------------
  .\Deploy-VCSA.ps1 -ConfigPath .\config.json


================================================================================
MODULE REFERENCE
================================================================================

01-Connect.ps1
--------------
  Connect-VCenterServer   Connect to vCenter with retry logic
  Test-VCenterConnection  Check if connected to vCenter
  Get-VCenterVersion      Get vCenter version information

02-Datacenter.ps1
-----------------
  New-VsphereDatacenter   Create a new Datacenter
  New-VsphereCluster      Create a new Cluster with HA/DRS
  Set-ClusterConfiguration Configure HA admission control and DRS
  Get-ClusterStatus       Get cluster configuration status

03-Hosts.ps1
------------
  Add-ESXiHostsToCluster       Add multiple ESXi hosts to cluster
  Remove-ESXiHostFromCluster   Remove a host from vCenter
  Set-ESXiHostMaintenanceMode  Enter/exit maintenance mode
  Get-ESXiHostStatus           Get status of all hosts

04-Networking.ps1
-----------------
  New-VsphereVDS          Create vSphere Distributed Switch
  New-VspherePortGroups   Create port groups on VDS
  Add-HostsToVDS          Add hosts to VDS with uplinks
  Configure-VMotionStack  Configure vMotion TCP/IP stack
  New-VsanVMkernel        Create vSAN VMkernel adapters

05-Storage.ps1
--------------
  Enable-VsanCluster           Enable vSAN on cluster
  Configure-VsanDiskGroups     Configure disk groups (supports auto-discovery)
  New-AutoDiscoveredDiskGroup  Auto-select cache/capacity disks
  Get-VsanDiskInventory        List all eligible disks in cluster
  Get-VsanClusterStatus        Get vSAN cluster status
  New-VsanStoragePolicy        Create vSAN storage policy
  Remove-VsanDiskGroup         Remove disk group from host

06-Configuration.ps1
--------------------
  Set-HostNtpConfiguration      Configure NTP servers
  Set-HostDnsConfiguration      Configure DNS servers
  Set-HostSyslogConfiguration   Configure remote syslog
  Set-HostSecurityConfiguration Configure SSH, lockdown, firewall
  Get-HostConfiguration         Get current host configuration
  Set-HostAdvancedSetting       Set advanced ESXi settings


================================================================================
VSAN DISK AUTO-DISCOVERY
================================================================================

The toolkit includes intelligent disk auto-discovery for vSAN:

Pre-flight Disk Inventory:
--------------------------
Before deploying, review available disks:

  . .\modules\05-Storage.ps1
  Get-VsanDiskInventory -ClusterName "Cluster-01" | Format-Table

Output example:
  Host                  CanonicalName          CapacityGB  Type  Status
  ----                  -------------          ----------  ----  ------
  esxi01.domain.local   naa.5000xxxxx          400         SSD   Eligible
  esxi01.domain.local   naa.5000yyyyy          1800        HDD   Eligible
  esxi01.domain.local   naa.5000zzzzz          1800        HDD   Eligible

Auto-Discovery Logic:
---------------------
  All-Flash:  Smallest SSD -> Cache, remaining SSDs -> Capacity
  Hybrid:     Any SSD -> Cache, All HDDs -> Capacity

Manual Override:
----------------
If you need specific disk assignments:

  New-VsanDiskGroup -VMHost "esxi01.domain.local" `
    -SsdCanonicalName "naa.5000xxxxxxxxxxxxx" `
    -DataDiskCanonicalName "naa.5000yyyyy","naa.5000zzzzz"


================================================================================
DEPLOYING A NEW VCSA
================================================================================

To deploy a fresh vCenter Server Appliance:

1. Set deployNew to true in config.json:
   "vcenter": {
     "deployNew": true,
     ...
   }

2. Configure the vcsa section:
   "vcsa": {
     "iso": "C:\\ISO\\VMware-VCSA-all-8.0.3-xxxxx.iso",
     "deploymentSize": "small",
     "targetEsxiHost": "esxi01.domain.local",
     "targetDatastore": "local-ds01",
     "targetNetwork": "VM Network",
     "hostname": "vcenter.domain.local",
     "ip": "192.168.1.10",
     ...
   }

3. Run Deploy-VCSA.ps1:
   .\Deploy-VCSA.ps1 -ConfigPath .\config.json

4. Follow the generated instructions to run vcsa-deploy CLI

Deployment Sizes:
  tiny   - Up to 10 hosts, 100 VMs
  small  - Up to 100 hosts, 1000 VMs
  medium - Up to 400 hosts, 4000 VMs
  large  - Up to 1000 hosts, 10000 VMs
  xlarge - Up to 2500 hosts, 45000 VMs


================================================================================
LOGGING
================================================================================

All deployment activities are logged to the logs/ directory:

  logs/deployment-YYYYMMDD-HHMMSS.log

Log levels:
  [INFO]    - Informational messages
  [WARN]    - Warnings (non-fatal issues)
  [ERROR]   - Errors (operation failed)
  [SUCCESS] - Successful completion


================================================================================
TROUBLESHOOTING
================================================================================

Problem: Cannot connect to vCenter
----------------------------------
  - Verify vCenter FQDN is resolvable: nslookup vcenter.domain.local
  - Check firewall allows port 443
  - Verify credentials are correct
  - Try: Connect-VIServer -Server vcenter.domain.local -Credential (Get-Credential)

Problem: Host cannot be added to cluster
----------------------------------------
  - Verify ESXi host is accessible: Test-Connection esxi01.domain.local
  - Check ESXi root password is correct
  - Ensure host is not already in a different vCenter
  - Check if host is in lockdown mode

Problem: VDS creation fails
---------------------------
  - Verify vCenter has Enterprise Plus license
  - Check datacenter exists first
  - Ensure VDS name is unique

Problem: vSAN disks not detected
--------------------------------
  - Run disk inventory to see available disks:
    Get-VsanDiskInventory -ClusterName "Cluster-01"
  - Verify disks are not partitioned or in use
  - Check if disks meet vSAN requirements (min 10GB)

Problem: vMotion fails
----------------------
  - Verify vMotion VMkernel exists on all hosts
  - Check vMotion VLAN connectivity between hosts
  - Ensure vMotion is enabled on the VMkernel adapter


================================================================================
SECURITY BEST PRACTICES
================================================================================

1. Never hardcode passwords in config.json
   - Leave password fields empty
   - Credentials are prompted at runtime using Get-Credential

2. Use a secrets manager for automation
   - Azure Key Vault
   - HashiCorp Vault
   - CyberArk

3. Restrict file permissions on config.json
   - Contains sensitive network topology information

4. Review security settings before deployment
   "security": {
     "sshEnabled": false,           <- Disable SSH in production
     "lockdownMode": "normal",      <- Enable lockdown mode
     "shellTimeout": 900            <- 15 minute shell timeout
   }

5. Secure the logs directory
   - Logs may contain sensitive operation details


================================================================================
CUSTOMIZATION
================================================================================

Adding Custom Port Groups:
--------------------------
Edit the portGroups array in config.json:

  "portGroups": [
    { "name": "PG-FaultTolerance", "vlanId": 40, "type": "FT" },
    { "name": "PG-iSCSI-A", "vlanId": 50, "type": "iSCSI" },
    { "name": "PG-iSCSI-B", "vlanId": 51, "type": "iSCSI" }
  ]

Adding More Hosts:
------------------
Add entries to the esxiHosts array in config.json:

  {
    "hostname": "esxi10.domain.local",
    "managementIp": "192.168.1.30",
    "vmotionIp": "10.10.10.30",
    "vsanIp": "10.10.20.30"
  }

Custom Advanced Settings:
-------------------------
Use the Set-HostAdvancedSetting function:

  Set-HostAdvancedSetting -HostName "esxi01.domain.local" `
    -SettingName "Mem.ShareScanGHz" `
    -Value 4


================================================================================
VERSION HISTORY
================================================================================

v1.0.0 (January 2026)
  - Initial release
  - Support for vSphere 8.0.3U
  - Modular script architecture
  - vSAN auto-discovery
  - Full infrastructure deployment


================================================================================
SUPPORT
================================================================================

For issues and feature requests:
  - Review the troubleshooting section above
  - Check VMware PowerCLI documentation
  - Verify vSphere 8.0.3U compatibility

VMware Documentation:
  - PowerCLI User Guide: https://developer.vmware.com/powercli
  - vSphere 8 Documentation: https://docs.vmware.com/en/VMware-vSphere/8.0

================================================================================
