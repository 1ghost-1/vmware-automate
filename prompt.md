This is a structured Markdown file that organizes your requirements, the automation logic, and the specialized prompts for use in your documentation or as a technical specification.

***

# vSphere 8.0.3U Infrastructure Automation Blueprint
## Infrastructure as Code (IaC) via PowerCLI

### Overview
This document outlines the strategy for automated infrastructure deployment and configuration for **VMware vSphere 8.0.3U**. The goal is to define core foundational components in code to ensure a repeatable, consistent, and rapid method for building or rebuilding the vSphere fabric—essential for disaster recovery (DR) and environment standardization.

---

### Core Automation Steps

| Step | Action | PowerCLI Logic (Example) |
| :--- | :--- | :--- |
| **1. Logical Containers** | Create top-level Datacenter and Cluster objects with HA and DRS services enabled. | `New-Datacenter -Name "MyDC"` <br> `New-Cluster -Name "MyCluster" -Location "MyDC" -HAEnabled -DrsEnabled` |
| **2. Add Hosts** | Join bare-metal ESXi hosts to the cluster to establish vCenter control. | `Add-VMHost -Name "esxi01.domain.local" -Location "MyCluster"` |
| **3. Networking** | Deploy vSphere Distributed Switches (VDS) and Port Groups; assign physical uplinks. | `New-VDSwitch -Name "Core-VDS" -Location "MyDC"` <br> `New-VDPortgroup -VDSwitch "Core-VDS" -Name "VM-Network"` |
| **4. Storage** | Automate connection to storage (iSCSI, NFS, or VMFS) and mount Datastores. | `New-Datastore -Nfs -Name "NFS-DS01" -Path "/vol/ds01" -NfsHost "storage-array.domain.local"` |
| **5. Configuration** | Enforce consistency using **vSphere Configuration Profiles** (vSphere 8+) for security and NTP. | `Get-Context` / `Set-Cluster` (via JSON-based configuration API in vSphere 8) |

---

### AI Prompt Templates
Use these prompts with an AI assistant to generate production-ready code based on the requirements above.

#### Prompt 1: The Full Environment Build (End-to-End)
> "Act as a Senior VMware Automation Engineer. Write a modular PowerCLI script for **vSphere 8.0.3U** that automates the deployment of a core fabric. The script should:
> 1. Define variables for Datacenter, Cluster, and Hostnames.
> 2. Create the Datacenter and a Cluster with HA and DRS (Fully Automated) enabled.
> 3. Add a list of ESXi hosts.
> 4. Create a VDS (Version 8.0.x) with Port Groups for Management, vMotion (VLAN 10), and Production (VLAN 20).
> 5. Mount a shared NFS 4.1 datastore across all hosts.
> 6. Include Error Handling using Try/Catch blocks and a final status report."

#### Prompt 2: Modern Configuration (vSphere Configuration Profiles)
> "In vSphere 8.0.3U, 'Host Profiles' are being superseded by **vSphere Configuration Profiles**. Provide a PowerCLI script snippet that enables Configuration Profiles on a specific cluster and applies a JSON-based configuration document to ensure all hosts meet the NTP and Firewall security baseline."

---

### vSphere 8.0.3U Best Practices for Automation
*   **VDS Versioning:** When creating a VDS, ensure you specify `-Version "8.0.0"` to leverage the latest hardware acceleration and offloading features.
*   **API-First Approach:** For features not yet fully covered by standard cmdlets (like some Configuration Profile settings), use `Get-CisService` to interact directly with the vSphere REST API.
*   **Desired State:** Ensure scripts are **idempotent** (the script checks if a Datacenter or Switch already exists before attempting to create it).
*   **Security:** Never hardcode credentials. Use `Get-Credential` or integrate with a Secret Management tool (like HashiCorp Vault or Azure Key Vault).

---

---

### Environment Specification (User Defined)

| Category | Setting | Value |
| :--- | :--- | :--- |
| **ESXi Hosts** | Count | 9 |
| | Hostnames | Placeholder (esxi01-08.domain.local) |
| | Management IPs | Placeholder |
| **vCenter** | Deployment Type | New VCSA or Existing |
| | FQDN | Placeholder (vcenter.domain.local) |
| **Networking** | VDS Count | 1 |
| | Port Groups | Management, vMotion, VM Traffic, vSAN |
| | Uplinks | vmnic0, vmnic1 |
| **Storage** | Type | vSAN |
| | Disk Groups | Placeholder |
| **HA/DRS** | HA Admission Control | 12% CPU/Memory Reserved |
| | DRS Automation | Fully Automated |
| **Services** | NTP Servers | Placeholder |
| | DNS Servers | Placeholder |
| | Syslog Server | Placeholder |
| | vMotion TCP/IP Stack | Yes |
| **Credentials** | Method | Get-Credential |
| | ESXi Password | Same across hosts |
| **Code Structure** | Style | Modular scripts |
| | Configuration | JSON file |

---

### Automation Code Structure

```
vmware-automate/
├── config.json                 # All environment parameters
├── Deploy-Infrastructure.ps1   # Main orchestrator
├── Deploy-VCSA.ps1            # New VCSA deployment
└── modules/
    ├── 01-Connect.ps1         # vCenter connection
    ├── 02-Datacenter.ps1      # Datacenter & Cluster
    ├── 03-Hosts.ps1           # Add ESXi hosts
    ├── 04-Networking.ps1      # VDS & Port Groups
    ├── 05-Storage.ps1         # vSAN configuration
    └── 06-Configuration.ps1   # NTP, DNS, Syslog
```

***