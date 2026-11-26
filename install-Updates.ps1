Set-Executionpolicy Bypass -Scope Process -Force
Install-Module -Name PSWindowsUpdate -Force
Import-Module -Name PSWindowsUpdate
Install-WindowsUpdate -AcceptAll
