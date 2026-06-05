#!/usr/bin/env pwsh
<#
Reports PackageReferences that are NOT using Central Package Management:
  - Hard-coded Version="..." on a <PackageReference> (escapes CPM).
  - VersionOverride="..." on a <PackageReference> (deliberately overrides the central version).
  - PackageReference Include="..." for a package that has no entry in Directory.Packages.props.
  - PackageVersion entries in Directory.Packages.props that no project references (orphans).

Exits non-zero when any of the first three categories is non-empty.
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

function Get-TrackedCsprojFiles {
    param([string]$Root)
    Push-Location $Root
    try {
        return git ls-files '*.csproj' | ForEach-Object { Join-Path $Root $_ }
    } finally {
        Pop-Location
    }
}

$propsPath = Join-Path $RepoRoot 'Directory.Packages.props'
if (-not (Test-Path $propsPath)) {
    Write-Error "Directory.Packages.props not found at $propsPath"
    exit 2
}

$propsContent = Get-Content -Raw -LiteralPath $propsPath
$centralVersions = @{}
foreach ($m in [regex]::Matches($propsContent, '<PackageVersion\s+Include="(?<name>[^"]+)"\s+Version="(?<ver>[^"]+)"')) {
    $centralVersions[$m.Groups['name'].Value] = $m.Groups['ver'].Value
}

$csprojFiles = Get-TrackedCsprojFiles -Root $RepoRoot

$pinned       = @()  # <PackageReference Include=".." Version="..">
$overrides    = @()  # <PackageReference Include=".." VersionOverride="..">
$missing      = @()  # <PackageReference Include=".."> with no central PackageVersion
$referencedNames = New-Object 'System.Collections.Generic.HashSet[string]'

# Match a single <PackageReference ... /> or <PackageReference ...> opening tag, including line breaks within attributes.
$refRegex = [regex]'(?s)<PackageReference\s+(?<attrs>[^>]+?)\s*/?>'

foreach ($file in $csprojFiles) {
    $content = Get-Content -Raw -LiteralPath $file
    foreach ($m in $refRegex.Matches($content)) {
        $attrs = $m.Groups['attrs'].Value
        $nameMatch = [regex]::Match($attrs, 'Include="(?<name>[^"]+)"')
        if (-not $nameMatch.Success) { continue }
        $name = $nameMatch.Groups['name'].Value
        [void]$referencedNames.Add($name)

        $verMatch = [regex]::Match($attrs, '\bVersion="(?<ver>[^"]+)"')
        $ovMatch  = [regex]::Match($attrs, 'VersionOverride="(?<ver>[^"]+)"')

        if ($verMatch.Success) {
            $pinned += [pscustomobject]@{ File = $file; Package = $name; Version = $verMatch.Groups['ver'].Value }
        }
        if ($ovMatch.Success) {
            $central = if ($centralVersions.ContainsKey($name)) { $centralVersions[$name] } else { '<not central>' }
            $overrides += [pscustomobject]@{ File = $file; Package = $name; Override = $ovMatch.Groups['ver'].Value; Central = $central }
        }
        if (-not $centralVersions.ContainsKey($name)) {
            $missing += [pscustomobject]@{ File = $file; Package = $name }
        }
    }
}

$orphans = $centralVersions.Keys | Where-Object { -not $referencedNames.Contains($_) } | Sort-Object

function Show-Section {
    param([string]$Title, [object[]]$Rows, [string[]]$Columns, [System.ConsoleColor]$Color)
    Write-Host ""
    if (-not $Rows -or $Rows.Count -eq 0) {
        Write-Host "$Title : none" -ForegroundColor Green
        return
    }
    Write-Host "$Title ($($Rows.Count)):" -ForegroundColor $Color
    $rel = $Rows | ForEach-Object {
        $obj = [ordered]@{}
        foreach ($c in $Columns) {
            $val = $_.$c
            if ($c -eq 'File') { $val = (Resolve-Path -LiteralPath $val -Relative -ErrorAction SilentlyContinue) ?? $val }
            $obj[$c] = $val
        }
        [pscustomobject]$obj
    }
    $rel | Format-Table -AutoSize | Out-String | Write-Host
}

Push-Location $RepoRoot
try {
    Show-Section -Title 'Hard-coded Version (escaping CPM)' -Rows $pinned    -Columns @('File','Package','Version')          -Color Red
    Show-Section -Title 'VersionOverride (overriding CPM)'  -Rows $overrides -Columns @('File','Package','Override','Central') -Color Yellow
    Show-Section -Title 'Missing from Directory.Packages.props' -Rows $missing -Columns @('File','Package')                   -Color Red
} finally {
    Pop-Location
}

Write-Host ""
if (-not $orphans -or $orphans.Count -eq 0) {
    Write-Host "Orphan PackageVersion entries (declared but unused): none" -ForegroundColor Green
} else {
    Write-Host "Orphan PackageVersion entries (declared but unused) ($($orphans.Count)):" -ForegroundColor Yellow
    $orphans | ForEach-Object { Write-Host "  $_" }
}

Write-Host ""
$total = $pinned.Count + $overrides.Count + $missing.Count
if ($total -eq 0) {
    Write-Host "All PackageReferences use Central Package Management cleanly." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$total PackageReference issue(s) found." -ForegroundColor Red
    exit 1
}
