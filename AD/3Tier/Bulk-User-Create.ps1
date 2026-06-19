# Bulk_User_Creation.ps1
# Purpose: Bulk create users with CSV file

param(
    [Parameter(Mandatory=$true)]
    [string]$CSVPath,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("Tier0", "Tier1", "Tier2")]
    [string]$Tier
)

# Import modules
Import-Module ActiveDirectory

# Logging
$LogPath = "C:\AD_Automation_Logs"
if (!(Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force }
$LogFile = "$LogPath\Bulk_User_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp [$Level] $Message" | Out-File -FilePath $LogFile -Append
    Write-Host "$Timestamp [$Level] $Message"
}

# Read CSV
try {
    $Users = Import-Csv -Path $CSVPath
    Write-Log "Loaded $($Users.Count) users from CSV" "INFO"
} catch {
    Write-Log "Error reading CSV: $_" "ERROR"
    exit 1
}

# Define paths based on tier
$TierPaths = @{
    "Tier0" = "OU=Domain Controllers,DC=yourdomain,DC=com"
    "Tier1" = "OU=Servers,DC=yourdomain,DC=com"
    "Tier2" = "OU=Users,DC=yourdomain,DC=com"
}

$TierGroups = @{
    "Tier0" = "Domain Admins"
    "Tier1" = "Server Admins"
    "Tier2" = "Domain Users"
}

$BasePath = $TierPaths[$Tier]
$DefaultGroup = $TierGroups[$Tier]

Write-Log "Starting bulk creation for $Tier" "INFO"

foreach ($User in $Users) {
    try {
        # Check if user exists
        if (Get-ADUser -Filter {SamAccountName -eq $User.SamAccountName} -ErrorAction SilentlyContinue) {
            Write-Log "User $($User.SamAccountName) already exists - skipping" "WARNING"
            continue
        }
        
        # Create user
        $SecurePassword = ConvertTo-SecureString $User.Password -AsPlainText -Force
        $UserParams = @{
            Name = $User.Name
            SamAccountName = $User.SamAccountName
            UserPrincipalName = "$($User.SamAccountName)@yourdomain.com"
            GivenName = $User.FirstName
            Surname = $User.LastName
            DisplayName = "$($User.FirstName) $($User.LastName)"
            Path = if ($User.Department) { "OU=$($User.Department),$BasePath" } else { $BasePath }
            AccountPassword = $SecurePassword
            Enabled = $true
            ChangePasswordAtLogon = $true
            Department = $User.Department
            Title = $User.Title
            Description = "Created via bulk import on $(Get-Date)"
        }
        
        New-ADUser @UserParams -PassThru | Out-Null
        
        # Add to appropriate group
        Add-ADGroupMember -Identity $DefaultGroup -Members $User.SamAccountName
        
        Write-Log "Created user: $($User.SamAccountName) in $Tier" "INFO"
    } catch {
        Write-Log "Error creating user $($User.SamAccountName): $_" "ERROR"
    }
}

Write-Log "Bulk user creation completed" "INFO"
