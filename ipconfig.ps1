#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Detects current network, requests free IP from NetBox, registers it with hostname,
    applies correct static IP + gateway + DNS, and logs everything.
.NOTES
    - Fixed: Default gateway now comes from RangeMap (no more invalid .1 assumption)
    - PowerShell 5.1+ compatible
    - Bypasses SSL validation for internal NetBox/AWX
    - Full logging to C:\Temp\NetBox-IP-Config.log
    - DNS: 172.27.246.251, 172.27.247.251
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$NetBoxToken,

    [string]$NetBoxUrl = "https://ipam.vanmarcke.be",

    [string]$LogPath = "C:\Temp\NetBox-IP-Config.log"
)

# ==============================
# Initialize Logging
# ==============================
$LogDir = Split-Path $LogPath -Parent
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    $logLine | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Host $logLine
}

Log "=== NetBox Static IP Assignment Started ===" "INFO"
Log "Log file: $LogPath" "INFO"
Log "Hostname: $([System.Net.Dns]::GetHostName())" "INFO"

# === Bypass SSL Certificate Validation (PS 5.1) ===
if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type) {
    $certCallback = @"
        using System;
        using System.Net;
        using System.Net.Security;
        using System.Security.Cryptography.X509Certificates;
        public class ServerCertificateValidationCallback {
            public static void Ignore() {
                ServicePointManager.ServerCertificateValidationCallback += 
                    delegate(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors sslPolicyErrors) 
                    { return true; };
            }
        }
"@
    Add-Type $certCallback
    [ServerCertificateValidationCallback]::Ignore()
    Log "SSL certificate validation bypassed" "INFO"
}

# ==============================
# Network Range Mapping (WITH CORRECT GATEWAYS)
# ==============================
$RangeMap = @{
    "appserver"   = @{ 
        CIDR     = "172.27.246.0/23"
        RangeId  = 17
        URL      = "$NetBoxUrl/api/ipam/ip-ranges/17/"
        Gateway  = "172.27.247.254"
    }
    "itmgt"       = @{ 
        CIDR     = "172.27.254.0/23"
        RangeId  = 8
        URL      = "$NetBoxUrl/api/ipam/ip-ranges/8/"
        Gateway  = "172.27.255.254"
    }
    "kubernetes"  = @{ 
        CIDR     = "172.27.235.0/24"
        RangeId  = 32
        URL      = "$NetBoxUrl/api/ipam/ip-ranges/32/"
        Gateway  = "172.27.235.254"
    }
    "dmz"         = @{ 
        CIDR     = "172.16.31.0/24"
        RangeId  = 4
        URL      = "$NetBoxUrl/api/ipam/ip-ranges/4/"
        Gateway  = "172.16.31.254"
    }
    # Add more networks below if needed, example:
    # "storage"    = @{ CIDR = "172.27.240.0/24"; RangeId = 45; URL = "$NetBoxUrl/api/ipam/ip-ranges/45/"; Gateway = "172.27.240.254" }
}

# DNS Servers (same for all networks)
$DNSServers = @("172.27.246.251", "172.27.247.251")

# ==============================
# Helper: Test IP in CIDR
# ==============================
function Test-IPInCIDR {
    param([string]$ip, [string]$cidr)
    $parts = $cidr.Split('/')
    if ($parts.Count -ne 2) { return $false }
    $network = $parts[0]
    $maskBits = [int]$parts[1]

    $ipInt = 0; $ip.Split('.') | ForEach-Object { $ipInt = ($ipInt -shl 8) + [int]$_ }
    $netInt = 0; $network.Split('.') | ForEach-Object { $netInt = ($netInt -shl 8) + [int]$_ }

    $maskInt = if ($maskBits -eq 0) { 0 } else { -bnot ((1 -shl (32 - $maskBits)) - 1) -band 0xFFFFFFFF }

    return (($ipInt -band $maskInt) -eq ($netInt -band $maskInt))
}

# ==============================
# 1. Detect Active Adapter & Current IP
# ==============================
try {
    $adapter = Get-NetAdapter | Where-Object Status -eq "Up" | ForEach-Object {
        $ip = Get-NetIPAddress -InterfaceAlias $_.Name -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ip) { [PSCustomObject]@{ Adapter = $_; IP = $ip } }
    } | Where-Object { $_.IP.IPAddress -like "172.*" -or $_.IP.IPAddress -like "10.*" } | Select-Object -First 1

    if (-not $adapter) { throw "No active IPv4 adapter found in internal ranges." }

    $currentIP      = $adapter.IP.IPAddress
    $interfaceAlias = $adapter.Adapter.Name

    Log "Found adapter: $interfaceAlias" "INFO"
    Log "Current IP: $currentIP" "INFO"
}
catch {
    Log "Adapter detection failed: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ==============================
# 2. Detect Network from RangeMap
# ==============================
$detectedNetwork = $null
foreach ($name in $RangeMap.Keys) {
    if (Test-IPInCIDR -ip $currentIP -cidr $RangeMap[$name].CIDR) {
        $detectedNetwork = $name
        break
    }
}
if (-not $detectedNetwork) {
    Log "Current IP $currentIP does not match any known network range." "ERROR"
    exit 1
}

Log "Detected network: $detectedNetwork" "INFO"
$range = $RangeMap[$detectedNetwork]
$availableIpsUrl = "$($range.URL)available-ips/"

# ==============================
# 3. Get Available IP from NetBox
# ==============================
$headers = @{
    "Authorization" = "Token $NetBoxToken"
    "Accept"        = "application/json"
}

Log "Requesting available IP from NetBox range $($range.RangeId)..." "INFO"
try {
    $response = Invoke-RestMethod -Uri $availableIpsUrl -Method Get -Headers $headers -TimeoutSec 30
    if (-not $response -or $response.Count -eq 0) { throw "No available IPs in range." }
}
catch {
    Log "Failed to retrieve available IPs: $($_.Exception.Message)" "ERROR"
    exit 1
}

$ipEntry     = $response | Select-Object -First 1
$fullAddress = $ipEntry.address
$ipAddress   = $fullAddress.Split('/')[0]
Log "Selected IP: $ipAddress (Full: $fullAddress)" "INFO"

# ==============================
# 4. Register IP in NetBox
# ==============================
$hostname  = [System.Net.Dns]::GetHostName()
$dnsName   = "$hostname.vanmarcke.be".ToUpper()

$body = @{
    address     = $fullAddress
    status      = "active"
    dns_name    = $dnsName
    description = "Assigned via PowerShell script on $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
} | ConvertTo-Json

Log "Registering IP in NetBox as $dnsName ..." "INFO"
try {
    $register = Invoke-RestMethod `
        -Uri "$NetBoxUrl/api/ipam/ip-addresses/" `
        -Method Post `
        -Headers $headers `
        -Body $body `
        -ContentType "application/json" `
        -TimeoutSec 30

    Log "IP successfully registered in NetBox (ID: $($register.id))" "INFO"
}
catch {
    Log "Failed to register IP in NetBox: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ==============================
# 5. Apply Static IP + Correct Gateway + DNS
# ==============================
$subnet = $fullAddress.Split('/')[1]
$cidr   = [int]$subnet
$gateway = $range.Gateway

# Safety check: IP and gateway must be in same subnet
if (-not (Test-IPInCIDR -ip $ipAddress -cidr "$gateway/$cidr")) {
    Log "FATAL: Assigned IP $ipAddress is NOT in the same subnet as gateway $gateway !" "ERROR"
    exit 1
}

Log "Applying network configuration..." "INFO"
Log "  IP:       $ipAddress/$cidr" "INFO"
Log "  Gateway:  $gateway" "INFO"
Log "  DNS:      $($DNSServers -join ', ')" "INFO"

try {
    # Clean removal of old IPv4 config
    Get-NetIPAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    Get-NetRoute -InterfaceAlias $interfaceAlias -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | 
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

    # Apply new static config
    New-NetIPAddress -InterfaceAlias $interfaceAlias `
                     -IPAddress $ipAddress `
                     -PrefixLength $cidr `
                     -DefaultGateway $gateway -ErrorAction Stop | Out-Null

    Set-DnsClientServerAddress -InterfaceAlias $interfaceAlias `
                               -ServerAddresses $DNSServers -ErrorAction Stop

    Log "Static IP, Gateway and DNS applied successfully!" "INFO"
}
catch {
    Log "Failed to apply network configuration: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ==============================
# Final Summary
# ==============================
Log "=== CONFIGURATION COMPLETE ===" "INFO"
Log "Hostname     : $hostname" "INFO"
Log "DNS Name     : $dnsName" "INFO"
Log "IP Address   : $ipAddress/$cidr" "INFO"
Log "Gateway      : $gateway" "INFO"
Log "DNS Servers  : $($DNSServers -join ', ')" "INFO"
Log "Network      : $detectedNetwork" "INFO"
Log "Interface    : $interfaceAlias" "INFO"
Log "Log file     : $LogPath" "INFO"

Write-Host "`nSetup complete! Your server is now statically configured." -ForegroundColor Green
Write-Host "Full log: $LogPath" -ForegroundColor Cyan
