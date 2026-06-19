[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Start-Sleep -Seconds 30
Connect-ExchangeOnline -CertificateThumbprint "" -AppId "" -Organization ""

$startDate = ""
$endDate = ""
$allMessages = @()
$allFiles = @()
#$page = 1
#$pagesize = 5000
$mailboxes = @("customerservice@domain.com","AR@domain.com")
$recipients = @('itsupport@vanmarcke.be')


#$exportFile = "C:\temp\facturatie_failed.csv"

foreach($mailbox in $mailboxes){
  $startDate = (Get-Date).AddDays(-7)
  $endDate = (get-Date).AddDays(-6)
  $allMessages = @()
  $exportFile = "C:\temp\"+$mailbox.split("@")[0]+"_failed.csv"
  if($exportFile -ne "C:\temp\reply_failed.csv"){
    $allFiles += $exportFile
  }
  $newCSVFile = {} | Select "Date","Recipient", "ClientNumber","Subject","Reason" | Export-Csv $exportFile
  $file = Import-Csv $exportFile

#get failed messages last week
  do {
    $currentMessages = Get-MessageTraceV2 -SenderAddress $mailbox -StartDate $startDate -EndDate $endDate -ResultSize 5000 -ErrorAction SilentlyContinue| Where-Object {$_.Status -eq "Failed"} | select MessageTraceId, Received, RecipientAddress, Subject, Status
    $allMessages += $currentMessages
    $startDate = $startDate.AddDays(1)
    $endDate = $endDate.AddDays(1)
    Start-Sleep -Seconds 1
  }
  until ((get-date).Date -lt $endDate.Date)
#$allMessages | Export-Csv C:\temp\facturatie_failed.csv

#get detail & split client number
  foreach($message in $allMessages){
    $id = $message.MessageTraceID
    $recipient = $message.RecipientAddress
    $clientNumber = ($message.Subject).Split("/")[0]
    $clientNumber = $clientNumber.Substring($clientNumber.Length -6,6)
    $reason = Get-MessageTraceDetailV2 -MessageTraceId $id -RecipientAddress $recipient -ErrorAction SilentlyContinue | select Detail
    Start-Sleep 5
    #$reason = Get-MessageTraceDetailV2 -StartDate $startDate2 -EndDate $endDate2 -MessageTraceId $id -RecipientAddress $recipient -ErrorAction SilentlyContinue | select Detail
    try{
      $reason = [string]$reason[1]
    }
    catch{
      $reason = "unable to extract reason"
    }

    $file.Date = $message.Received
    $file.Recipient = $message.RecipientAddress
    $file.ClientNumber = $clientNumber
    $file.Subject = $message.Subject
    $file.Reason = $reason

    if(!($file.Subject.Contains("Automatisch antwoord"))){
      $file | Export-Csv $exportFile -Append
    }
  }
  
}
Send-MailMessage -From "noreply@domain.com" -to $recipients -Subject "Failed mails log" -Attachments $allFiles -SmtpServer "smtp.domain.com"
Send-MailMessage -From "noreply@domain.com" -to "itsupport@domain.com" -Subject "Failed mails log" -Attachments "C:\temp\reply_failed.csv" -SmtpServer "smtp.domain.com"
Start-Sleep 60
Remove-Item $allFiles
Remove-Item "C:\temp\reply_failed.csv"
