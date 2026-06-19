# AD_Auto_Scheduler.ps1
# Purpose: Schedule recurring AD management tasks

param(
    [string]$TaskName = "AD_Auto_Management",
    [string]$ScheduleTime = "02:00"
)

# Create scheduled tasks for different tiers
$Tasks = @(
    @{
        Name = "AD_Tier0_Report"
        Script = "Tier0_Operations.ps1"
        Args = "-Action Report"
        Description = "Daily Tier 0 report"
        Schedule = "Daily"
    },
    @{
        Name = "AD_Tier1_Report"
        Script = "Tier1_Operations.ps1"
        Args = "-Action Report"
        Description = "Daily Tier 1 report"
        Schedule = "Daily"
    },
    @{
        Name = "AD_Tier2_Report"
        Script = "Tier2_Operations.ps1"
        Args = "-Action Report"
        Description = "Daily Tier 2 report"
        Schedule = "Daily"
    }
)

foreach ($Task in $Tasks) {
    try {
        # Check if task exists
        $ExistingTask = Get-ScheduledTask -TaskName $Task.Name -ErrorAction SilentlyContinue
        if ($ExistingTask) {
            Unregister-ScheduledTask -TaskName $Task.Name -Confirm:$false
            Write-Host "Removed existing task: $($Task.Name)" -ForegroundColor Yellow
        }
        
        # Create action
        $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\AD_Automation\$($Task.Script)`" $($Task.Args)"
        
        # Create trigger (daily at specified time)
        $Trigger = New-ScheduledTaskTrigger -Daily -At $ScheduleTime
        
        # Create principal (run as SYSTEM)
        $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        # Create settings
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        # Register task
        Register-ScheduledTask -TaskName $Task.Name -Action $Action -Trigger $Trigger `
            -Principal $Principal -Settings $Settings -Description $Task.Description
        
        Write-Host "Created scheduled task: $($Task.Name)" -ForegroundColor Green
    } catch {
        Write-Host "Error creating task $($Task.Name): $_" -ForegroundColor Red
    }
}

# Show all tasks
Write-Host "`nAll AD automation tasks:" -ForegroundColor Cyan
Get-ScheduledTask | Where-Object {$_.TaskName -like "AD_*"} | Format-Table TaskName, State
