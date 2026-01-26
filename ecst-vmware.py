#!/usr/bin/env python3
"""
ECST VMware Automation Tool
---------------------------
A menu-driven Python interface for VMware vSphere infrastructure deployment and management.
Orchestrates PowerShell scripts for vCenter, datacenter, cluster, and VM operations.

Author: ECST Team
Version: 1.0.0
"""

import os
import sys
import json
import subprocess
import getpass
from pathlib import Path
from typing import Optional, Dict, Any, List
from dataclasses import dataclass
from enum import Enum


# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR = Path(__file__).parent.resolve()
CONFIG_FILE = SCRIPT_DIR / "config.json"
MODULES_DIR = SCRIPT_DIR / "modules"

# VM Templates available for deployment
VM_TEMPLATES = {
    "1": {"name": "Splunk", "template": "template-splunk-enterprise", "description": "Splunk Enterprise Server"},
    "2": {"name": "Cribl", "template": "template-cribl-stream", "description": "Cribl Stream/Edge"},
    "3": {"name": "Forescout", "template": "template-forescout", "description": "Forescout CounterACT"},
    "4": {"name": "Windows Server", "template": "template-windows-2022", "description": "Windows Server 2022"},
    "5": {"name": "RHEL 9", "template": "template-rhel9", "description": "Red Hat Enterprise Linux 9"},
    "6": {"name": "Ubuntu 22.04", "template": "template-ubuntu-2204", "description": "Ubuntu Server 22.04 LTS"},
}

# VM Size configurations
VM_SIZES = {
    "Small": {"cpu": 2, "memory_gb": 4, "disk_gb": 50},
    "Medium": {"cpu": 4, "memory_gb": 8, "disk_gb": 100},
    "Large": {"cpu": 8, "memory_gb": 16, "disk_gb": 200},
    "XLarge": {"cpu": 16, "memory_gb": 32, "disk_gb": 500},
}

# OS Types for standard VM deployment
OS_TYPES = {
    "1": {"name": "RHEL", "guest_id": "rhel9_64Guest", "description": "Red Hat Enterprise Linux"},
    "2": {"name": "Ubuntu", "guest_id": "ubuntu64Guest", "description": "Ubuntu Linux"},
    "3": {"name": "Windows", "guest_id": "windows2019srv_64Guest", "description": "Windows Server"},
    "4": {"name": "CentOS", "guest_id": "centos9_64Guest", "description": "CentOS Stream"},
    "5": {"name": "Debian", "guest_id": "debian11_64Guest", "description": "Debian Linux"},
}


# =============================================================================
# Helper Classes
# =============================================================================

class Colors:
    """ANSI color codes for terminal output."""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

    @classmethod
    def disable(cls):
        """Disable colors for non-supporting terminals."""
        cls.HEADER = ''
        cls.BLUE = ''
        cls.CYAN = ''
        cls.GREEN = ''
        cls.YELLOW = ''
        cls.RED = ''
        cls.ENDC = ''
        cls.BOLD = ''
        cls.UNDERLINE = ''


@dataclass
class VMConfig:
    """Configuration for a virtual machine deployment."""
    name: str
    os_type: str
    size: str
    tag_name: str
    ip_address: str
    template: Optional[str] = None
    guest_id: Optional[str] = None
    cpu: Optional[int] = None
    memory_gb: Optional[int] = None
    disk_gb: Optional[int] = None


# =============================================================================
# Utility Functions
# =============================================================================

def clear_screen():
    """Clear the terminal screen."""
    os.system('cls' if os.name == 'nt' else 'clear')


def print_header(title: str):
    """Print a formatted header."""
    width = 60
    print()
    print(f"{Colors.CYAN}{'=' * width}{Colors.ENDC}")
    print(f"{Colors.BOLD}{Colors.CYAN}  {title}{Colors.ENDC}")
    print(f"{Colors.CYAN}{'=' * width}{Colors.ENDC}")
    print()


def print_success(message: str):
    """Print a success message."""
    print(f"{Colors.GREEN}[SUCCESS]{Colors.ENDC} {message}")


def print_error(message: str):
    """Print an error message."""
    print(f"{Colors.RED}[ERROR]{Colors.ENDC} {message}")


def print_warning(message: str):
    """Print a warning message."""
    print(f"{Colors.YELLOW}[WARNING]{Colors.ENDC} {message}")


def print_info(message: str):
    """Print an info message."""
    print(f"{Colors.CYAN}[INFO]{Colors.ENDC} {message}")


def get_input(prompt: str, default: str = "") -> str:
    """Get user input with optional default value."""
    if default:
        user_input = input(f"{prompt} [{default}]: ").strip()
        return user_input if user_input else default
    return input(f"{prompt}: ").strip()


def get_password(prompt: str) -> str:
    """Get password input (hidden)."""
    return getpass.getpass(f"{prompt}: ")


def confirm_action(message: str) -> bool:
    """Ask for user confirmation."""
    response = input(f"{Colors.YELLOW}{message} (y/n): {Colors.ENDC}").strip().lower()
    return response in ('y', 'yes')


def load_config() -> Dict[str, Any]:
    """Load configuration from JSON file."""
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print_error(f"Configuration file not found: {CONFIG_FILE}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print_error(f"Invalid JSON in configuration file: {e}")
        sys.exit(1)


def save_config(config: Dict[str, Any]):
    """Save configuration to JSON file."""
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)


def run_powershell(script: str, params: Dict[str, str] = None) -> subprocess.CompletedProcess:
    """Execute a PowerShell script with parameters."""
    cmd = ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", str(script)]
    
    if params:
        for key, value in params.items():
            cmd.extend([f"-{key}", str(value)])
    
    print_info(f"Executing: {script}")
    print(f"{Colors.CYAN}{'─' * 50}{Colors.ENDC}")
    
    result = subprocess.run(
        cmd,
        capture_output=False,
        text=True,
        cwd=str(SCRIPT_DIR)
    )
    
    print(f"{Colors.CYAN}{'─' * 50}{Colors.ENDC}")
    return result


def run_powershell_command(command: str) -> subprocess.CompletedProcess:
    """Execute a PowerShell command directly."""
    cmd = ["powershell.exe", "-ExecutionPolicy", "Bypass", "-Command", command]
    
    print_info(f"Executing PowerShell command...")
    print(f"{Colors.CYAN}{'─' * 50}{Colors.ENDC}")
    
    result = subprocess.run(
        cmd,
        capture_output=False,
        text=True,
        cwd=str(SCRIPT_DIR)
    )
    
    print(f"{Colors.CYAN}{'─' * 50}{Colors.ENDC}")
    return result


# =============================================================================
# Menu Display Functions
# =============================================================================

def display_main_menu():
    """Display the main menu."""
    clear_screen()
    print_header("ECST VMware Automation Tool")
    
    config = load_config()
    print(f"  Environment: {Colors.GREEN}{config['environment']['name']}{Colors.ENDC}")
    print(f"  vCenter:     {Colors.CYAN}{config['vcenter']['server']}{Colors.ENDC}")
    print(f"  Datacenter:  {Colors.CYAN}{config['datacenter']['name']}{Colors.ENDC}")
    print(f"  Cluster:     {Colors.CYAN}{config['cluster']['name']}{Colors.ENDC}")
    print()
    
    print(f"{Colors.BOLD}Main Menu:{Colors.ENDC}")
    print()
    print("  1. Deploy vCenter (VCSA)")
    print("  2. Deploy Infrastructure (Full)")
    print("  3. Deploy Datacenter")
    print("  4. Deploy Cluster")
    print("  5. Configure Infrastructure")
    print("  6. Deploy Virtual Machine")
    print()
    print("  C. Configuration Management")
    print("  S. Show Current Status")
    print("  Q. Quit")
    print()


def display_configure_menu():
    """Display the configuration submenu."""
    clear_screen()
    print_header("Configure Infrastructure")
    
    print(f"{Colors.BOLD}Configuration Options:{Colors.ENDC}")
    print()
    print("  1. Configure vSAN")
    print("  2. Configure vDS (Distributed Switch)")
    print("  3. Configure vMotion")
    print("  4. Configure NTP/DNS/Syslog")
    print("  5. Configure Security Settings")
    print("  6. Configure All (Full)")
    print()
    print("  B. Back to Main Menu")
    print()


def display_vm_menu():
    """Display the VM deployment submenu."""
    clear_screen()
    print_header("Deploy Virtual Machine")
    
    print(f"{Colors.BOLD}VM Deployment Options:{Colors.ENDC}")
    print()
    print("  1. Deploy VM from Template")
    print("  2. Deploy Standard Virtual Machine")
    print()
    print("  B. Back to Main Menu")
    print()


def display_template_menu():
    """Display available VM templates."""
    clear_screen()
    print_header("Deploy VM from Template")
    
    print(f"{Colors.BOLD}Available Templates:{Colors.ENDC}")
    print()
    for key, template in VM_TEMPLATES.items():
        print(f"  {key}. {template['name']:20} - {template['description']}")
    print()
    print("  B. Back to VM Menu")
    print()


def display_config_management_menu():
    """Display configuration management menu."""
    clear_screen()
    print_header("Configuration Management")
    
    print(f"{Colors.BOLD}Configuration Options:{Colors.ENDC}")
    print()
    print("  1. View Current Configuration")
    print("  2. Edit vCenter Settings")
    print("  3. Edit Datacenter/Cluster Settings")
    print("  4. Edit ESXi Host List")
    print("  5. Edit Network Settings")
    print("  6. Edit Storage (vSAN) Settings")
    print("  7. Reload Configuration")
    print()
    print("  B. Back to Main Menu")
    print()


# =============================================================================
# Deployment Functions
# =============================================================================

def deploy_vcenter():
    """Deploy vCenter Server Appliance."""
    print_header("Deploy vCenter Server Appliance (VCSA)")
    
    config = load_config()
    vcsa_config = config['vcenter']['vcsa']
    
    print(f"VCSA Deployment Configuration:")
    print(f"  Target ESXi Host: {vcsa_config['targetEsxiHost']}")
    print(f"  VCSA Hostname:    {vcsa_config['hostname']}")
    print(f"  VCSA IP:          {vcsa_config['ip']}")
    print(f"  Deployment Size:  {vcsa_config['deploymentSize']}")
    print(f"  SSO Domain:       {vcsa_config['ssoDomain']}")
    print()
    
    if not confirm_action("Do you want to proceed with VCSA deployment?"):
        print_warning("VCSA deployment cancelled.")
        return
    
    script_path = SCRIPT_DIR / "Deploy-VCSA.ps1"
    if not script_path.exists():
        print_error(f"Script not found: {script_path}")
        return
    
    result = run_powershell(script_path, {"ConfigPath": str(CONFIG_FILE)})
    
    if result.returncode == 0:
        print_success("VCSA deployment preparation completed!")
    else:
        print_error(f"VCSA deployment failed with exit code: {result.returncode}")
    
    input("\nPress Enter to continue...")


def deploy_infrastructure():
    """Deploy full infrastructure."""
    print_header("Deploy Full Infrastructure")
    
    config = load_config()
    
    print("This will deploy the following components:")
    print(f"  • Datacenter: {config['datacenter']['name']}")
    print(f"  • Cluster:    {config['cluster']['name']}")
    print(f"  • Hosts:      {len(config['esxiHosts'])} ESXi hosts")
    print(f"  • VDS:        {config['networking']['vds']['name']}")
    print(f"  • vSAN:       {'Enabled' if config['storage']['vsan']['enabled'] else 'Disabled'}")
    print()
    
    if not confirm_action("Do you want to proceed with full infrastructure deployment?"):
        print_warning("Infrastructure deployment cancelled.")
        return
    
    script_path = SCRIPT_DIR / "Deploy-Infrastructure.ps1"
    if not script_path.exists():
        print_error(f"Script not found: {script_path}")
        return
    
    result = run_powershell(script_path, {"ConfigPath": str(CONFIG_FILE)})
    
    if result.returncode == 0:
        print_success("Infrastructure deployment completed!")
    else:
        print_error(f"Infrastructure deployment failed with exit code: {result.returncode}")
    
    input("\nPress Enter to continue...")


def deploy_datacenter():
    """Deploy datacenter only."""
    print_header("Deploy Datacenter")
    
    config = load_config()
    dc_name = config['datacenter']['name']
    
    print(f"Datacenter to create: {dc_name}")
    print()
    
    if not confirm_action("Create this datacenter?"):
        print_warning("Datacenter creation cancelled.")
        return
    
    ps_command = f"""
    . '{MODULES_DIR / "01-Connect.ps1"}'
    . '{MODULES_DIR / "02-Datacenter.ps1"}'
    
    $config = Get-Content '{CONFIG_FILE}' -Raw | ConvertFrom-Json
    $cred = Get-Credential -Message "Enter vCenter Administrator Credentials"
    
    Connect-VCenterServer -Server $config.vcenter.server -Credential $cred
    New-VsphereDatacenter -Config $config
    
    Disconnect-VIServer -Server * -Force -Confirm:$false
    """
    
    result = run_powershell_command(ps_command)
    
    if result.returncode == 0:
        print_success("Datacenter created successfully!")
    else:
        print_error(f"Datacenter creation failed with exit code: {result.returncode}")
    
    input("\nPress Enter to continue...")


def deploy_cluster():
    """Deploy cluster only."""
    print_header("Deploy Cluster")
    
    config = load_config()
    cluster_config = config['cluster']
    
    print(f"Cluster Configuration:")
    print(f"  Name:          {cluster_config['name']}")
    print(f"  HA Enabled:    {cluster_config['ha']['enabled']}")
    print(f"  DRS Enabled:   {cluster_config['drs']['enabled']}")
    print(f"  DRS Level:     {cluster_config['drs']['automationLevel']}")
    print()
    
    if not confirm_action("Create this cluster?"):
        print_warning("Cluster creation cancelled.")
        return
    
    ps_command = f"""
    . '{MODULES_DIR / "01-Connect.ps1"}'
    . '{MODULES_DIR / "02-Datacenter.ps1"}'
    
    $config = Get-Content '{CONFIG_FILE}' -Raw | ConvertFrom-Json
    $cred = Get-Credential -Message "Enter vCenter Administrator Credentials"
    
    Connect-VCenterServer -Server $config.vcenter.server -Credential $cred
    New-VsphereCluster -Config $config
    
    Disconnect-VIServer -Server * -Force -Confirm:$false
    """
    
    result = run_powershell_command(ps_command)
    
    if result.returncode == 0:
        print_success("Cluster created successfully!")
    else:
        print_error(f"Cluster creation failed with exit code: {result.returncode}")
    
    input("\nPress Enter to continue...")


# =============================================================================
# Configuration Functions
# =============================================================================

def configure_vsan():
    """Configure vSAN storage."""
    print_header("Configure vSAN")
    
    config = load_config()
    vsan_config = config['storage']['vsan']
    
    print(f"vSAN Configuration:")
    print(f"  Enabled:      {vsan_config['enabled']}")
    print(f"  Claim Mode:   {vsan_config['claimMode']}")
    print(f"  Dedup:        {vsan_config['deduplicationEnabled']}")
    print(f"  Compression:  {vsan_config['compressionEnabled']}")
    print()
    
    if not confirm_action("Configure vSAN with these settings?"):
        print_warning("vSAN configuration cancelled.")
        return
    
    ps_command = f"""
    . '{MODULES_DIR / "01-Connect.ps1"}'
    . '{MODULES_DIR / "05-Storage.ps1"}'
    
    $config = Get-Content '{CONFIG_FILE}' -Raw | ConvertFrom-Json
    $cred = Get-Credential -Message "Enter vCenter Administrator Credentials"
    
    Connect-VCenterServer -Server $config.vcenter.server -Credential $cred
    Enable-VsanCluster -Config $config
    Configure-VsanDiskGroups -Config $config -AutoClaim
    
    Disconnect-VIServer -Server * -Force -Confirm:$false
    """
    
    result = run_powershell_command(ps_command)
    
    if result.returncode == 0:
        print_success("vSAN configured successfully!")
    else:
        print_error(f"vSAN configuration failed with exit code: {result.returncode}")
    
    input("\nPress Enter to continue...")


def configure_vds():
    """Configure vSphere Distributed Switch."""
    print_header("Configure Distributed Switch (VDS)")
    
    config = load_config()
    vds_config = config['networking']['vds']
    
    print(f"VDS Configuration:")
    print(f"  Name:           {vds_config['name']}")
    print(f"  Version:        {vds_config['version']}")
    print(f"  MTU:            {vds_config['mtu']}")
    print(f"  Uplinks:        {vds_config['uplinks']}")
    print(f"  Load Balancing: {vds_config['loadBalancing']}")
    print()
    print("Port Groups:")
    for pg in config['networking']['portGroups']:
        print(f"  • {pg['name']} (VLAN {pg['vlanId']}) - {pg['type']}")
    print()
    
    if not confirm_action("Configure VDS with these settings?"):
        print_warning("VDS configuration cancelled.")
        return
    
    ps_command = f"""
    . '{MODULES_DIR / "01-Connect.ps1"}'
    . '{MODULES_DIR / "04-Networking.ps1"}'
    
    $config = Get-Content '{CONFIG_FILE}' -Raw | ConvertFrom-Json
    $cred = Get-Credential -Message "Enter vCenter Administrator Credentials"
    
    Connect-VCenterServer -Server $config.vcenter.server -Credential $cred
    New-VsphereVDS -Config $config
    New-VspherePortGroups -Config $config
    Add-HostsToVDS -Config $config
    
    Disconnect-VIServer -Server * -Force -Confirm:$false
    """
    
    result = run_powershell_command(ps_command)
    
    if result.returncode == 0:
        print_success("VDS configured successfully!")
    else:
        print_error(f"VDS configuration failed with exit code: {result.returncode}")
    
    input("\nPress Enter to continue...")


def configure_vmotion():
    """Configure vMotion networking."""
    print_header("Configure vMotion")
    
    config = load_config()
    vmotion_config = config['networking']['vmotionTcpIpStack']
    
    print(f"vMotion Configuration:")
    print(f"  Enabled:     {vmotion_config['enabled']}")
    print(f"  Gateway:     {vmotion_config['gateway']}")
    print(f"  Subnet Mask: {vmotion_config['subnetMask']}")
    print()
    print("Host vMotion IPs:")
    for host in config['esxiHosts']:
        print(f"  • {host['hostname']}: {host['vmotionIp']}")
    print()
    
    if not confirm_action("Configure vMotion with these settings?"):
        print_warning("vMotion configuration cancelled.")
        return
    
    ps_command = f"""
    . '{MODULES_DIR / "01-Connect.ps1"}'
    . '{MODULES_DIR / "04-Networking.ps1"}'
    
    $config = Get-Content '{CONFIG_FILE}' -Raw | ConvertFrom-Json
    $cred = Get-Credential -Message "Enter vCenter Administrator Credentials"
    
    Connect-VCenterServer -Server $config.vcenter.server -Credential $cred
    Configure-VMotionStack -Config $config
    
    Disconnect-VIServer -Server * -Force -Confirm:$false
    """
    
    result = run_powershell_command(ps_command)
    
    if result.returncode == 0:
        print_success("vMotion configured successfully!")
    else:
        print_error(f"vMotion configuration failed with exit code: {result.returncode}")
    
    input("\nPress Enter to continue...")


def configure_services():
    """Configure NTP, DNS, and Syslog services."""
    print_header("Configure Host Services (NTP/DNS/Syslog)")
    
    config = load_config()
    
    print("NTP Configuration:")
    print(f"  Servers: {', '.join(config['services']['ntp']['servers'])}")
    print(f"  Policy:  {config['services']['ntp']['policy']}")
    print()
    print("DNS Configuration:")
    print(f"  Servers: {', '.join(config['services']['dns']['servers'])}")
    print(f"  Search:  {', '.join(config['services']['dns']['searchDomains'])}")
    print()
    print("Syslog Configuration:")
    print(f"  Server:   {config['services']['syslog']['server']}")
    print(f"  Port:     {config['services']['syslog']['port']}")
    print(f"  Protocol: {config['services']['syslog']['protocol']}")
    print()
    
    if not confirm_action("Configure services with these settings?"):
        print_warning("Service configuration cancelled.")
        return
    
    ps_command = f"""
    . '{MODULES_DIR / "01-Connect.ps1"}'
    . '{MODULES_DIR / "06-Configuration.ps1"}'
    
    $config = Get-Content '{CONFIG_FILE}' -Raw | ConvertFrom-Json
    $cred = Get-Credential -Message "Enter vCenter Administrator Credentials"
    
    Connect-VCenterServer -Server $config.vcenter.server -Credential $cred
    Set-HostNtpConfiguration -Config $config
    Set-HostDnsConfiguration -Config $config
    Set-HostSyslogConfiguration -Config $config
    
    Disconnect-VIServer -Server * -Force -Confirm:$false
    """
    
    result = run_powershell_command(ps_command)
    
    if result.returncode == 0:
        print_success("Host services configured successfully!")
    else:
        print_error(f"Service configuration failed with exit code: {result.returncode}")
    
    input("\nPress Enter to continue...")


def configure_security():
    """Configure security settings."""
    print_header("Configure Security Settings")
    
    config = load_config()
    security_config = config['security']
    
    print("Security Configuration:")
    print(f"  Lockdown Mode:  {security_config['lockdownMode']}")
    print(f"  SSH Enabled:    {security_config['sshEnabled']}")
    print(f"  Shell Timeout:  {security_config['shellTimeout']} seconds")
    print(f"  Firewall Rules: {', '.join(security_config['firewallRulesetsEnabled'])}")
    print()
    
    if not confirm_action("Apply these security settings?"):
        print_warning("Security configuration cancelled.")
        return
    
    ps_command = f"""
    . '{MODULES_DIR / "01-Connect.ps1"}'
    . '{MODULES_DIR / "06-Configuration.ps1"}'
    
    $config = Get-Content '{CONFIG_FILE}' -Raw | ConvertFrom-Json
    $cred = Get-Credential -Message "Enter vCenter Administrator Credentials"
    
    Connect-VCenterServer -Server $config.vcenter.server -Credential $cred
    Set-HostSecurityConfiguration -Config $config
    
    Disconnect-VIServer -Server * -Force -Confirm:$false
    """
    
    result = run_powershell_command(ps_command)
    
    if result.returncode == 0:
        print_success("Security settings applied successfully!")
    else:
        print_error(f"Security configuration failed with exit code: {result.returncode}")
    
    input("\nPress Enter to continue...")


def configure_all():
    """Configure all infrastructure components."""
    print_header("Configure All Infrastructure")
    
    print("This will configure:")
    print("  • vSAN Storage")
    print("  • Distributed Switch (VDS)")
    print("  • vMotion Networking")
    print("  • NTP, DNS, Syslog Services")
    print("  • Security Settings")
    print()
    
    if not confirm_action("Proceed with full infrastructure configuration?"):
        print_warning("Full configuration cancelled.")
        return
    
    script_path = SCRIPT_DIR / "Deploy-Infrastructure.ps1"
    result = run_powershell(script_path, {
        "ConfigPath": str(CONFIG_FILE),
        "SkipVCSA": "$true"
    })
    
    if result.returncode == 0:
        print_success("Full infrastructure configuration completed!")
    else:
        print_error(f"Configuration failed with exit code: {result.returncode}")
    
    input("\nPress Enter to continue...")


# =============================================================================
# VM Deployment Functions
# =============================================================================

def deploy_vm_from_template():
    """Deploy a VM from a template."""
    display_template_menu()
    
    choice = get_input("Select template").upper()
    
    if choice == 'B':
        return
    
    if choice not in VM_TEMPLATES:
        print_error("Invalid template selection.")
        input("\nPress Enter to continue...")
        return
    
    template = VM_TEMPLATES[choice]
    
    print()
    print(f"Selected Template: {Colors.GREEN}{template['name']}{Colors.ENDC}")
    print(f"Template Name:     {template['template']}")
    print()
    
    # Get VM details
    vm_name = get_input("Enter VM Name (e.g., splunk-prod-01)")
    if not vm_name:
        print_error("VM name is required.")
        return
    
    # Select size
    print("\nAvailable Sizes:")
    for size, specs in VM_SIZES.items():
        print(f"  • {size}: {specs['cpu']} vCPU, {specs['memory_gb']} GB RAM, {specs['disk_gb']} GB Disk")
    
    vm_size = get_input("Enter Size", "Medium")
    if vm_size not in VM_SIZES:
        print_error("Invalid size selection.")
        return
    
    # Get network configuration
    ip_address = get_input("Enter IP Address (e.g., 192.168.1.100)")
    netmask = get_input("Enter Subnet Mask", "255.255.255.0")
    gateway = get_input("Enter Gateway", "192.168.1.1")
    
    # Get additional configuration
    tag_name = get_input("Enter Tag Name (e.g., Production-App)")
    
    # Summary
    size_specs = VM_SIZES[vm_size]
    print()
    print_header("VM Deployment Summary")
    print(f"  VM Name:    {vm_name}")
    print(f"  Template:   {template['name']}")
    print(f"  Size:       {vm_size} ({size_specs['cpu']} vCPU, {size_specs['memory_gb']} GB RAM)")
    print(f"  IP Address: {ip_address}")
    print(f"  Tag:        {tag_name}")
    print()
    
    if not confirm_action("Deploy this VM?"):
        print_warning("VM deployment cancelled.")
        return
    
    config = load_config()
    
    ps_command = f"""
    $cred = Get-Credential -Message "Enter vCenter Administrator Credentials"
    
    Connect-VIServer -Server '{config['vcenter']['server']}' -Credential $cred
    
    # Get the template
    $template = Get-Template -Name '{template['template']}' -ErrorAction Stop
    
    # Get the cluster
    $cluster = Get-Cluster -Name '{config['cluster']['name']}' -ErrorAction Stop
    
    # Get datastore (vSAN or first available)
    $datastore = Get-Datastore -Location $cluster | Where-Object {{ $_.Type -eq 'vsan' }} | Select-Object -First 1
    if (-not $datastore) {{
        $datastore = Get-Datastore -Location $cluster | Select-Object -First 1
    }}
    
    # Get port group for VM network
    $portGroup = Get-VDPortgroup -Name 'PG-VMTraffic' -ErrorAction SilentlyContinue
    if (-not $portGroup) {{
        $portGroup = Get-VirtualPortGroup | Select-Object -First 1
    }}
    
    # Create VM from template
    Write-Host "Creating VM from template..."
    $vm = New-VM -Name '{vm_name}' `
        -Template $template `
        -ResourcePool $cluster `
        -Datastore $datastore `
        -ErrorAction Stop
    
    # Configure VM resources
    Write-Host "Configuring VM resources..."
    Set-VM -VM $vm `
        -NumCpu {size_specs['cpu']} `
        -MemoryGB {size_specs['memory_gb']} `
        -Confirm:$false
    
    # Configure network adapter
    $adapter = Get-NetworkAdapter -VM $vm
    Set-NetworkAdapter -NetworkAdapter $adapter -Portgroup $portGroup -Confirm:$false
    
    # Tag the VM
    $tag = Get-Tag -Name '{tag_name}' -ErrorAction SilentlyContinue
    if ($tag) {{
        New-TagAssignment -Tag $tag -Entity $vm
    }}
    
    Write-Host "VM '{vm_name}' created successfully!" -ForegroundColor Green
    
    # Optionally power on
    $powerOn = Read-Host "Power on the VM? (y/n)"
    if ($powerOn -eq 'y') {{
        Start-VM -VM $vm -Confirm:$false
        Write-Host "VM powered on." -ForegroundColor Green
    }}
    
    Disconnect-VIServer -Server * -Force -Confirm:$false
    """
    
    result = run_powershell_command(ps_command)
    
    if result.returncode == 0:
        print_success(f"VM '{vm_name}' deployed from template!")
    else:
        print_error(f"VM deployment failed with exit code: {result.returncode}")
    
    input("\nPress Enter to continue...")


def deploy_standard_vm():
    """Deploy a standard virtual machine."""
    print_header("Deploy Standard Virtual Machine")
    
    # Get VM name
    vm_name = get_input("Enter VM Name (e.g., rhel-web-01)")
    if not vm_name:
        print_error("VM name is required.")
        return
    
    # Select OS type
    print("\nAvailable OS Types:")
    for key, os_type in OS_TYPES.items():
        print(f"  {key}. {os_type['name']:10} - {os_type['description']}")
    
    os_choice = get_input("Select OS Type", "1")
    if os_choice not in OS_TYPES:
        print_error("Invalid OS type selection.")
        return
    
    os_type = OS_TYPES[os_choice]
    
    # Select size
    print("\nAvailable Sizes:")
    for size, specs in VM_SIZES.items():
        print(f"  • {size}: {specs['cpu']} vCPU, {specs['memory_gb']} GB RAM, {specs['disk_gb']} GB Disk")
    
    vm_size = get_input("Enter Size", "Small")
    if vm_size not in VM_SIZES:
        print_error("Invalid size selection.")
        return
    
    # Get network configuration
    ip_address = get_input("Enter IP Address (e.g., 192.168.1.100)")
    
    # Get tag
    tag_name = get_input("Enter Tag Name (e.g., WebApp-Linux)")
    
    # Summary
    size_specs = VM_SIZES[vm_size]
    print()
    print_header("VM Deployment Summary")
    print(f"  VM Name:    {vm_name}")
    print(f"  OS Type:    {os_type['name']} ({os_type['description']})")
    print(f"  Size:       {vm_size}")
    print(f"  vCPU:       {size_specs['cpu']}")
    print(f"  Memory:     {size_specs['memory_gb']} GB")
    print(f"  Disk:       {size_specs['disk_gb']} GB")
    print(f"  IP Address: {ip_address}")
    print(f"  Tag:        {tag_name}")
    print()
    
    if not confirm_action("Create this VM?"):
        print_warning("VM creation cancelled.")
        return
    
    config = load_config()
    
    ps_command = f"""
    $cred = Get-Credential -Message "Enter vCenter Administrator Credentials"
    
    Connect-VIServer -Server '{config['vcenter']['server']}' -Credential $cred
    
    # Get the cluster
    $cluster = Get-Cluster -Name '{config['cluster']['name']}' -ErrorAction Stop
    
    # Get datastore
    $datastore = Get-Datastore -Location $cluster | Where-Object {{ $_.Type -eq 'vsan' }} | Select-Object -First 1
    if (-not $datastore) {{
        $datastore = Get-Datastore -Location $cluster | Sort-Object FreeSpaceGB -Descending | Select-Object -First 1
    }}
    
    # Get port group for VM network
    $portGroup = Get-VDPortgroup -Name 'PG-VMTraffic' -ErrorAction SilentlyContinue
    if (-not $portGroup) {{
        $portGroup = Get-VirtualPortGroup | Where-Object {{ $_.Name -like '*VM*' }} | Select-Object -First 1
    }}
    
    # Create new VM
    Write-Host "Creating VM '{vm_name}'..."
    $vm = New-VM -Name '{vm_name}' `
        -ResourcePool $cluster `
        -Datastore $datastore `
        -NumCpu {size_specs['cpu']} `
        -MemoryGB {size_specs['memory_gb']} `
        -DiskGB {size_specs['disk_gb']} `
        -DiskStorageFormat Thin `
        -GuestId '{os_type['guest_id']}' `
        -NetworkName $portGroup.Name `
        -ErrorAction Stop
    
    Write-Host "VM created successfully!" -ForegroundColor Green
    
    # Tag the VM
    $tag = Get-Tag -Name '{tag_name}' -ErrorAction SilentlyContinue
    if ($tag) {{
        New-TagAssignment -Tag $tag -Entity $vm
        Write-Host "Tag assigned: {tag_name}" -ForegroundColor Green
    }} else {{
        Write-Host "Note: Tag '{tag_name}' not found, skipping tag assignment" -ForegroundColor Yellow
    }}
    
    Write-Host ""
    Write-Host "VM Summary:" -ForegroundColor Cyan
    $vm | Select-Object Name, NumCpu, MemoryGB, @{{N='DiskGB';E={{($_ | Get-HardDisk | Measure-Object -Property CapacityGB -Sum).Sum}}}}, PowerState | Format-Table
    
    # Optionally power on
    $powerOn = Read-Host "Power on the VM? (y/n)"
    if ($powerOn -eq 'y') {{
        Start-VM -VM $vm -Confirm:$false
        Write-Host "VM powered on." -ForegroundColor Green
    }}
    
    Disconnect-VIServer -Server * -Force -Confirm:$false
    """
    
    result = run_powershell_command(ps_command)
    
    if result.returncode == 0:
        print_success(f"Standard VM '{vm_name}' created successfully!")
    else:
        print_error(f"VM creation failed with exit code: {result.returncode}")
    
    input("\nPress Enter to continue...")


# =============================================================================
# Status and Configuration Management
# =============================================================================

def show_status():
    """Show current infrastructure status."""
    print_header("Infrastructure Status")
    
    config = load_config()
    
    ps_command = f"""
    $config = Get-Content '{CONFIG_FILE}' -Raw | ConvertFrom-Json
    $cred = Get-Credential -Message "Enter vCenter Administrator Credentials"
    
    try {{
        Connect-VIServer -Server $config.vcenter.server -Credential $cred -ErrorAction Stop
        
        Write-Host ""
        Write-Host "=== vCenter Connection ===" -ForegroundColor Cyan
        Write-Host "Server:  $($global:DefaultVIServer.Name)"
        Write-Host "Version: $($global:DefaultVIServer.Version)"
        
        Write-Host ""
        Write-Host "=== Datacenter ===" -ForegroundColor Cyan
        Get-Datacenter | Format-Table Name, @{{N='Clusters';E={{($_ | Get-Cluster).Count}}}}, @{{N='Hosts';E={{($_ | Get-VMHost).Count}}}}, @{{N='VMs';E={{($_ | Get-VM).Count}}}}
        
        Write-Host "=== Clusters ===" -ForegroundColor Cyan
        Get-Cluster | Format-Table Name, HAEnabled, DrsEnabled, @{{N='Hosts';E={{($_ | Get-VMHost).Count}}}}, @{{N='VMs';E={{($_ | Get-VM).Count}}}}
        
        Write-Host "=== ESXi Hosts ===" -ForegroundColor Cyan
        Get-VMHost | Format-Table Name, ConnectionState, PowerState, Version, @{{N='CPU(GHz)';E={{[math]::Round($_.CpuTotalMhz/1000,1)}}}}, @{{N='Mem(GB)';E={{[math]::Round($_.MemoryTotalGB,0)}}}}
        
        Write-Host "=== Datastores ===" -ForegroundColor Cyan
        Get-Datastore | Format-Table Name, Type, @{{N='Capacity(GB)';E={{[math]::Round($_.CapacityGB,0)}}}}, @{{N='Free(GB)';E={{[math]::Round($_.FreeSpaceGB,0)}}}}, @{{N='Used%';E={{[math]::Round((1-($_.FreeSpaceGB/$_.CapacityGB))*100,0)}}}}
        
        Write-Host "=== VDS ===" -ForegroundColor Cyan
        Get-VDSwitch | Format-Table Name, Version, Mtu, @{{N='Hosts';E={{($_ | Get-VMHost).Count}}}}, @{{N='PortGroups';E={{($_ | Get-VDPortgroup).Count}}}}
        
        Disconnect-VIServer -Server * -Force -Confirm:$false
    }}
    catch {{
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }}
    """
    
    result = run_powershell_command(ps_command)
    
    input("\nPress Enter to continue...")


def view_configuration():
    """View current configuration."""
    print_header("Current Configuration")
    
    config = load_config()
    
    print(json.dumps(config, indent=2))
    
    input("\nPress Enter to continue...")


def reload_configuration():
    """Reload configuration from file."""
    print_info("Reloading configuration...")
    config = load_config()
    print_success("Configuration reloaded successfully!")
    print(f"  Environment: {config['environment']['name']}")
    print(f"  vCenter:     {config['vcenter']['server']}")
    input("\nPress Enter to continue...")


# =============================================================================
# Menu Handlers
# =============================================================================

def handle_configure_menu():
    """Handle the configure infrastructure submenu."""
    while True:
        display_configure_menu()
        choice = get_input("Select option").upper()
        
        if choice == '1':
            configure_vsan()
        elif choice == '2':
            configure_vds()
        elif choice == '3':
            configure_vmotion()
        elif choice == '4':
            configure_services()
        elif choice == '5':
            configure_security()
        elif choice == '6':
            configure_all()
        elif choice == 'B':
            break
        else:
            print_error("Invalid option. Please try again.")
            input("\nPress Enter to continue...")


def handle_vm_menu():
    """Handle the VM deployment submenu."""
    while True:
        display_vm_menu()
        choice = get_input("Select option").upper()
        
        if choice == '1':
            deploy_vm_from_template()
        elif choice == '2':
            deploy_standard_vm()
        elif choice == 'B':
            break
        else:
            print_error("Invalid option. Please try again.")
            input("\nPress Enter to continue...")


def handle_config_management_menu():
    """Handle the configuration management submenu."""
    while True:
        display_config_management_menu()
        choice = get_input("Select option").upper()
        
        if choice == '1':
            view_configuration()
        elif choice == '7':
            reload_configuration()
        elif choice == 'B':
            break
        elif choice in ('2', '3', '4', '5', '6'):
            print_warning("Configuration editing is not yet implemented.")
            print_info("Please edit config.json directly for now.")
            input("\nPress Enter to continue...")
        else:
            print_error("Invalid option. Please try again.")
            input("\nPress Enter to continue...")


def main():
    """Main entry point."""
    # Check if running on Windows
    if os.name != 'nt':
        Colors.disable()
        print_warning("This tool is designed for Windows with PowerShell.")
        print_warning("Some features may not work correctly on other platforms.")
    
    # Check for config file
    if not CONFIG_FILE.exists():
        print_error(f"Configuration file not found: {CONFIG_FILE}")
        print_info("Please create a config.json file before running this tool.")
        sys.exit(1)
    
    # Main menu loop
    while True:
        try:
            display_main_menu()
            choice = get_input("Select option").upper()
            
            if choice == '1':
                deploy_vcenter()
            elif choice == '2':
                deploy_infrastructure()
            elif choice == '3':
                deploy_datacenter()
            elif choice == '4':
                deploy_cluster()
            elif choice == '5':
                handle_configure_menu()
            elif choice == '6':
                handle_vm_menu()
            elif choice == 'C':
                handle_config_management_menu()
            elif choice == 'S':
                show_status()
            elif choice == 'Q':
                print()
                print_info("Thank you for using ECST VMware Automation Tool!")
                print()
                sys.exit(0)
            else:
                print_error("Invalid option. Please try again.")
                input("\nPress Enter to continue...")
                
        except KeyboardInterrupt:
            print()
            print_warning("Operation cancelled by user.")
            if confirm_action("Do you want to exit?"):
                sys.exit(0)


if __name__ == "__main__":
    main()
