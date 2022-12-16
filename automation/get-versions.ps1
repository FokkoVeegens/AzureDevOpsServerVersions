#https://go.microsoft.com/fwlink/?LinkId=2200892
#https://aka.ms/devops2020.1.2patch4

$ErrorActionPreference = 'Break'

$response = Invoke-WebRequest -uri "https://devblogs.microsoft.com/devops/december-patches-for-azure-devops-server-2/"
$downloadLinks = $response.Links | Where-Object { $_.href -like "https://aka.ms*" }
foreach ($downloadLink in $downloadLinks) {
    $linkTitle = $downloadLink.OuterHTML -replace '<[^>]+>',''
    Write-Output "Processing $linkTitle"

    Invoke-WebRequest -uri $downloadLink.href -OutFile "./data/azdo.exe"
    $azDoVersionInfo = (Get-Item "./data/azdo.exe").VersionInfo
    if ($azDoVersionInfo | Get-Member | Where-Object { $_.Name -eq "ProductVersion" }) {
        Write-Output "File found"
        $azDoVersion = $azDoVersionInfo.ProductVersion
        Write-Output "$linkTitle has version $azDoVersion"
    }
    else {
        Write-Output "No file found in link"
    }
}