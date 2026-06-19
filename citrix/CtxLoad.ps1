# init - don't touch these pls
asnp Citrix.*
$ErrorActionPreference = "SilentlyContinue"
$ExistingVariables = Get-Variable | Select-Object -ExpandProperty Name

Do {

# configurable vars
$ctx_ddc = "ctxddc1.domain.be" # DDC server address
$max_ddc_rec = 800 # Max results on a DDC query
$ctx_load_crit = 8000 # Critical load index threshold
$ctx_load_high = 6500 # High load index threshold
$ctx_load_med = 5100 # Medium load index threshold
$updatename = "CTXXAUPD"

# don't touch these pls
$outfile = "C:\temp\ctxload.htm"
$tmpfile = "C:\temp\temp.htm"
$output = @()
$serverload = @{"critical" = 0; "high" = 0; "medium" = 0; "low" = 0}
$sesscount = 0
$html_title =  "<h1>Citrix Load info</h1>"
$script_head = @"

<script>
var interval = Math.floor(Math.random() * (80000 - 30000 + 1)) + 30000;
setInterval(function() { window.location.reload() }, interval );
</script>
"@
$script_body = @"

<script>
document.getElementById("Refresh").innerHTML = 'Next refresh in ' + interval / 1000 + ' seconds';
</script>
"@
$header = @"
<style>

    h1 {
        font-family: Consolas, Helvetica, sans-serif;
        color: #000099;
        font-size: 28px;
        text-transform: uppercase;
    }
    
    h2 {
        font-family: Consolas, Helvetica, sans-serif;
        color: #000099;
        font-size: 16px;
    }
 
   table {
		font-size: 14px;
		border: 0px; 
		font-family: Consolas, Helvetica, sans-serif;
	} 
	
    td {
		padding: 4px;
		margin: 0px;
		border: 0;
        text-align: center;
	}
	
    th {
        background: #395870;
        background: linear-gradient(#49708f, #293f50);
        color: #fff;
        font-size: 16px;
        text-transform: uppercase;
        padding: 10px 15px;
        vertical-align: middle;
	}

    tr.ctx_load_crit {
        background-color: tomato;
    }

    tr.ctx_load_high {
        background-color: darkorange;
    }

    tr.ctx_load_med {
        background-color: gold;
    }

    tr.ctx_load_low {
        background-color: lightgreen;
    }

    tr.ctx_load_off {
        background-color: deepskyblue
    }

        #CreationDate {
        font-family: Consolas, Helvetica, sans-serif;
        color: darkgray;
        font-size: 9px;
        padding: 0;
        margin: 0;
        }

        #Refresh {
        font-family: Consolas, Helvetica, sans-serif;
        color: darkgray;
        font-size: 9px;
        padding: 0;
        margin: 0;
        }

        #SessionCounts {
        font-family: Consolas, Helvetica, sans-serif;
        font-size: 12px;
        }

        #LoadSummary {
        font-family: Consolas, Helvetica, sans-serif;
        font-size: 12px;
        }
</style>
"@

# functions
Function CleanMem {
    $NewVariables = Get-Variable | Select-Object -ExpandProperty Name | Where-Object {$ExistingVariables -notcontains $_ -and $_ -ne "ExistingVariables"}
    If ($NewVariables) { ForEach ($v in $NewVariables) { Remove-Variable $v } }
    [System.GC]::Collect()
}

$servers = $(Get-BrokerMachine).MachineName

ForEach ($entry in $servers) {
    If ($entry -eq $null) { continue }
    $brokermachine = Get-BrokerMachine -MachineName $entry
    If ($brokermachine.MachineName.Contains($updatename)) { continue }
    $sesscnt = $brokermachine.SessionCount.ToString()
    If ($brokermachine.LoadIndex -ge $ctx_load_crit) { $serverload["critical"]++ }
    ElseIf ($brokermachine.LoadIndex -ge $ctx_load_high) { $serverload["high"]++ }
    ElseIf ($brokermachine.LoadIndex -ge $ctx_load_med) { $serverload["medium"]++ }
    Else { $serverload["low"]++ }
    $output += [PSCustomObject]@{"Server"=$($entry.SubString(3)); "Total Users"=$sesscnt; "Load Index"=$brokermachine.LoadIndex; "Load Indexes"=$($brokermachine.LoadIndexes -join ', ')}
    $sesscount = $sesscount + $brokermachine.SessionCount
}
$tabledata = $output | ConvertTo-Html -Fragment
[xml]$xml = $tabledata
ForEach ($tr in $xml.table.tr) {
    $tr.SetAttribute("class", "ctx_load_low")
    If ($tr.td[2] -ge $ctx_load_med) { $tr.SetAttribute("class", "ctx_load_med") }
    If ($tr.td[2] -ge $ctx_load_high) { $tr.SetAttribute("class", "ctx_load_high") }
    If ($tr.td[2] -ge $ctx_load_crit) { $tr.SetAttribute("class", "ctx_load_crit") }
    If ($tr.td[2] -eq 10000) { $tr.SetAttribute("class", "ctx_load_crit") }
    If ($tr.td[2].Length -le 3) { $tr.SetAttribute("class", "ctx_load_low") }
    If ($tr.td[3].Length -eq 0) { $tr.SetAttribute("class", "ctx_load_off") }
}
$xml.Save($tmpfile)
$tabledata = Get-Content $tmpfile
Remove-Item $tmpfile
$sessioncount = "<p id='SessionCounts'>Total # of sessions: $sesscount"
$loadsummary = "<p id='LoadSummary'><u>Server Load</u><br>* Critical: $($serverload["critical"])<br>* High: $($serverload["high"])<br>* Medium: $($serverload["medium"])<br>* Low: $($serverload["low"])"
$report = ConvertTo-Html -Head "$header $script_head" -Body "$html_title $tabledata $sessioncount $loadsummary" -PostContent "<p id='CreationDate'>Generated on: $(Get-Date)</p><p id='Refresh'></p>$script_body"
$report | Out-File -FilePath $outfile

Copy-Item $outfile "\\ctxddc1\c$\inetpub\wwwroot\ctxload.htm"
Copy-Item $outfile "\\ctxddc2\c$\inetpub\wwwroot\ctxload.htm"
CleanMem
Write-Host "Done $(Get-Date)"
Start-Sleep -seconds 10
} While ($true)
