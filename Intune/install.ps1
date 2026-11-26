#Install OSDCloud
Install-Module OSD -Force

#Install HPCMSL
Install-module HPCMSL

#Make Sure you're running Latest
Update-Module -name OSD -Force

#Make Sure you're running Latest
Update-Module -name HPCMSL -Force -Acceptlicense

#If the module is not found but installed
import-module -name OSD -Force

#Get ADK Default Locations
$ADKAMD64WinPELocation = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\en-us\winpe.wim"
$ADKAMD64WinPEVersion = (Get-WindowsImage -ImagePath $ADKAMD64WinPELocation -Index 1).Version.replace('10.0.','')

#Create the Template Name & Display Name in Console 
$TemplateName = "OSDCloudWinPE-$($ADKAMD64WinPEVersion)"
Write-Host -ForegroundColor Green "OSDCloud Template Name Set to: $TemplateName"

#Setup WorkSpace Location
Import-Module -name OSD -force
$OSDCloudWorkspace = "C:\OSDCloudWinPE-$($ADKAMD64WinPEVersion)"
[void][System.IO.Directory]::CreateDirectory($OSDCloudWorkspace)
if (Test-Path -Path $OSDCloudWorkspace){
    Write-Host -ForegroundColor Green "Workspace Location Created: $OSDCloudWorkspace"
}

#New Template, this will create a new template based on the ADK WinPE version installed on the system
#This takes awhile, so be patient. It will take the winpe.wim from the ADK, apply all of the optional components
#It also will add 7Zip into the WinPE image, long with several other components uses by OSDCloud.
New-OSDCloudTemplate -Name $TemplateName -Add7Zip


#Create USB
#This will create a new workspace based on the template created above.  This is very quick because it's just copying the template to the workspace location.
#Once it does the copy, you can make your edits to the workspace, most of which are done with Edit-OSDCloudWinPE.
New-OSDCloudWorkspace -WorkspacePath $OSDCloudWorkspace
#Create the Setup Complete Templates that you can modify to have OSDCloud kick off your own custom script during Setup Complete.
New-OSDCloudWorkSpaceSetupCompleteTemplate

#Added HPCMSL into WinPE, USB Ethernet Drivers & HP WinPE DriverPack, You can choose and pick. HPCMSL helps installing firmware and drivers for HP devices
Edit-OSDCloudWinPE -PSModuleInstall HPCMSL -CloudDriver Dell,HP,IntelNet,LenovoDock,Nutanix,USB,VMware,WiFi -Wallpaper "C:\Wallpapers\LebonIT.jpg" -StartOSDCloudGUI -Brand 'Lebon.IT'
#After you run this, if you're going to use this for PXE or ISE, you do not need to create the USB drive.

#Instead of creating the USB drive, you can create a new ISO file that you can use for PXE or ISE.
New-OSDCloudISO -WorkspacePath $OSDCloudWorkspace
#You can now use that ISO to boot VM's or grab the contents for PXE.

#Create Cloud USB, which will be based on the workspace created above.
#This takes a little awhile and does the basic setup of the USB drive, including copying the WinPE image to the USB drive.
New-OSDCloudUSB
