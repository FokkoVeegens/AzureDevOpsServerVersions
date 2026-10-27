$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "azdo-versions-$([guid]::NewGuid())"
$null = New-Item -Path $testRoot -ItemType Directory

function Assert-Equal($actual, $expected) {
    if ($actual -cne $expected) {
        throw "Expected '$expected', got '$actual'."
    }
}

function Assert-Throws([scriptblock]$action, [string]$messagePattern) {
    try {
        & $action
    }
    catch {
        if ($_.Exception.Message -notlike $messagePattern) {
            throw
        }
        return
    }
    throw "Expected an error matching '$messagePattern'."
}

function New-Link($href, $title) {
    [PSCustomObject]@{ href = $href; OuterHTML = "<a href='$href'>$title</a>" }
}

function Invoke-WebRequest($Uri, $OutFile) {
    $requests.Add([string]$Uri)
    if ($OutFile) {
        Assert-Equal $Uri $expectedDownload
        switch ($downloadMode) {
            'failure' { throw 'Simulated HTTP 503' }
            'html' { Set-Content -Path $OutFile -Value '<html>Not an installer</html>' }
            default { Copy-Item -Path $fixture -Destination $OutFile -Force }
        }
    }
    elseif ($Uri -eq $blogUrl) {
        [PSCustomObject]@{ Links = $blogLinks }
    }
    elseif ($Uri -eq $learnUrl) {
        [PSCustomObject]@{ Content = $downloadHtml }
    }
    else {
        throw "Unexpected request: $Uri"
    }
}

function Get-TestRows {
    & (Join-Path $testRoot 'get-versions.ps1') -BlogUrl $blogUrl -PublishDateString '2026-10-27 20:31:59Z'
}

try {
    Copy-Item -Path (Join-Path $PSScriptRoot 'get-versions.ps1'), (Join-Path $PSScriptRoot 'process-issue.ps1'), (Join-Path $PSScriptRoot 'api-versions.json') -Destination $testRoot
    $fixture = Join-Path $testRoot 'installer.exe'
    $versionStrings = [string]::Join([char]0, @('FileVersion', '', '1.2.3.4', 'ProductVersion', '', '20.0.37715.1', 'Other'))
    [System.IO.File]::WriteAllBytes($fixture, [System.Text.Encoding]::Unicode.GetBytes($versionStrings))

    $blogUrl = 'https://devblogs.microsoft.com/devops/test-release/'
    $learnUrl = 'https://learn.microsoft.com/azure/devops/server/download/azuredevopsserver?view=azure-devops#download-the-latest-release'
    $expectedDownload = 'https://go.microsoft.com/fwlink/?LinkId=2383605&test=1'
    $requests = [System.Collections.Generic.List[string]]::new()
    $downloadMode = 'valid'
    $blogLinks = @(
        (New-Link $learnUrl 'download Azure DevOps Server RC (26H2)')
        (New-Link $learnUrl 'download Azure DevOps Server RC (26H2)')
    )
    $downloadHtml = @'
<table>
<tr><td><strong>Azure DevOps Server RC (26H2)</strong></td><td></td><td></td></tr>
<tr><td>Azure DevOps Server Express RC (26H2)</td><td><a href="https://go.microsoft.com/express">EXE</a></td></tr>
<tr><td>Azure DevOps Server</td><td><a href="https://go.microsoft.com/ga">EXE</a></td></tr>
<tr><td>Azure DevOps Server RC&nbsp;(26H2)</td>
<td><a data-linktype="external" href="https://go.microsoft.com/fwlink/?LinkId=2383605&amp;test=1">EXE</a></td>
<td><a href="https://go.microsoft.com/iso">ISO</a></td></tr>
</table>
'@
    $expectedRow = "||RC (26H2)|20.0.37715.1|7.2|27-Oct-2026|$blogUrl|"
    Assert-Equal (Get-TestRows).Trim() $expectedRow
    Assert-Equal $requests.Count 3
    Write-Host 'PASS: Learn discovery selects only the matching EXE and deduplicates links.'

    foreach ($localizedUrl in @(
        'https://learn.microsoft.com/en-us/azure/devops/server/download/azuredevopsserver?view=azure-devops#download-the-latest-release',
        'https://learn.microsoft.com/nl-nl/azure/devops/server/download/azuredevopsserver?view=azure-devops'
    )) {
        $learnUrl = $localizedUrl
        $blogLinks = @((New-Link $learnUrl 'download Azure DevOps Server RC (26H2)'))
        $requests.Clear()
        Assert-Equal (Get-TestRows).Trim() $expectedRow
        Assert-Equal $requests.Count 3
    }
    Write-Host 'PASS: Localized Learn download links (e.g. /en-us/azure/devops/...) are discovered.'

    $readmePath = Join-Path $testRoot 'README.md'
    Set-Content -Path $readmePath -Value "# Azure DevOps Server`n`n||Public version number|Semantic Version Number|Rest API Version|Release Date|Announcement URL|`n|-|-|-|-|-|-|`n||Existing|20.0.36719.1|7.2|9-Dec-2025|old|"
    & (Join-Path $testRoot 'process-issue.ps1') -IssueBody "Hyperlink: $blogUrl`nPublish date: 2026-10-27 20:31:59Z" -RepoRoot $testRoot
    $readmeLines = Get-Content $readmePath
    Assert-Equal $readmeLines[4] $expectedRow
    Assert-Equal $readmeLines[5] '||Existing|20.0.36719.1|7.2|9-Dec-2025|old|'
    Write-Host 'PASS: Issue processing inserts the generated row and preserves existing rows.'

    $expectedDownload = 'https://aka.ms/devops2022.2patch11'
    $blogLinks = @(
        (New-Link $expectedDownload 'Download patch')
        (New-Link $expectedDownload 'Download patch')
        (New-Link 'https://aka.ms/devops2022.2iso' 'ISO')
    )
    $requests.Clear()
    Assert-Equal (Get-TestRows).Trim() "||2022.2 Patch 11|20.0.37715.1|7.2|27-Oct-2026|$blogUrl|"
    Assert-Equal $requests.Count 2
    Write-Host 'PASS: Direct patch links, URL-derived titles, deduplication, and ISO exclusion are preserved.'

    $expectedDownload = 'https://go.microsoft.com/fwlink/?LinkId=123'
    $blogLinks = @((New-Link $expectedDownload 'Azure DevOps Server 2022.2 Web Install'))
    Assert-Equal (Get-TestRows).Trim() "||2022.2 Web Install|20.0.37715.1|7.2|27-Oct-2026|$blogUrl|"
    Write-Host 'PASS: Direct web installer links are preserved.'

    $requests.Clear()
    $result = & (Join-Path $testRoot 'get-versions.ps1') -BlogUrl $blogUrl -PublishDateString '2026-10-27 20:31:59Z' -DownloadUrl $expectedDownload -DownloadTitle 'RC'
    Assert-Equal $result.Trim() "||RC|20.0.37715.1|7.2|27-Oct-2026|$blogUrl|"
    Assert-Equal $requests.Count 1
    Write-Host 'PASS: Explicit installer URLs bypass blog fetching.'

    $versionStrings = [string]::Join([char]0, @('ProductVersion', '', '19.235.37517.2', 'Other'))
    [System.IO.File]::WriteAllBytes($fixture, [System.Text.Encoding]::Unicode.GetBytes($versionStrings))
    Assert-Equal (Get-TestRows).Trim() "||2022.2 Web Install|19.235.37517.2|7.1|27-Oct-2026|$blogUrl|"
    Write-Host 'PASS: Older installers use their matching API version.'

    $versionStrings = [string]::Join([char]0, @('ProductVersion', '', '1.0.0.0', 'Other'))
    [System.IO.File]::WriteAllBytes($fixture, [System.Text.Encoding]::Unicode.GetBytes($versionStrings))
    Assert-Equal (Get-TestRows).Trim() "||2022.2 Web Install|1.0.0.0||27-Oct-2026|$blogUrl|"
    Write-Host 'PASS: Unmapped API versions retain the existing blank-cell behavior.'

    $versionStrings = [string]::Join([char]0, @('ProductVersion', '', '20.0.invalid.1', 'Other'))
    [System.IO.File]::WriteAllBytes($fixture, [System.Text.Encoding]::Unicode.GetBytes($versionStrings))
    Assert-Throws { Get-TestRows } '*No valid ProductVersion found*'
    Write-Host 'PASS: Malformed product versions are rejected.'

    $downloadMode = 'failure'
    Assert-Throws { Get-TestRows } '*Simulated HTTP 503*'
    Write-Host 'PASS: Failed downloads terminate instead of reading a stale installer.'

    $downloadMode = 'html'
    Assert-Throws { Get-TestRows } '*No valid ProductVersion found*'
    Write-Host 'PASS: Non-installer responses produce an explicit version-metadata error.'

    $downloadMode = 'valid'
    $blogLinks = @((New-Link $learnUrl 'download Azure DevOps Server Missing Release'))
    $requests.Clear()
    Assert-Throws { Get-TestRows } '*No matching EXE download links found*'
    Assert-Equal $requests.Count 2
    Write-Host 'PASS: Unmatched product names never fall back to another release.'

    $blogLinks = @()
    Assert-Throws { Get-TestRows } '*No matching EXE download links found*'
    Write-Host 'PASS: Missing installer links produce an explicit discovery error.'

    Write-Host 'All version extraction regression checks passed.'
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
