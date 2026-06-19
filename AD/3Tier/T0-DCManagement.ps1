# Tier0_Operations.ps1
# Purpose: Manage Domain Controllers, Schema, and Forest-level operations

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Create", "Modify", "Delete", "Report")]
    [string]$Action,
    
    [string]$TargetOU,
    [string]$TargetUser,
    [string]$LogFile
)

# Global logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp [$Level] $Message" | Out-File -FilePath $LogFile -Append
    Write-Host "$Timestamp [$Level] $Message"
}

# Import Active Directory module
Import-Module ActiveDirectory

# Define Tier 0 OUs and groups
$Tier0OUs = @("Domain Controllers", "Domain Admins", "Schema Admins", "Enterprise Admins")
$Tier0AdminGroup = "Domain Admins"
$Tier0DCOU = "OU=Domain Controllers,DC=yourdomain,DC=com"

# Function: Create Tier 0 objects
function Create-Tier0 {
    Write-Log "Creating Tier 0 objects" "INFO"
    
    # Create necessary OUs if they don't exist
    foreach ($OU in $Tier0OUs) {
        $OUPath = "OU=$OU,DC=yourdomain,DC=com"
        try {
            if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$OU'")) {
                New-ADOrganizationalUnit -Name $OU -Path "DC=yourdomain,DC=com" -ProtectedFromAccidentalDeletion $true
                Write-Log "Created OU: $OU" "INFO"
            }
        } catch {
            Write-Log "Error creating OU $OU : $_" "ERROR"
        }
    }
    
    # Create a sample Tier 0 administrator
    if ($TargetUser) {
        try {
            $UserPrincipalName = "$TargetUser@yourdomain.com"
            $SecurePassword = Read-Host "Enter password for $TargetUser" -AsSecureString
            New-ADUser -Name $TargetUser -UserPrincipalName $UserPrincipalName -SamAccountName $TargetUser `
                -Enabled $true -AccountPassword $SecurePassword -Path $Tier0DCOU -PassThru
            Add-ADGroupMember -Identity $Tier0AdminGroup -Members $TargetUser
            Write-Log "Created Tier 0 user: $TargetUser" "INFO"
        } catch {
            Write-Log "Error creating Tier 0 user: $_" "ERROR"
        }
    }
}

# Function: Modify Tier 0 objects
function Modify-Tier0 {
    Write-Log "Modifying Tier 0 objects" "INFO"
    
    if ($TargetUser) {
        try {
            # Example: Force password change
            Set-ADUser -Identity $TargetUser -ChangePasswordAtLogon $true
            Write-Log "Tier 0 user $TargetUser will change password at next logon" "INFO"
            
            # Example: Update description
            Set-ADUser -Identity $TargetUser -Description "Tier 0 Administrator - Managed by automation"
            
            # Disable user if old
            if ($TargetUser -match "old_") {
                Disable-ADAccount -Identity $TargetUser
                Write-Log "Disabled Tier 0 user: $TargetUser" "INFO"
            }
        } catch {
            Write-Log "Error modifying Tier 0 user: $_" "ERROR"
        }
    }
}

# Function: Delete Tier 0 objects (with safety checks)
function Delete-Tier0 {
    Write-Log "Tier 0 deletion requires additional confirmation" "WARNING"
    Write-Host "WARNING: You are about to delete Tier 0 objects. This is critical!" -ForegroundColor Red
    $Confirm = Read-Host "Type 'CONFIRM' to proceed"
    
    if ($Confirm -ne "CONFIRM") {
        Write-Log "Deletion cancelled by user" "INFO"
        return
    }
    
    if ($TargetUser) {
        try {
            # Check if user is not the last DC admin
            $Admins = Get-ADGroupMember -Identity $Tier0AdminGroup | Where-Object {$_.ObjectClass -eq "user"}
            if ($Admins.Count -le 1) {
                Write-Log "Cannot delete last Tier 0 admin: $TargetUser" "ERROR"
                return
            }
            
            Remove-ADUser -Identity $TargetUser -Confirm:$false
            Write-Log "Deleted Tier 0 user: $TargetUser" "INFO"
        } catch {
            Write-Log "Error deleting Tier 0 user: $_" "ERROR"
        }
    }
}

# Function: Generate Tier 0 report
function Report-Tier0 {
    Write-Log "Generating Tier 0 report" "INFO"
    
    $Report = @()
    $Report += "Tier 0 - AD Infrastructure Report"
    $Report += "Generated: $(Get-Date)"
    $Report += "=" * 50
    
    # Get Domain Controllers
    $DCs = Get-ADDomainController -Filter * | Select-Object Name, Site, IPv4Address
    $Report += "Domain Controllers:"
    $Report += $DCs | Format-Table -AutoSize | Out-String
    
    # Get Tier 0 admins
    $Admins = Get-ADGroupMember -Identity $Tier0AdminGroup | Where-Object {$_.ObjectClass -eq "user"}
    $Report += "Tier 0 Administrators:"
    $Report += $Admins | Format-Table -AutoSize | Out-String
    
    # Check FSMO roles
    $FSMO = Get-ADDomain | Select-Object InfrastructureMaster, PDCEmulator, RIDMaster, SchemaMaster
    $Report += "FSMO Role Holders:"
    $Report += $FSMO | Format-List | Out-String
    
    # Save report
    $ReportPath = "C:\AD_Automation_Logs\Tier0_Report_$(Get-Date -Format 'yyyyMMdd').txt"
    $Report | Out-File -FilePath $ReportPath
    Write-Log "Report saved to: $ReportPath" "INFO"
}

# Execute based on action
switch ($Action) {
    "Create" { Create-Tier0 }
    "Modify" { Modify-Tier0 }
    "Delete" { Delete-Tier0 }
    "Report" { Report-Tier0 }
}
