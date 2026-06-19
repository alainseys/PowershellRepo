$controllerip = ""

New-NetFirewallRule -DisplayName "Ansible - Allow WinRm HTTP" -Direction Inbound -Protocol TCP -LocalPort 5985 -RemoteAddress $controllerip -Action Allow
New-NetFirewallRule -DisplayName "Ansible - Allow WinRm HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5985 -RemoteAddress $controllerip -Action Allow
