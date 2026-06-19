# Tier1_Operations.ps1
# Purpose: Manage member servers, applications, and infrastructure services

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Create", "Modify", "Delete", "Report")]
    [string]$Action,
    
    [string]$TargetOU,
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

# Define Tier 1 OUs and groups
$Tier1ServersOU = "OU=Servers,DC=yourdomain,DC=com"
$Tier1AdminGroup = "Server Admins"
$Tier1ServiceGroup = "Service Accounts"

# Function: Create Tier 1 objects
function Create-Tier1 {
    Write-Log "Creating Tier 1 objects" "INFO"
    
    # Create server OUs
    $ServerTypeOUs = @("Application Servers", "Database Servers", "File Servers", "Web Servers")
    foreach ($OU in $ServerTypeOUs) {
        $OUPath = "OU=$OU,$Tier1ServersOU"
        try {
            if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$OU'")) {
                New-ADOrganizationalUnit -Name $OU -Path $Tier1ServersOU -ProtectedFromAccidentalDeletion $true
                Write-Log "Created server OU: $OU" "INFO"
            }
        } catch {
            Write-Log "Error creating server OU $OU : $_" "ERROR"
        }
    }
    
    # Create computer account
    if ($TargetComputer) {
        try {
            # Check if computer already exists
            if (!(Get-ADComputer -Identity $TargetComputer -ErrorAction SilentlyContinue)) {
                New-ADComputer -Name $TargetComputer -Path $Tier1ServersOU `
                    -Description "Tier 1 Server - Managed by automation" -Enabled $true
                Write-Log "Created computer account: $TargetComputer" "INFO"
            } else {
                Write-Log "Computer $TargetComputer already exists" "WARNING"
            }
        } catch {
            Write-Log "Error creating computer: $_" "ERROR"
        }
    }
    
    # Create service account group
    if ($GroupName) {
        try {
            if (!(Get-ADGroup -Identity $Tier1ServiceGroup -ErrorAction SilentlyContinue)) {
                New-ADGroup -Name $Tier1ServiceGroup -GroupScope Global -GroupCategory Security `
                    -Path $Tier1ServersOU -Description "Tier 1 Service Accounts"
                Write-Log "Created service account group: $Tier1ServiceGroup" "INFO"
            }
            
            # Add member to service group
            if ($TargetComputer) {
                Add-ADGroupMember -Identity $Tier1ServiceGroup -Members $TargetComputer
                Write-Log "Added $TargetComputer to service group" "INFO"
            }
        } catch {
            Write-Log "Error creating service group: $_" "ERROR"
        }
    }
}

# Function: Modify Tier 1 objects
function Modify-Tier1 {
    Write-Log "Modifying Tier 1 objects" "INFO"
    
    if ($TargetComputer) {
        try {
            # Move computer to appropriate OU
            if ($TargetOU) {
                Move-ADObject -Identity "CN=$TargetComputer,$Tier1ServersOU" -TargetPath $TargetOU
                Write-Log "Moved $TargetComputer to OU: $TargetOU" "INFO"
            }
            
            # Modify computer properties
            Set-ADComputer -Identity $TargetComputer -Description "Tier 1 Server - Modified $(Get-Date)" -Enabled $true
            
            # Add computer to server admin group
            Add-ADGroupMember -Identity $Tier1AdminGroup -Members $TargetComputer
            
            Write-Log "Modified server: $TargetComputer" "INFO"
        } catch {
            Write-Log "Error modifying server: $_" "ERROR"
        }
    }
}

# Function: Delete Tier 1 objects
function Delete-Tier1 {
    Write-Log "Deleting Tier 1 objects" "INFO"
    
    if ($TargetComputer) {
        try {
            # Check if computer is a domain controller
            $IsDC = Get-ADComputer -Identity $TargetComputer -Properties OperatingSystem |
                Where-Object {$_.OperatingSystem -like "*Server*" -and $_.DistinguishedName -match "Domain Controllers"}
            if ($IsDC) {
                Write-Log "Cannot delete $TargetComputer - is a Domain Controller" "ERROR"
                return
            }
            
            # Remove from groups first
            Get-ADGroup -Filter {Members -eq $TargetComputer} | ForEach-Object {
                Remove-ADGroupMember -Identity $_.Name -Members $TargetComputer -Confirm:$false
                Write-Log "Removed $TargetComputer from group: $($_.Name)" "INFO"
            }
            
            # Disable computer account
            Disable-ADAccount -Identity $TargetComputer
            Write-Log "Disabled computer account: $TargetComputer" "INFO"
            
            # Remove computer account after 30 days (soft delete)
            # Remove-ADComputer -Identity $TargetComputer -Confirm:$false
            # Write-Log "Deleted computer account: $TargetComputer" "INFO"
        } catch {
            Write-Log "Error deleting server: $_" "ERROR"
        }
    }
}

# Function: Generate Tier 1 report
function Report-Tier1 {
    Write-Log "Generating Tier 1 report" "INFO"
    
    $Report = @()
    $Report += "Tier 1 - Server Infrastructure Report"
    $Report += "Generated: $(Get-Date)"
    $Report += "=" * 50
    
    # Get all servers
    $Servers = Get-ADComputer -Filter {OperatingSystem -like "*Server*"} `
        -Properties OperatingSystem, LastLogonDate, Description |
        Select-Object Name, OperatingSystem, LastLogonDate, Description
    $Report += "Servers:"
    $Report += $Servers | Format-Table -AutoSize | Out-String
    
    # Get server groups
    $Groups = Get-ADGroup -Filter {Name -like "*Server*"} | Select-Object Name, GroupCategory, GroupScope
    $Report += "Server Groups:"
    $Report += $Groups | Format-Table -AutoSize | Out-String
    
    # Get members of server admin group
    $Admins = Get-ADGroupMember -Identity $Tier1AdminGroup
    $Report += "Tier 1 Administrators:"
    $Report += $Admins | Format-Table -AutoSize | Out-String
    
    # Save report
    $ReportPath = "C:\AD_Automation_Logs\Tier1_Report_$(Get-Date -Format 'yyyyMMdd').txt"
    $Report | Out-File -FilePath $ReportPath
    Write-Log "Report saved to: $ReportPath" "INFO"
}

# Execute based on action
switch ($Action) {
    "Create" { Create-Tier1 }
    "Modify" { Modify-Tier1 }
    "Delete" { Delete-Tier1 }
    "Report" { Report-Tier1 }
}
