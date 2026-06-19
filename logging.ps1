##############
# Module Log #
##############

$LogApp = "LOG"
function New-LogEntry() {
    <#
        .SYNOPSIS
        Write new logentry.
        
        .DESCRIPTION
        Write a new logentry to textfile or Sql Server

        .EXAMPLE
        New-LogEntry -LogApp $LogApp -LogAppFunction $LogAppFunction -LogStatus "ERROR" -LogDescription $LogDescription -LogADAccount $LogADAccount -Txt -Sql
        
        .PARAMETER LogApp
        Name category: Adu, Adc, Eol, Eop, Max, Sap, SCCM, ...

        .PARAMETER LogAppFunction
        Name function: Get-Adu...

        .PARAMETER LogStatus
        Status: ACTION, PRESENT, SUCCESS, ERROR, WARNING
        
        .PARAMETER LogDescription
        Description of the status: function of the code        

        .PARAMETER LogSAPID
        SAPID of processed user
        
        .PARAMETER Txt
        SAPID of processed user    

        .PARAMETER Sql
        SAPID of processed user   

        .NOTES
        author: Simon Willemen
    #>    
    [CmdletBinding()]
    param (   
        [Parameter(Mandatory = $True)][String]$LogApp              
        , [Parameter(Mandatory = $True)][String]$LogAppFunction
        , [Parameter(Mandatory = $False)][String]$LogStatus
        , [Parameter(Mandatory = $True)][String]$LogDescription
        , [Parameter(Mandatory = $False)][Switch]$Txt
        , [Parameter(Mandatory = $False)][Switch]$Sql
    )

    Begin {
        Write-Verbose "Log wegschrijven naar een logbestand en/of naar Sql Server."
    }
    Process {
        [String]$LogADAccount = $env:username
        [String]$LogAdComputerName = $env:computername

        if ($txt) {        
            Set-Location $env:USERPROFILE
    
            #Log wegschrijven naar file    
            $DateTime = Get-Date -Format 'yyyy-MM-dd HH:mm'
            $Date = Get-Date -Format 'yyyy-MM-dd'
            $Jaar = Get-Date -Format 'yyyy'
            $Maand = Get-Date -Format 'MM'
    
            $DirJaar = "$PathLogDir\$Jaar"
            $DirMaand = "$PathLogDir\$Jaar\$Maand"
            $DirLogApp = "$PathLogDir\$Jaar\$Maand\$LogApp"
            $DirLogAppFunction = "$PathLogDir\$Jaar\$Maand\$LogApp\$LogAppFunction"
    
            if ((Test-LogPathCreateDir -Directory $DirJaar) -eq $false) { PrintErrorLog -LogApp "Log" -LogAppFunction "New-LogEntry" -LogDescription "Test-LogPathCreateDir -Directory $DirJaar" -LogADAccount $LogADAccount }
            if ((Test-LogPathCreateDir -Directory $DirMaand) -eq $false) { PrintErrorLog -LogApp "Log" -LogAppFunction "New-LogEntry" -LogDescription "Test-LogPathCreateDir -Directory $DirJaar" -LogADAccount $LogADAccount }
            if ((Test-LogPathCreateDir -Directory $DirLogApp) -eq $false) { PrintErrorLog -LogApp "Log" -LogAppFunction "New-LogEntry" -LogDescription "Test-LogPathCreateDir -Directory $DirJaar" -LogADAccount $LogADAccount }
            if ((Test-LogPathCreateDir -Directory $DirLogAppFunction) -eq $false) { PrintErrorLog -LogApp "Log" -LogAppFunction "New-LogEntry" -LogDescription "Test-LogPathCreateDir -Directory $DirJaar" -LogADAccount $LogADAccount }
       
            $Out = "$DateTime - $LogStatus - $LogDescription - $LogADAccount - $LogAdComputerName"
            $PathLogFile = "$PathLogDir\$Jaar\$Maand\$LogApp\$LogAppFunction\$Date - $LogApp - $LogAppFunction.log"
            if (Test-Path -Path $PathLogFile) {
                #Logfile vullen als bestaat
                Add-Content -Path $PathLogFile -Value $Out  -ErrorAction SilentlyContinue
            }
            else {
                #LogFile maken als niet bestaat
                #PrintAction "LogFile $PathLogFile wordt aangemaakt."   
                New-Item -Path $PathLogFile -ItemType file -Force | Out-Null
                Add-Content -Path $PathLogFile -Value $Out  -ErrorAction SilentlyContinue
            } 
        }
        if ($sql) {
            #Log wegschrijven naar DB     
            $LogDescription = $LogDescription.replace("'", "")   # speciaal teken wegwerken    
            return Invoke-Sqlcmd -Query "   INSERT INTO LogApp ( LogDate,     LogApp,    LogAppFunction,    LogStatus,    LogDescription,    LogADAccount,    LogAdComputerName) 
                                            VALUES   ( GETDATE(), '$LogApp', '$LogAppFunction', '$LogStatus', '$LogDescription', '$LogADAccount', '$LogAdComputerName' ) " -ServerInstance $LogSqlServer -Database $LogSqlServerDatabase                
        } 
    }   
    End {
        Write-Verbose "Wegschrijven naar logbestand en/of Sql Server beëindigd."
    }     
} 

function New-LogReportAsHtml() {
    param (     
        [string]$LogApp
        , [string]$LogAppFunction
        , [string]$Html        
    )

    Set-Location $env:USERPROFILE
    #Report wegschrijven naar file    
    $DateTime = Get-Date -Format 'yyyyMMdd HHmmss'    

    $Jaar = Get-Date -Format 'yyyy'
    $Maand = Get-Date -Format 'MM'

    $DirJaar = "$PathReport\$Jaar"
    $DirMaand = "$PathReport\$Jaar\$Maand"
    $DirLogApp = "$PathReport\$Jaar\$Maand\$LogApp"
    $DirLogAppFunction = "$PathReport\$Jaar\$Maand\$LogApp\$LogAppFunction"

    if ((Test-LogPathCreateDir -Directory $DirJaar) -eq $false) { PrintErrorLog -LogApp "Log" -LogAppFunction "New-LogEntry" -LogDescription "Test-LogPathCreateDir -Directory $DirJaar" -LogADAccount $LogADAccount }
    if ((Test-LogPathCreateDir -Directory $DirMaand) -eq $false) { PrintErrorLog -LogApp "Log" -LogAppFunction "New-LogEntry" -LogDescription "Test-LogPathCreateDir -Directory $DirJaar" -LogADAccount $LogADAccount }
    if ((Test-LogPathCreateDir -Directory $DirLogApp) -eq $false) { PrintErrorLog -LogApp "Log" -LogAppFunction "New-LogEntry" -LogDescription "Test-LogPathCreateDir -Directory $DirJaar" -LogADAccount $LogADAccount }
    if ((Test-LogPathCreateDir -Directory $DirLogAppFunction) -eq $false) { PrintErrorLog -LogApp "Log" -LogAppFunction "New-LogEntry" -LogDescription "Test-LogPathCreateDir -Directory $DirJaar" -LogADAccount $LogADAccount }

    $PathReportFile = "$PathReport\$Jaar\$Maand\$LogApp\$LogAppFunction\$DateTime - $LogApp - $LogAppFunction.html"
    if (Test-Path -Path $PathReportFile) {
        #Logfile vullen als bestaat
        Add-Content -Path $PathReportFile -Value $Out
    }
    else {
        #LogFile maken als niet bestaat
        PrintAction "Rapport in html $PathReportFile wordt aangemaakt."   
        New-Item -Path $PathReportFile -ItemType file -Force 
        Add-Content -Path $PathReportFile -Value $Html
    }  
}

function Test-LogPathCreateDir() {
    <#
    - Test of directory bestaat -> als niet bestaat -> aanmaken
    #>
    [CmdletBinding()]                
    param 
    (
        [parameter(Mandatory = $true, Position = 1)]
        [string]$Directory   
    )  
  
    if (Test-Path -Path $Directory) {
        # return $true  
    }
    else {
        New-Item -Path $Directory -ItemType Directory
                
        if (Test-Path -Path $Directory) {
            #   return $true
        }
        else {
            #  return $false    
        }        
    }
}

function Set-LogToArchive {
    [CmdletBinding()]                
    param 
    (
        [parameter(Mandatory = $true, Position = 1)]
        [string]$Days   
    )  
    $LogAppFunction = "Set-LogToArchive"
    $LogAppRows = Get-LogRowsNumber | Select-Object -ExpandProperty Rows                                
    $LogAppArchiveRows = Get-LogArchiveRowsNumber | Select-Object -ExpandProperty Rows    
    PrintLog -LogApp $LogApp -LogAppFunction $LogAppFunction -LogStatus "INFO" -LogDescription "Aantal rijen: $LogAppRows - LogApp." 
    PrintLog -LogApp $LogApp -LogAppFunction $LogAppFunction -LogStatus "INFO" -LogDescription "Aantal rijen: $LogAppArchiveRows - LogAppArchive." 
    PrintLog -LogApp $LogApp -LogAppFunction $LogAppFunction -LogStatus "ACTION" -LogDescription "Logs uit LogApp die ouder zijn dan $Days dagen verplaatsen naar LogAppArchive." 
    Invoke-Sqlcmd -Query   " 
                                    INSERT INTO LogAppArchive ([LogDate],[LogApp],[LogAppFunction], [LogStatus],[LogDescription],[LogId],[LogADAccount],[LogAdComputerName] )
                                    SELECT [LogDate]
                                        ,[LogApp]
                                        ,[LogAppFunction]
                                        ,[LogStatus]
                                        ,[LogDescription]
                                        ,[LogId]
                                        ,[LogADAccount]
                                        ,[LogAdComputerName]
                                    FROM [PowerMGMT].[dbo].[LogApp]
                                    WHERE LogDate < DATEADD(day, -$Days, GETDATE());

                                    DELETE FROM LogApp WHERE LogApp.LogId IN (SELECT LogAppArchive.LogId FROM LogAppArchive);
                                " -ServerInstance $LogSqlServer -Database $LogSqlServerDatabase                
    $LogAppRows = Get-LogRowsNumber | Select-Object -ExpandProperty Rows                                
    $LogAppArchiveRows = Get-LogArchiveRowsNumber | Select-Object -ExpandProperty Rows
    PrintLog -LogApp $LogApp -LogAppFunction $LogAppFunction -LogStatus "INFO" -LogDescription "Aantal rijen: $LogAppRows - LogApp." 
    PrintLog -LogApp $LogApp -LogAppFunction $LogAppFunction -LogStatus "INFO" -LogDescription "Aantal rijen: $LogAppArchiveRows - LogAppArchive." 
} 

function Get-LogRowsNumber {
    [CmdletBinding()]                
    param ( )
    return Invoke-Sqlcmd -Query   "SELECT count(distinct logid) As Rows FROM [PowerMGMT].[dbo].[LogApp] " -ServerInstance $LogSqlServer -Database $LogSqlServerDatabase         
}
function Get-LogArchiveRowsNumber {
    [CmdletBinding()]                
    param ()
    return Invoke-Sqlcmd -Query   "SELECT count(distinct logid) As Rows FROM [PowerMGMT].[dbo].[LogAppArchive] " -ServerInstance $LogSqlServer -Database $LogSqlServerDatabase         
}

function Get-LogVmwErrorToday {
    [CmdletBinding()]                
    param ()
    return Invoke-Sqlcmd -Query   " SELECT LogDate, LogStatus, LogDescription FROM [PowerMGMT].[dbo].[LogApp] 
                                    WHERE CAST(LogDate AS DATE) = CAST( GETDATE() AS DATE)
                                    AND LogStatus = 'ERROR' 
                                    AND LogApp = 'Vmw' " -ServerInstance $LogSqlServer -Database $LogSqlServerDatabase      
}

function Get-LogWusErrorToday {
    [CmdletBinding()]                
    param ()
    return Invoke-Sqlcmd -Query   " SELECT LogDate, LogStatus, LogDescription FROM [PowerMGMT].[dbo].[LogApp] 
                                    WHERE CAST(LogDate AS DATE) = CAST( GETDATE() AS DATE)
                                    AND LogStatus = 'ERROR' 
                                    AND LogApp = 'Wus' " -ServerInstance $LogSqlServer -Database $LogSqlServerDatabase    
}
