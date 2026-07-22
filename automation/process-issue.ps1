param(
    [Parameter(Mandatory=$true)]
    [string]$IssueBody,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path "$PSScriptRoot/..").Path
}

# Parse issue body for blog URL and publish date
if ($IssueBody -match 'Hyperlink:\s*\[?((https://devblogs\.microsoft\.com/devops/[^\s\)\]]+))') {
    $blogUrl = $Matches[1]
}
else {
    Write-Error "Could not extract blog URL from issue body"
    exit 1
}

if ($IssueBody -match 'Publish date:\s*(\d{4}-\d{2}-\d{2}\s*\d{2}:\d{2}:\d{2}Z?)') {
    $publishDateString = $Matches[1]
}
else {
    Write-Error "Could not extract publish date from issue body"
    exit 1
}

Write-Host "Blog URL: $blogUrl"
Write-Host "Publish date: $publishDateString"

# Run get-versions.ps1 to extract version information from download binaries
$markdownOutput = & "$PSScriptRoot/get-versions.ps1" -BlogUrl $blogUrl -PublishDateString $publishDateString

if (-not $markdownOutput) {
    Write-Error "No output from get-versions.ps1"
    exit 1
}

# Parse output into individual markdown table rows
$rows = $markdownOutput -split "`n" | Where-Object { $_ -match '^\|' }

if ($rows.Count -eq 0) {
    Write-Error "No version rows were generated"
    exit 1
}

Write-Host "Generated $($rows.Count) version row(s)"

# Map a public version title to its README section header
function Get-SectionHeader($title) {
    if ($title -match '^(\d{4})') {
        $year = [int]$Matches[1]
        if ($year -ge 2019) {
            return "# Azure DevOps Server $year"
        }
        else {
            return "# Team Foundation Server $year"
        }
    }
    else {
        # No year prefix (e.g. "Patch 6", "GA", "RC") = newest Azure DevOps Server
        return "# Azure DevOps Server"
    }
}

# Read README.md
$readmePath = Join-Path $RepoRoot "README.md"
$readmeLines = Get-Content -Path $readmePath

# Group rows by their target section
$rowsBySection = [ordered]@{}
foreach ($row in $rows) {
    $fields = $row -split '\|'
    $title = $fields[2].Trim()
    $sectionHeader = Get-SectionHeader $title
    if (-not $rowsBySection.Contains($sectionHeader)) {
        $rowsBySection[$sectionHeader] = @()
    }
    $rowsBySection[$sectionHeader] += $row
    Write-Host "  '$title' -> section '$sectionHeader'"
}

# Find insertion point for each section (right after the table separator row |-|-|...)
$insertions = @()
foreach ($section in $rowsBySection.Keys) {
    $sectionFound = $false
    $insertIndex = -1

    for ($i = 0; $i -lt $readmeLines.Count; $i++) {
        if ($readmeLines[$i].Trim() -eq $section) {
            $sectionFound = $true
        }
        if ($sectionFound -and $readmeLines[$i] -match '^\|-') {
            $insertIndex = $i + 1
            break
        }
    }

    if ($insertIndex -eq -1) {
        Write-Warning "Could not find section '$section' in README.md - skipping"
        continue
    }

    $insertions += [PSCustomObject]@{
        Index   = $insertIndex
        Rows    = $rowsBySection[$section]
        Section = $section
    }
}

if ($insertions.Count -eq 0) {
    Write-Error "No valid sections found for insertion"
    exit 1
}

# Insert from bottom to top to preserve line numbers
$insertions = $insertions | Sort-Object -Property Index -Descending

foreach ($insertion in $insertions) {
    Write-Host "Inserting $($insertion.Rows.Count) row(s) into '$($insertion.Section)' at line $($insertion.Index + 1)"
    $before = $readmeLines[0..($insertion.Index - 1)]
    $after = if ($insertion.Index -lt $readmeLines.Count) {
        $readmeLines[$insertion.Index..($readmeLines.Count - 1)]
    }
    else { @() }
    $readmeLines = @($before) + @($insertion.Rows) + @($after)
}

# Write updated README.md
$readmeLines | Set-Content -Path $readmePath -Encoding UTF8
Write-Host "README.md updated successfully"
