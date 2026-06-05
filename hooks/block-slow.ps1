# PreToolUse:Bash hook that blocks slow find+exec patterns.
# Pure PowerShell - no bash/jq dependency for fast execution on Windows.

$input_bytes = [System.Console]::OpenStandardInput()
$reader = New-Object System.IO.StreamReader($input_bytes)
$json = $reader.ReadToEnd()
$reader.Close()

if (-not $json) { exit 0 }

$data = $json | ConvertFrom-Json
$cmd = $data.tool_input.command

if (-not $cmd) { exit 0 }

# Detect: any "find" command used as the main command (not as part of grep/rg)
# Matches: find ..., cd /x && find ..., but not: grep --find, rg --find
if ($cmd -match '(?:^|&&\s*|;\s*|\|\s*)\s*find\s+') {
    $reason = "Blocked: find command is slow. Use dedicated tools (Grep, Glob) instead."

    [Console]::Error.WriteLine($reason)

    $output = @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "deny"
            permissionDecisionReason = $reason
        }
    } | ConvertTo-Json -Depth 3 -Compress

    Write-Output $output
    exit 0
}

# Detect: grep -r without --exclude-dir=node_modules
if ($cmd -match '\bgrep\s+.*-r' -and $cmd -notmatch '--exclude-dir=node_modules') {
    $reason = "Blocked: grep -r without --exclude-dir=node_modules is very slow. Use the Grep tool instead."

    [Console]::Error.WriteLine($reason)

    $output = @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "deny"
            permissionDecisionReason = $reason
        }
    } | ConvertTo-Json -Depth 3 -Compress

    Write-Output $output
    exit 0
}

exit 0
