asnp Citrix.*
$organization = "Seys Consults"
$tag = "prod_eu"
$off_machines_eu = Get-BrokerMachine -DesktopGroupName "$organization Apps and Desktops" -PowerState Off -Tag $tag

Foreach ($machine in $off_machines_eu) {
    New-BrokerHostingPowerAction -Action TurnOn -MachineName $machine.MachineName
}
