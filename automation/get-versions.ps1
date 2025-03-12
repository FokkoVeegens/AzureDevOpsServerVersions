#https://go.microsoft.com/fwlink/?LinkId=2200892
#https://aka.ms/devops2020.1.2patch4
#https://devblogs.microsoft.com/devops/now-available-azure-devops-server-2022-rtw/

$ErrorActionPreference = 'Break'
$regexRemoveHTML = '<[^>]+>'
$dataPath = "$($PSScriptRoot)/data"
$downloadFilePath = "$dataPath/azdo.exe"

function ConvertTo-Title($outerHTML) {
    return $outerHTML -replace '<[^>]+>',''
}

if (!(Test-Path -Path $dataPath -PathType Container)) {
    New-Item -Path $dataPath -ItemType Directory
}

$response = Invoke-WebRequest -uri "https://devblogs.microsoft.com/devops/march-patches-for-azure-devops-server-3/"
$downloadLinks = $response.Links | `
    Where-Object { $_.href -like "https://aka.ms/*" -and `
                    ((ConvertTo-Title -outerHTML $_.OuterHTML) -like "*Azure DevOps*" `
                        -or (ConvertTo-Title -outerHTML $_.OuterHTML) -like "*Patch*") `
                     -and `
                    (ConvertTo-Title -outerHTML $_.OuterHTML) -notlike "*ISO*"  } | Group-Object -Property href | ForEach-Object { $_.Group[0] }
foreach ($downloadLink in $downloadLinks) {
    $linkTitle = ConvertTo-Title -outerHTML $downloadLink.OuterHTML
    Write-Output -NoNewline "Processing $linkTitle"

    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -uri $downloadLink.href -OutFile $downloadFilePath
    $ProgressPreference = 'Continue'
    $FindResults = Select-String -Path $downloadFilePath -Pattern "P\u0000r\u0000o\u0000d\u0000u\u0000c\u0000t\u0000V\u0000e\u0000r\u0000s\u0000i\u0000o\u0000n\u0000\u0000\u0000.*?(\u0000\u0000\u0000\u0000\u0000D)"
    if ($FindResults.Matches.length -gt 0) {
        foreach ($match in $FindResults.Matches) {
            $cleanedMatch = $match -replace '\u0000'
            $versionNumber = ($cleanedMatch -replace 'ProductVersion') -replace 'D'
            Write-Host "Version: $versionNumber"
        }
    }
}