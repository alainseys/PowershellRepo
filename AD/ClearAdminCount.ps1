Import-Module ActiveDirectory

# Path to file containing usernames (sAMAccountName or UPN)
$userList = Get-Content "C:\Temp\tiering_gpo\users.txt"

foreach ($user in $userList) {
    try {
        $adUser = Get-ADUser -Identity $user -Properties adminCount

        if ($adUser.adminCount -eq 1) {
            Set-ADUser -Identity $user -Clear adminCount
            Write-Host "adminCount cleared for $user" -ForegroundColor Green
        }
        else {
            Write-Host "$user does not have adminCount set" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Error processing $user : $_" -ForegroundColor Red
    }
}
