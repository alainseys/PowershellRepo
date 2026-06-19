# Tier2_Operations.ps1
# Purpose: Manage end users, workstations, and standard groups

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Create", "Modify", "Delete", "Report")]
    [string]$Action,
    
    [string]$TargetOU,
    [string]$TargetUser,
    [string]$TargetComputer,
    [string]$GroupName,
    [string]$LogFile
)

# Import modules
Import-Module ActiveDirectory

# Global logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp [$Level] $Message" | Out-File -FilePath $LogFile -Append
    Write-Host "$Timestamp [$Level] $Message"
}

# Define Tier 2 OUs and groups
$Tier2UsersOU = "OU=Users,DC=yourdomain,DC=com"
$Tier2ComputersOU = "OU=Workstations,DC=yourdomain,DC=com"
$Tier2Groups = @("Domain Users", "Tier2 Support")

# Function: Create Tier 2 objects
function Create-Tier2 {
    Write-Log "Creating Tier 2 objects" "INFO"
    
    # Create department-based user OUs
    $DepartmentOUs = @("Finance", "HR", "IT", "Sales", "Marketing", "Operations")
    foreach ($Dept in $DepartmentOUs) {
        $OUPath = "OU=$Dept,$Tier2UsersOU"
        try {
            if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$Dept'")) {
                New-ADOrganizationalUnit -Name $Dept -Path $Tier2UsersOU
                Write-Log "Created department OU: $Dept" "INFO"
            }
        } catch {
            Write-Log "Error creating department OU $Dept : $_" "ERROR"
        }
    }
    
    # Create user
    if ($TargetUser) {
        try {
            # Get department from OU or prompt
            $Department = if ($TargetOU) { (Get-ADOrganizationalUnit -Identity $TargetOU).Name } else { "Users" }
            $UserPath = "OU=$Department,$Tier2UsersOU"
            
            $UserPrincipalName = "$TargetUser@yourdomain.com"
            $SecurePassword = Read-Host "Enter password for $TargetUser" -AsSecureString
            
            New-ADUser -Name $TargetUser -UserPrincipalName $UserPrincipalName -SamAccountName $TargetUser `
                -Enabled $true -AccountPassword $SecurePassword -Path $UserPath `
                -Department $Department -Title "Employee" -PassThru
            
            # Set user properties
            Set-ADUser -Identity $TargetUser -ChangePasswordAtLogon $true -PasswordNeverExpires $false
            
            # Add to appropriate groups
            Add-ADGroupMember -Identity "Domain Users" -Members $TargetUser
            
            Write-Log "Created user: $TargetUser in department: $Department" "INFO"
        } catch {
            Write-Log "Error creating user: $_" "ERROR"
        }
    }
    
    # Create workstation
    if ($TargetComputer) {
        try {
            if (!(Get-ADComputer -Identity $TargetComputer -ErrorAction SilentlyContinue)) {
                $WorkstationPath = "OU=Workstations,$Tier2ComputersOU"
                New-ADComputer -Name $TargetComputer -Path $WorkstationPath `
                    -Description "Tier 2 Workstation - $(Get-Date)" -Enabled $true
                Write-Log "Created workstation: $TargetComputer" "INFO"
            } else {
                Write-Log "Computer $TargetComputer already exists" "WARNING"
            }
        } catch {
            Write-Log "Error creating workstation: $_" "ERROR"
        }
    }
}

# Function: Modify Tier 2 objects
function Modify-Tier2 {
    Write-Log "Modifying Tier 2 objects" "INFO"
    
    # Modify user
    if ($TargetUser) {
        try {
            # Update user properties
            $UserProperties = @{
                Title = "Employee"
                Department = (Get-ADOrganizationalUnit -Identity $TargetOU).Name
                Description = "Tier 2 User - Modified $(Get-Date)"
            }
            
            Set-ADUser -Identity $TargetUser @UserProperties
            
            # Reset password if requested
            $ResetPassword = Read-Host "Reset password for $TargetUser? (y/n)"
            if ($ResetPassword -eq "y") {
                $SecurePassword = Read-Host "Enter new password" -AsSecureString
                Set-ADAccountPassword -Identity $TargetUser -NewPassword $SecurePassword -Reset
                Set-ADUser -Identity $TargetUser -ChangePasswordAtLogon $true
                Write-Log "Reset password for user: $TargetUser" "INFO"
            }
            
            # Enable/disable account
            $DisableUser = Read-Host "Disable user account? (y/n)"
            if ($DisableUser -eq "y") {
                Disable-ADAccount -Identity $TargetUser
                Write-Log "Disabled user account: $TargetUser" "INFO"
            }
            
            Write-Log "Modified user: $TargetUser" "INFO"
        } catch {
            Write-Log "Error modifying user: $_" "ERROR"
        }
    }
    
    # Modify computer
    if ($TargetComputer) {
        try {
            # Move computer to different OU
            if ($TargetOU) {
                Move-ADObject -Identity "CN=$TargetComputer,$Tier2ComputersOU" -TargetPath $TargetOU
                Write-Log "Moved computer $TargetComputer to OU: $TargetOU" "INFO"
            }
            
            # Update computer description
            Set-ADComputer -Identity $TargetComputer -Description "Tier 2 Workstation - Modified $(Get-Date)"
            Write-Log "Modified workstation: $TargetComputer" "INFO"
        } catch {
            Write-Log "Error modifying computer: $_" "ERROR"
        }
    }
}

# Function: Delete Tier 2 objects
function Delete-Tier2 {
    Write-Log "Deleting Tier 2 objects" "INFO"
    
    if ($TargetUser) {
        try {
            # Disable user account first
            Disable-ADAccount -Identity $TargetUser
            Write-Log "Disabled user account: $TargetUser" "INFO"
            
            # Remove from all groups
            Get-ADGroup -Filter {Members -eq $TargetUser} | ForEach-Object {
                Remove-ADGroupMember -Identity $_.Name -Members $TargetUser -Confirm:$false
                Write-Log "Removed user from group: $($_.Name)" "INFO"
            }
            
            # Move to disabled users OU
            $DisabledOU = "OU=Disabled Users,$Tier2UsersOU"
            if (!(Get-ADOrganizationalUnit -Identity $DisabledOU -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name "Disabled Users" -Path $Tier2UsersOU
            }
            Move-ADObject -Identity (Get-ADUser $TargetUser).DistinguishedName -TargetPath $DisabledOU
            Write-Log "Moved user to Disabled Users OU" "INFO"
            
            # Delete after 30 days (soft delete)
            $Confirm = Read-Host "Delete user permanently? (y/n)"
            if ($Confirm -eq "y") {
                Remove-ADUser -Identity $TargetUser -Confirm:$false
                Write-Log "Permanently deleted user: $TargetUser" "INFO"
            }
        } catch {
            Write-Log "Error deleting user: $_" "ERROR"
        }
    }
    
    if ($TargetComputer) {
        try {
            # Disable computer account
            Disable-ADAccount -Identity $TargetComputer
            Write-Log "Disabled computer account: $TargetComputer" "INFO"
            
            # Move to disabled computers OU
            $DisabledCompOU = "OU=Disabled Workstations,$Tier2ComputersOU"
            if (!(Get-ADOrganizationalUnit -Identity $DisabledCompOU -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name "Disabled Workstations" -Path $Tier2ComputersOU
            }
            Move-ADObject -Identity (Get-ADComputer $TargetComputer).DistinguishedName -TargetPath $DisabledCompOU
            Write-Log "Moved computer to Disabled Workstations OU" "INFO"
            
            # Delete after 30 days
            # Remove-ADComputer -Identity $TargetComputer -Confirm:$false
        } catch {
            Write-Log "Error deleting computer: $_" "ERROR"
        }
    }
}

# Function: Generate Tier 2 report
function Report-Tier2 {
    Write-Log "Generating Tier 2 report" "INFO"
    
    $Report = @()
    $Report += "Tier 2 - End User & Workstation Report"
    $Report += "Generated: $(Get-Date)"
    $Report += "=" * 50
    
    # Get all users
    $Users = Get-ADUser -Filter * -Properties Department, Title, Enabled, LastLogonDate |
        Select-Object Name, SamAccountName, Department, Title, Enabled, LastLogonDate
    $Report += "Users:"
    $Report += "Total Users: $($Users.Count)"
    $Report += "Enabled Users: $(($Users | Where-Object {$_.Enabled}).Count)"
    $Report += "Disabled Users: $(($Users | Where-Object {!$_.Enabled}).Count)"
    $Report += $Users | Format-Table -AutoSize | Out-String
    
    # Get computers
    $Computers = Get-ADComputer -Filter {OperatingSystem -like "*Windows*"} -Properties LastLogonDate
    $Report += "Workstations:"
    $Report += "Total Workstations: $($Computers.Count)"
    $Report += "Active (last 30 days): $(($Computers | Where-Object {$_.LastLogonDate -gt (Get-Date).AddDays(-30)}).Count)"
    $Report += $Computers | Select-Object Name, LastLogonDate | Format-Table -AutoSize | Out-String
    
    # Get recently created/modified users
    $RecentUsers = Get-ADUser -Filter {WhenCreated -gt (Get-Date).AddDays(-30)} -Properties WhenCreated, Department
    $Report += "Recently Created Users (Last 30 days):"
    $Report += $RecentUsers | Format-Table -AutoSize | Out-String
    
    # Save report
    $ReportPath = "C:\AD_Automation_Logs\Tier2_Report_$(Get-Date -Format 'yyyyMMdd').txt"
    $Report | Out-File -FilePath $ReportPath
    Write-Log "Report saved to: $ReportPath" "INFO"
}

# Execute based on action
switch ($Action) {
    "Create" { Create-Tier2 }
    "Modify" { Modify-Tier2 }
    "Delete" { Delete-Tier2 }
    "Report" { Report-Tier2 }
}
