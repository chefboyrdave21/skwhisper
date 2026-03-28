# SKWhisper Session Save Hook for Claude Code (Windows)
# Triggers SKWhisper digest after session ends.
#
# Hook type: SessionEnd
# Input (stdin): JSON with session_id, reason
# Exit 0 always

$ErrorActionPreference = "SilentlyContinue"

$Agent = if ($env:SKCAPSTONE_AGENT) { $env:SKCAPSTONE_AGENT } else { "lumina" }

$SkWhisperDir = $null
$SearchPaths = @(
    (Join-Path $env:USERPROFILE "clawd" "projects" "skwhisper"),
    (Join-Path $env:USERPROFILE "projects" "skwhisper"),
    (Join-Path $env:USERPROFILE "skwhisper")
)
foreach ($D in $SearchPaths) {
    if (Test-Path (Join-Path $D "skwhisper" "__main__.py")) {
        $SkWhisperDir = $D
        break
    }
}

if (-not $SkWhisperDir) { exit 0 }

# Run digest + curate in background
$env:PYTHONPATH = $SkWhisperDir
Start-Process -NoNewWindow -FilePath "python" -ArgumentList "-m", "skwhisper", "digest" -WorkingDirectory $SkWhisperDir -RedirectStandardOutput "NUL" -RedirectStandardError "NUL"
Start-Process -NoNewWindow -FilePath "python" -ArgumentList "-m", "skwhisper", "curate" -WorkingDirectory $SkWhisperDir -RedirectStandardOutput "NUL" -RedirectStandardError "NUL"

exit 0
