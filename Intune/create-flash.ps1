#Instead of creating the USB drive, you can create a new ISO file that you can use for PXE or ISE.
New-OSDCloudISO -WorkspacePath $OSDCloudWorkspace
#You can now use that ISO to boot VM's or grab the contents for PXE.

#Create Cloud USB, which will be based on the workspace created above.
#This takes a little awhile and does the basic setup of the USB drive, including copying the WinPE image to the USB drive.
New-OSDCloudUSB
