#https://go.microsoft.com/fwlink/?LinkId=2200892
#https://aka.ms/devops2020.1.2patch4
#https://devblogs.microsoft.com/devops/now-available-azure-devops-server-2022-rtw/

$ErrorActionPreference = 'Break'
$regexRemoveHTML = '<[^>]+>'

function ConvertTo-Title($outerHTML) {
    return $outerHTML -replace '<[^>]+>',''
}

$response = Invoke-WebRequest -uri "https://devblogs.microsoft.com/devops/now-available-azure-devops-server-2022-rtw/"
$downloadLinks = $response.Links | `
    Where-Object { ($_.href -like "https://aka.ms/*" -or `
                    $_.href -like "https://go.microsoft.com/*") -and `
                    (ConvertTo-Title -outerHTML $_.OuterHTML) -like "*Azure DevOps*" -and `
                    (ConvertTo-Title -outerHTML $_.OuterHTML) -notlike "*ISO*"  }
foreach ($downloadLink in $downloadLinks) {
    $linkTitle = ConvertTo-Title -outerHTML $downloadLink.OuterHTML
    Write-Output "Processing $linkTitle"

    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -uri $downloadLink.href -OutFile "./data/azdo.exe"
    $ProgressPreference = 'Continue'
    $azDoVersionInfo = (Get-Item "./data/azdo.exe").VersionInfo
    if ($azDoVersionInfo | Get-Member | Where-Object { $_.Name -eq "ProductVersion" }) {
        $azDoVersion = $azDoVersionInfo.ProductVersion
        Write-Output "$linkTitle has version $azDoVersion"
    }
    else {
        Write-Output "No file found in link"
    }
}