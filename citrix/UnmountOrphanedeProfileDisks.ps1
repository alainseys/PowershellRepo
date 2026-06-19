$DryRun = $true

$activeUsers = @()
$quserOutput = quser 2>$null

if ($quserOutput) {
    $activeUsers = $quserOutput |
        Select-Object -Skip 1 |
        ForEach-Object {
            ($_ -replace '\s{2,}', ',' -split ',')[0].Trim().Trim('>')
        } |
        Sort-Object -Unique
}

Write-Host "Active users: $($activeUsers -join ', ')"

$disks = Get-Disk | Where-Object {
    $_.Location -like "*Profile_*.vhdx*"
}

foreach ($disk in $disks) {

    $path = $disk.Location

    if (-not $path) {
        continue
    }

    $username = $null

    if ($path -match "Profile_(.+?)\.vhdx") {
        $username = $matches[1]
    }

    if (-not $username) {
        Write-Host "SKIP (cannot parse): $path"
        continue
    }

    $isActive = $false

    foreach ($u in $activeUsers) {
        if ($u -eq $username) {
            $isActive = $true
            break
        }
    }

    if ($isActive) {
        Write-Host "KEEP (active): $username"
        continue
    }

    Write-Host "ORPHAN mounted VHDX: $username -> $path"

    if ($DryRun) {
        Write-Host "[DRY RUN] Would detach: $path"
    }
    else {

        $script = @()
        $script += "select vdisk file=`"$path`""
        $script += "detach vdisk"

        $temp = "$env:TEMP\detach_vhdx.txt"
        $script | Out-File -Encoding ASCII -FilePath $temp

        Write-Host "Detaching via DiskPart: $path"

        diskpart /s $temp | Out-Null
    }
}

$tempFile = "$env:TEMP\detach_vhdx.txt"

if (Test-Path $tempFile) {
    try {
        Remove-Item $tempFile -Force -ErrorAction Stop
        Write-Host "Temp file cleaned: $tempFile"
    }
    catch {
        Write-Warning "Failed to remove temp file: $_"
    }
}
else {
    Write-Host "No temp file to clean."
}
