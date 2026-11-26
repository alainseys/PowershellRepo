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

.NOTES
    Start dit script als administrator in Windows PowerShell 5.1.
    Sluit na een upgrade van PowerShellGet alle PowerShell-vensters en start opnieuw.
    Het formatteren van een USB-schijf verwijdert alle gegevens op de gekozen schijf.
#>

[CmdletBinding()]
param(
    [string]$WallpaperPath = 'C:\Wallpapers\LebonIT.jpg',
    [string]$Brand = 'Lebon.IT'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host $Message -ForegroundColor Green
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
            Name         = $Name
            Repository   = 'PSGallery'
            Scope        = 'AllUsers'
            Force        = $true
            AllowClobber = $true
            ErrorAction  = 'Stop'
        }

        if ($AcceptLicense) {
            $InstallParameters.AcceptLicense = $true
        }

        Install-Module @InstallParameters
    }
    else {
        $UpdateParameters = @{
            Name        = $Name
            Force       = $true
            ErrorAction = 'Stop'
        }

        if ($AcceptLicense) {
            $UpdateParameters.AcceptLicense = $true
        }

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
                    Name         = $Name
                    Repository   = 'PSGallery'
                    Scope        = 'AllUsers'
                    Force        = $true
                    AllowClobber = $true
                    ErrorAction  = 'Stop'
                }

                if ($AcceptLicense) {
                    $InstallParameters.AcceptLicense = $true
                }

                Install-Module @InstallParameters
            }
        }
    }

    Import-Module -Name $Name -Force -ErrorAction Stop
    $LoadedModule = Get-Module -Name $Name |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $LoadedModule) {
        throw "Module $Name is niet correct geladen."
    }

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
        WinPEPath     = $WinPEPath
        WinPEVersion  = $WinPEVersion
        TemplateName  = $TemplateName
        WorkspacePath = $WorkspacePath
    }
}

function Test-Wallpaper {
    if (-not (Test-Path -LiteralPath $WallpaperPath)) {
        throw "Wallpaper niet gevonden: $WallpaperPath"
    }
}

function Invoke-OSDCloudWinPEEdit {
    Test-Wallpaper

    $Parameters = @{
        PSModuleInstall  = 'HPCMSL'
        CloudDriver      = @('Dell', 'HP', 'IntelNet', 'LenovoDock', 'Nutanix', 'USB', 'VMware', 'WiFi')
        Wallpaper        = $WallpaperPath
        StartOSDCloudGUI = $true
        Brand            = $Brand
    }

    Edit-OSDCloudWinPE @Parameters
}

function New-CompleteOSDCloudBuild {
    Install-RequiredModules
    $Configuration = Get-OSDCloudConfiguration

    Write-Success "OSDCloud-template: $($Configuration.TemplateName)"
    Write-Success "Workspace: $($Configuration.WorkspacePath)"

    [void][System.IO.Directory]::CreateDirectory($Configuration.WorkspacePath)

    Write-Step 'Nieuwe OSDCloud-template maken'
    New-OSDCloudTemplate -Name $Configuration.TemplateName -Add7Zip

    Write-Step 'Nieuwe OSDCloud-workspace maken'
    New-OSDCloudWorkspace -WorkspacePath $Configuration.WorkspacePath

    Write-Step 'SetupComplete-template toevoegen'
    New-OSDCloudWorkSpaceSetupCompleteTemplate

    Write-Step 'WinPE aanpassen met HPCMSL, drivers, branding en OSDCloud GUI'
    Invoke-OSDCloudWinPEEdit

    Write-Step 'OSDCloud ISO maken'
    New-OSDCloudISO -WorkspacePath $Configuration.WorkspacePath

    Write-Success 'OSDCloud-template, workspace en ISO zijn aangemaakt.'
}

function New-OSDCloudISOOnly {
    Install-RequiredModules
    $Configuration = Get-OSDCloudConfiguration

    if (-not (Test-Path -LiteralPath $Configuration.WorkspacePath)) {
        throw "Workspace niet gevonden: $($Configuration.WorkspacePath). Voer eerst de volledige build uit."
    }

    Write-Step "ISO maken vanuit $($Configuration.WorkspacePath)"
    New-OSDCloudISO -WorkspacePath $Configuration.WorkspacePath
    Write-Success 'OSDCloud ISO is aangemaakt.'
}

function Select-USBPhysicalDisk {
    $UsbDisks = @(Get-Disk | Where-Object {
        $_.BusType -eq 'USB' -and $_.OperationalStatus -eq 'Online'
    } | Sort-Object Number)

    if ($UsbDisks.Count -eq 0) {
        throw 'Geen online USB-schijf gevonden. Plaats een USB-schijf en probeer opnieuw.'
    }

    Write-Host "`nBeschikbare USB-schijven:" -ForegroundColor Yellow
    $UsbDisks | Format-Table Number, FriendlyName, BusType,
        @{Name = 'SizeGB'; Expression = { [math]::Round($_.Size / 1GB, 2) }},
        PartitionStyle, OperationalStatus -AutoSize

    $Selection = Read-Host 'Voer het schijfnummer van de USB-schijf in'
    if ($Selection -notmatch '^\d+$') {
        throw 'Ongeldig schijfnummer.'
    }

    $DiskNumber = [int]$Selection
    $SelectedDisk = $UsbDisks | Where-Object Number -eq $DiskNumber

    if (-not $SelectedDisk) {
        throw "Schijf $DiskNumber is niet een van de getoonde USB-schijven."
    }

    $SelectedDisk
}

function Format-USBAsMBR {
    $Disk = Select-USBPhysicalDisk
    $SizeGB = [math]::Round($Disk.Size / 1GB, 2)

    Write-Host "`nWAARSCHUWING: alle gegevens worden verwijderd." -ForegroundColor Red
    Write-Host "Geselecteerd: schijf $($Disk.Number), $($Disk.FriendlyName), $SizeGB GB" -ForegroundColor Yellow
    $Confirmation = Read-Host "Typ exact FORMATTEER-$($Disk.Number) om door te gaan"

    if ($Confirmation -cne "FORMATTEER-$($Disk.Number)") {
        Write-Warning 'Formatteren geannuleerd.'
        return $null
    }

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

    $FormattedDisk = Format-USBAsMBR
    if (-not $FormattedDisk) {
        return
    }

    Write-Step 'OSDCloud USB aanmaken'
    Write-Host "Selecteer in de OSDCloud-prompt schijfnummer $($FormattedDisk.Number)." -ForegroundColor Yellow
    New-OSDCloudUSB
    Write-Success 'OSDCloud USB-proces is voltooid.'
}

function Update-OSDCloudEnvironment {
    Install-RequiredModules

    Write-Step 'Actieve OSDCloud-workspace ophalen'
    $CloudWorkspace = Get-OSDCloudWorkspace
    if (-not $CloudWorkspace) {
        throw 'Er is geen actieve OSDCloud-workspace gevonden.'
    }

    $WorkspaceOSDModule = Join-Path $CloudWorkspace 'PowerShell\Offline\Modules\OSD'
    Write-Step 'Oude OSD-module uit workspace verwijderen'
    Remove-Item -LiteralPath $WorkspaceOSDModule -Force -Recurse -ErrorAction SilentlyContinue

    Write-Step 'Oude OSD-modules van verwijderbare stations verwijderen'
    $FlashDrives = @(Get-Volume | Where-Object {
        $_.DriveType -eq 'Removable' -and $_.DriveLetter
    })

    foreach ($FlashDrive in $FlashDrives) {
        $UsbOSDModule = "$($FlashDrive.DriveLetter):\OSDCloud\PowerShell\Offline\Modules\OSD"
        if (Test-Path -LiteralPath $UsbOSDModule) {
            Remove-Item -LiteralPath $UsbOSDModule -Force -Recurse -ErrorAction SilentlyContinue
            Write-Success "Oude OSD-module verwijderd van $($FlashDrive.DriveLetter):"
        }
    }

    Write-Step 'WinPE boot image actualiseren'
    Invoke-OSDCloudWinPEEdit

    Write-Step 'OSDCloud USB actualiseren met de nieuwste PowerShell-modules en boot image'
    Update-OSDCloudUSB -PSUpdate

    Write-Success 'Onderhoud van OSDCloud is voltooid.'
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

    do {
        Show-Menu
        $Choice = Read-Host 'Maak een keuze'

        switch ($Choice) {
            '1' { New-CompleteOSDCloudBuild; Pause }
            '2' { New-OSDCloudISOOnly; Pause }
            '3' { New-OSDCloudUSBMedia; Pause }
            '4' { Update-OSDCloudEnvironment; Pause }
            '5' { Install-RequiredModules; Pause }
            '0' { Write-Host 'Script afgesloten.' -ForegroundColor Cyan }
            default { Write-Warning 'Ongeldige keuze.'; Start-Sleep -Seconds 2 }
        }
    } while ($Choice -ne '0')
}
catch {
    Write-Host "`nFOUT: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Regel: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkRed
    exit 1
}
