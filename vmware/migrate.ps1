# ==============================
# CONFIGURATION
# ==============================

$sourceHost = "dc2-esx02.domain.be"
$targetHost = "dc2-esx01.domain.be"

# ==============================
# CONNECT TO VCENTER
# ==============================
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

Connect-VIServer -Server "vcenter.domain.be"

# ==============================
# GET HOSTS
# ==============================
$src = Get-VMHost -Name $sourceHost
$dst = Get-VMHost -Name $targetHost

if (-not $src -or -not $dst) {
    Write-Host "âŒ One or both hosts not found." -ForegroundColor Red
    exit
}

# ==============================
# GET RUNNING VMS ON SOURCE HOST
# ==============================
$vms = Get-VM -Location $src | Where-Object {$_.PowerState -eq "PoweredOn"}

if ($vms.Count -eq 0) {
    Write-Host "â„¹ï¸ "No running VMs found on $sourceHost" -ForegroundColor Yellow
    exit
}

# ==============================
# SHOW VM LIST
# ==============================
Write-Host " VMs currently running on $sourceHost`n" -ForegroundColor Cyan
$vms | Select Name, PowerState | Format-Table -AutoSize

# ==============================
# CONFIRMATION STEP
# ==============================
$confirm = Read-Host "Do you want to migrate ALL these VMs to $targetHost? (Y/N)"

if ($confirm -notmatch "^[Yy]$") {
    Write-Host "âŒ Migration cancelled by user." -ForegroundColor Red
    exit
}

# ==============================
# MIGRATION LOOP
# ==============================
foreach ($vm in $vms) {
    try {
        Write-Host "Migrating $($vm.Name)..." -ForegroundColor Green

        Move-VM -VM $vm -Destination $dst -RunAsync

    } catch {
        Write-Host "âŒ Failed to migrate $($vm.Name): $_" -ForegroundColor Red
    }
}

Write-Host "Migration process started for all VMs." -ForegroundColor Cyan
