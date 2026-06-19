# Load environment variables from .env file
function GetEnv() {
    Get-Content .env | ForEach-Object {
        if ($_ -match "^\s*([^=]+)=(.+)\s*$") {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Process)
        }
    }
}

# Function to send the error report email
function SendReport($errorReport) {
    $htmlErrorTable = $errorReport | ConvertTo-Html -Property VMName, ErrorMessage -Fragment
    $sMail = @{
        To = $env:EMAIL_TO
        From = $env:EMAIL_FROM
        Subject = $env:EMAIL_SUBJECT_ERROR
        Body = if ($errorReport.Count -gt 0) {
            "The following errors occurred while updating VM Tools:`r`n$htmlErrorTable`r`n`r`n"
        } else {
            "No errors occurred while updating VM Tools.`r`n`r`n"
        }
        BodyAsHtml = $true
        SmtpServer = $env:SMTP_SERVER
    }
    Send-MailMessage @sMail
}

# Initialize script
GetEnv
Connect-VIServer -Server $env:VCENTER_SERVER -User $env:VCENTER_USERNAME -Password $env:VCENTER_PASSWORD
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# Import VMs from CSV file
$vmlist = Import-Csv 'files/test.csv'

# Initialize error report variable
$errorReport = @()

# Process each VM in the CSV
foreach ($vm in $vmlist) {
    $strNewVmname = $vm.name
    try {
        if ([string]::IsNullOrWhiteSpace($strNewVmname)) {
            throw "VM name is null or empty."
        }
        # Update VMware tools without a reboot
        Get-Cluster $env:VCENTER_CLUSTER | Get-VM $strNewVmname | Update-Tools -NoReboot -ErrorAction Stop
        Write-Host "VMware tools updated on: $strNewVmname"
    } catch {
        $errorMessage = "Failed to update VMware tools"
        Write-Host $errorMessage
        $errorReport += [PSCustomObject]@{
            VMName       = $strNewVmname
            ErrorMessage = $_.Exception.Message
        }
    }
}

# Send the error report
SendReport -errorReport $errorReport
