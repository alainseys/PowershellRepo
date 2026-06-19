# PowerShell script to report DHCP reservations for a specific scope and store details in variables
# Define the DHCP server and scope
$dhcpServer = "DC1"

$scopeId = "172.27.228.0" #Define scope here 
$apiendpoint = "https://ipam.domain.com/api/ipam/ip-addresses/"

# Check if the DHCP server module is available
Import-Module DhcpServer -ErrorAction SilentlyContinue

# Verify if the DHCP server is reachable
if (-not (Test-Connection -ComputerName $dhcpServer -Count 1 -Quiet)) {
    Write-Error "Cannot connect to DHCP server $dhcpServer. Please check connectivity."
    exit
}

try {
    # Retrieve DHCP reservations for the specified scope
    $reservations = Get-DhcpServerv4Reservation -ComputerName $dhcpServer -ScopeId $scopeId -ErrorAction Stop

    # Initialize an array to store reservation details
    $reservationList = @()

    # Check if any reservations were found
    if ($reservations) {
        foreach ($reservation in $reservations) {
            # Store each reservation's details in a custom object
            $reservationDetails = [PSCustomObject]@{
                Name        = $reservation.Name
                IPAddress   = $reservation.IPAddress
                ClientId    = $reservation.ClientId
                Description = $reservation.Description
            }
            $reservationList += $reservationDetails
        }

        # Output the reservations for verification
        $reservationList | Format-Table -AutoSize

        # Example of how to access the variables for API calls
        foreach ($item in $reservationList) {
            Write-Output "============================"
            Write-Output "Processing reservation:"
            Write-Output "Name: $($item.Name)"
            Write-Output "IPAddress: $($item.IPAddress)"
            Write-Output "ClientId: $($item.ClientId)"
            Write-Output "Description: $($item.Description)"
            Write-Output "============================"
            # Example placeholder for API call
            # Invoke-RestMethod -Uri "https://api.example.com/register" -Method Post -Body ($item | ConvertTo-Json)
        }
    } else {
        Write-Output "No reservations found for scope $scopeId on server $dhcpServer."
    }
}
catch {
    Write-Error "An error occurred while retrieving DHCP reservations: $_"
}
