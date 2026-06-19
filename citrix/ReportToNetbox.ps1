# Citrix to NetBox Sync with Primary IP Assignment + Journal Entries

Add-PSSnapin Citrix.Broker.Admin.V2

# === CONFIGURATION ===
$NetBoxURL = "https://ipam.domain.com"
$NetBoxToken = "APITOKEN"
$ClusterName = "Citrix VDI Cluster"
# =====================

$headers = @{
    "Authorization" = "Token $NetBoxToken"
    "Content-Type"  = "application/json"
}

# -------------------------------
# Journal Entry Function
# -------------------------------
function Add-NetBoxJournalEntry {
    param(
        [string]$NetBoxURL,
        [hashtable]$Headers,
        [string]$ObjectType,
        [int]$ObjectID,
        [string]$Kind,
        [string]$Comments
    )

    try {
        $journalData = @{
            assigned_object_type = $ObjectType
            assigned_object_id   = $ObjectID
            kind                 = $Kind
            comments             = $Comments
        }

        Invoke-RestMethod -Uri "$NetBoxURL/api/extras/journal-entries/" `
            -Headers $Headers `
            -Method Post `
            -Body ($journalData | ConvertTo-Json -Depth 5) | Out-Null

    } catch {
        Write-Warning "Failed to create journal entry: $_"
    }
}

# -------------------------------
# Clean VM Name
# -------------------------------
function Clean-VMName {
    param([string]$Name)

    if ($Name -match '\\') {
        $Name = $Name.Split('\')[-1]
    }

    $Name = $Name -replace '[^a-zA-Z0-9\-_\.]', '-'
    return $Name.Trim('-', '_', '.')
}

# -------------------------------
# Get/Create Interface
# -------------------------------
function Get-VM-Interface {
    param($NetBoxURL, $Headers, $VMID, $VMName)

    try {
        $interfaces = Invoke-RestMethod -Uri "$NetBoxURL/api/virtualization/interfaces/?virtual_machine_id=$VMID" `
            -Headers $Headers -Method Get -ErrorAction SilentlyContinue

        if ($interfaces -and $interfaces.count -gt 0) {
            return $interfaces.results[0]
        }

        $interfaceData = @{
            virtual_machine = $VMID
            name            = "eth0"
            type            = "virtual"
            enabled         = $true
            description     = "Primary interface for $VMName"
        }

        return Invoke-RestMethod -Uri "$NetBoxURL/api/virtualization/interfaces/" `
            -Headers $Headers -Method Post -Body ($interfaceData | ConvertTo-Json)

    } catch {
        Write-Warning "Failed to get/create interface for $VMName $_"
        return $null
    }
}

# -------------------------------
# Ensure IP
# -------------------------------
function Ensure-IP-Address {
    param($NetBoxURL, $Headers, $IPAddress, $DNSName, $VMName, $InterfaceID)

    try {
        $cleanIP = $IPAddress.Trim()

        if ([string]::IsNullOrEmpty($cleanIP) -or $cleanIP -eq '0.0.0.0') {
            return $null
        }

        $existingIP = Invoke-RestMethod -Uri "$NetBoxURL/api/ipam/ip-addresses/?address=$cleanIP" `
            -Headers $Headers -Method Get -ErrorAction SilentlyContinue

        if ($existingIP -and $existingIP.count -gt 0) {
            $ipObject = $existingIP.results[0]

            $updateData = @{
                assigned_object_type = "virtualization.vminterface"
                assigned_object_id   = $InterfaceID
                dns_name             = $DNSName
                description          = "Citrix VM: $VMName"
            }

            Invoke-RestMethod -Uri "$NetBoxURL/api/ipam/ip-addresses/$($ipObject.id)/" `
                -Headers $Headers -Method Patch -Body ($updateData | ConvertTo-Json) | Out-Null

            return $ipObject

        } else {
            $ipData = @{
                address               = $cleanIP
                dns_name              = $DNSName
                description           = "Citrix VM: $VMName"
                status                = "active"
                assigned_object_type  = "virtualization.vminterface"
                assigned_object_id    = $InterfaceID
            }

            return Invoke-RestMethod -Uri "$NetBoxURL/api/ipam/ip-addresses/" `
                -Headers $Headers -Method Post -Body ($ipData | ConvertTo-Json)
        }

    } catch {
        Write-Warning "Failed to ensure IP $IPAddress $_"
        return $null
    }
}

# -------------------------------
# Set Primary IP
# -------------------------------
function Set-VM-PrimaryIP {
    param($NetBoxURL, $Headers, $VMID, $IPID, $VMName)

    try {
        if ($IPID -eq 0) { return $false }

        $ipInfo = Invoke-RestMethod -Uri "$NetBoxURL/api/ipam/ip-addresses/$IPID/" -Headers $Headers
        $ipAddress = $ipInfo.address

        $updateData = @{}

        if ($ipAddress -match '\.') {
            $updateData.primary_ip4 = $IPID
        } elseif ($ipAddress -match ':') {
            $updateData.primary_ip6 = $IPID
        } else {
            return $false
        }

        Invoke-RestMethod -Uri "$NetBoxURL/api/virtualization/virtual-machines/$VMID/" `
            -Headers $Headers -Method Patch -Body ($updateData | ConvertTo-Json) | Out-Null

        # Journal entry
        Add-NetBoxJournalEntry `
            -NetBoxURL $NetBoxURL `
            -Headers $Headers `
            -ObjectType "virtualization.virtualmachine" `
            -ObjectID $VMID `
            -Kind "success" `
            -Comments "Primary IP set to $ipAddress"

        return $true

    } catch {
        Write-Warning "Failed to set primary IP for $VMName $_"
        return $false
    }
}

# -------------------------------
# MAIN
# -------------------------------

Write-Host "Citrix → NetBox Sync (with Journal)" -ForegroundColor Cyan

# Test connection
Invoke-RestMethod -Uri "$NetBoxURL/api/" -Headers $headers | Out-Null

# Get cluster
$cluster = (Invoke-RestMethod -Uri "$NetBoxURL/api/virtualization/clusters/?name=$ClusterName" -Headers $headers).results[0]

# Get Citrix VMs
$citrixVMs = Get-BrokerMachine -MaxRecordCount 500

foreach ($citrixVM in $citrixVMs) {

    $cleanName = Clean-VMName $citrixVM.MachineName
    Write-Host "Processing: $cleanName"

    $vmID = $null

    try {
        $existingVM = Invoke-RestMethod -Uri "$NetBoxURL/api/virtualization/virtual-machines/?name=$cleanName" `
            -Headers $headers

        $vmData = @{
            name     = $cleanName
            cluster  = $cluster.id
            status   = if ($citrixVM.PowerState -eq "On") { "active" } else { "offline" }
            comments = "Citrix VM | Catalog: $($citrixVM.CatalogName)"
        }

        if ($existingVM.count -gt 0) {

            $vmID = $existingVM.results[0].id
            $current = $existingVM.results[0]

            $changes = @()

            if ($current.status.value -ne $vmData.status) {
                $changes += "Status: $($current.status.value) → $($vmData.status)"
            }

            if ($current.comments -ne $vmData.comments) {
                $changes += "Comments updated"
            }

            if ($changes.Count -gt 0) {

                Invoke-RestMethod -Uri "$NetBoxURL/api/virtualization/virtual-machines/$vmID/" `
                    -Headers $headers -Method Put -Body ($vmData | ConvertTo-Json)

                Add-NetBoxJournalEntry `
                    -NetBoxURL $NetBoxURL `
                    -Headers $headers `
                    -ObjectType "virtualization.virtualmachine" `
                    -ObjectID $vmID `
                    -Kind "success" `
                    -Comments ($changes -join "`n")

                Write-Host "  UPDATED" -ForegroundColor Yellow

            } else {
                Write-Host "  NO CHANGE" -ForegroundColor DarkGray
            }

        } else {

            $result = Invoke-RestMethod -Uri "$NetBoxURL/api/virtualization/virtual-machines/" `
                -Headers $headers -Method Post -Body ($vmData | ConvertTo-Json)

            $vmID = $result.id

            Add-NetBoxJournalEntry `
                -NetBoxURL $NetBoxURL `
                -Headers $headers `
                -ObjectType "virtualization.virtualmachine" `
                -ObjectID $vmID `
                -Kind "success" `
                -Comments "VM created from Citrix sync"

            Write-Host "  CREATED" -ForegroundColor Green
        }

        # IP handling
        if ($citrixVM.IPAddress -and $vmID) {

            $interface = Get-VM-Interface $NetBoxURL $headers $vmID $cleanName

            $ips = $citrixVM.IPAddress -split ',' | Where-Object { $_ -ne "0.0.0.0" }

            $primarySet = $false

            foreach ($ip in $ips) {

                $ipObj = Ensure-IP-Address $NetBoxURL $headers $ip $citrixVM.DNSName $cleanName $interface.id

                if ($ipObj -and -not $primarySet) {
                    if (Set-VM-PrimaryIP $NetBoxURL $headers $vmID $ipObj.id $cleanName) {
                        $primarySet = $true
                    }
                }
            }
        }

    } catch {

        Write-Host "  ERROR: $_" -ForegroundColor Red

        if ($vmID) {
            Add-NetBoxJournalEntry `
                -NetBoxURL $NetBoxURL `
                -Headers $headers `
                -ObjectType "virtualization.virtualmachine" `
                -ObjectID $vmID `
                -Kind "warning" `
                -Comments "Sync error: $_"
        }
    }

    Start-Sleep -Milliseconds 200
}

Write-Host "Done." -ForegroundColor Green
