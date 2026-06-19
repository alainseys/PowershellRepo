

function GetEnv()
{
    Get-Content .env | ForEach-Object {
        if ($_ -match "^\s*([^=]+)=(.+)\s*$") {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Process)
        }
    }
}
GetEnv
# Check if PowerCLI is installed
Install-Module -Name VMware.PowerCLI -Scope CurrentUser
Import-Module VMware.PowerCLI


Connect-VIServer -Server $env:VCENTER_SERVER -User $env:VCENTER_USERNAME -Password $env:VCENTER_PASSWORD
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

$report = Get-View -ViewType VirtualMachine -Property Name,Guest |
    Select-Object Name,
    @{N='ToolsStatus';E={$_.Guest.ToolsStatus}},
    @{N='ToolsType';E={$_.Guest.ToolsInstallType}},
    @{N='ToolsVersion';E={$_.Guest.ToolsVersion}},
    @{N='ToolsRunningStatus';E={$_.Guest.ToolsRunningStatus}},
    @{N='vCenter';E={([uri]$_.Client.ServiceUrl).Host}} |
    Where-Object { $_.ToolsStatus -eq "toolsOld" -or $_.ToolsStatus -eq "toolsNotRunning" -or $_.ToolsStatus -eq "toolsNotInstalled" } |
    Sort-Object -Property Name 

    $report | Select-Object Name | Export-Csv -Path "C:\temp\vm_list.csv" -NoTypeInformation
    $sMail = @{
        To = $env:EMAIL_TO
        CC = $env:EMAIL_CC
        From = $env:EMAIL_FROM
        Subject = $env:EMAIL_SUBJECT
        Body = $report | ConvertTo-Html | Out-String
        BodyAsHtml = $true
        SmtpServer = $env:SMTP_SERVER
    }
    
    Send-MailMessage @sMail
