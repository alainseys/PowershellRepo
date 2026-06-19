# CCB Advisory Monitor - Sends email via open relay when keywords (HTTP, n8n) appear
$advisoriesUrl = "https://ccb.belgium.be/advisories"
$keywords = @("HTTP", "n8n")
$smtpServer = "smtp.domain.com"     # Change to your open relay server
$smtpPort = 25                          # Usually 25 for open relay
$fromEmail = "ansible@outlook.com"    # Change to sender email
$toEmail = "alain.seys@outlook.com"         # Change to recipient email
$stateFile = "$env:TEMP\ccb_last_links.txt"

# Set the cutoff date (7 days ago)
$cutoffDate = (Get-Date).AddDays(-7).Date

function Send-AlertEmail {
    param(
        [string]$Keyword,
        [string]$Title,
        [string]$Link,
        [datetime]$PublishedDate
    )
    $subject = "CCB Advisory Match: $Keyword"
    $body = @"
New CCB advisory matches keyword "$Keyword":

Title: $Title
Published: $($PublishedDate.ToString('yyyy-MM-dd'))
Full advisory link: $Link

Checked from: $advisoriesUrl
"@

    Send-MailMessage -SmtpServer $smtpServer -Port $smtpPort `
        -From $fromEmail -To $toEmail -Subject $subject -Body $body
}

function Get-PublishedDate {
    param([string]$HtmlContent)
    
    # Look for date in div with class "global-search--type--date"
    $datePattern = '<div[^>]*class="[^"]*global-search--type--date[^"]*"[^>]*>\s*Published:\s*(\d{2}/\d{2}/\d{4})\s*</div>'
    $dateMatch = [regex]::Match($HtmlContent, $datePattern)
    
    if ($dateMatch.Success) {
        $dateStr = $dateMatch.Groups[1].Value
        try {
            # Parse date in DD/MM/YYYY format
            $date = [datetime]::ParseExact($dateStr, "dd/MM/yyyy", $null)
            return $date
        } catch {
            Write-Warning "Could not parse date: $dateStr"
            return $null
        }
    }
    
    # Fallback: look for just "Published: DD/MM/YYYY" without the div class
    $fallbackPattern = 'Published:\s*(\d{2}/\d{2}/\d{4})'
    $fallbackMatch = [regex]::Match($HtmlContent, $fallbackPattern)
    
    if ($fallbackMatch.Success) {
        $dateStr = $fallbackMatch.Groups[1].Value
        try {
            $date = [datetime]::ParseExact($dateStr, "dd/MM/yyyy", $null)
            return $date
        } catch {
            return $null
        }
    }
    
    return $null
}

# Load previously sent advisory links (avoid duplicates)
$sentLinks = @()
if (Test-Path $stateFile) {
    $sentLinks = Get-Content $stateFile
}

# Fetch the page
try {
    Write-Host "Fetching advisories from $advisoriesUrl..." -ForegroundColor Cyan
    $response = Invoke-WebRequest -Uri $advisoriesUrl -UseBasicParsing -TimeoutSec 10
    $content = $response.Content
} catch {
    Write-Error "Failed to fetch page: $_"
    exit 1
}

# Split the content into advisory blocks
# Each advisory appears to be contained within a div or article
$blockPattern = '(?s)<div[^>]*class="[^"]*view-content[^"]*"[^>]*>(.*?)</div>\s*<div[^>]*class="[^"]*global-search--type--date[^"]*"[^>]*>.*?</div>'
$advisoryBlocks = [regex]::Matches($content, $blockPattern)

if ($advisoryBlocks.Count -eq 0) {
    # Alternative: Extract each advisory by finding date divs and looking backward for titles
    Write-Host "Using alternative parsing method..." -ForegroundColor Yellow
    
    # Find all date divs
    $dateDivs = [regex]::Matches($content, '<div[^>]*class="[^"]*global-search--type--date[^"]*"[^>]*>\s*Published:\s*(\d{2}/\d{2}/\d{4})\s*</div>')
    
    foreach ($dateDiv in $dateDivs) {
        $dateStr = $dateDiv.Groups[1].Value
        $datePosition = $dateDiv.Index
        
        # Look backwards for a link in the preceding content (within 1000 characters)
        $searchStart = [Math]::Max(0, $datePosition - 1000)
        $precedingContent = $content.Substring($searchStart, $datePosition - $searchStart)
        
        # Find the advisory link in preceding content
        $linkPattern = '<a\s+href="([^"]+)"[^>]*>[\s\S]*?<span[^>]*>[\s\S]*?<span>([^<]+)</span>'
        $linkMatch = [regex]::Match($precedingContent, $linkPattern)
        
        if ($linkMatch.Success) {
            $relativeLink = $linkMatch.Groups[1].Value
            $fullLink = "https://ccb.belgium.be" + $relativeLink
            $title = $linkMatch.Groups[2].Value.Trim()
            
            try {
                $publishedDate = [datetime]::ParseExact($dateStr, "dd/MM/yyyy", $null)
                
                # Process this advisory
                $dateOnly = $publishedDate.Date
                $cutoffDateOnly = $cutoffDate.Date
                
                if ($dateOnly -lt $cutoffDateOnly) {
                    Write-Host "✗ SKIPPED (older than 7 days - $($publishedDate.ToString('yyyy-MM-dd'))): $title" -ForegroundColor Red
                    continue
                }
                
                Write-Host "✓ Within date range ($($publishedDate.ToString('yyyy-MM-dd'))): $title" -ForegroundColor Green
                
                # Check if already sent
                if ($fullLink -in $sentLinks) {
                    Write-Host "  Already sent previously, skipping." -ForegroundColor Gray
                    continue
                }
                
                # Check for keywords
                $keywordMatched = $false
                foreach ($kw in $keywords) {
                    if ($title -match "(?i)$kw") {
                        Write-Host "  >>> MATCH FOUND for keyword '$kw'! Sending email..." -ForegroundColor Yellow
                        Send-AlertEmail -Keyword $kw -Title $title -Link $fullLink -PublishedDate $publishedDate
                        $sentLinks += $fullLink
                        $keywordMatched = $true
                        break
                    }
                }
                
                if (-not $keywordMatched) {
                    Write-Host "  No keyword match, skipping." -ForegroundColor Gray
                }
                
                Write-Host ""
                
            } catch {
                Write-Warning "Could not parse date: $dateStr"
            }
        }
    }
    
    # Save updated sent links
    $sentLinks | Set-Content $stateFile
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Complete! Checked advisories and sent emails for matching items." -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    
} else {
    # Original method if blocks are found
    Write-Host "Found $($advisoryBlocks.Count) advisory blocks" -ForegroundColor Green
    # ... rest of original processing would go here
}
