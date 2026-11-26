#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installeert en onderhoudt een OSDCloud WinPE-omgeving.

.DESCRIPTION
    - Controleert en laadt een ondersteunde PowerShellGet-versie.
    - Installeert of actualiseert de OSD- en HPCMSL-modules.
    - Accepteert automatisch de licentie van HPCMSL en de HP-afhankelijkheden.
    - Bepaalt de geinstalleerde ADK WinPE-versie.
    - Maakt een OSDCloud-template en workspace.
    - Bouwt een ISO.
    - Selecteert en formatteert optioneel een USB-schijf als MBR/FAT32.
    - Onderhoudt een bestaande workspace en OSDCloud-USB.
    - Toont verbose OSD-uitvoer en rapporteert bestandswijzigingen in de console.
    - Schrijft de volledige console-uitvoer naar een transcriptlog.

.NOTES
    Start dit script als administrator in Windows PowerShell 5.1.
    Sluit na een upgrade van PowerShellGet alle PowerShell-vensters en start opnieuw.
    Het formatteren van een USB-schijf verwijdert alle gegevens op de gekozen schijf.
#>

[CmdletBinding()]
param(
    [string]$WallpaperPath = 'C:\Wallpapers\LebonIT.jpg',
    [string]$Brand = 'Lebon.IT',
    [string]$LogDirectory = 'C:\OSDCloudLogs'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
$VerbosePreference = 'Continue'
$script:TranscriptStarted = $false
$script:FileWatcherSubscriptions = @()
$script:FileWatchers = @()

function Get-TimeStamp {
    Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','STEP','FILE','COPY','WARN','ERROR','SUCCESS')]
        [string]$Level = 'INFO',
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Host "[$(Get-TimeStamp)] [$Level] $Message" -ForegroundColor $Color
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Log -Message $Message -Level STEP -Color Cyan
}

function Write-Success {
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message $Message -Level SUCCESS -Color Green
}

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return "$Bytes bytes"
}

function Write-FileDetails {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Path
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $File = Get-Item -LiteralPath $Path -Force
        Write-Log -Message ("{0}: {1} | Size: {2} | Modified: {3}" -f $Action, $File.FullName, (Format-FileSize $File.Length), $File.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) -Level FILE -Color DarkGray
    }
    else {
        Write-Log -Message "$Action`: $Path" -Level FILE -Color DarkGray
    }
}

function Start-BuildTranscript {
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        [void](New-Item -Path $LogDirectory -ItemType Directory -Force)
    }

    $LogFile = Join-Path $LogDirectory ("OSDCloud-Build-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Start-Transcript -Path $LogFile -Force | Out-Null
    $script:TranscriptStarted = $true
    Write-Success "Transcript gestart: $LogFile"
}

function Stop-BuildTranscript {
    if ($script:TranscriptStarted) {
        Stop-Transcript | Out-Null
        $script:TranscriptStarted = $false
    }
}

function Start-FileMonitoring {
    param([Parameter(Mandatory)][string[]]$Paths)

    Stop-FileMonitoring

    foreach ($Path in ($Paths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $Path)) {
            [void](New-Item -Path $Path -ItemType Directory -Force)
        }

        $Watcher = New-Object System.IO.FileSystemWatcher
        $Watcher.Path = $Path
        $Watcher.Filter = '*'
        $Watcher.IncludeSubdirectories = $true
        $Watcher.NotifyFilter = [IO.NotifyFilters]'FileName, DirectoryName, Size, LastWrite'
        $Watcher.EnableRaisingEvents = $true

        foreach ($EventName in @('Created','Changed','Deleted','Renamed')) {
            $SourceIdentifier = "OSDCloud.FileWatcher.$([guid]::NewGuid().Guid)"
            $Subscription = Register-ObjectEvent -InputObject $Watcher -EventName $EventName -SourceIdentifier $SourceIdentifier -Action {
                $Timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
                $ChangeType = $Event.SourceEventArgs.ChangeType
                $FullPath = $Event.SourceEventArgs.FullPath
                $OldPath = $Event.SourceEventArgs.OldFullPath

                if ($OldPath) {
                    Write-Host "[$Timestamp] [FILE] $ChangeType`: $OldPath -> $FullPath" -ForegroundColor DarkGray
                }
                else {
                    $SizeText = ''
                    if (Test-Path -LiteralPath $FullPath -PathType Leaf) {
                        try {
                            $Length = (Get-Item -LiteralPath $FullPath -Force -ErrorAction Stop).Length
                            $SizeText = " | $Length bytes"
                        }
                        catch { }
                    }
                    Write-Host "[$Timestamp] [FILE] $ChangeType`: $FullPath$SizeText" -ForegroundColor DarkGray
                }
            }

            $script:FileWatcherSubscriptions += $Subscription
        }

        $script:FileWatchers += $Watcher
        Write-Log -Message "Bestandsmonitor actief: $Path" -Level INFO -Color DarkCyan
    }
}

function Stop-FileMonitoring {
    foreach ($Subscription in $script:FileWatcherSubscriptions) {
        Unregister-Event -SourceIdentifier $Subscription.Name -ErrorAction SilentlyContinue
        Remove-Job -Id $Subscription.Id -Force -ErrorAction SilentlyContinue
    }
    $script:FileWatcherSubscriptions = @()

    foreach ($Watcher in $script:FileWatchers) {
        $Watcher.EnableRaisingEvents = $false
        $Watcher.Dispose()
    }
    $script:FileWatchers = @()
}

function Invoke-VerboseOSDOperation {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Operation,
        [string[]]$MonitorPaths
    )

    Write-Step $Name

    if ($MonitorPaths) {
        Start-FileMonitoring -Paths $MonitorPaths
    }

    $OldVerbosePreference = $VerbosePreference
    $OldInformationPreference = $InformationPreference
    $VerbosePreference = 'Continue'
    $InformationPreference = 'Continue'

    try {
        & $Operation 4>&1 6>&1 | ForEach-Object {
            $Line = $_.ToString()
            Write-Host "[$(Get-TimeStamp)] [OSD] $Line"
        }
        Write-Success "$Name voltooid."
    }
    finally {
        Start-Sleep -Milliseconds 750
        Stop-FileMonitoring
        $VerbosePreference = $OldVerbosePreference
        $InformationPreference = $OldInformationPreference
    }
}

function Assert-Administrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)

    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Start Windows PowerShell als administrator en voer het script opnieuw uit.'
    }
}

function Initialize-PowerShellEnvironment {
    Write-Step 'PowerShell-provider en vereiste modules voorbereiden'

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }

    $PowerShellGet = Get-Module -Name PowerShellGet -ListAvailable |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $PowerShellGet -or $PowerShellGet.Version -lt [version]'2.0.0') {
        throw 'PowerShellGet 2.x of nieuwer is vereist. Installeer PowerShellGet en PackageManagement, sluit PowerShell volledig af en start opnieuw.'
    }

    $LoadedPowerShellGet = Get-Module -Name PowerShellGet
    if ($LoadedPowerShellGet -and $LoadedPowerShellGet.Version -lt [version]'2.0.0') {
        Remove-Module -Name PowerShellGet -Force -ErrorAction SilentlyContinue
    }

    Import-Module -Name PowerShellGet -RequiredVersion $PowerShellGet.Version -Force
    Write-Success "PowerShellGet versie $($PowerShellGet.Version) is actief geladen."

    $Repository = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if (-not $Repository) {
        Register-PSRepository -Default
        $Repository = Get-PSRepository -Name PSGallery
    }

    if ($Repository.InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }
}

function Install-OrUpdateModule {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$AcceptLicense
    )

    Write-Step "Module $Name installeren of actualiseren"

    $InstalledModule = Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $InstalledModule) {
        $InstallParameters = @{
            Name = $Name; Repository = 'PSGallery'; Scope = 'AllUsers'
            Force = $true; AllowClobber = $true; ErrorAction = 'Stop'; Verbose = $true
        }
        if ($AcceptLicense) { $InstallParameters.AcceptLicense = $true }
        Install-Module @InstallParameters
    }
    else {
        $UpdateParameters = @{ Name = $Name; Force = $true; ErrorAction = 'Stop'; Verbose = $true }
        if ($AcceptLicense) { $UpdateParameters.AcceptLicense = $true }

        try {
            Update-Module @UpdateParameters
        }
        catch {
            if ($_.Exception.Message -match 'currently in use') {
                Write-Warning "$Name versie $($InstalledModule.Version) is momenteel geladen. De geinstalleerde versie wordt verder gebruikt."
            }
            else {
                Write-Warning "Update van $Name is niet gelukt. De module wordt opnieuw geinstalleerd. Fout: $($_.Exception.Message)"
                $InstallParameters = @{
                    Name = $Name; Repository = 'PSGallery'; Scope = 'AllUsers'
                    Force = $true; AllowClobber = $true; ErrorAction = 'Stop'; Verbose = $true
                }
                if ($AcceptLicense) { $InstallParameters.AcceptLicense = $true }
                Install-Module @InstallParameters
            }
        }
    }

    Import-Module -Name $Name -Force -ErrorAction Stop
    $LoadedModule = Get-Module -Name $Name | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $LoadedModule) { throw "Module $Name is niet correct geladen." }
    Write-Success "$Name versie $($LoadedModule.Version) is geladen."
}

function Install-RequiredModules {
    Initialize-PowerShellEnvironment
    Install-OrUpdateModule -Name 'OSD'
    Install-OrUpdateModule -Name 'HPCMSL' -AcceptLicense
}

function Get-OSDCloudConfiguration {
    $WinPEPath = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\en-us\winpe.wim'
    if (-not (Test-Path -LiteralPath $WinPEPath)) {
        throw "ADK WinPE-image niet gevonden: $WinPEPath. Installeer de Windows ADK en de afzonderlijke WinPE add-on."
    }

    $Image = Get-WindowsImage -ImagePath $WinPEPath -Index 1
    $WinPEVersion = $Image.Version.ToString() -replace '^10\.0\.', ''
    $TemplateName = "OSDCloudWinPE-$WinPEVersion"
    $WorkspacePath = "C:\OSDCloudWinPE-$WinPEVersion"

    [pscustomobject]@{
        WinPEPath = $WinPEPath
        WinPEVersion = $WinPEVersion
        TemplateName = $TemplateName
        WorkspacePath = $WorkspacePath
        OSDCloudRoot = 'C:\ProgramData\OSDCloud'
    }
}

function Test-Wallpaper {
    if (-not (Test-Path -LiteralPath $WallpaperPath)) { throw "Wallpaper niet gevonden: $WallpaperPath" }
}

function Invoke-OSDCloudWinPEEdit {
    param([Parameter(Mandatory)]$Configuration)
    Test-Wallpaper

    Invoke-VerboseOSDOperation -Name 'WinPE aanpassen met HPCMSL, drivers, branding en OSDCloud GUI' -MonitorPaths @($Configuration.OSDCloudRoot, $Configuration.WorkspacePath) -Operation {
        Edit-OSDCloudWinPE -PSModuleInstall HPCMSL `
            -CloudDriver Dell,HP,IntelNet,LenovoDock,Nutanix,USB,VMware,WiFi `
            -Wallpaper $WallpaperPath -StartOSDCloudGUI -Brand $Brand -Verbose
    }
}

function New-CompleteOSDCloudBuild {
    Install-RequiredModules
    $Configuration = Get-OSDCloudConfiguration

    Write-Success "OSDCloud-template: $($Configuration.TemplateName)"
    Write-Success "Workspace: $($Configuration.WorkspacePath)"
    Write-FileDetails -Action 'ADK WinPE source' -Path $Configuration.WinPEPath

    [void][System.IO.Directory]::CreateDirectory($Configuration.WorkspacePath)
    [void][System.IO.Directory]::CreateDirectory($Configuration.OSDCloudRoot)

    Invoke-VerboseOSDOperation -Name 'Nieuwe OSDCloud-template maken' -MonitorPaths @($Configuration.OSDCloudRoot) -Operation {
        Write-Log -Message "Copying ADK WinPE.wim: $($Configuration.WinPEPath)" -Level COPY -Color Yellow
        New-OSDCloudTemplate -Name $Configuration.TemplateName -Add7Zip -Verbose
    }

    Invoke-VerboseOSDOperation -Name 'Nieuwe OSDCloud-workspace maken' -MonitorPaths @($Configuration.WorkspacePath, $Configuration.OSDCloudRoot) -Operation {
        New-OSDCloudWorkspace -WorkspacePath $Configuration.WorkspacePath -Verbose
    }

    Invoke-VerboseOSDOperation -Name 'SetupComplete-template toevoegen' -MonitorPaths @($Configuration.WorkspacePath) -Operation {
        New-OSDCloudWorkSpaceSetupCompleteTemplate -Verbose
    }

    Invoke-OSDCloudWinPEEdit -Configuration $Configuration

    Invoke-VerboseOSDOperation -Name 'OSDCloud ISO maken' -MonitorPaths @($Configuration.WorkspacePath) -Operation {
        New-OSDCloudISO -WorkspacePath $Configuration.WorkspacePath -Verbose
    }

    Write-Success 'OSDCloud-template, workspace en ISO zijn aangemaakt.'
}

function New-OSDCloudISOOnly {
    Install-RequiredModules
    $Configuration = Get-OSDCloudConfiguration
    if (-not (Test-Path -LiteralPath $Configuration.WorkspacePath)) {
        throw "Workspace niet gevonden: $($Configuration.WorkspacePath). Voer eerst de volledige build uit."
    }

    Invoke-VerboseOSDOperation -Name "ISO maken vanuit $($Configuration.WorkspacePath)" -MonitorPaths @($Configuration.WorkspacePath) -Operation {
        New-OSDCloudISO -WorkspacePath $Configuration.WorkspacePath -Verbose
    }
}

function Select-USBPhysicalDisk {
    $UsbDisks = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.OperationalStatus -eq 'Online' } | Sort-Object Number)
    if ($UsbDisks.Count -eq 0) { throw 'Geen online USB-schijf gevonden. Plaats een USB-schijf en probeer opnieuw.' }

    Write-Host "`nBeschikbare USB-schijven:" -ForegroundColor Yellow
    $UsbDisks | Format-Table Number, FriendlyName, BusType,
        @{Name = 'SizeGB'; Expression = { [math]::Round($_.Size / 1GB, 2) }}, PartitionStyle, OperationalStatus -AutoSize

    $Selection = Read-Host 'Voer het schijfnummer van de USB-schijf in'
    if ($Selection -notmatch '^\d+$') { throw 'Ongeldig schijfnummer.' }
    $SelectedDisk = $UsbDisks | Where-Object Number -eq ([int]$Selection)
    if (-not $SelectedDisk) { throw "Schijf $Selection is niet een van de getoonde USB-schijven." }
    $SelectedDisk
}

function Format-USBAsMBR {
    $Disk = Select-USBPhysicalDisk
    $SizeGB = [math]::Round($Disk.Size / 1GB, 2)
    Write-Host "`nWAARSCHUWING: alle gegevens worden verwijderd." -ForegroundColor Red
    Write-Host "Geselecteerd: schijf $($Disk.Number), $($Disk.FriendlyName), $SizeGB GB" -ForegroundColor Yellow
    $Confirmation = Read-Host "Typ exact FORMATTEER-$($Disk.Number) om door te gaan"
    if ($Confirmation -cne "FORMATTEER-$($Disk.Number)") { Write-Warning 'Formatteren geannuleerd.'; return $null }

    Write-Step "USB-schijf $($Disk.Number) wissen en initialiseren als MBR"
    Set-Disk -Number $Disk.Number -IsOffline $false -ErrorAction SilentlyContinue
    Set-Disk -Number $Disk.Number -IsReadOnly $false -ErrorAction SilentlyContinue
    Clear-Disk -Number $Disk.Number -RemoveData -RemoveOEM -Confirm:$false
    Initialize-Disk -Number $Disk.Number -PartitionStyle MBR
    $Partition = New-Partition -DiskNumber $Disk.Number -UseMaximumSize -AssignDriveLetter -IsActive
    Format-Volume -Partition $Partition -FileSystem FAT32 -NewFileSystemLabel 'OSDCloud' -Confirm:$false -Force | Out-Null
    $Volume = $Partition | Get-Volume
    Write-Success "USB-schijf is als MBR/FAT32 geformatteerd en gekoppeld als $($Volume.DriveLetter):"
    $Disk
}

function New-OSDCloudUSBMedia {
    Install-RequiredModules
    $Configuration = Get-OSDCloudConfiguration
    $FormattedDisk = Format-USBAsMBR
    if (-not $FormattedDisk) { return }

    $DriveLetter = ($FormattedDisk | Get-Partition | Get-Volume | Where-Object DriveLetter | Select-Object -First 1).DriveLetter
    $MonitorPaths = @($Configuration.WorkspacePath)
    if ($DriveLetter) { $MonitorPaths += "$DriveLetter`:" }

    Invoke-VerboseOSDOperation -Name 'OSDCloud USB aanmaken' -MonitorPaths $MonitorPaths -Operation {
        Write-Host "Selecteer in de OSDCloud-prompt schijfnummer $($FormattedDisk.Number)." -ForegroundColor Yellow
        New-OSDCloudUSB -Verbose
    }
}

function Update-OSDCloudEnvironment {
    Install-RequiredModules
    $Configuration = Get-OSDCloudConfiguration
    $CloudWorkspace = Get-OSDCloudWorkspace
    if (-not $CloudWorkspace) { throw 'Er is geen actieve OSDCloud-workspace gevonden.' }

    $WorkspaceOSDModule = Join-Path $CloudWorkspace 'PowerShell\Offline\Modules\OSD'
    Write-Step 'Oude OSD-module uit workspace verwijderen'
    Remove-Item -LiteralPath $WorkspaceOSDModule -Force -Recurse -Verbose -ErrorAction SilentlyContinue

    $FlashDrives = @(Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter })
    foreach ($FlashDrive in $FlashDrives) {
        $UsbOSDModule = "$($FlashDrive.DriveLetter):\OSDCloud\PowerShell\Offline\Modules\OSD"
        if (Test-Path -LiteralPath $UsbOSDModule) {
            Remove-Item -LiteralPath $UsbOSDModule -Force -Recurse -Verbose -ErrorAction SilentlyContinue
        }
    }

    Invoke-OSDCloudWinPEEdit -Configuration $Configuration

    $MonitorPaths = @($CloudWorkspace) + @($FlashDrives | ForEach-Object { "$($_.DriveLetter):" })
    Invoke-VerboseOSDOperation -Name 'OSDCloud USB actualiseren' -MonitorPaths $MonitorPaths -Operation {
        Update-OSDCloudUSB -PSUpdate -Verbose
    }
}

function Show-Menu {
    Clear-Host
    Write-Host 'OSDCloud Build en Onderhoud' -ForegroundColor Cyan
    Write-Host '==========================' -ForegroundColor Cyan
    Write-Host '1. Volledige build: modules, template, workspace en ISO'
    Write-Host '2. Alleen ISO maken vanuit bestaande workspace'
    Write-Host '3. USB als MBR/FAT32 formatteren en OSDCloud USB maken'
    Write-Host '4. Bestaande OSDCloud-workspace en USB onderhouden'
    Write-Host '5. Alleen vereiste PowerShell-modules installeren/actualiseren'
    Write-Host '0. Afsluiten'
}

try {
    Assert-Administrator
    Start-BuildTranscript

    do {
        Show-Menu
        $Choice = Read-Host 'Maak een keuze'
        switch ($Choice) {
            '1' { New-CompleteOSDCloudBuild; Pause }
            '2' { New-OSDCloudISOOnly; Pause }
            '3' { New-OSDCloudUSBMedia; Pause }
            '4' { Update-OSDCloudEnvironment; Pause }
            '5' { Install-RequiredModules; Pause }
            '0' { Write-Log -Message 'Script afgesloten.' -Level INFO -Color Cyan }
            default { Write-Warning 'Ongeldige keuze.'; Start-Sleep -Seconds 2 }
        }
    } while ($Choice -ne '0')
}
catch {
    Write-Log -Message $_.Exception.Message -Level ERROR -Color Red
    Write-Host "Regel: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkRed
    exit 1
}
finally {
    Stop-FileMonitoring
    Stop-BuildTranscript
}
