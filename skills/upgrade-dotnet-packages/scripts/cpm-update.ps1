#!/usr/bin/env pwsh
<#
Updates PackageVersion entries in Directory.Packages.props using the NuGet v3 API.

Rules:
  - All packages: cross-major bumps are ALLOWED. The candidate list is ordered
    highest-first across all majors, so we always prefer the newest version that
    satisfies the constraints below.
  - A candidate is rejected if it has no asset compatible with the project's TFM
    (e.g. net10.0-only packages are skipped for a net9.0 project).
  - A candidate is rejected if every transitive dependency declared by the candidate's
    .nuspec is not satisfied by what we already pin centrally (no NU1605 downgrades).
  - Pre-release versions are skipped UNLESS the current version is itself pre-release
    (e.g. "1.34.0-alpha"), in which case pre-release candidates are also allowed.
  - For every package, a candidate is rejected if it would cause an NU1605
    package-downgrade error: the candidate's .nuspec declares a dependency on
    another centrally-pinned package at a LOWER version than the candidate requires.
    The script falls back to the next-lower candidate until one fits, or stays put.
  - Packages already on the latest compatible version are left alone.

Usage:
  pwsh ./scripts/cpm-update.ps1                 # apply updates in-place
  pwsh ./scripts/cpm-update.ps1 -DryRun         # report only, do not write
  pwsh ./scripts/cpm-update.ps1 -PropsPath X    # custom path to Directory.Packages.props
  pwsh ./scripts/cpm-update.ps1 -Throttle 32    # parallel HTTP fan-out (default 16)
#>

[CmdletBinding()]
param(
    # Path to Directory.Packages.props. When omitted, the script walks up from its own
    # location to find the nearest Directory.Packages.props (so it works regardless of
    # where the script lives in the repo — e.g. relocated under .claude/skills/...).
    [string]$PropsPath,
    [switch]$DryRun,
    [int]$Throttle = 16,
    # Project target framework. Candidates must ship a compatible asset (matching netX.Y
    # or any netstandard / "any"). Auto-detected from any *.Common.props if present.
    [string]$TargetFramework,
    # Path to the .sln/.slnf used for the post-update build validation. Set to ''
    # to skip (faster but won't catch issues NuGet metadata can't predict — e.g.
    # ABI breaks within a "compatible" netstandard asset, like System.ServiceModel.*
    # repackaging across majors).
    [string]$ValidateTarget,
    [int]$ValidateMaxRounds = 6
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "PowerShell 7+ required (current: $($PSVersionTable.PSVersion)). Parallel fan-out uses ForEach-Object -Parallel."
    exit 2
}

# --- Resolve PropsPath -----------------------------------------------------------------
# If not supplied, walk up from the script's directory to find the nearest
# Directory.Packages.props. This is robust to the script being relocated anywhere in
# the repo (it no longer assumes the props file is exactly one level up).
if (-not $PropsPath) {
    $dir = $PSScriptRoot
    while ($dir) {
        $probe = Join-Path $dir 'Directory.Packages.props'
        if (Test-Path -LiteralPath $probe) { $PropsPath = $probe; break }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    if (-not $PropsPath) {
        Write-Error "Could not auto-locate Directory.Packages.props by walking up from $PSScriptRoot. Pass -PropsPath explicitly."
        exit 2
    }
}
# Normalize to an absolute path so relative inputs (e.g. -PropsPath Directory.Packages.props)
# resolve against the caller's cwd and never reach downstream cmdlets as an empty/unresolved
# string (which otherwise surfaces as a cryptic "LiteralPath ... empty string" binding error).
$resolvedProps = Resolve-Path -LiteralPath $PropsPath -ErrorAction SilentlyContinue
if (-not $resolvedProps) {
    Write-Error "Directory.Packages.props not found at '$PropsPath' (resolved against '$($PWD.Path)')."
    exit 2
}
$PropsPath = $resolvedProps.Path

# --- Resolve ValidateTarget ------------------------------------------------------------
# Normalize to absolute when supplied; a relative target would otherwise be evaluated
# against an unexpected cwd by `dotnet restore/build`.
if ($ValidateTarget) {
    $resolvedTarget = Resolve-Path -LiteralPath $ValidateTarget -ErrorAction SilentlyContinue
    if (-not $resolvedTarget) {
        Write-Error "Validation target not found at '$ValidateTarget' (resolved against '$($PWD.Path)')."
        exit 2
    }
    $ValidateTarget = $resolvedTarget.Path
}

# Auto-detect the project's TFM by scanning any *.Common.props next to
# Directory.Packages.props (project-name-agnostic).
if (-not $TargetFramework) {
    $propsDir = Split-Path -Parent $PropsPath
    $candidates = Get-ChildItem -LiteralPath $propsDir -Filter '*.Common.props' -File -ErrorAction SilentlyContinue
    foreach ($candidate in $candidates) {
        $commonContent = Get-Content -Raw -LiteralPath $candidate.FullName
        $tfmMatch = [regex]::Match($commonContent, '<TargetFramework[^>]*>([^<]+)</TargetFramework>')
        if ($tfmMatch.Success) {
            $val = $tfmMatch.Groups[1].Value.Trim()
            $tfmInline = [regex]::Match($val, '(net\d+\.\d+|netstandard\d+\.\d+|netcoreapp\d+\.\d+|net\d{3,})')
            if ($tfmInline.Success) { $TargetFramework = $tfmInline.Value; break }
        }
    }
}
if (-not $TargetFramework) {
    Write-Host 'Could not auto-detect TargetFramework — TFM compatibility check disabled.' -ForegroundColor Yellow
    $TargetFramework = ''
}
if ($TargetFramework) {
    Write-Host "Project TFM: $TargetFramework" -ForegroundColor DarkCyan
}

# --- NuGet service index discovery ---------------------------------------------------
$nugetIndexUrl = 'https://api.nuget.org/v3/index.json'
try {
    $serviceIndex = Invoke-RestMethod -Uri $nugetIndexUrl -Method Get
} catch {
    Write-Error "Failed to fetch NuGet service index: $_"
    exit 2
}

$flatContainerBase = ($serviceIndex.resources |
    Where-Object { $_.'@type' -eq 'PackageBaseAddress/3.0.0' } |
    Select-Object -First 1).'@id'

if (-not $flatContainerBase) {
    Write-Error 'Could not locate PackageBaseAddress/3.0.0 endpoint in NuGet service index.'
    exit 2
}
$flatContainerBase = $flatContainerBase.TrimEnd('/')

# --- Read props (single regex pass) -------------------------------------------------
$propsContent = Get-Content -Raw -LiteralPath $PropsPath
$entries = foreach ($m in [regex]::Matches($propsContent, '<PackageVersion\s+Include="(?<name>[^"]+)"\s+Version="(?<ver>[^"]+)"\s*/>')) {
    [pscustomobject]@{
        Name    = $m.Groups['name'].Value
        Version = $m.Groups['ver'].Value
        Match   = $m.Value
    }
}

if (-not $entries -or $entries.Count -eq 0) {
    Write-Host 'No <PackageVersion> entries found.' -ForegroundColor Yellow
    exit 0
}

# Map of centrally pinned package -> version string. Workers use this to detect
# whether a candidate's .nuspec demands a higher minimum than our pin (NU1605).
$pinnedMap = @{}
foreach ($e in $entries) { $pinnedMap[$e.Name] = $e.Version }

Write-Host "Checking $($entries.Count) packages against nuget.org (parallel x$Throttle)..." -ForegroundColor Cyan

# --- Parallel fan-out (with fixed-point iteration) ----------------------------------
# Each worker:
#   1. Fetches the package version index (one HTTP, cached across rounds).
#   2. Builds the candidate list (same major or cross-major for Microsoft/System).
#   3. Walks candidates highest-first; for each, fetches the .nuspec (one HTTP,
#      cached across rounds) and checks transitive constraints against $pinnedMap.
#      Accepts the first that fits.
#
# Constraint resolution between sibling updates (e.g. Microsoft.IdentityModel.Tokens
# bumps to 8.18.0 -> System.IdentityModel.Tokens.Jwt 8.18.0 then becomes acceptable)
# requires multiple rounds. Each round uses the previous round's accepted versions
# as the new pinned map. We iterate until no new updates are accepted (fixed point).
# Pinned versions only ever increase, so convergence is guaranteed and usually 2-3
# rounds is enough.
$maxRounds = 8
$round = 0
$accepted = @{}     # Name -> latest accepted result (pscustomobject)
$originalVersion = @{}     # Name -> version at script entry, for display
foreach ($e in $entries) { $originalVersion[$e.Name] = $e.Version }

# Anchors: peer packages whose published binary was compiled against a specific version
# of another centrally-pinned package. Used as upper-bound guard so we don't bump the
# dependency past what its peer was built against (catches ABI breaks like a base class
# adding an abstract method that the peer doesn't override).
#
# Example: linq2db.EntityFrameworkCore 8.1.0 declares dep on linq2db 5.4.0. While we
# keep EFCore at 8.1.0, linq2db must stay at 5.4.x and not bump beyond 5.4.0, since
# linq2db 5.4.1 added an abstract Quote() that EFCore 8.1.0's subclass doesn't override.
#
# Built lazily and refreshed every round (anchors shift as anchors themselves get bumped).
# Map shape: { dependencyId -> [ pscustomobject{ AnchorId; AnchorVersion; PinnedAtMin } ] }
$anchorCache = @{}     # name@version -> nuspec deps array (memoized HTTP)
function Get-AnchorMap {
    param([hashtable]$pinned, [string]$base, $projectTfm)
    $map = @{}
    foreach ($anchorId in $pinned.Keys) {
        $anchorVer = $pinned[$anchorId]
        $cacheKey = "$anchorId@$anchorVer"
        if (-not $anchorCache.ContainsKey($cacheKey)) {
            $anchorCache[$cacheKey] = (Get-NuspecDeps $base $anchorId $anchorVer $projectTfm)
        }
        foreach ($d in $anchorCache[$cacheKey]) {
            if (-not $pinned.ContainsKey($d.Id)) { continue }
            if (-not $map.ContainsKey($d.Id)) { $map[$d.Id] = @() }
            $map[$d.Id] += [pscustomobject]@{
                AnchorId      = $anchorId
                AnchorVersion = $anchorVer
                PinnedAtMin   = $d.MinVersion
            }
        }
    }
    return $map
}

# Lightweight nuspec dep extractor used only to build the anchor map (parent scope).
# Same compatibility rules as the worker's Get-NuspecInfo: only deps from compatible
# <group> entries are included, so we don't false-positive on net10.0-only deps.
function Get-NuspecDeps {
    param([string]$base, [string]$id, [string]$version, $projectTfm)
    $idLower = $id.ToLowerInvariant()
    $url = "$base/$idLower/$version/$idLower.nuspec"
    try { $xml = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop } catch { return @() }
    $depsRoot = $xml.package.metadata.dependencies
    if (-not $depsRoot) { return @() }
    $out = @()
    if ($depsRoot.dependency) {
        foreach ($d in @($depsRoot.dependency)) {
            if (-not $d.id) { continue }
            $min = Get-RangeMinParent $d.version
            if ($min) { $out += [pscustomobject]@{ Id = [string]$d.id; MinVersion = [string]$min } }
        }
    }
    if ($depsRoot.group) {
        foreach ($g in @($depsRoot.group)) {
            $tfm = $g.targetFramework
            $compat = Test-TfmCompatibleParent $projectTfm $tfm
            if (-not $compat) { continue }
            if ($g.dependency) {
                foreach ($d in @($g.dependency)) {
                    if (-not $d.id) { continue }
                    $min = Get-RangeMinParent $d.version
                    if ($min) { $out += [pscustomobject]@{ Id = [string]$d.id; MinVersion = [string]$min } }
                }
            }
        }
    }
    return $out
}

# Parent-scope copies of the worker's range-parsing helper (workers can't call
# parent-scope functions across runspace boundaries).
function Get-RangeMinParent ([string]$range) {
    if ([string]::IsNullOrWhiteSpace($range)) { return $null }
    $r = $range.Trim()
    if ($r.StartsWith('[') -or $r.StartsWith('(')) {
        $inclusive = $r.StartsWith('[')
        $body = $r.Substring(1, $r.Length - 2)
        $parts = $body.Split(',', 2)
        $lo = $parts[0].Trim()
        if ([string]::IsNullOrEmpty($lo)) { return $null }
        if (-not $inclusive)              { return $null }
        return $lo
    }
    return $r
}

function Test-TfmCompatibleParent ($projectTfm, [string]$candidateRaw) {
    if (-not $projectTfm) { return $true }
    if ([string]::IsNullOrWhiteSpace($candidateRaw)) { return $true }
    $t = $candidateRaw.Trim().ToLowerInvariant()
    $m = [regex]::Match($t, '^(net|netcoreapp)(\d+)\.(\d+)$')
    if ($m.Success) {
        $maj = [int]$m.Groups[2].Value; $min = [int]$m.Groups[3].Value
        if ($projectTfm.Family -ne 'net') { return $false }
        if ($maj -lt $projectTfm.Major) { return $true }
        if ($maj -eq $projectTfm.Major -and $min -le $projectTfm.Minor) { return $true }
        return $false
    }
    if ($t -match '^netstandard\d+\.\d+$') { return $true }
    if ($t -match '^net\d{2,}$') { return $false }
    return $true
}

# Project TFM in parent scope (mirrors what the worker computes).
$projectTfmParent = $null
if ($TargetFramework) {
    $tm = [regex]::Match($TargetFramework, '^(?<fam>net|netstandard|netcoreapp)(?<maj>\d+)\.(?<min>\d+)$')
    if ($tm.Success) {
        $projectTfmParent = [pscustomobject]@{
            Family = $tm.Groups['fam'].Value
            Major  = [int]$tm.Groups['maj'].Value
            Minor  = [int]$tm.Groups['min'].Value
        }
    }
}
$workItems = @($entries)
while ($workItems.Count -gt 0 -and $round -lt $maxRounds) {
    $round++
    Write-Host "  round $round (probing $($workItems.Count) package(s))..." -ForegroundColor DarkCyan

    # Rebuild anchor map from the current pin state. An anchor for dependency D is any
    # centrally-pinned package P whose published nuspec at its currently-pinned version
    # depends on D — that exact P binary was compiled against the version of D it names,
    # so D shouldn't be bumped beyond that within the same major while P stays put.
    $anchorMap = Get-AnchorMap -pinned $pinnedMap -base $flatContainerBase -projectTfm $projectTfmParent

    $roundResults = $workItems | ForEach-Object -ThrottleLimit $Throttle -Parallel {
    $entry = $_
    $base   = $using:flatContainerBase
    $pinned = $using:pinnedMap     # snapshot at the start of this round
    $anchors = $using:anchorMap    # dep-id -> [{ AnchorId, AnchorVersion, PinnedAtMin }]
    $tfm    = $using:TargetFramework
    $pkg    = $entry.Name
    $cur    = $entry.Version
    $allowMajor = $true

    # Parse our project's TFM ("net8.0" -> @{ Family='net'; Major=8; Minor=0 }) for
    # comparing with candidate's <group targetFramework=".."> entries.
    $projTfm = $null
    if ($tfm) {
        $tm = [regex]::Match($tfm, '^(?<fam>net|netstandard|netcoreapp)(?<maj>\d+)\.(?<min>\d+)$')
        if ($tm.Success) {
            $projTfm = [pscustomobject]@{
                Family = $tm.Groups['fam'].Value
                Major  = [int]$tm.Groups['maj'].Value
                Minor  = [int]$tm.Groups['min'].Value
            }
        }
    }

    # ------- Helpers (defined inside worker; runspaces don't share scope) -------
    function ConvertTo-PkgVersion ([string]$v) {
        if ([string]::IsNullOrWhiteSpace($v)) { return $null }
        $dash = $v.IndexOf('-')
        if ($dash -ge 0) { $core = $v.Substring(0, $dash); $pre = $v.Substring($dash + 1) }
        else             { $core = $v; $pre = '' }
        $parts = $core.Split('.')
        $nums  = [int[]]::new(4)
        for ($i = 0; $i -lt $parts.Length -and $i -lt 4; $i++) {
            $n = 0
            if (-not [int]::TryParse($parts[$i], [ref]$n)) { return $null }
            $nums[$i] = $n
        }
        [pscustomobject]@{
            Major = $nums[0]; Minor = $nums[1]; Patch = $nums[2]; Revision = $nums[3]
            PreRelease = $pre; IsPre = [bool]$pre; Original = $v
        }
    }

    function Compare-PkgVersion ($a, $b) {
        if ($a.Major    -ne $b.Major)    { return [int][math]::Sign($a.Major    - $b.Major) }
        if ($a.Minor    -ne $b.Minor)    { return [int][math]::Sign($a.Minor    - $b.Minor) }
        if ($a.Patch    -ne $b.Patch)    { return [int][math]::Sign($a.Patch    - $b.Patch) }
        if ($a.Revision -ne $b.Revision) { return [int][math]::Sign($a.Revision - $b.Revision) }
        if ($a.IsPre -and -not $b.IsPre) { return -1 }
        if (-not $a.IsPre -and $b.IsPre) { return 1 }
        return [string]::Compare($a.PreRelease, $b.PreRelease, [StringComparison]::Ordinal)
    }

    # Parse a NuGet version range like "[1.2.3, )" or "1.2.3" and return the
    # minimum-inclusive lower bound as a string (or $null if there's no lower bound,
    # which means "any version" and never causes a downgrade).
    function Get-RangeMin ([string]$range) {
        if ([string]::IsNullOrWhiteSpace($range)) { return $null }
        $r = $range.Trim()
        # Bracketed form: [min, max] or [min, ) or (min, max]
        if ($r.StartsWith('[') -or $r.StartsWith('(')) {
            $inclusive = $r.StartsWith('[')
            $body = $r.Substring(1, $r.Length - 2)
            $parts = $body.Split(',', 2)
            $lo = $parts[0].Trim()
            if ([string]::IsNullOrEmpty($lo)) { return $null }      # (, X] => no lower bound
            if (-not $inclusive)              { return $null }      # exclusive lower bound: NU1605 won't fire from this kind of constraint in practice; treat as non-binding
            return $lo
        }
        # Bare version "1.2.3" means ">= 1.2.3" inclusive.
        return $r
    }

    # Parse a TFM moniker like "net8.0", "netstandard2.0", "net462" into a comparable
    # object, or $null if unrecognized (which we treat as a wildcard / accept-all).
    function ConvertTo-Tfm ([string]$s) {
        if ([string]::IsNullOrWhiteSpace($s)) { return $null }
        $t = $s.Trim().ToLowerInvariant()
        # Long-form .NET 5+ ("net8.0")
        $m = [regex]::Match($t, '^(net|netcoreapp)(\d+)\.(\d+)$')
        if ($m.Success) {
            return [pscustomobject]@{ Family = 'net'; Major = [int]$m.Groups[2].Value; Minor = [int]$m.Groups[3].Value }
        }
        # netstandard
        $m = [regex]::Match($t, '^netstandard(\d+)\.(\d+)$')
        if ($m.Success) {
            return [pscustomobject]@{ Family = 'netstandard'; Major = [int]$m.Groups[1].Value; Minor = [int]$m.Groups[2].Value }
        }
        # Short-form .NET Framework ("net462" -> 4.6.2). We only need to know it's NETFW.
        if ($t -match '^net(\d{2,})$') {
            return [pscustomobject]@{ Family = 'netfw'; Major = 0; Minor = 0 }
        }
        return $null
    }

    # Is candidate's TFM group compatible with our project's TFM?
    # - net8.0 project accepts: net8.0, netN.M where N<8 (back compat), netstandard2.x, netstandard1.x.
    # - net8.0 project REJECTS: net9.0, net10.0, etc. (no forward compat).
    # - Empty/unknown TFM is treated as "any" (wildcard) and always compatible — this
    #   matches NuGet's fallback behavior for ungrouped <dependency> entries.
    function Test-TfmCompatible ($projectTfm, $candidateTfm) {
        if (-not $projectTfm) { return $true }      # project TFM unknown -> skip check
        if (-not $candidateTfm) { return $true }    # candidate is "any" -> compatible
        if ($candidateTfm.Family -eq 'netstandard') {
            # net 5+ supports netstandard2.1; older nets and netstandard always work.
            return $true
        }
        if ($candidateTfm.Family -eq 'netfw') {
            return $false   # .NET Framework asset is not compatible with .NET (Core/5+).
        }
        if ($projectTfm.Family -ne 'net') { return $false }
        if ($candidateTfm.Major -lt $projectTfm.Major) { return $true }
        if ($candidateTfm.Major -eq $projectTfm.Major -and $candidateTfm.Minor -le $projectTfm.Minor) { return $true }
        return $false
    }

    # Enumerate names of abstract methods on public/protected types defined in the
    # package's primary DLL for the given version. Each entry is "Namespace.Type::Method".
    # Returns $null if the asset can't be opened.
    #
    # Signal: when a vendor adds a new public/protected abstract method between
    # versions, every existing subclass that hasn't been recompiled to override it
    # will fail to load with TypeLoadException at runtime. We diff this set between
    # the current pin and a candidate to detect ABI-breaking SemVer violations like
    # linq2db 5.4.0 -> 5.4.1 (added abstract SqlTransparentExpression.Quote) or
    # EFCore.Relational 8.x -> 9.x (added abstract SqlExpression.Quote).
    function Get-AbstractMethodSet ([string]$base, [string]$id, [string]$version, $projectTfm) {
        $idLower = $id.ToLowerInvariant()
        $nupkgUrl = "$base/$idLower/$version/$idLower.$version.nupkg"
        $tmpFile = $null
        $zip = $null
        $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        try {
            $tmpFile = [System.IO.Path]::GetTempFileName()
            Invoke-WebRequest -Uri $nupkgUrl -OutFile $tmpFile -UseBasicParsing -ErrorAction Stop | Out-Null
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $zip = [System.IO.Compression.ZipFile]::OpenRead($tmpFile)
            $dllName = "$idLower.dll"
            $libEntries = @($zip.Entries | Where-Object {
                $_.FullName -like 'lib/*' -and
                [System.IO.Path]::GetFileName($_.FullName).ToLowerInvariant() -eq $dllName
            })
            if ($libEntries.Count -eq 0) { return $null }

            $score = {
                param($entry)
                $tfmFolder = ($entry.FullName -split '/')[1]
                $t = ConvertTo-Tfm $tfmFolder
                if (-not $t) { return 0 }
                if (-not $projectTfm) {
                    if ($t.Family -eq 'netstandard') { return 50 }
                    return 10
                }
                if ($t.Family -eq 'net' -and $projectTfm.Family -eq 'net' -and
                    $t.Major -eq $projectTfm.Major -and $t.Minor -eq $projectTfm.Minor) { return 100 }
                if ($t.Family -eq 'net' -and $projectTfm.Family -eq 'net' -and
                    ($t.Major -lt $projectTfm.Major -or
                     ($t.Major -eq $projectTfm.Major -and $t.Minor -lt $projectTfm.Minor))) { return 80 }
                if ($t.Family -eq 'netstandard') { return 50 }
                return 5
            }
            $best = $libEntries | Sort-Object -Descending { & $score $_ } | Select-Object -First 1
            if (-not $best) { return $null }

            $dllTmp = [System.IO.Path]::GetTempFileName()
            try {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($best, $dllTmp, $true)
                $stream = [System.IO.File]::OpenRead($dllTmp)
                try {
                    $peReader = [System.Reflection.PortableExecutable.PEReader]::new($stream)
                    try {
                        $mdReader = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($peReader)
                        # Iterate type defs; collect abstract methods on visible types.
                        foreach ($typeHandle in $mdReader.TypeDefinitions) {
                            $td = $mdReader.GetTypeDefinition($typeHandle)
                            $vis = ([int]$td.Attributes) -band 0x7
                            # 1=Public, 2=NestedPublic, 4=NestedFamily(=protected), 6=NestedFamORAssem.
                            if ($vis -ne 1 -and $vis -ne 2 -and $vis -ne 4 -and $vis -ne 6) { continue }
                            $tname = $mdReader.GetString($td.Name)
                            $tns = $mdReader.GetString($td.Namespace)
                            $fqType = if ([string]::IsNullOrEmpty($tns)) { $tname } else { "$tns.$tname" }
                            foreach ($methodHandle in $td.GetMethods()) {
                                $mdef = $mdReader.GetMethodDefinition($methodHandle)
                                $attrs = [int]$mdef.Attributes
                                # MethodAttributes.Abstract = 0x400
                                if (($attrs -band 0x400) -eq 0) { continue }
                                # Visibility: Public(0x06), Family(0x04), FamORAssem(0x05). Skip private/internal.
                                $mvis = $attrs -band 0x7
                                if ($mvis -ne 6 -and $mvis -ne 4 -and $mvis -ne 5) { continue }
                                $mname = $mdReader.GetString($mdef.Name)
                                [void]$set.Add("$fqType::$mname")
                            }
                        }
                    } finally { $peReader.Dispose() }
                } finally { $stream.Dispose() }
            } finally {
                if (Test-Path -LiteralPath $dllTmp) { Remove-Item -LiteralPath $dllTmp -Force -ErrorAction SilentlyContinue }
            }
        } catch {
            return $null
        } finally {
            if ($zip) { $zip.Dispose() }
            if ($tmpFile -and (Test-Path -LiteralPath $tmpFile)) { Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue }
        }
        return $set
    }

    # Read the AssemblyVersion of the package's primary DLL (id.dll under lib/<tfm>/)
    # for the given package version. Returns a pscustomobject with Major/Minor/Patch/
    # Revision, or $null if the asset can't be located/read.
    #
    # Why this exists: NuGet semver and CLR strong-name AssemblyVersion are independent.
    # Some vendors (e.g. linq2db) ship a higher package version that REGRESSES
    # AssemblyVersion (5.4.1 -> 5.4.1.9 dropped AsmVer from 5.4.1.0 to 5.0.0.0). When a
    # downstream consumer was compiled against AsmVer 5.4.0.0 and we ship AsmVer 5.0.0.0
    # at runtime, the CLR throws FileNotFoundException because .NET (Core/5+) only
    # rolls forward, never backward. Pure NuGet metadata can't see this — we have to
    # crack open the .nupkg and read the actual DLL.
    function Get-AssemblyVersionFromNupkg ([string]$base, [string]$id, [string]$version, $projectTfm) {
        $idLower = $id.ToLowerInvariant()
        $nupkgUrl = "$base/$idLower/$version/$idLower.$version.nupkg"
        $tmpFile = $null
        $zip = $null
        try {
            $tmpFile = [System.IO.Path]::GetTempFileName()
            Invoke-WebRequest -Uri $nupkgUrl -OutFile $tmpFile -UseBasicParsing -ErrorAction Stop | Out-Null
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $zip = [System.IO.Compression.ZipFile]::OpenRead($tmpFile)
            $dllName = "$idLower.dll"
            # Prefer lib/<exact-tfm>/, then matching family with lower/equal version,
            # then netstandard2.x, then any lib entry.
            $libEntries = @($zip.Entries | Where-Object {
                $_.FullName -like 'lib/*' -and
                [System.IO.Path]::GetFileName($_.FullName).ToLowerInvariant() -eq $dllName
            })
            if ($libEntries.Count -eq 0) { return $null }

            $score = {
                param($entry)
                $tfmFolder = ($entry.FullName -split '/')[1]
                $t = ConvertTo-Tfm $tfmFolder
                if (-not $t) { return 0 }
                if (-not $projectTfm) {
                    if ($t.Family -eq 'netstandard') { return 50 }
                    return 10
                }
                if ($t.Family -eq 'net' -and $projectTfm.Family -eq 'net' -and
                    $t.Major -eq $projectTfm.Major -and $t.Minor -eq $projectTfm.Minor) { return 100 }
                if ($t.Family -eq 'net' -and $projectTfm.Family -eq 'net' -and
                    ($t.Major -lt $projectTfm.Major -or
                     ($t.Major -eq $projectTfm.Major -and $t.Minor -lt $projectTfm.Minor))) { return 80 }
                if ($t.Family -eq 'netstandard') { return 50 }
                return 5
            }
            $best = $libEntries | Sort-Object -Descending { & $score $_ } | Select-Object -First 1
            if (-not $best) { return $null }

            $dllTmp = [System.IO.Path]::GetTempFileName()
            try {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($best, $dllTmp, $true)
                $asmName = [Reflection.AssemblyName]::GetAssemblyName($dllTmp)
                if (-not $asmName -or -not $asmName.Version) { return $null }
                return [pscustomobject]@{
                    Major = $asmName.Version.Major; Minor = $asmName.Version.Minor
                    Patch = [Math]::Max(0, $asmName.Version.Build); Revision = [Math]::Max(0, $asmName.Version.Revision)
                    PreRelease = ''; IsPre = $false; Original = $asmName.Version.ToString()
                }
            } finally {
                if (Test-Path -LiteralPath $dllTmp) { Remove-Item -LiteralPath $dllTmp -Force -ErrorAction SilentlyContinue }
            }
        } catch {
            return $null
        } finally {
            if ($zip) { $zip.Dispose() }
            if ($tmpFile -and (Test-Path -LiteralPath $tmpFile)) { Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue }
        }
    }

    # Fetch the .nuspec for a given package version. Returns:
    #   @{ Compatible = bool; Deps = [pscustomobject]{ Id; MinVersion }[] }
    # Compatible means at least one <group targetFramework="..."> matches our project
    # TFM (or there are no groups / no dependencies block, treated as "any framework").
    # Deps are aggregated only from compatible groups (ungrouped or matching TFM), so
    # NU1605 checks don't false-positive on net10.0-only deps that don't apply to us.
    function Get-NuspecInfo ([string]$base, [string]$id, [string]$version, $projectTfm) {
        $idLower = $id.ToLowerInvariant()
        $url = "$base/$idLower/$version/$idLower.nuspec"
        try {
            $xml = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        } catch {
            return [pscustomobject]@{ Compatible = $false; Deps = @() }
        }
        $depsRoot = $xml.package.metadata.dependencies
        # No <dependencies> block at all = trivially compatible (asset-only or no deps).
        if (-not $depsRoot) { return [pscustomobject]@{ Compatible = $true; Deps = @() } }

        $hasAnyGroup = $false
        $compatible  = $false
        $deps = @()

        # Ungrouped <dependency> children apply to all frameworks.
        if ($depsRoot.dependency) {
            $compatible = $true
            foreach ($d in @($depsRoot.dependency)) {
                if (-not $d.id) { continue }
                $min = Get-RangeMin $d.version
                if (-not $min) { continue }
                $deps += [pscustomobject]@{ Id = [string]$d.id; MinVersion = [string]$min }
            }
        }

        # Grouped <group targetFramework="..."> deps: only count if the group is compatible.
        if ($depsRoot.group) {
            foreach ($g in @($depsRoot.group)) {
                $hasAnyGroup = $true
                $gTfm = ConvertTo-Tfm $g.targetFramework
                if (-not (Test-TfmCompatible $projectTfm $gTfm)) { continue }
                $compatible = $true
                if ($g.dependency) {
                    foreach ($d in @($g.dependency)) {
                        if (-not $d.id) { continue }
                        $min = Get-RangeMin $d.version
                        if (-not $min) { continue }
                        $deps += [pscustomobject]@{ Id = [string]$d.id; MinVersion = [string]$min }
                    }
                }
            }
        }

        # If there were no groups at all but we had ungrouped deps, $compatible was already
        # set above. If neither, treat as compatible (no constraints to check).
        if (-not $hasAnyGroup -and $deps.Count -eq 0) { $compatible = $true }

        return [pscustomobject]@{ Compatible = $compatible; Deps = $deps }
    }

    # ------- Step 1: fetch versions index -------
    $current = ConvertTo-PkgVersion $cur
    if (-not $current) {
        return [pscustomobject]@{ Name = $pkg; Status = 'failed'; From = $cur; To = $null; Match = $entry.Match; Reason = 'unparseable current version' }
    }

    $url = "$base/$($pkg.ToLowerInvariant())/index.json"
    try {
        $resp = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ Name = $pkg; Status = 'failed'; From = $cur; To = $null; Match = $entry.Match; Reason = $_.Exception.Message }
    }

    # ------- Step 2: build candidate list, sorted high to low -------
    # Cross-major bumps allowed for all packages; the TFM and transitive-dep guards
    # below filter out anything that would actually break the build.
    $candidates = foreach ($v in $resp.versions) {
        $p = ConvertTo-PkgVersion $v
        if (-not $p) { continue }
        if (-not $allowMajor -and $p.Major -ne $current.Major) { continue }
        if (-not $current.IsPre -and $p.IsPre) { continue }
        if ((Compare-PkgVersion $p $current) -le 0) { continue }    # only versions strictly newer than current
        $p
    }
    $candidates = @($candidates | Sort-Object -Descending {
        # Build a tuple-y composite for fast Sort-Object; CLR sort is stable.
        '{0:D10}.{1:D10}.{2:D10}.{3:D10}-{4}' -f $_.Major, $_.Minor, $_.Patch, $_.Revision, ($_.PreRelease.PadRight(20))
    })

    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{ Name = $pkg; Status = 'unchanged'; From = $cur; To = $cur; Match = $entry.Match; Reason = 'already at latest' }
    }

    # Cap how many candidates we probe via .nuspec to keep the runtime bounded.
    # In practice the highest candidate fits almost always; this is a safety net for
    # packages with hundreds of historical versions across multiple majors.
    if ($candidates.Count -gt 25) { $candidates = $candidates[0..24] }

    # ------- Step 3: walk candidates high->low, accept the first that's compatible -------
    # Cache the current pin's AssemblyVersion (read once, reused per candidate). This
    # is our "minimum acceptable AssemblyVersion" — any candidate that ships a lower
    # AssemblyVersion would break strong-name binding for downstream consumers compiled
    # against the current pin's AsmVer.
    $currentAsmVer = Get-AssemblyVersionFromNupkg $base $pkg $cur $projTfm

    # Snapshot of the current pin's dependency closure (for our TFM). Used by the
    # new-dependency guard below to detect candidates that introduce transitive deps
    # that didn't exist in the prior version.
    $currentInfo = Get-NuspecInfo $base $pkg $cur $projTfm
    $currentDepIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ($currentInfo -and $currentInfo.Deps) {
        foreach ($d in $currentInfo.Deps) { [void]$currentDepIds.Add($d.Id) }
    }

    # Snapshot of the current pin's abstract methods on visible types. Used by the
    # ABI-break guard below to detect candidates that add new abstract methods —
    # subclasses of those types in any dependent assembly will fail to load with
    # TypeLoadException at runtime if they don't override the new method.
    $currentAbstractMethods = Get-AbstractMethodSet $base $pkg $cur $projTfm

    $rejected = @()
    # Walks the candidate's full transitive nuspec closure (bounded), returning the
    # first centrally-pinned package whose required min-version exceeds our central pin
    # (i.e. a real NU1605 downgrade). Without this, direct-only checks miss cases like
    # Serilog.AspNetCore 10.0.0 -> Serilog.Extensions.Hosting 10.0.0 -> ... ->
    # Microsoft.Extensions.DependencyInjection 10.0.0 where DI is centrally pinned at 9.x.
    function Find-NU1605Downgrade ([string]$base, [string]$rootId, [string]$rootVer, $projectTfm, [hashtable]$pinned) {
        $visited = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $queue = New-Object 'System.Collections.Generic.Queue[object]'
        $queue.Enqueue([pscustomobject]@{ Id = $rootId; Version = $rootVer; Depth = 0; Path = @() })
        [void]$visited.Add("$rootId|$rootVer")
        $maxDepth = 4
        while ($queue.Count -gt 0) {
            $node = $queue.Dequeue()
            if ($node.Depth -ge $maxDepth) { continue }
            $nspec = Get-NuspecInfo $base $node.Id $node.Version $projectTfm
            if (-not $nspec.Compatible) { continue }
            foreach ($d in $nspec.Deps) {
                $depKey = "$($d.Id)|$($d.MinVersion)"
                if (-not $visited.Add($depKey)) { continue }
                # Downgrade check: only meaningful for packages we centrally pin.
                if ($pinned.ContainsKey($d.Id)) {
                    $pinnedVer = ConvertTo-PkgVersion $pinned[$d.Id]
                    $needVer   = ConvertTo-PkgVersion $d.MinVersion
                    if ($pinnedVer -and $needVer -and ((Compare-PkgVersion $needVer $pinnedVer) -gt 0)) {
                        $chain = @($node.Path) + @("$($node.Id) $($node.Version)") + @("$($d.Id) $($d.MinVersion)")
                        return [pscustomobject]@{
                            Id = $d.Id; Need = $d.MinVersion; Have = $pinned[$d.Id]
                            Chain = ($chain -join ' -> ')
                        }
                    }
                }
                # Recurse only when we can resolve a concrete version to fetch the nuspec of.
                if (-not [string]::IsNullOrWhiteSpace($d.MinVersion)) {
                    $nextPath = @($node.Path) + @("$($node.Id) $($node.Version)")
                    $queue.Enqueue([pscustomobject]@{
                        Id = $d.Id; Version = $d.MinVersion; Depth = $node.Depth + 1; Path = $nextPath
                    })
                }
            }
        }
        return $null
    }

    foreach ($cand in $candidates) {
        $info = Get-NuspecInfo $base $pkg $cand.Original $projTfm
        $conflict = $null
        if (-not $info.Compatible) {
            $conflict = "no asset compatible with $tfm"
        } else {
            $downgrade = Find-NU1605Downgrade $base $pkg $cand.Original $projTfm $pinned
            if ($downgrade) {
                $conflict = "$($downgrade.Id) >= $($downgrade.Need) (we pin $($downgrade.Have)); via $($downgrade.Chain)"
            }
        }
        # Strong-name regression guard: reject candidates whose primary DLL
        # AssemblyVersion is lower than the current pin's AssemblyVersion. Catches
        # vendor mistakes like linq2db 5.4.1 (AsmVer 5.4.1.0) -> 5.4.1.9 (AsmVer 5.0.0.0).
        if (-not $conflict -and $currentAsmVer) {
            $candAsmVer = Get-AssemblyVersionFromNupkg $base $pkg $cand.Original $projTfm
            if ($candAsmVer -and ((Compare-PkgVersion $candAsmVer $currentAsmVer) -lt 0)) {
                $conflict = "AssemblyVersion regressed: candidate ships $($candAsmVer.Original), current pin $cur ships $($currentAsmVer.Original)"
            }
        }
        # Peer-anchor cross-major guard: cross-MAJOR bump while an anchor still pins to
        # an older major. Always reject — even if the candidate doesn't add abstract
        # members visible to our IL diff (e.g. type renames, removed types, signature
        # changes are also runtime-fatal). Catches EFCore 8.x -> 9.x while
        # linq2db.EFCore 8.1.0 is still pinned.
        if (-not $conflict -and $anchors -and $anchors.ContainsKey($pkg)) {
            foreach ($a in $anchors[$pkg]) {
                $anchorMin = ConvertTo-PkgVersion $a.PinnedAtMin
                if (-not $anchorMin) { continue }
                if ($cand.Major -gt $anchorMin.Major) {
                    $conflict = "anchor $($a.AnchorId) $($a.AnchorVersion) was built against $pkg $($a.PinnedAtMin) (major $($anchorMin.Major)); candidate $($cand.Original) crosses to major $($cand.Major) — anchor must be bumped first or peer will fail to load"
                    break
                }
            }
        }
        # ABI-break guard: reject candidates that ADD new public/protected abstract
        # methods compared to the current pin. Any subclass of those types in another
        # already-compiled assembly that doesn't override the new method will fail to
        # load with TypeLoadException at runtime.
        # Catches: linq2db 5.4.0 -> 5.4.1 (added SqlTransparentExpression.Quote that
        # linq2db.EFCore 8.1.0's subclass doesn't override — TypeLoadException).
        # Same-major patch bumps with no new abstract members (e.g. EFCore 8.0.0 ->
        # 8.0.26) pass through.
        if (-not $conflict -and $currentAbstractMethods) {
            $candAbstractMethods = Get-AbstractMethodSet $base $pkg $cand.Original $projTfm
            if ($candAbstractMethods) {
                $added = @()
                foreach ($m in $candAbstractMethods) {
                    if (-not $currentAbstractMethods.Contains($m)) { $added += $m }
                }
                if ($added.Count -gt 0) {
                    $sample = ($added | Select-Object -First 3) -join ', '
                    $conflict = "candidate adds $($added.Count) new abstract method(s) on visible types (e.g. $sample); existing subclasses in centrally-pinned consumers may fail to load (TypeLoadException)"
                }
            }
        }
        # New-dependency guard: reject candidates that introduce a transitive dep
        # absent from both the prior version's deps AND our central pin set. NuGet
        # can resolve any transitive that's centrally pinned (we'll deploy the lib
        # asset for our TFM ourselves) — but a brand-new transitive isn't covered by
        # the props file, and asset selection can fail silently when the dep's lib
        # asset doesn't match our target framework, leaving downstream DLLs unable to
        # resolve types at runtime.
        # Catches: NPOI 2.7.2 (no net8.0 deps) -> 2.8.0 (added SkiaSharp net8.0 dep).
        # SkiaSharp wasn't centrally pinned, the runtime asset wasn't deployed, and
        # consumers of NPOI's types failed with FileNotFoundException for SkiaSharp.
        if (-not $conflict -and $info.Compatible) {
            foreach ($d in $info.Deps) {
                if ($currentDepIds.Contains($d.Id)) { continue }      # already a dep in current version
                if ($pinned.ContainsKey($d.Id)) { continue }          # we manage it centrally — fine
                $conflict = "introduces new transitive dep '$($d.Id) >= $($d.MinVersion)' not in current $cur deps and not centrally pinned"
                break
            }
        }
        if (-not $conflict) {
            return [pscustomobject]@{
                Name     = $pkg
                Status   = 'updated'
                From     = $cur
                To       = $cand.Original
                Match    = $entry.Match
                Reason   = if ($rejected.Count -gt 0) { "skipped: $($rejected -join '; ')" } else { $null }
                Skipped  = $rejected.Count
            }
        }
        $rejected += "$($cand.Original) needs $conflict"
    }

    # No candidate fit -> stay on current.
    return [pscustomobject]@{
        Name    = $pkg
        Status  = 'unchanged'
        From    = $cur
        To      = $cur
        Match   = $entry.Match
        Reason  = "all $($candidates.Count) candidate(s) blocked by transitive constraints; latest tried: $($rejected[0])"
        Skipped = $rejected.Count
    }
    }   # end ForEach-Object -Parallel

    # Merge this round's results into the accepted map and update pin floors.
    # Subtle: when re-probing an already-updated package, the worker probes from its
    # current accepted version, so an "unchanged + Skipped=0" result means "no further
    # bump possible from here" — we must NOT lose the prior "updated" record. Only
    # overwrite when the new result is itself an update (strictly higher) or when the
    # prior record was also "unchanged".
    $anyBump = $false
    foreach ($r in $roundResults) {
        $prior = $accepted[$r.Name]
        if ($r.Status -eq 'updated') {
            $accepted[$r.Name] = $r
            $pinnedMap[$r.Name] = $r.To
            $anyBump = $true
        } elseif (-not $prior -or $prior.Status -ne 'updated') {
            # Replace only if there's no prior accepted update we'd be discarding.
            $accepted[$r.Name] = $r
        }
        # else: keep the prior 'updated' record; this round's probe yielded nothing newer.
    }
    if (-not $anyBump) { break }

    # Re-probe every package that was held back (Status=unchanged with Skipped>0)
    # AND every package whose accepted version was forced lower by transitive limits
    # in an earlier round (Status=updated with Skipped>0). The latter case is needed
    # because a later-round pin bump might unblock a higher candidate for that package.
    # Pin floors only ever rise, so accepted updates can't regress.
    $newWork = @()
    foreach ($r in $accepted.Values) {
        if (-not $r.Skipped -or $r.Skipped -le 0) { continue }
        if ($r.Status -ne 'unchanged' -and $r.Status -ne 'updated') { continue }
        # Probe from the currently-accepted version so we only consider strictly-newer
        # candidates than what we already have. The worker filters with > current.
        $probeFrom = if ($r.Status -eq 'updated') { $r.To } else { $r.From }
        $newWork += [pscustomobject]@{
            Name    = $r.Name
            Version = $probeFrom
            Match   = $r.Match
        }
    }
    $workItems = $newWork
}

$results = @($accepted.Values)

# Rewrite the "From" field on every result to reflect the original version (pre-script).
# Multi-round runs may have probed from an interim accepted version; the user wants
# the diff vs. what was checked in.
foreach ($r in $results) {
    if ($originalVersion.ContainsKey($r.Name)) {
        $orig = $originalVersion[$r.Name]
        $r.From = $orig
        # An "updated" result whose final To equals the original means the bump round-tripped — treat as unchanged.
        if ($r.Status -eq 'updated' -and $r.To -eq $orig) {
            $r.Status = 'unchanged'
        }
    }
}

# --- Bucket results -----------------------------------------------------------------
$updated   = @($results | Where-Object Status -EQ 'updated')
$unchanged = @($results | Where-Object Status -EQ 'unchanged')
$failed    = @($results | Where-Object Status -EQ 'failed')

# --- Apply edits via single regex Replace pass --------------------------------------
if ($updated.Count -gt 0) {
    $replacements = @{}
    foreach ($u in $updated) {
        $replacements[$u.Match] = ('<PackageVersion Include="{0}" Version="{1}" />' -f $u.Name, $u.To)
    }
    $pattern = [regex]'<PackageVersion\s+Include="[^"]+"\s+Version="[^"]+"\s*/>'
    $newContent = $pattern.Replace($propsContent, {
        param($m)
        $key = $m.Value
        if ($replacements.ContainsKey($key)) { return $replacements[$key] }
        return $key
    })
} else {
    $newContent = $propsContent
}

# --- Report -------------------------------------------------------------------------
Write-Host ''
if ($updated.Count -gt 0) {
    Write-Host "Updated ($($updated.Count)):" -ForegroundColor Green
    $updated | Sort-Object Name | Format-Table Name, From, To -AutoSize | Out-String | Write-Host
} else {
    Write-Host 'No packages need updating.' -ForegroundColor Green
}

# Highlight packages where transitive constraints blocked one or more newer versions.
$blocked = @($unchanged | Where-Object { $_.Skipped -gt 0 })
if ($blocked.Count -gt 0) {
    Write-Host "Held back by transitive constraints ($($blocked.Count)):" -ForegroundColor Yellow
    $blocked | Sort-Object Name | Format-Table Name, From, Reason -AutoSize -Wrap | Out-String | Write-Host
}

if ($failed.Count -gt 0) {
    Write-Host "Failed lookups ($($failed.Count)):" -ForegroundColor Yellow
    $failed | Format-Table Name, From, Reason -AutoSize | Out-String | Write-Host
}

Write-Host "Already up to date: $(@($unchanged | Where-Object { -not $_.Skipped }).Count)" -ForegroundColor DarkGray

# --- Write --------------------------------------------------------------------------
if ($updated.Count -eq 0) { exit 0 }

if ($DryRun) {
    Write-Host '(DryRun) Directory.Packages.props was NOT modified.' -ForegroundColor Cyan
    exit 0
}

# Preserve original encoding (UTF-8 without BOM is the typical .props convention).
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($PropsPath, $newContent, $utf8NoBom)
Write-Host "Wrote updates to $PropsPath" -ForegroundColor Green

# --- Regenerate lock files ----------------------------------------------------------
# Central Package Management + RestorePackagesWithLockFile pins the full transitive
# graph in each project's packages.lock.json. After changing any PackageVersion,
# locked-mode restore (CI) would fail with NU1004 unless we refresh the lock files.
# --force-evaluate forces NuGet to re-resolve the graph against the new pins instead
# of reading the stale cached lockfile entries.
if ($ValidateTarget -and (Test-Path -LiteralPath $ValidateTarget)) {
    Write-Host '' ; Write-Host "Restoring with --force-evaluate to refresh lock files..." -ForegroundColor Cyan
    & dotnet restore $ValidateTarget --force-evaluate
    if ($LASTEXITCODE -ne 0) {
        Write-Host "dotnet restore failed (exit $LASTEXITCODE). Lock files may be out of date." -ForegroundColor Red
        exit 1
    }
}

# --- Build validation ---------------------------------------------------------------
# Some breakages can't be predicted from NuGet metadata (e.g. an assembly that ships
# a netstandard2.0 asset but whose API surface changed across majors). The only
# reliable validator is `dotnet build`. We compile the target solution; on failure,
# we identify packages mentioned in error lines, revert those bumps in the props
# file, and rebuild. Loop terminates when build is clean, no revertable offenders
# remain, or we hit $ValidateMaxRounds.
if (-not $ValidateTarget -or -not (Test-Path -LiteralPath $ValidateTarget)) {
    Write-Host '' ; Write-Host 'Build validation skipped (no -ValidateTarget).' -ForegroundColor DarkYellow
    exit 0
}

# Map of currently-applied bumps so we can revert individual ones.
$activeBumps = @{}
foreach ($u in $updated) { $activeBumps[$u.Name] = $u }

# Mutable copy of $newContent that we rewrite each iteration.
$workingContent = $newContent

# For each active bump, compute "match keys": the package id and its parent dotted
# path one level up (e.g. "System.ServiceModel.Http" -> ["System.ServiceModel.Http",
# "System.ServiceModel"]). Build a regex that maps every key back to its package id,
# letting us match error lines that reference a parent namespace (CS0234 typically
# names the namespace, not the package). We skip 1-segment keys ("System") since
# those would over-match unrelated errors.
function New-BumpMatcher ([System.Collections.IDictionary]$bumps) {
    if ($bumps.Count -eq 0) { return $null }
    $keyToId = @{}
    foreach ($id in $bumps.Keys) {
        $keyToId[$id] = $id
        $segments = $id.Split('.')
        if ($segments.Length -ge 3) {
            # Parent namespace (id minus the last segment).
            $parent = ($segments[0..($segments.Length - 2)] -join '.')
            if (-not $keyToId.ContainsKey($parent)) { $keyToId[$parent] = $id }
        }
    }
    # Order keys by length descending so longer matches win (e.g. match
    # "System.ServiceModel.Http" before "System.ServiceModel").
    $orderedKeys = $keyToId.Keys | Sort-Object { $_.Length } -Descending
    $alts = $orderedKeys | ForEach-Object { [regex]::Escape($_) }
    $rx = [regex]("(?<![A-Za-z0-9._])(?<key>" + ($alts -join '|') + ")(?![A-Za-z0-9._])")
    return [pscustomobject]@{ Regex = $rx; Map = $keyToId }
}

for ($vRound = 1; $vRound -le $ValidateMaxRounds; $vRound++) {
    Write-Host '' ; Write-Host "Build validation round $vRound (target: $ValidateTarget)..." -ForegroundColor Cyan
    # `--verbosity quiet` keeps stdout small; errors still surface on stderr.
    # `-nowarn` suppresses noise unrelated to package conflicts.
    $buildOutput = & dotnet build $ValidateTarget --verbosity quiet -nowarn:NU1902,NU1903,NU1904 2>&1
    $buildExit = $LASTEXITCODE
    if ($buildExit -eq 0) {
        Write-Host 'Build succeeded.' -ForegroundColor Green
        break
    }

    $matcher = New-BumpMatcher $activeBumps
    $offenders = New-Object 'System.Collections.Generic.HashSet[string]'
    if ($matcher) {
        foreach ($line in $buildOutput) {
            $s = [string]$line
            # Look at error lines (CSxxxx, NUxxxx, "error", "Error") and lines that
            # name a package version like "Foo 10.0.7".
            if ($s -notmatch '\b(error|Error|CS\d{3,4}|NU\d{4})\b') { continue }
            foreach ($m in $matcher.Regex.Matches($s)) {
                $key = $m.Groups['key'].Value
                $pkgId = $matcher.Map[$key]
                if ($pkgId) { [void]$offenders.Add($pkgId) }
            }
        }
    }

    # If a build fails with no specific package mentioned in the errors, it's likely
    # a source-code issue introduced by an API break. We can't pinpoint which bump
    # caused it from the error text alone. Heuristic: revert the riskiest bumps —
    # i.e. ones that crossed a major boundary — and try again.
    if ($offenders.Count -eq 0) {
        $crossMajor = @($activeBumps.Values | Where-Object {
            $f = ConvertTo-PkgVersion -Version $_.From
            $t = ConvertTo-PkgVersion -Version $_.To
            $f -and $t -and ($f.Major -ne $t.Major)
        })
        if ($crossMajor.Count -eq 0) {
            Write-Host 'Build failed but no bumped package was identified and no cross-major bumps remain to revert. Errors:' -ForegroundColor Red
            $buildOutput | Where-Object { [string]$_ -match '\berror\b|\bCS\d{3,4}\b|\bNU\d{4}\b' } | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            Write-Host '' ; Write-Host 'Could not auto-revert. Inspect Directory.Packages.props manually.' -ForegroundColor Red
            exit 1
        }
        Write-Host "Build error doesn't name a specific package; reverting all $($crossMajor.Count) cross-major bump(s) as a fallback." -ForegroundColor Yellow
        foreach ($u in $crossMajor) { [void]$offenders.Add($u.Name) }
    }

    Write-Host "Reverting $($offenders.Count) offending bump(s):" -ForegroundColor Yellow
    foreach ($name in $offenders) {
        $u = $activeBumps[$name]
        if (-not $u) { continue }     # already reverted in a prior pass
        $orig = $originalVersion[$name]
        $newAttr      = '<PackageVersion Include="{0}" Version="{1}" />' -f $name, $u.To
        $revertedAttr = '<PackageVersion Include="{0}" Version="{1}" />' -f $name, $orig
        $workingContent = $workingContent.Replace($newAttr, $revertedAttr)
        $activeBumps.Remove($name)
        Write-Host "  $name : $($u.To) -> $orig" -ForegroundColor Yellow
    }

    [System.IO.File]::WriteAllText($PropsPath, $workingContent, $utf8NoBom)
}

if ($LASTEXITCODE -ne 0) {
    Write-Host '' ; Write-Host "Build still failing after $ValidateMaxRounds rounds. Manual inspection required." -ForegroundColor Red
    exit 1
}

# Final summary: how many bumps survived validation. Show the revert direction
# (Proposed -> RestoredTo) rather than the proposed bump direction.
$reverted = @($updated | Where-Object { -not $activeBumps.ContainsKey($_.Name) } | ForEach-Object {
    [pscustomobject]@{
        Name       = $_.Name
        Proposed   = $_.To
        RestoredTo = $originalVersion[$_.Name]
    }
})
if ($reverted.Count -gt 0) {
    Write-Host '' ; Write-Host "Reverted ($($reverted.Count)):" -ForegroundColor Yellow
    $reverted | Sort-Object Name | Format-Table Name, Proposed, RestoredTo -AutoSize | Out-String | Write-Host
}
Write-Host "Net updated: $($activeBumps.Count) of $($updated.Count) proposed bumps survived build validation." -ForegroundColor Green
