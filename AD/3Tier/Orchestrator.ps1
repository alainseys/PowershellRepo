# Main_AD_3Tier_Management.ps1
# Purpose: Orchestrates 3-tier AD administration automation
# Author: System Administrator
# Version: 1.0

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Tier0", "Tier1", "Tier2")]
    [string]$Tier,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("Create", "Modify", "Delete", "Report")]
    [string]$Action,
    
    [string]$TargetOU,
    [string]$TargetUser,
    [string]$TargetComputer,
    [string]$GroupName
)

# Import required modules
Import-Module ActiveDirectory
Import-Module GroupPolicy

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Logging configuration
$LogPath = "C:\AD_Automation_Logs"
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force }
$LogFile = "$LogPath\AD_3Tier_$Tier-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Function: Write to log
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp [$Level] $Message" | Out-File -FilePath $LogFile -Append
    Write-Host "$Timestamp [$Level] $Message" -ForegroundColor $($Level -eq "ERROR" ? "Red" : "Green")
}

# Function: Validate admin credentials
function Test-AdminCredentials {
    try {
        $CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $Principal = New-Object System.Security.Principal.WindowsPrincipal($CurrentUser)
        if ($Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Log "Admin credentials validated" "INFO"
            return $true
        } else {
            Write-Log "Not running as administrator" "ERROR"
            return $false
        }
    } catch {
        Write-Log "Error validating admin credentials: $_" "ERROR"
        return $false
    }
}

# Function: Execute based on tier
function Invoke-TierAction {
    param($Tier, $Action)
    
    Write-Log "Starting $Action operation for $Tier" "INFO"
    
    switch ($Tier) {
        "Tier0" { 
            Write-Log "Tier 0 - Domain Controller Operations" "INFO"
            & ".\Tier0_Operations.ps1" -Action $Action -TargetOU $TargetOU -TargetUser $TargetUser -LogFile $LogFile
        }
        "Tier1" { 
            Write-Log "Tier 1 - Server Management" "INFO"
            & ".\Tier1_Operations.ps1" -Action $Action -TargetOU $TargetOU -TargetComputer $TargetComputer -GroupName $GroupName -LogFile $LogFile
        }
        "Tier2" { 
            Write-Log "Tier 2 - End User & Workstation Management" "INFO"
            & ".\Tier2_Operations.ps1" -Action $Action -TargetOU $TargetOU -TargetUser $TargetUser -TargetComputer $TargetComputer -GroupName $GroupName -LogFile $LogFile
        }
    }
}

# Main execution
Write-Log "=== Starting AD 3-Tier Management ===" "INFO"
Write-Log "Tier: $Tier, Action: $Action" "INFO"

# Validate credentials
if (!(Test-AdminCredentials)) {
    Write-Log "Administrator privileges required" "ERROR"
    exit 1
}

# Verify AD connectivity
try {
    Get-ADDomain | Out-Null
    Write-Log "Active Directory connectivity verified" "INFO"
} catch {
    Write-Log "Cannot connect to AD: $_" "ERROR"
    exit 1
}

# Execute appropriate function
Invoke-TierAction -Tier $Tier -Action $Action

Write-Log "=== Completed AD 3-Tier Management ===" "INFO"
Write-Log "Log file: $LogFile"
