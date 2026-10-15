<#
.SYNOPSIS
    Installs or upgrades Polygent components as Windows Services.

.DESCRIPTION
    Downloads the selected components (Server, Session Worker, Deployment Worker) from the
    Polygent GitHub releases, verifies their SHA-256 digests, extracts each into its own folder,
    writes the machine's settings to appsettings.Production.json, and registers an auto-start Windows Service
    with restart-on-failure recovery.

    Running it again upgrades in place: the service is stopped, the files of the previous
    package are replaced (including appsettings.json, so new defaults arrive), and
    appsettings.Production.json, logs and crash.log are kept. Settings an older install kept in
    appsettings.json are moved to appsettings.Production.json.

    Missing prerequisites (.NET 10 Hosting Bundle, Git for Windows) are downloaded from their
    vendors, hash-verified, and installed. Services run as LocalSystem.

    Any parameter left out is prompted for interactively, with a suggested default.

.NOTES
    Maintainers: docs/install/SCRIPT.md in the Polygent repository describes publishing, the
    product contracts this script depends on, and the design decisions behind it.

.EXAMPLE
    irm https://raw.githubusercontent.com/roeibajayo/polygent-official/main/install-polygent.ps1 | iex

    Runs the published script without saving it first.

.EXAMPLE
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/roeibajayo/polygent-official/main/install-polygent.ps1))) -Components DeployWorker

    Runs the published script with parameters.

.EXAMPLE
    .\install-polygent.ps1

.EXAMPLE
    .\install-polygent.ps1 -Components Server -DataRoot D:\Polygent -PublicUrl https://polygent.example.com

.EXAMPLE
    .\install-polygent.ps1 -Components SessionWorker -ServerUrl https://polygent.example.com
#>
[CmdletBinding()]
param(
    # Components to install, upgrade, or uninstall.
    [string[]] $Components,

    # What to do with selected components that are already installed. Default: ask.
    # Components that are not installed are always installed (or skipped for Uninstall).
    [string] $Action,

    # Uninstall: also delete each component's StoragePath (database, working copies, logs).
    # Default: ask, with No as the default answer.
    [switch] $RemoveData,

    # Parent folder for program files; each component goes to its own subfolder.
    # Default: C:\Program Files\Polygent.
    [string] $InstallRoot,

    # Parent folder for component data; each component's StoragePath is a subfolder.
    # Default: the local drive with the most free space (<drive>:\Polygent, or C:\ProgramData\Polygent).
    [string] $DataRoot,

    # Release to install, e.g. 1.1.0. Default: for workers, the release of the server they connect
    # to; otherwise the latest release.
    [string] $Version = 'latest',

    # Server: public HTTPS URL users browse to (sets ClientUrl and Login:ClientUrl).
    [string] $PublicUrl,

    # Workers: public URL of the Polygent server the worker connects to.
    [string] $ServerUrl,

    # Session Worker host API key (Hosts -> API Keys -> New API Key -> Session Worker).
    # SecureString or plain text; omit it to be prompted.
    $SessionWorkerApiKey,

    # Deployment Worker host API key (Hosts -> API Keys -> New API Key -> Deploy Worker).
    # SecureString or plain text; omit it to be prompted.
    $DeployWorkerApiKey,

    # Workers: name shown on the Hosts page; also the Deployment Worker's stable ServerId.
    # Default: the computer name.
    [string] $WorkerName,

    # Register and configure the services without starting them.
    [switch] $NoStart,

    # Fail instead of installing missing prerequisites (.NET 10 Hosting Bundle, Git).
    [switch] $SkipPrerequisites,

    # GitHub repository that publishes the release assets.
    [string] $Repository = 'roeibajayo/polygent-official'
)

# Rebuilds this invocation as an encoded command that runs $ScriptPath with the same arguments.
# Secrets cross the process boundary DPAPI-encrypted for the current user; a process running as a
# different account cannot decrypt them and prompts again.
function Get-RelaunchCommand([string] $ScriptPath, $BoundParameters, [switch] $PassExitCode) {
    $quote = { param($value) "'" + ([string] $value).Replace("'", "''") + "'" }
    $decrypt = { param($secure) "`$(try { ConvertTo-SecureString $(& $quote (ConvertFrom-SecureString $secure)) } catch { `$null })" }
    $arguments = foreach ($entry in $BoundParameters.GetEnumerator()) {
        $value = $entry.Value
        if ($entry.Key -like '*ApiKey' -and $value -is [string] -and $value) { $value = ConvertTo-SecureString $value -AsPlainText -Force }
        if ($value -is [securestring]) { "-$($entry.Key) $(& $decrypt $value)"; continue }
        if ($value -is [switch]) { "-$($entry.Key):`$$($value.IsPresent.ToString().ToLowerInvariant())"; continue }
        if ($value -is [array]) { "-$($entry.Key) $(($value | ForEach-Object { & $quote $_ }) -join ',')"; continue }
        "-$($entry.Key) $(& $quote $value)"
    }
    $command = "& $(& $quote $ScriptPath) $($arguments -join ' ')"
    if ($PassExitCode) { $command += '; exit $LASTEXITCODE' }
    # A new process started through UAC does not inherit this session's environment.
    if ($env:GITHUB_TOKEN) {
        $token = & $decrypt (ConvertTo-SecureString $env:GITHUB_TOKEN -AsPlainText -Force)
        $command = "`$secureToken = $token; if (`$secureToken) { `$env:GITHUB_TOKEN = [pscredential]::new('token', `$secureToken).GetNetworkCredential().Password }; $command"
    }
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
}

# Run as text ("irm <url> | iex", or "& ([scriptblock]::Create((irm <url>))) -Param ...") there is no
# file to relaunch elevated, 'exit' would close the caller's PowerShell window, and under iex every
# assignment below would land in the caller's session. So before anything else, save a copy to a
# temporary file and run it in a child process in this console. Under iex the script cannot read its
# own text and downloads the published copy. (Marker: polygent-installer-bootstrap.)
if (-not $PSCommandPath) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $installerText = "$($MyInvocation.MyCommand.ScriptBlock)"
    if ($installerText -notmatch 'polygent-installer-bootstrap') {
        $installerText = Invoke-RestMethod -UseBasicParsing -Headers @{ 'User-Agent' = 'polygent-installer' } `
            -Uri 'https://raw.githubusercontent.com/roeibajayo/polygent-official/main/install-polygent.ps1'
    }
    $installerCopy = Join-Path ([IO.Path]::GetTempPath()) 'install-polygent.ps1'
    [IO.File]::WriteAllText($installerCopy, $installerText, (New-Object Text.UTF8Encoding $true))
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -EncodedCommand (Get-RelaunchCommand $installerCopy $PSBoundParameters -PassExitCode)
    return
}

$ErrorActionPreference = 'Stop'

# Validated here rather than with [ValidateSet]: that attribute breaks "irm <url> | iex".
foreach ($name in @($Components)) {
    if ($name -and $name -notin 'Server', 'SessionWorker', 'DeployWorker') { throw "-Components accepts Server, SessionWorker, DeployWorker; got '$name'." }
}
if ($Action -and $Action -notin 'Upgrade', 'Uninstall') { throw "-Action accepts Upgrade or Uninstall; got '$Action'." }
$ProgressPreference = 'SilentlyContinue'

$definitions = [ordered]@{
    Server        = @{ Label = 'Server'; Summary = 'Web app and API; also runs sessions itself'; Asset = 'server'; Folder = 'server'; Exe = 'Polygent.Api.exe'; ServiceName = 'Polygent'; DisplayName = 'Polygent Server' }
    SessionWorker = @{ Label = 'Session Worker'; Summary = 'Runs agent sessions on this machine for a remote Server'; Asset = 'session-worker'; Folder = 'session-worker'; Exe = 'Polygent.SessionWorker.exe'; ServiceName = 'PolygentSessionWorker'; DisplayName = 'Polygent Session Worker' }
    DeployWorker  = @{ Label = 'Deployment Worker'; Summary = 'Runs preview deployment slots on this machine'; Asset = 'deploy-worker'; Folder = 'deploy-worker'; Exe = 'Polygent.DeployWorker.exe'; ServiceName = 'PolygentDeploymentWorker'; DisplayName = 'Polygent Deployment Worker' }
}

# Files that belong to the operator, not the package: never deleted or overwritten on upgrade.
$productionSettingsName = 'appsettings.Production.json'
$baselineName = 'install-baseline.json'  # copy of the installed package's appsettings.json
$preservedNames = @($productionSettingsName, $baselineName, 'crash.log')
$preservedDirs = @('logs')
$manifestName = 'install-manifest.txt'

#region Helpers

function Write-Step([string] $Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Note([string] $Message) { Write-Host "    $Message" }

$script:Prompted = $false

function Read-Value([string] $Prompt, [string] $Default, [switch] $Required) {
    $script:Prompted = $true
    while ($true) {
        $suffix = if ($Default) { " [$Default]" } else { '' }
        $value = Read-Host "$Prompt$suffix"
        if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
        if ($value -or -not $Required) { return $value }
        Write-Host '    A value is required.' -ForegroundColor Yellow
    }
}

function Read-YesNo([string] $Prompt, [bool] $Default = $true) {
    $script:Prompted = $true
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = Read-Host "$Prompt $hint"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        if ($answer -match '^(y|yes)$') { return $true }
        if ($answer -match '^(n|no)$') { return $false }
    }
}

function Read-Choice([string] $Prompt, [string[]] $Options) {
    for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host "  $($i + 1)) $($Options[$i])" }
    while ($true) {
        $answer = Read-Value $Prompt '1'
        $n = 0
        if ([int]::TryParse($answer, [ref] $n) -and $n -ge 1 -and $n -le $Options.Count) { return $Options[$n - 1] }
        Write-Host '    Invalid selection.' -ForegroundColor Yellow
    }
}

function Read-Secret([string] $Prompt) {
    $script:Prompted = $true
    while ($true) {
        $value = Read-Host $Prompt -AsSecureString
        if ($value.Length -gt 0) { return $value }
        Write-Host '    A value is required.' -ForegroundColor Yellow
    }
}

# API key parameters accept a SecureString (when the script is invoked in-process) or plain text
# (the only form that survives "powershell -File", which passes arguments as strings).
function ConvertTo-SecretValue($Value, [string] $Name) {
    if ($null -eq $Value -or $Value -is [securestring]) { return $Value }
    $text = [string] $Value
    if ($text -eq 'System.Security.SecureString') {
        throw "-$Name received a SecureString through 'powershell -File', which turns it into text. Omit -$Name to be prompted for the key, or pass the key as plain text."
    }
    if (-not $text) { return $null }
    return ConvertTo-SecureString $text -AsPlainText -Force
}

function ConvertTo-PlainText([securestring] $Value) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Assert-AbsoluteUrl([string] $Url, [string] $Name) {
    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref] $uri) -or $uri.Scheme -notin 'http', 'https') {
        throw "$Name must be an absolute http(s) URL, got '$Url'."
    }
    if ($uri.Scheme -eq 'http' -and -not $uri.IsLoopback) {
        Write-Warning "$Name uses plain HTTP. Production traffic must go through HTTPS."
    }
    return $Url.TrimEnd('/')
}

function Get-JsonValue($Object, [string] $Path) {
    $node = $Object
    foreach ($part in $Path -split ':') {
        if ($null -eq $node -or -not ($node.PSObject.Properties.Name -contains $part)) { return $null }
        $node = $node.$part
    }
    return $node
}

function Set-JsonValue($Object, [string] $Path, $Value) {
    $parts = $Path -split ':'
    $node = $Object
    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
        $name = $parts[$i]
        if (-not ($node.PSObject.Properties.Name -contains $name) -or $null -eq $node.$name) {
            $node | Add-Member -NotePropertyName $name -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $node = $node.$name
    }
    $node | Add-Member -NotePropertyName $parts[-1] -NotePropertyValue $Value -Force
}

function Read-JsonFile([string] $Path) {
    if (-not (Test-Path $Path)) { return $null }
    return Get-Content -Raw -Path $Path | ConvertFrom-Json
}

function Write-JsonFile([string] $Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 32), (New-Object Text.UTF8Encoding $false))
}

function Test-JsonObject($Value) { return $Value -is [Management.Automation.PSCustomObject] }

# Copies $Source into $Target. Without -Override, values already in $Target win.
function Merge-Json($Target, $Source, [switch] $Override) {
    foreach ($property in $Source.PSObject.Properties) {
        $name = $property.Name
        $exists = $Target.PSObject.Properties.Name -contains $name
        if ($exists -and (Test-JsonObject $Target.$name) -and (Test-JsonObject $property.Value)) {
            Merge-Json $Target.$name $property.Value -Override:$Override
        }
        elseif (-not $exists -or $Override) {
            $Target | Add-Member -NotePropertyName $name -NotePropertyValue $property.Value -Force
        }
    }
}

# The values in $Current that differ from (or are absent in) $Baseline, keeping the nesting.
# Arrays are compared and copied whole.
function Get-JsonOverrides($Current, $Baseline) {
    $overrides = [pscustomobject]@{}
    foreach ($property in $Current.PSObject.Properties) {
        $name = $property.Name
        $inBaseline = $Baseline -and ($Baseline.PSObject.Properties.Name -contains $name)
        $baseValue = if ($inBaseline) { $Baseline.$name } else { $null }
        if ($inBaseline -and (Test-JsonObject $property.Value) -and (Test-JsonObject $baseValue)) {
            $nested = Get-JsonOverrides $property.Value $baseValue
            if (@($nested.PSObject.Properties).Count -gt 0) { $overrides | Add-Member -NotePropertyName $name -NotePropertyValue $nested }
        }
        elseif (-not $inBaseline -or (ConvertTo-Json -InputObject $property.Value -Compress -Depth 32) -ne (ConvertTo-Json -InputObject $baseValue -Compress -Depth 32)) {
            $overrides | Add-Member -NotePropertyName $name -NotePropertyValue $property.Value
        }
    }
    return $overrides
}

# appsettings.json belongs to the package and is replaced on every upgrade so new defaults arrive.
# Everything this script or the operator sets lives in appsettings.Production.json, which the
# services load on top of it (they run in the Production environment) and which upgrades keep.
# This returns the effective configuration: appsettings.json overlaid by appsettings.Production.json.
function Read-AppSettings([string] $Directory) {
    $settings = Read-JsonFile (Join-Path $Directory 'appsettings.json')
    if (-not $settings) { $settings = [pscustomobject]@{} }
    $production = Read-JsonFile (Join-Path $Directory $productionSettingsName)
    if ($production) { Merge-Json $settings $production -Override }
    return $settings
}

# The appsettings.json a given release shipped, used to tell operator edits from package defaults.
function Get-ReleaseAppSettings([string] $Version, $Definition, [string] $TempRoot) {
    if ($Version -eq $releaseVersion) { return Read-JsonFile (Join-Path $TempRoot "$($Definition.Asset)\appsettings.json") }
    try {
        $baselineRelease = Get-GitHubRelease $Repository "v$Version"
        $zip = Join-Path $TempRoot "baseline-$($Definition.Asset)-$Version.zip"
        Save-GitHubAsset $baselineRelease "$($Definition.Asset)-$Version-win-x64.zip" $zip
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            $entry = $archive.GetEntry('appsettings.json')
            if (-not $entry) { return $null }
            $reader = New-Object IO.StreamReader($entry.Open())
            try { return $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        }
        finally { $archive.Dispose() }
    }
    catch { return $null }
}

# Folders created directly under a drive root inherit "Authenticated Users: Modify", which would
# let any local user replace binaries that run as LocalSystem, or read the API keys in
# appsettings.Production.json. New (or still empty) folders get an explicit ACL instead of the inherited one;
# folders that already hold content keep the permissions the operator gave them.
function New-ProtectedDirectory([string] $Path, [switch] $AllowUsersRead) {
    if ([IO.Path]::GetPathRoot($Path).TrimEnd('\') -eq $Path.TrimEnd('\')) { return }  # never re-ACL a drive root
    if (Test-Path $Path) {
        if (Get-ChildItem -Path $Path -Force) { return }
    }
    else {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    $grants = @('*S-1-5-32-544:(OI)(CI)F', '*S-1-5-18:(OI)(CI)F')  # Administrators, SYSTEM
    if ($AllowUsersRead) { $grants += '*S-1-5-32-545:(OI)(CI)RX' }  # Users
    & icacls.exe $Path /inheritance:r /grant:r @grants | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls failed to set permissions on '$Path' (exit code $LASTEXITCODE)." }
}

function Get-InstalledService([string] $Name) {
    return Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'"
}

function Get-ServiceExePath($Service) {
    $pathName = $Service.PathName.Trim()
    if ($pathName.StartsWith('"')) { return $pathName.Substring(1, $pathName.IndexOf('"', 1) - 1) }
    return ($pathName -split ' ')[0]
}

function Stop-ComponentService([string] $Name, [string] $ExePath) {
    $service = Get-Service -Name $Name
    if ($service.Status -ne 'Stopped') {
        Write-Note "Stopping service '$Name'..."
        Stop-Service -Name $Name -Force
    }
    # The process can outlive the SCM "stopped" state briefly and keep its files locked.
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $ExePath }) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
}

function Assert-HarnessRollbackReady($Item, [string] $InstalledVersion, [string] $TargetVersion) {
    if ($Item.Key -notin @('Server', 'SessionWorker')) { return }
    $installed = ($InstalledVersion -split '\+')[0].TrimStart('v')
    $target = $TargetVersion.TrimStart('v')
    if (-not $installed) { throw 'Cannot establish the installed harness version; refusing to replace its binaries.' }
    if ([version](($target -split '-')[0]) -gt [version](($installed -split '-')[0]) -or $target -eq $installed) { return }
    if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $Item.InstallDir $Item.Definition.Exe) }) {
        throw 'The harness host is still running. Stop it before preparing or installing a rollback.'
    }

    $settings = Read-AppSettings $Item.InstallDir
    $harnessRoot = Get-JsonValue $settings 'Harness:DataDirectory'
    $machineHarnessRoot = [Environment]::GetEnvironmentVariable('Harness__DataDirectory', 'Machine')
    if ($machineHarnessRoot) { $harnessRoot = $machineHarnessRoot }
    $environmentRoot = [Environment]::GetEnvironmentVariable('POLYGENT_HARNESS_DATA_DIR', 'Machine')
    $serviceSettings = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($Item.Definition.ServiceName)" -ErrorAction SilentlyContinue
    foreach ($entry in $serviceSettings.Environment) {
        if ($entry -like 'Harness__DataDirectory=*') { $harnessRoot = $entry.Substring('Harness__DataDirectory='.Length) }
        if ($entry -like 'POLYGENT_HARNESS_DATA_DIR=*') { $environmentRoot = $entry.Substring('POLYGENT_HARNESS_DATA_DIR='.Length) }
    }
    if ($environmentRoot) { $harnessRoot = $environmentRoot }
    if (-not $harnessRoot) {
        $service = Get-InstalledService $Item.Definition.ServiceName
        if ($service.StartName -ne 'LocalSystem') {
            throw 'Rollback requires an explicit Harness:DataDirectory for a service using a custom account. Verify its actual harness directory before retrying.'
        }
        $harnessRoot = Join-Path $env:SystemRoot 'System32\config\systemprofile\.polygent\harness'
    }
    if (-not [IO.Path]::IsPathRooted($harnessRoot)) { throw 'Rollback requires an absolute harness data directory.' }
    $sessionsRoot = Join-Path $harnessRoot 'sessions'
    if (-not (Test-Path -LiteralPath $sessionsRoot)) { return }
    foreach ($session in Get-ChildItem -LiteralPath $sessionsRoot -Directory -Force) {
        $journal = Join-Path $session.FullName 'journal'
        if ((Test-Path -LiteralPath $journal) -and (Get-ChildItem -LiteralPath $journal -File -Force -Filter '*.jsonl')) {
            throw "Rollback blocked: harness journals remain in '$harnessRoot'. With the host stopped, use a build containing --prepare-harness-rollback to convert this directory into checkpoints with a new backup outside it, then retry. See docs/modules/polygent-code-harness.md. The installed binaries have not been replaced."
        }
    }
}

function Get-ComponentState([string] $Key) {
    $service = Get-InstalledService $definitions[$Key].ServiceName
    if (-not $service) { return [pscustomobject]@{ Installed = $false; Service = $null; Status = 'Not installed'; Version = $null; InstallDir = $null } }
    $exe = Get-ServiceExePath $service
    $version = (Get-Item -Path $exe -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
    $version = if ($version) { 'v' + ($version -split '\+')[0] } else { 'unknown version' }
    return [pscustomobject]@{ Installed = $true; Service = $service; Status = $service.State; Version = $version; InstallDir = (Split-Path -Parent $exe) }
}

# Only folders this script created or configured are ever deleted; this guards against a
# misconfigured StoragePath pointing at a drive root or a system folder.
function Test-SafeToDelete([string] $Path) {
    if (-not $Path) { return $false }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ([IO.Path]::GetPathRoot($full).TrimEnd('\') -eq $full) { return $false }
    $protected = @($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:USERPROFILE, (Split-Path -Parent $env:USERPROFILE)) |
        Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    return $full -notin $protected
}

function Remove-DirectoryTree([string] $Path) {
    if (-not (Test-Path $Path)) { return }
    try { Remove-Item -Path $Path -Recurse -Force }
    catch {
        # Working copies can exceed MAX_PATH, which Windows PowerShell's Remove-Item cannot delete.
        & cmd.exe /c "rd /s /q `"\\?\$([IO.Path]::GetFullPath($Path))`""
        if (Test-Path $Path) { throw "Could not delete '$Path': $($_.Exception.Message)" }
    }
}

function Remove-EmptyDirectory([string] $Path) {
    if ((Test-SafeToDelete $Path) -and (Test-Path $Path) -and -not (Get-ChildItem -Path $Path -Force)) {
        Remove-Item -Path $Path -Force
    }
}

function Uninstall-Component($Item) {
    $definition = $Item.Definition
    if ($Item.Key -eq 'SessionWorker') { Write-Note 'The Session Worker waits for running sessions to finish before stopping (up to ShutdownDrainTimeoutSeconds).' }
    Stop-ComponentService $definition.ServiceName (Join-Path $Item.InstallDir $definition.Exe)
    & sc.exe delete $definition.ServiceName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not delete service '$($definition.ServiceName)' (sc.exe exit code $LASTEXITCODE)." }
    Write-Note "Removed service '$($definition.ServiceName)'."

    if ($Item.ScriptInstalled) {
        Remove-DirectoryTree $Item.InstallDir
        Write-Note "Removed $($Item.InstallDir)."
        Remove-EmptyDirectory (Split-Path -Parent $Item.InstallDir)
    }
    else {
        Write-Note "Kept $($Item.InstallDir): it was not installed by this script."
    }

    if ($Item.RemoveData) {
        Remove-DirectoryTree $Item.DataDir
        Write-Note "Removed $($Item.DataDir)."
        Remove-EmptyDirectory (Split-Path -Parent $Item.DataDir)
    }
}

function Get-RelativeFiles([string] $Root) {
    $prefix = $Root.TrimEnd('\').Length + 1
    return @(Get-ChildItem -Path $Root -Recurse -File | ForEach-Object { $_.FullName.Substring($prefix) })
}

function Test-Preserved([string] $RelativePath) {
    $first = ($RelativePath -split '\\')[0]
    return ($RelativePath -in $preservedNames) -or ($first -in $preservedDirs) -or ($RelativePath -eq $manifestName)
}

# Replaces the previous package's files with the new package's. Files listed in the previous
# manifest but absent from the new package are removed.
# -KeepAppSettings leaves the installed appsettings.json in place (settings that could not be migrated).
function Sync-PackageFiles([string] $Staging, [string] $Target, [switch] $KeepAppSettings) {
    $newFiles = Get-RelativeFiles $Staging | Where-Object { -not (Test-Preserved $_) }
    $manifestPath = Join-Path $Target $manifestName

    if (Test-Path $manifestPath) {
        $oldFiles = Get-Content -Path $manifestPath
        foreach ($stale in $oldFiles | Where-Object { $_ -and $_ -notin $newFiles -and -not (Test-Preserved $_) }) {
            $stalePath = Join-Path $Target $stale
            if (Test-Path $stalePath) { Remove-Item -Path $stalePath -Force }
        }
        Get-ChildItem -Path $Target -Recurse -Directory |
            Where-Object { ($_.FullName.Substring($Target.TrimEnd('\').Length + 1) -split '\\')[0] -notin $preservedDirs } |
            Sort-Object { $_.FullName.Length } -Descending |
            Where-Object { -not (Get-ChildItem -Path $_.FullName -Force) } |
            Remove-Item -Force
    }
    else {
        # Installed without this script: only the harness plugin folder, which older packages shipped
        # and current packages no longer do, is known to be package-owned.
        $pluginRoot = Join-Path $Target 'plugins'
        if (Test-Path $pluginRoot) { Remove-Item -Path $pluginRoot -Recurse -Force }
    }

    # Excluded by full source path, so only the root-level file is skipped.
    $keep = @($preservedNames) + $(if ($KeepAppSettings) { 'appsettings.json' })
    $excluded = @($keep | Where-Object { $_ -and (Test-Path (Join-Path $Target $_)) } | ForEach-Object { Join-Path $Staging $_ })
    $robocopyArgs = @($Staging, $Target, '/E', '/R:3', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($excluded.Count -gt 0) { $robocopyArgs += @('/XF') + $excluded }
    & robocopy.exe @robocopyArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Copying files to '$Target' failed (robocopy exit code $LASTEXITCODE)." }

    [IO.File]::WriteAllLines($manifestPath, [string[]] $newFiles)
}

# Kestrel:Endpoints overrides Urls. HTTP is preferred: it needs no trusted certificate for the local
# health check or for a worker on the same machine.
function Get-ListenUrl([string] $Directory) {
    $settings = Read-AppSettings $Directory
    $urls = @()
    $endpoints = Get-JsonValue $settings 'Kestrel:Endpoints'
    if ($endpoints) { $urls = @($endpoints.PSObject.Properties | ForEach-Object { $_.Value.Url } | Where-Object { $_ }) }
    if (-not $urls -and (Get-JsonValue $settings 'Urls')) { $urls = @((Get-JsonValue $settings 'Urls') -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    if (-not $urls) { return 'http://localhost:5000' }
    $url = @($urls | Where-Object { $_ -like 'http://*' }) + @($urls) | Select-Object -First 1
    return $url -replace '://(\*|\+|0\.0\.0\.0|\[::\])', '://localhost'
}

function Show-CrashLog([string] $Directory) {
    $crashLog = Join-Path $Directory 'crash.log'
    if ((Test-Path $crashLog) -and (Get-Item $crashLog).Length -gt 0) {
        Write-Host "    crash.log:" -ForegroundColor Yellow
        Get-Content -Path $crashLog -Tail 20 | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
    }
}

function Wait-ComponentHealthy([string] $Key, $Definition, [string] $Directory) {
    $name = $Definition.ServiceName
    if ($Key -eq 'Server') {
        $url = Get-ListenUrl $Directory
        if ($url.StartsWith('http://')) {
            $ping = "$($url.TrimEnd('/'))/api/ping"
            $deadline = (Get-Date).AddMinutes(2)
            while ((Get-Date) -lt $deadline) {
                if ((Get-Service -Name $name).Status -eq 'Stopped') { break }
                try {
                    if ((Invoke-WebRequest -Uri $ping -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200) {
                        Write-Note "Health check passed: $ping"
                        return $true
                    }
                }
                catch { Start-Sleep -Seconds 2 }
            }
            Write-Warning "$($Definition.Label) did not answer $ping."
            Show-CrashLog $Directory
            return $false
        }
    }

    # Workers exit within seconds on a configuration error (for example a missing StoragePath).
    Start-Sleep -Seconds 10
    if ((Get-Service -Name $name).Status -eq 'Running') {
        Write-Note "Service '$name' is running."
        return $true
    }
    Write-Warning "Service '$name' is not running."
    Show-CrashLog $Directory
    return $false
}

function Save-VerifiedFile([string] $Url, [string] $Destination, [string] $Algorithm, [string] $ExpectedHash, [hashtable] $Headers = @{}) {
    $name = Split-Path -Leaf $Destination
    Write-Note "Downloading $name..."
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -Headers (@{ 'User-Agent' = 'polygent-installer' } + $Headers)
    if (-not $ExpectedHash) {
        Write-Warning "No published digest for $name; integrity was not verified."
        return
    }
    if ((Get-FileHash -Path $Destination -Algorithm $Algorithm).Hash -ne $ExpectedHash) {
        throw "$Algorithm mismatch for $name. The download may be corrupted or tampered with."
    }
    Write-Note "$Algorithm verified."
}

# A token is optional: it is needed only for a private -Repository and raises the API rate limit.
# Taken from GITHUB_TOKEN, else from the GitHub CLI login of the account running the script.
function Get-GitHubAuthHeaders {
    if ($null -eq $script:GitHubToken) {
        $script:GitHubToken = $env:GITHUB_TOKEN
        if (-not $script:GitHubToken -and (Get-Command gh -ErrorAction SilentlyContinue)) {
            $script:GitHubToken = "$(& gh auth token 2>$null)".Trim()
        }
    }
    if ($script:GitHubToken) { return @{ 'Authorization' = "Bearer $script:GitHubToken" } }
    return @{}
}

function Get-GitHubRelease([string] $Repo, [string] $Tag) {
    $headers = @{ 'User-Agent' = 'polygent-installer'; 'Accept' = 'application/vnd.github+json' } + (Get-GitHubAuthHeaders)
    $uri = if ($Tag -eq 'latest') { "https://api.github.com/repos/$Repo/releases/latest" } else { "https://api.github.com/repos/$Repo/releases/tags/$Tag" }
    try { return Invoke-RestMethod -Uri $uri -Headers $headers }
    catch {
        $hint = if ((Get-GitHubAuthHeaders).Count -eq 0) { ' For a private repository, set GITHUB_TOKEN or sign in with the GitHub CLI (gh auth login).' } else { '' }
        throw "Could not find release '$Tag' in $Repo ($($_.Exception.Message)).$hint"
    }
}

function Save-GitHubAsset($Release, [string] $AssetName, [string] $Destination) {
    $asset = $Release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
    if (-not $asset) { throw "Release $($Release.tag_name) has no asset named '$AssetName'." }
    $digest = if ($asset.PSObject.Properties.Name -contains 'digest' -and "$($asset.digest)".StartsWith('sha256:')) { $asset.digest.Substring(7) } else { $null }
    $auth = Get-GitHubAuthHeaders
    if ($auth.Count -gt 0) {
        # Private assets are only served through the API endpoint; the browser URL returns 404.
        Save-VerifiedFile $asset.url $Destination 'SHA256' $digest ($auth + @{ 'Accept' = 'application/octet-stream' })
    }
    else {
        Save-VerifiedFile $asset.browser_download_url $Destination 'SHA256' $digest
    }
}

# Workers must run the same release as the server they connect to; the server's public
# /api/version reports it (when licensed). Returns $null when it cannot be determined.
function Get-ServerVersion([string] $Url) {
    try {
        $response = Invoke-RestMethod -Uri "$Url/api/version" -TimeoutSec 10
        if ($response.version) { return ([string] $response.version -split '\+')[0] }
    }
    catch { }
    return $null
}

function Invoke-Installer([string] $Path, [string[]] $Arguments) {
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru
    # 3010 / 1641: installed, restart required.
    if ($process.ExitCode -notin 0, 3010, 1641) { throw "$(Split-Path -Leaf $Path) failed with exit code $($process.ExitCode)." }
    return $process.ExitCode -ne 0
}

# Services run as LocalSystem, so only machine-wide state counts: the machine PATH, the registered
# .NET install location, and the default install folders. A per-user install of the admin running
# this script is invisible to the services.
function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
}

function Test-DotNetRuntime {
    $registered = Get-ItemProperty -Path 'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64' -Name InstallLocation -ErrorAction SilentlyContinue
    $roots = @([Environment]::GetEnvironmentVariable('DOTNET_ROOT', 'Machine'), $(if ($registered) { $registered.InstallLocation }), (Join-Path $env:ProgramFiles 'dotnet')) | Where-Object { $_ }
    foreach ($root in $roots) {
        $found = foreach ($framework in 'Microsoft.NETCore.App', 'Microsoft.AspNetCore.App') {
            @(Get-ChildItem -Path (Join-Path $root "shared\$framework") -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '10.*' }).Count -gt 0
        }
        if ($found -notcontains $false) { return $true }
    }
    return $false
}

function Get-GitVersion {
    $candidates = @([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';' | Where-Object { $_ } | ForEach-Object { Join-Path $_ 'git.exe' }) +
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe')
    $git = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $git) { return $null }
    $match = [regex]::Match((& $git --version), '(\d+)\.(\d+)\.(\d+)')
    if (-not $match.Success) { return $null }
    return [version]$match.Value
}

function Install-DotNetHostingBundle([string] $TempRoot) {
    $metadata = Invoke-RestMethod -Uri 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json'
    $release = $metadata.releases | Where-Object { $_.'release-version' -eq $metadata.'latest-release' } | Select-Object -First 1
    if (-not $release) { $release = $metadata.releases[0] }
    # The Hosting Bundle carries both the .NET and ASP.NET Core runtimes; the standalone ASP.NET Core
    # installer does not include the .NET runtime it depends on.
    $file = $release.'aspnetcore-runtime'.files | Where-Object { $_.name -eq 'dotnet-hosting-win.exe' } | Select-Object -First 1
    if (-not $file) { throw "The .NET $($release.'release-version') release metadata has no Hosting Bundle installer." }

    $installer = Join-Path $TempRoot "dotnet-hosting-$($release.'release-version')-win.exe"
    Save-VerifiedFile $file.url $installer 'SHA512' $file.hash
    Write-Note "Running the .NET $($release.'release-version') Hosting Bundle installer..."
    return Invoke-Installer $installer @('/install', '/quiet', '/norestart')
}

function Install-Git([string] $TempRoot) {
    $release = Get-GitHubRelease 'git-for-windows/git' 'latest'
    $asset = $release.assets | Where-Object { $_.name -match '^Git-[\d.]+-64-bit\.exe$' } | Select-Object -First 1
    if (-not $asset) { throw "Git for Windows $($release.tag_name) has no 64-bit installer." }

    $installer = Join-Path $TempRoot $asset.name
    Save-GitHubAsset $release $asset.name $installer
    Write-Note "Running the Git for Windows $($release.tag_name) installer..."
    return Invoke-Installer $installer @('/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/SUPPRESSMSGBOXES', '/CLOSEAPPLICATIONS')
}

$minimumGit = [version]'2.29.0'

# Read-only checks against the System Requirements page. Returns which prerequisites are missing;
# everything else is reported as a warning because the install can still proceed.
function Test-SystemRequirements($Plan, [string] $WorkerServerUrl) {
    $newInstalls = @($Plan | Where-Object Action -eq 'Install')

    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt 17763) { Write-Warning "Windows build $build is not supported. Use Windows 10/11 or Windows Server 2019 or later." }

    $cores = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $memoryGb = [math]::Round((Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    Write-Note "Hardware: $cores CPU cores, $memoryGb GB RAM."
    if ($cores -lt 2) { Write-Warning 'Polygent needs at least 2 CPU cores (4+ recommended).' }
    if ($memoryGb -lt 3.5) { Write-Warning 'Polygent needs at least 4 GB RAM (8+ GB recommended).' }

    foreach ($item in $newInstalls) {
        $free = Get-FreeSpaceGb $item.DataDir
        if ($null -ne $free -and $free -lt 10) { Write-Warning "$($item.Definition.Label): only $free GB free for $($item.DataDir); at least 10 GB is required (50+ GB recommended)." }
    }

    if ($newInstalls | Where-Object Key -eq 'Server') {
        $listener = Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($listener) {
            $owner = (Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue).ProcessName
            Write-Warning "Port 5000 is already in use by '$owner'. Set 'Urls' in the Server appsettings.Production.json to another port after installation."
        }
    }

    # Workers connect outbound to the server; check that path now rather than after the service starts.
    if ($WorkerServerUrl -and ($Plan | Where-Object Key -ne 'Server')) {
        try {
            [void] (Invoke-WebRequest -Uri "$WorkerServerUrl/api/ping" -UseBasicParsing -TimeoutSec 10)
            Write-Note "Server reachable: $WorkerServerUrl"
        }
        catch {
            Write-Warning "Cannot reach $WorkerServerUrl/api/ping from this machine ($($_.Exception.Message)). The worker will keep retrying once installed."
        }
    }

    $needDotNet = -not (Test-DotNetRuntime)
    Write-Note ".NET 10 runtimes: $(if ($needDotNet) { 'missing' } else { 'installed' })."
    $gitVersion = Get-GitVersion
    $needGit = -not $gitVersion -or $gitVersion -lt $minimumGit
    Write-Note "Git: $(if (-not $gitVersion) { 'missing' } elseif ($needGit) { "$gitVersion (older than $minimumGit)" } else { "$gitVersion" })."

    if ($SkipPrerequisites -and ($needDotNet -or $needGit)) {
        throw 'Missing prerequisites. Install the .NET 10 Hosting Bundle (https://dotnet.microsoft.com/download/dotnet/10.0) and Git 2.29+ (https://git-scm.com/download/win), or run again without -SkipPrerequisites.'
    }
    return [pscustomobject]@{ DotNet = $needDotNet; Git = $needGit }
}

# Returns the names of the prerequisites installed in this run.
function Install-Prerequisites([string] $TempRoot, $Missing) {
    $installed = @()
    if ($Missing.DotNet) {
        [void] (Install-DotNetHostingBundle $TempRoot)
        if (-not (Test-DotNetRuntime)) { throw 'The .NET 10 Hosting Bundle installer finished, but the runtimes were not found.' }
        $installed += '.NET 10 Hosting Bundle'
    }
    if ($Missing.Git) {
        [void] (Install-Git $TempRoot)
        Update-SessionPath
        $gitVersion = Get-GitVersion
        if (-not $gitVersion -or $gitVersion -lt $minimumGit) { throw 'The Git for Windows installer finished, but Git was not found on the machine PATH.' }
        $installed += "Git $gitVersion"
    }
    return $installed
}

# Data grows with every working copy, so suggest the local drive with the most free space.
function Get-SuggestedDataRoot {
    $best = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object -Property FreeSpace -Descending | Select-Object -First 1
    if (-not $best -or $best.DeviceID -eq $env:SystemDrive) { return Join-Path $env:ProgramData 'Polygent' }
    return "$($best.DeviceID)\Polygent"
}

function Get-FreeSpaceGb([string] $Path) {
    $drive = [IO.Path]::GetPathRoot($Path).TrimEnd('\')
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction SilentlyContinue
    if ($disk) { return [math]::Floor($disk.FreeSpace / 1GB) }
    return $null
}

function ConvertFrom-JwtPayload([string] $Token) {
    $parts = "$Token" -split '\.'
    if ($parts.Count -lt 2) { return $null }
    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
    try { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json }
    catch { return $null }
}

# The services run as LocalSystem, whose own profile has no command-line tool logins. The login of
# the admin running this script can be shared instead, per host, in the UI's Agent Logins section:
# the Claude Code login folder (Polygent then also launches that account's own Claude CLI install)
# and the Codex login folder for the ChatGPT/Codex subscription used by OpenAI models. The script
# detects them and prints the folders to paste there in Next steps.
function Find-ClaudeLogin {
    $directory = Join-Path $env:USERPROFILE '.claude'
    $credentials = Join-Path $directory '.credentials.json'
    if (-not (Test-Path $credentials)) { return $null }
    $plan = $null
    try { $plan = (Get-Content -Raw -Path $credentials | ConvertFrom-Json).claudeAiOauth.subscriptionType } catch { }
    $cli = @(
        (Join-Path $env:USERPROFILE '.local\bin\claude.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\claude'),
        (Join-Path $env:APPDATA 'npm\claude.cmd')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    return [pscustomobject]@{ Directory = $directory; Plan = $plan; CliFound = [bool] $cli }
}

function Find-CodexLogin {
    $directory = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $authPath = Join-Path $directory 'auth.json'
    if (-not (Test-Path $authPath)) { return $null }
    try { $auth = Get-Content -Raw -Path $authPath | ConvertFrom-Json } catch { return $null }
    # An API-key-only login carries no OAuth tokens and is not a subscription.
    if (-not $auth.tokens -or -not $auth.tokens.refresh_token) { return $null }
    $plan = $null
    foreach ($token in $auth.tokens.access_token, $auth.tokens.id_token) {
        $claims = ConvertFrom-JwtPayload $token
        if ($claims -and $claims.'https://api.openai.com/auth'.chatgpt_plan_type) { $plan = $claims.'https://api.openai.com/auth'.chatgpt_plan_type; break }
    }
    return [pscustomobject]@{ Directory = $directory; Plan = $plan }
}

function Get-StoragePath($Key, $Settings) {
    $path = if ($Key -eq 'DeployWorker') { 'Agent:StoragePath' } else { 'StoragePath' }
    return Get-JsonValue $Settings $path
}

# Reuses what this machine already knows: the public URL entered for a Server in this run, a URL an
# installed worker already connects to, or the local Server's listen address.
function Get-SuggestedServerUrl {
    if ($PublicUrl) { return $PublicUrl }
    $placeholders = @('https://localhost:5001', 'https://localhost:6457')
    foreach ($key in 'SessionWorker', 'DeployWorker') {
        $service = Get-InstalledService $definitions[$key].ServiceName
        if (-not $service) { continue }
        $settings = Read-AppSettings (Split-Path -Parent (Get-ServiceExePath $service))
        $url = Get-JsonValue $settings $(if ($key -eq 'DeployWorker') { 'Agent:MainServerUrl' } else { 'ApiUrl' })
        if ($url -and $url -notin $placeholders) { return $url }
    }
    $server = Get-InstalledService $definitions.Server.ServiceName
    if ($server) { return Get-ListenUrl (Split-Path -Parent (Get-ServiceExePath $server)) }
    if ($Components -contains 'Server') { return 'http://localhost:5000' }
    return $null
}

#endregion

#region Preconditions

$SessionWorkerApiKey = ConvertTo-SecretValue $SessionWorkerApiKey 'SessionWorkerApiKey'
$DeployWorkerApiKey = ConvertTo-SecretValue $DeployWorkerApiKey 'DeployWorkerApiKey'
# The elevated relaunch below rebuilds its arguments from the bound parameters; keep keys encrypted there.
foreach ($name in 'SessionWorkerApiKey', 'DeployWorkerApiKey') {
    if ($PSBoundParameters.ContainsKey($name)) { $PSBoundParameters[$name] = Get-Variable -Name $name -ValueOnly }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Relaunch elevated (UAC prompt) with the same arguments. The new window stays open after the script
# ends so its output can be read.
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Administrator rights are required; continuing in an elevated window (approve the UAC prompt).'
    try {
        Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -WorkingDirectory (Split-Path -Parent $PSCommandPath) `
            -ArgumentList '-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', (Get-RelaunchCommand $PSCommandPath $PSBoundParameters)
    }
    catch {
        Write-Host 'Elevation was cancelled; nothing was changed.' -ForegroundColor Yellow
        exit 1
    }
    exit 0
}

#endregion

#region Collect choices

$states = [ordered]@{}
foreach ($key in $definitions.Keys) { $states[$key] = Get-ComponentState $key }
$latestRelease = try { (Get-GitHubRelease $Repository 'latest').tag_name.TrimStart('v') } catch { $null }

Write-Host ''
Write-Host "Polygent on ${env:COMPUTERNAME}$(if ($latestRelease) { " (latest release: $latestRelease)" })"
$keys = @($definitions.Keys)
for ($i = 0; $i -lt $keys.Count; $i++) {
    $definition = $definitions[$keys[$i]]
    $state = $states[$keys[$i]]
    $detail = if ($state.Installed) { '{0,-9} {1,-9} {2}' -f $state.Status, $state.Version, $state.InstallDir } else { "Not installed - $($definition.Summary)" }
    Write-Host ('  {0}) {1,-18} {2}' -f ($i + 1), $definition.Label, $detail)
}
Write-Host ''

if (-not $Components) {
    while (-not $Components) {
        $answer = Read-Value 'Select components (numbers separated by commas)' '1'
        $picked = @($answer -split '[,\s]+' | Where-Object { $_ } | ForEach-Object {
            $n = 0
            if ([int]::TryParse($_, [ref] $n) -and $n -ge 1 -and $n -le $keys.Count) { $keys[$n - 1] } else { '?' }
        })
        if ($picked -contains '?' -or $picked.Count -eq 0) { Write-Host '    Invalid selection.' -ForegroundColor Yellow; continue }
        $Components = @($picked | Select-Object -Unique)
    }
}

# Components that are not installed get installed; installed ones are upgraded in place or uninstalled.
$plan = @(foreach ($key in $keys | Where-Object { $_ -in $Components }) {
    $definition = $definitions[$key]
    $state = $states[$key]
    $itemAction = 'Install'
    $dataDir = $null
    if ($state.Installed) {
        $itemAction = $Action
        if (-not $itemAction) {
            Write-Host "$($definition.Label) is installed ($($state.Version), $("$($state.Status)".ToLowerInvariant())):"
            $itemAction = Read-Choice 'Choose' @('Upgrade', 'Uninstall')
        }
        $dataDir = Get-StoragePath $key (Read-AppSettings $state.InstallDir)
    }
    elseif ($Action -eq 'Uninstall') {
        Write-Note "$($definition.Label) is not installed; skipping."
        continue
    }
    [pscustomobject]@{
        Key = $key; Definition = $definition; Service = $state.Service; Action = $itemAction
        InstallDir = $state.InstallDir; DataDir = $dataDir; InstalledVersion = $state.Version
        ScriptInstalled = [bool] ($state.Installed -and (Test-Path (Join-Path $state.InstallDir $manifestName)))
        RemoveData = $false
    }
})
if ($plan.Count -eq 0) { Write-Host 'Nothing to do.'; exit 0 }

$active = @($plan | Where-Object Action -ne 'Uninstall')
$removals = @($plan | Where-Object Action -eq 'Uninstall')

foreach ($item in $removals) {
    if (-not $item.DataDir -or -not (Test-Path $item.DataDir)) { continue }
    if (-not (Test-SafeToDelete $item.DataDir)) {
        Write-Warning "$($item.Definition.Label) StoragePath '$($item.DataDir)' is a drive root or system folder; it will not be deleted."
        continue
    }
    $item.RemoveData = if ($PSBoundParameters.ContainsKey('RemoveData')) { [bool] $RemoveData }
        else { Read-YesNo "Also delete the $($item.Definition.Label) StoragePath $($item.DataDir) (database, working copies, logs)? This cannot be undone." $false }
}

$newInstalls = @($plan | Where-Object Action -eq 'Install')
if ($newInstalls.Count -gt 0) {
    if (-not $InstallRoot) { $InstallRoot = Read-Value 'Install folder for program files' (Join-Path $env:ProgramFiles 'Polygent') -Required }
    $InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
    $suggestedDataRoot = if ($DataRoot) { [IO.Path]::GetFullPath($DataRoot) } else { Get-SuggestedDataRoot }

    foreach ($item in $newInstalls) {
        $item.InstallDir = Join-Path $InstallRoot $item.Definition.Folder
        $suggested = Join-Path $suggestedDataRoot $item.Definition.Folder
        if (-not $DataRoot) {
            $free = Get-FreeSpaceGb $suggested
            $hint = if ($null -ne $free) { ", $free GB free" } else { '' }
            $suggested = Read-Value "$($item.Definition.Label) StoragePath (database, logs, working copies$hint)" $suggested -Required
        }
        $item.DataDir = [IO.Path]::GetFullPath($suggested)

        # Upgrades remove files of the previous package from the install folder, so data must live elsewhere.
        $installPrefix = $item.InstallDir.TrimEnd('\') + '\'
        if (($item.DataDir.TrimEnd('\') + '\').StartsWith($installPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            $installPrefix.StartsWith($item.DataDir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "$($item.Definition.Label) StoragePath '$($item.DataDir)' must not overlap its install folder '$($item.InstallDir)'."
        }
    }
}

$newWorkers = @($newInstalls | Where-Object { $_.Key -ne 'Server' })

if ($PublicUrl) { $PublicUrl = Assert-AbsoluteUrl $PublicUrl 'PublicUrl' }
elseif ($newInstalls | Where-Object Key -eq 'Server') {
    $fqdn = try { [Net.Dns]::GetHostEntry([string]'').HostName.ToLowerInvariant() } catch { $env:COMPUTERNAME.ToLowerInvariant() }
    $answer = Read-Value "Public HTTPS URL users browse to, e.g. https://$fqdn (Enter to set later)"
    if ($answer) { $PublicUrl = Assert-AbsoluteUrl $answer 'PublicUrl' }
}

if ($ServerUrl) { $ServerUrl = Assert-AbsoluteUrl $ServerUrl 'ServerUrl' }
elseif ($newWorkers.Count -gt 0) {
    $ServerUrl = Assert-AbsoluteUrl (Read-Value 'Polygent server URL the workers connect to' (Get-SuggestedServerUrl) -Required) 'ServerUrl'
}

if (-not $WorkerName -and $newWorkers.Count -gt 0) {
    $WorkerName = Read-Value 'Worker name shown on the Hosts page (unique per worker)' $env:COMPUTERNAME -Required
}

# New workers need a key; upgrades keep the current one unless a replacement is passed as a parameter.
foreach ($key in 'SessionWorker', 'DeployWorker') {
    $item = $active | Where-Object Key -eq $key
    $variable = "${key}ApiKey"
    if (-not $item -or $item.Action -eq 'Upgrade' -or (Get-Variable -Name $variable -ValueOnly)) { continue }
    $prompt = "$($item.Definition.Label) host API key (Hosts -> API Keys -> New API Key -> $(if ($key -eq 'DeployWorker') { 'Deploy Worker' } else { 'Session Worker' }))"
    Set-Variable -Name $variable -Value (Read-Secret $prompt)
}

# Command-line model logins are set per host in the UI; detect the admin's own logins so Next steps
# can print the folders to paste there.
$sessionHosts = @($active | Where-Object { $_.Key -in 'Server', 'SessionWorker' })
$claudeLogin = if ($sessionHosts.Count -gt 0) { Find-ClaudeLogin } else { $null }
$codexLogin = if ($sessionHosts.Count -gt 0) { Find-CodexLogin } else { $null }

#endregion

$missingPrerequisites = [pscustomobject]@{ DotNet = $false; Git = $false }
$serverVersion = $null
$release = $null
$releaseVersion = $null
if ($active.Count -gt 0) {
    Write-Step 'Checking system requirements'
    $missingPrerequisites = Test-SystemRequirements $active $ServerUrl

    # Workers must run the same release as their server: an older worker is rejected by a newer server.
    # Unless -Version was given, install the server's release.
    if (($active | Where-Object Key -ne 'Server') -and -not ($active | Where-Object Key -eq 'Server')) {
        $versionUrl = if ($ServerUrl) { $ServerUrl } else { Get-SuggestedServerUrl }
        $serverVersion = if ($versionUrl) { Get-ServerVersion $versionUrl } else { $null }
        if (-not $serverVersion) {
            Write-Warning "Could not read the server version from $versionUrl/api/version. Workers must run the same release as the server; installing '$Version'."
        }
        elseif (-not $PSBoundParameters.ContainsKey('Version')) {
            Write-Note "Server runs $serverVersion; installing the same release."
            $Version = $serverVersion
        }
        elseif ($Version.TrimStart('v') -ne $serverVersion) {
            Write-Warning "-Version $Version differs from the server's $serverVersion; the worker may be rejected by the server."
        }
    }

    try {
        $release = Get-GitHubRelease $Repository $(if ($Version -eq 'latest') { 'latest' } else { "v$($Version.TrimStart('v'))" })
    }
    catch {
        if ($serverVersion -and $Version -eq $serverVersion) {
            throw "The server runs $serverVersion, but $Repository has no v$serverVersion release. Publish it there, or pass -Repository with a repository that has it. ($($_.Exception.Message))"
        }
        throw
    }
    $releaseVersion = $release.tag_name.TrimStart('v')
}

Write-Step 'Plan'
foreach ($item in $plan) {
    $label = switch ($item.Action) {
        'Install' { "install v$releaseVersion" }
        'Upgrade' { if ($item.InstalledVersion -eq "v$releaseVersion") { "reinstall v$releaseVersion" } else { "upgrade $($item.InstalledVersion) -> v$releaseVersion" } }
        'Uninstall' { 'uninstall' }
    }
    Write-Host ("  {0,-18} {1}" -f $item.Definition.Label, $label)
    if ($item.Action -eq 'Uninstall') {
        $files = if ($item.ScriptInstalled) { 'service and program files removed' } else { 'service removed; program files kept (not installed by this script)' }
        Write-Host ("  {0,-18} {1}: {2}" -f '', $item.InstallDir, $files)
        if ($item.DataDir) { Write-Host ("  {0,-18} StoragePath {1}: {2}" -f '', $item.DataDir, $(if ($item.RemoveData) { 'DELETED' } else { 'kept' })) }
        continue
    }
    Write-Host ("  {0,-18} {1}" -f '', $item.InstallDir)
    if ($item.DataDir) { Write-Host ("  {0,-18} StoragePath: {1}" -f '', $item.DataDir) }
}
if ($active.Count -gt 0) {
    Write-Host "  Release:           $releaseVersion ($Repository)"
    Write-Host '  Service account:   LocalSystem, automatic start, restart on failure'
}
if ($PublicUrl) { Write-Host "  Public URL:        $PublicUrl" }
if ($ServerUrl -and $newWorkers.Count -gt 0) { Write-Host "  Server URL:        $ServerUrl" }
if ($WorkerName -and $newWorkers.Count -gt 0) { Write-Host "  Worker name:       $WorkerName" }
$toInstall = @($(if ($missingPrerequisites.DotNet) { '.NET 10 Hosting Bundle' }), $(if ($missingPrerequisites.Git) { 'Git for Windows' })) | Where-Object { $_ }
if ($toInstall) { Write-Host "  Prerequisites:     will install $($toInstall -join ', ')" }

if ($script:Prompted -and -not (Read-YesNo 'Proceed?')) {
    Write-Host 'Cancelled; nothing was changed.'
    exit 0
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "polygent-install-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$results = @()
$installedPrerequisites = @()

try {
    if ($toInstall) {
        Write-Step 'Installing prerequisites'
        $installedPrerequisites = @(Install-Prerequisites $tempRoot $missingPrerequisites)
    }

    foreach ($item in $plan) {
        $definition = $item.Definition
        if ($item.Action -eq 'Uninstall') {
            Write-Step "Uninstalling $($definition.Label)"
            Uninstall-Component $item
            $results += [pscustomobject]@{ Item = $item; Healthy = $null; Action = 'Uninstall' }
            continue
        }
        $isUpgrade = $item.Action -eq 'Upgrade'
        Write-Step "$(if ($isUpgrade) { 'Upgrading' } else { 'Installing' }) $($definition.Label) $releaseVersion"

        $assetName = "$($definition.Asset)-$releaseVersion-win-x64.zip"
        $zipPath = Join-Path $tempRoot $assetName
        $staging = Join-Path $tempRoot $definition.Asset
        Save-GitHubAsset $release $assetName $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $staging -Force
        if (-not (Test-Path (Join-Path $staging $definition.Exe))) { throw "$assetName does not contain $($definition.Exe)." }

        $exePath = Join-Path $item.InstallDir $definition.Exe
        $previous = if ($isUpgrade) { (Get-Item $exePath -ErrorAction SilentlyContinue).VersionInfo.ProductVersion } else { $null }

        # Settings an older install kept in appsettings.json are found by comparing it with the
        # appsettings.json its release shipped, then moved to appsettings.Production.json. Done before
        # the service stops, since it may download the installed release.
        $keepAppSettings = $false
        $migrated = $null
        $currentPath = Join-Path $item.InstallDir 'appsettings.json'
        if ($isUpgrade -and (Test-Path $currentPath)) {
            $baseline = Read-JsonFile (Join-Path $item.InstallDir $baselineName)
            if (-not $baseline -and $previous) { $baseline = Get-ReleaseAppSettings ($previous -split '\+')[0] $definition $tempRoot }
            if ($baseline) {
                $migrated = Get-JsonOverrides (Read-JsonFile $currentPath) $baseline
            }
            else {
                $keepAppSettings = $true
                Write-Warning "Could not find the appsettings.json that version '$previous' shipped, so the installed appsettings.json is kept as is and does not receive the new version's defaults. To switch to the upgrade-safe layout, move your settings to $productionSettingsName, delete appsettings.json, and run this script again."
            }
        }

        if ($isUpgrade) {
            if ($previous) { Write-Note "Installed version: $previous" }
            if ($item.Key -eq 'SessionWorker') { Write-Note 'The Session Worker waits for running sessions to finish before stopping (up to ShutdownDrainTimeoutSeconds).' }
            Stop-ComponentService $definition.ServiceName $exePath
            Assert-HarnessRollbackReady $item $previous $releaseVersion
        }
        else {
            if ((Test-Path $item.InstallDir) -and (Get-ChildItem -Path $item.InstallDir -Force)) {
                throw "Install folder '$($item.InstallDir)' is not empty and is not registered as the $($definition.Label) service. Choose another folder or empty it."
            }
            New-ProtectedDirectory $InstallRoot -AllowUsersRead
            New-ProtectedDirectory (Split-Path -Parent $item.DataDir) -AllowUsersRead
            New-ProtectedDirectory $item.InstallDir
            New-ProtectedDirectory $item.DataDir
        }

        Sync-PackageFiles $staging $item.InstallDir -KeepAppSettings:$keepAppSettings
        if (-not $keepAppSettings) { Copy-Item -Path (Join-Path $staging 'appsettings.json') -Destination (Join-Path $item.InstallDir $baselineName) -Force }

        # Fresh installs get the required values; upgrades change only what was passed explicitly.
        # Existing appsettings.Production.json values win over migrated ones.
        $productionPath = Join-Path $item.InstallDir $productionSettingsName
        $settings = Read-JsonFile $productionPath
        if (-not $settings) { $settings = [pscustomobject]@{} }
        $changed = -not $isUpgrade
        if ($migrated -and @($migrated.PSObject.Properties).Count -gt 0) {
            Merge-Json $settings $migrated
            $changed = $true
        }
        switch ($item.Key) {
            'Server' {
                if (-not $isUpgrade) { Set-JsonValue $settings 'StoragePath' $item.DataDir }
                if ($PublicUrl) {
                    Set-JsonValue $settings 'ClientUrl' $PublicUrl
                    Set-JsonValue $settings 'Login:ClientUrl' $PublicUrl
                    $changed = $true
                }
            }
            'SessionWorker' {
                if (-not $isUpgrade) { Set-JsonValue $settings 'StoragePath' $item.DataDir }
                if ($WorkerName) { Set-JsonValue $settings 'DisplayHostname' $WorkerName; $changed = $true }
                if ($ServerUrl) { Set-JsonValue $settings 'ApiUrl' $ServerUrl; $changed = $true }
                if ($SessionWorkerApiKey) { Set-JsonValue $settings 'ApiKey' (ConvertTo-PlainText $SessionWorkerApiKey); $changed = $true }
            }
            'DeployWorker' {
                # ServerId is the host's identity; changing it on upgrade would register a new host.
                if (-not $isUpgrade) {
                    Set-JsonValue $settings 'Agent:StoragePath' $item.DataDir
                    Set-JsonValue $settings 'Agent:ServerId' $WorkerName
                }
                if ($WorkerName) { Set-JsonValue $settings 'Agent:Name' $WorkerName; $changed = $true }
                if ($ServerUrl) { Set-JsonValue $settings 'Agent:MainServerUrl' $ServerUrl; $changed = $true }
                if ($DeployWorkerApiKey) { Set-JsonValue $settings 'Agent:ApiKey' (ConvertTo-PlainText $DeployWorkerApiKey); $changed = $true }
            }
        }
        if ($changed) { Write-JsonFile $productionPath $settings }

        if (-not $isUpgrade) {
            New-Service -Name $definition.ServiceName -BinaryPathName "`"$exePath`"" -DisplayName $definition.DisplayName `
                -Description $definition.DisplayName -StartupType Automatic | Out-Null
            Write-Note "Registered service '$($definition.ServiceName)' (LocalSystem, automatic start)."
        }
        & sc.exe failure $definition.ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null

        $healthy = $null
        if (-not $NoStart) {
            try {
                Start-Service -Name $definition.ServiceName
                $healthy = Wait-ComponentHealthy $item.Key $definition $item.InstallDir
            }
            catch {
                Write-Warning "Service '$($definition.ServiceName)' failed to start: $($_.Exception.Message)"
                Show-CrashLog $item.InstallDir
                $healthy = $false
            }
        }
        $results += [pscustomobject]@{ Item = $item; Healthy = $healthy; Action = $item.Action }
    }
}
finally {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

#region Summary

Write-Step 'Done'
foreach ($result in $results) {
    $item = $result.Item
    $status = if ($result.Action -eq 'Uninstall') { 'uninstalled' } elseif ($null -eq $result.Healthy) { 'not started' } elseif ($result.Healthy) { 'running' } else { 'NOT HEALTHY' }
    Write-Host ("  {0,-18} {1,-12} {2}" -f $item.Definition.Label, $status, $item.InstallDir)
}

Write-Host ''
Write-Host 'Next steps:'
foreach ($result in $results | Where-Object { $_.Action -eq 'Install' }) {
    $item = $result.Item
    $settingsPath = Join-Path $item.InstallDir $productionSettingsName
    switch ($item.Key) {
        'Server' {
            Write-Note "Server: set the Login provider and Database in $settingsPath, then restart the 'Polygent' service."
            Write-Note "        Publish $(Get-ListenUrl $item.InstallDir) through your HTTPS reverse proxy. The first user to sign in becomes Admin."
        }
        'SessionWorker' {
            Write-Note 'Session Worker: approve the host on the Hosts page.'
        }
        'DeployWorker' {
            Write-Note 'Deployment Worker: approve the host on the Hosts page, then create deploy templates and slots.'
        }
    }
}
foreach ($result in $results | Where-Object { $_.Action -eq 'Uninstall' -and $_.Item.Key -ne 'Server' }) {
    Write-Note "$($result.Item.Definition.Label): delete this machine's host on the Hosts page, and revoke its host API key."
}
if (@($results | Where-Object { $_.Action -ne 'Uninstall' -and $_.Item.Key -in 'Server', 'SessionWorker' }).Count -gt 0) {
    $loginLocation = "the host's Agent Logins section (Hosts page, or Polygent Code -> Settings in the open-source edition)"
    if ($claudeLogin) {
        $details = @($(if ($claudeLogin.Plan) { "$($claudeLogin.Plan) plan" }), $(if (-not $claudeLogin.CliFound) { 'CLI not found' })) | Where-Object { $_ }
        $suffix = if ($details) { " ($($details -join ', '))" } else { '' }
        Write-Note "Claude Code models: to run them with ${env:USERNAME}'s Claude subscription$suffix, set Claude Code Login Folder to $($claudeLogin.Directory) in $loginLocation."
    }
    else {
        Write-Note "Claude Code models: sign in with 'claude auth login', then set Claude Code Login Folder to that account's .claude folder in $loginLocation."
    }
    if ($codexLogin) {
        $suffix = if ($codexLogin.Plan) { " (ChatGPT $($codexLogin.Plan) plan)" } else { '' }
        Write-Note "OpenAI subscription: to run OpenAI models with ${env:USERNAME}'s ChatGPT subscription$suffix, set Codex Login Folder to $($codexLogin.Directory) in $loginLocation."
        if ($codexLogin.Plan -eq 'free') { Write-Warning 'The ChatGPT Free plan may not include Codex usage; OpenAI models then fall back to the OpenAI API key.' }
    }
    else {
        Write-Note "OpenAI subscription: sign in with 'codex login' and set Codex Login Folder to that account's .codex folder in $loginLocation, or save an OpenAI API key in Backend Connections."
    }
    Write-Note 'Check Backend readiness on the Hosts page for the status of every command-line model.'
}
if ($installedPrerequisites.Count -gt 0) {
    Write-Warning "Installed in this run: $($installedPrerequisites -join ', '). Restart Windows at the next opportunity; services only see the updated PATH after a restart."
}
if (@($results | Where-Object { $_.Healthy -eq $false }).Count -gt 0) {
    Write-Warning 'At least one component is not healthy. Check crash.log in its install folder and the logs folder under its StoragePath.'
    exit 1
}
exit 0

#endregion
