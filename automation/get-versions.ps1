#https://go.microsoft.com/fwlink/?LinkId=2200892
#https://aka.ms/devops2020.1.2patch4
#https://devblogs.microsoft.com/devops/now-available-azure-devops-server-2022-rtw/

param(
    [Parameter(Mandatory=$true)]
    [string]$BlogUrl,
    [Parameter(Mandatory=$true)]
    [string]$PublishDateString,
    [string]$DownloadUrl,
    [string]$DownloadTitle
)

$publishDate = [datetime]$PublishDateString
$culture = New-Object System.Globalization.CultureInfo("en-US")
$publishDateFormattedString = $publishDate.ToString("d-MMM-yyyy", $culture)

$ErrorActionPreference = 'Stop'
$Global_RegexRemoveHTML = '<[^>]+>'
$dataPath = "$($PSScriptRoot)/data"
$downloadFilePath = "$dataPath/azdo.exe"

function ConvertTo-Title($outerHTML) {
    return ([System.Net.WebUtility]::HtmlDecode(($outerHTML -replace $Global_RegexRemoveHTML,'')) -replace '\s+', ' ').Trim()
}

function Get-LearnDownloadLinks($response) {
    $downloadPages = $response.Links | Where-Object {
        $_.href -match '^https://learn\.microsoft\.com/(?:[a-z]{2}(?:-[a-z]+)?/)?azure/devops/server/download/' -and
        (ConvertTo-Title $_.OuterHTML) -match 'Azure DevOps Server'
    } | Group-Object -Property href, OuterHTML | ForEach-Object { $_.Group[0] }

    foreach ($page in $downloadPages) {
        $productTitle = (ConvertTo-Title $page.OuterHTML) -replace '^download\s+', ''
        Write-Host "Looking for '$productTitle' on $($page.href)"
        $downloadPage = Invoke-WebRequest -Uri $page.href
        foreach ($row in [regex]::Matches($downloadPage.Content, '(?is)<tr\b[^>]*>.*?</tr>')) {
            $cells = [regex]::Matches($row.Value, '(?is)<td\b[^>]*>(.*?)</td>')
            if ($cells.Count -lt 2 -or (ConvertTo-Title $cells[0].Groups[1].Value) -ne $productTitle) {
                continue
            }

            $exeLink = [regex]::Match($cells[1].Groups[1].Value, '(?is)<a\b[^>]*href=["''](?<url>https://go\.microsoft\.com/[^"'']+)["''][^>]*>\s*EXE\s*</a>')
            if ($exeLink.Success) {
                [PSCustomObject]@{
                    href = [System.Net.WebUtility]::HtmlDecode($exeLink.Groups['url'].Value)
                    OuterHTML = $productTitle
                }
            }
        }
    }
}

function Process-DownloadLink($downloadLinkHref, $linkTitle, $apiVersions) {
    $ProgressPreference = 'SilentlyContinue'
    Write-Host "Downloading $downloadLinkHref"
    Invoke-WebRequest -uri $downloadLinkHref -OutFile $downloadFilePath
    # Native Windows version metadata is UTF-16LE; FileVersionInfo cannot read native EXEs on Unix.
    $binaryText = [System.Text.Encoding]::Unicode.GetString([System.IO.File]::ReadAllBytes($downloadFilePath))
    $versionMatch = [regex]::Match($binaryText, 'ProductVersion\0+(?<version>\d+\.\d+\.\d+\.\d+)\0')
    if (-not $versionMatch.Success) {
        throw "No valid ProductVersion found in installer '$downloadLinkHref' for '$linkTitle'."
    }
    $versionNumber = $versionMatch.Groups['version'].Value

    $apiVersionEntry = $apiVersions | Where-Object { $_.ProductVersion -le [System.Version]$versionNumber } |
        Sort-Object -Property ProductVersion -Descending | Select-Object -First 1
    Write-Host "Version: $versionNumber"
    return "||$($linkTitle)|$($versionNumber)|$($apiVersionEntry.ApiVersion)|$($publishDateFormattedString)|$($blogUrl)|`n"
}

if (!(Test-Path -Path $dataPath -PathType Container)) {
    $null = New-Item -Path $dataPath -ItemType Directory
}
if (!$downloadUrl) {
    $response = Invoke-WebRequest -uri $blogUrl
    $downloadLinks = @($response.Links | Where-Object {
        (
            $_.href -match '^https://aka\.ms/devops(server|20\d{2})' -and
            (ConvertTo-Title -outerHTML $_.OuterHTML) -notlike "*ISO*"
        ) -or (
            $_.href -like "https://aka.ms/*" -and
            (ConvertTo-Title -outerHTML $_.OuterHTML) -like "*Azure DevOps*" -and
            (ConvertTo-Title -outerHTML $_.OuterHTML) -notlike "*ISO*"
        ) -or (
            $_.href -like "https://go.microsoft.com/*" -and
            (ConvertTo-Title -outerHTML $_.OuterHTML) -like "*Web Install*"
        )
    } | Group-Object -Property href | ForEach-Object { $_.Group[0] })

    if ($downloadLinks.Count -eq 0) {
        $downloadLinks = @(Get-LearnDownloadLinks $response | Group-Object -Property href | ForEach-Object { $_.Group[0] })
    }
    if ($downloadLinks.Count -eq 0) {
        throw "No matching EXE download links found in '$blogUrl' or its linked Microsoft Learn download pages."
    }
}

$apiVersions = Get-Content -Path "$($PSScriptRoot)/api-versions.json" | ConvertFrom-Json
$apiVersions | ForEach-Object { $_.ProductVersion = [System.Version]$_.ProductVersion }

$markDown = ""
if (!$downloadUrl) {
    foreach ($downloadLink in $downloadLinks) {
        $linkText = ConvertTo-Title -outerHTML $downloadLink.OuterHTML
        if ($linkText -like "*Azure DevOps*") {
            $linkTitle = $linkText -replace "Azure DevOps Server "
        } else {
            # Extract version title from URL (e.g. aka.ms/devops2022.2patch11 -> "2022.2 Patch 11")
            $urlSegment = ($downloadLink.href -split '/')[-1]
            if ($urlSegment -match '^devopsserver(.+)$') {
                $linkTitle = ($Matches[1] -creplace 'patch', ' Patch ').Trim()
            }
            elseif ($urlSegment -match '^devops(\d.+)$') {
                $linkTitle = ($Matches[1] -creplace 'patch', ' Patch ').Trim()
            }
            else {
                $linkTitle = $linkText
            }
        }
        Write-Host "Processing $linkTitle"
        $markDown += Process-DownloadLink -downloadLinkHref $downloadLink.href -linkTitle $linkTitle -apiVersions $apiVersions
    }
}
else {
    $markDown += Process-DownloadLink -downloadLinkHref $downloadUrl -linkTitle $downloadTitle -apiVersions $apiVersions
}

Write-Output $markDown
