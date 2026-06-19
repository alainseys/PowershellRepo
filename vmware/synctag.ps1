Import-Module ActiveDirectory
Import-Module VMware.VimAutomation.Core
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
Set-PowerCLIConfiguration -Scope User -ParticipateInCeip $false -Confirm:$false

$username = "ansible@vsphere.local"
$password = "PASSWORDHERE"
$vcenter = "vcenter.domain.be"
Write-Host "Logging file at: $logFilePath"
$groupNames = "gl_mg_sv_wu_prepilot","gl_mg_sv_wu_monthly1","gl_mg_sv_wu_monthly2","gl_mg_sv_wu_monthly3","gl_mg_sv_wu_monthly4","gl_mg_sv_wu_monthly5","gl_mg_sv_wu_monthly6"

# Verbind met vcenter: 
Connect-VIServer -Server $vcenter -Protocol https -User $username -Password $password

$logFilePath = "C:\vmc\Logs\TagSync.log"


foreach($groupName in $groupNames){
    Write-Host "Members of $groupName"
    $groupMembers = Get-ADGroupMember  -Identity $groupName
    foreach($member in $groupMembers){
        $vmName = $member.Name
        #Poging tot zoeken op vcenter:
        $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if($vm){
            #Indien gevonden
            Write-host "VM $vmName gevonden, tag toepassen"
            #Tagging
            New-TagAssignment -Tag $groupName -Entity $vm -Confirm:$false
            Write-Host "Tag ($groupName) applied to vm"
			"$vmName - Tag ($groupName) applied to vm" | Out-File -FilePath $logFilePath -Append

        }else{
            Write-Host "you fucked up"
			"Error: $vmName - VM not found" | Out-File -FilePath $logFilePath -Append

        }
        }
    }
    #$groupMembers | ForEach-Object {$_.Name }
