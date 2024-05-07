#https://go.microsoft.com/fwlink/?LinkId=2200892
#https://aka.ms/devops2020.1.2patch4
#https://devblogs.microsoft.com/devops/now-available-azure-devops-server-2022-rtw/

# Params
# body.primaryLink
$blogUrl = "https://devblogs.microsoft.com/devops/azure-devops-server-2022-update-2-rc-now-available/"
$downloadUrl = "https://go.microsoft.com/fwlink/?LinkId=2269844"
$downloadTitle = "2022.2 RC"
# body.publishDate
$publishDateString = "2024-05-07 18:00:00Z"


$publishDate = [datetime]$publishDateString
$culture = New-Object System.Globalization.CultureInfo("en-US")
$publishDateFormattedString = $publishDate.ToString("d-MMM-yyyy", $culture)

$ErrorActionPreference = 'Break'
$Global_RegexRemoveHTML = '<[^>]+>'
$dataPath = "$($PSScriptRoot)/data"
$downloadFilePath = "$dataPath/azdo.exe"

function ConvertTo-Title($outerHTML) {
    return $outerHTML -replace $Global_RegexRemoveHTML,''
}

function Process-DownloadLink($downloadLinkHref, $linkTitle, $apiVersions) {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -uri $downloadLinkHref -OutFile $downloadFilePath
    $ProgressPreference = 'Continue'
    $FindResults = Select-String -Path $downloadFilePath -Pattern "P\u0000r\u0000o\u0000d\u0000u\u0000c\u0000t\u0000V\u0000e\u0000r\u0000s\u0000i\u0000o\u0000n\u0000\u0000\u0000.*?(\u0000\u0000\u0000\u0000\u0000D)"
    $markDownResult = ""
    if ($FindResults.Matches.length -gt 0) {
        if ($FindResults.Matches.length -gt 1) {
            Write-Warning "Multiple matches found for $linkTitle"
        }
        foreach ($match in $FindResults.Matches) {
            $cleanedMatch = $match -replace '\u0000'
            $versionNumber = ($cleanedMatch -replace 'ProductVersion') -replace 'D'

            $apiVersionEntry = $apiVersions | Where-Object { $_.ProductVersion -le $versionNumber } | Sort-Object -Descending | Select-Object -First 1
            if ($apiVersionEntry) {
                $markDownResult += "||$($linkTitle)|$($versionNumber)|$($apiVersionEntry.ApiVersion)|$($publishDateFormattedString)|$($blogUrl)|`n"
            }
            else {
                $markDownResult += "||$($linkTitle)|$($versionNumber)||$($publishDateFormattedString)|$($blogUrl)|`n"
            }
            Write-Host "Version: $versionNumber"
            break
        }
    }
    return $markDownResult
}

if (!(Test-Path -Path $dataPath -PathType Container)) {
    $null = New-Item -Path $dataPath -ItemType Directory
}
else {
    Remove-Item -Path $dataPath/* -Recurse -Force
}

$response = Invoke-WebRequest -uri $blogUrl
$downloadLinks = $response.Links | `
    Where-Object { (`
                        $_.href -like "https://aka.ms/*" -and `
                        (ConvertTo-Title -outerHTML $_.OuterHTML) -like "*Azure DevOps*" -and `
                        (ConvertTo-Title -outerHTML $_.OuterHTML) -notlike "*ISO*"`
                    ) -or `
                    (`
                        $_.href -like "https://go.microsoft.com/*" -and `
                        (ConvertTo-Title -outerHTML $_.OuterHTML) -like "*Web Install*" `
                    )  } | Group-Object -Property href | ForEach-Object { $_.Group[0] }

$apiVersions = Get-Content -Path "$($PSScriptRoot)/api-versions.json" | ConvertFrom-Json
$apiVersions | ForEach-Object { $_.ProductVersion = [System.Version]$_.ProductVersion }

$markDown = ""
if (!$downloadUrl) {
    foreach ($downloadLink in $downloadLinks) {
        $linkTitle = (ConvertTo-Title -outerHTML $downloadLink.OuterHTML) -replace "Azure DevOps Server "
        Write-Output "Processing $linkTitle"
        $markDown += Process-DownloadLink -downloadLinkHref $downloadLink.href -linkTitle $linkTitle -apiVersions $apiVersions
    }
}
else {
    $markDown += Process-DownloadLink -downloadLinkHref $downloadUrl -linkTitle $downloadTitle -apiVersions $apiVersions
}

Write-Host $markDown
Set-Clipboard -Value $markDown
