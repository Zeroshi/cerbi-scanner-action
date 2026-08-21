$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'

$scanPath = if ([string]::IsNullOrWhiteSpace($env:CERBI_SCAN_PATH)) { '.' } else { $env:CERBI_SCAN_PATH }
$policyPath = $env:CERBI_POLICY
$failOn = if ([string]::IsNullOrWhiteSpace($env:CERBI_FAIL_ON)) { 'none' } else { $env:CERBI_FAIL_ON }
$scannerVersion = if ([string]::IsNullOrWhiteSpace($env:CERBI_SCANNER_VERSION)) { '1.1.0' } else { $env:CERBI_SCANNER_VERSION }
$noSnippets = $env:CERBI_NO_SNIPPETS -ne 'false'

if ([string]::IsNullOrWhiteSpace($env:CERBI_OUTPUT_DIRECTORY)) {
    if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
        $outputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'cerbi-scanner'
    }
    else {
        $outputDirectory = Join-Path $env:RUNNER_TEMP 'cerbi-scanner'
    }
}
else {
    $outputDirectory = $env:CERBI_OUTPUT_DIRECTORY
}

$outputDirectory = [System.IO.Path]::GetFullPath($outputDirectory)
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$jsonFile = Join-Path $outputDirectory 'findings.json'
$sarifFile = Join-Path $outputDirectory 'findings.sarif'
$summaryFile = Join-Path $outputDirectory 'summary.md'

$toolRoot = if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    Join-Path ([System.IO.Path]::GetTempPath()) 'cerbi-tools'
}
else {
    Join-Path $env:RUNNER_TEMP 'cerbi-tools'
}
New-Item -ItemType Directory -Force -Path $toolRoot | Out-Null

$scannerExecutable = if ($IsWindows) {
    Join-Path $toolRoot 'cerbi-scanner.exe'
}
else {
    Join-Path $toolRoot 'cerbi-scanner'
}

$toolArgs = @('tool')
if (Test-Path $scannerExecutable) {
    $toolArgs += @('update', 'Cerbi.Scanner', '--tool-path', $toolRoot)
}
else {
    $toolArgs += @('install', 'Cerbi.Scanner', '--tool-path', $toolRoot)
}

if ($scannerVersion -ne 'latest') {
    $toolArgs += @('--version', $scannerVersion)
}

Write-Host "Installing Cerbi.Scanner $scannerVersion"
& dotnet @toolArgs
if ($LASTEXITCODE -ne 0) {
    throw "Unable to install Cerbi.Scanner $scannerVersion."
}

if (-not (Test-Path $scannerExecutable)) {
    throw "Cerbi Scanner executable was not found at $scannerExecutable after installation."
}

Write-Host "Cerbi Scanner executable: $scannerExecutable"
& $scannerExecutable --version
if ($LASTEXITCODE -ne 0) {
    throw 'Cerbi Scanner failed its version check.'
}

$scanArgs = @(
    'scan',
    '--path', $scanPath,
    '--fail-on', $failOn,
    '--format', 'json',
    '--output', $jsonFile,
    '--sarif', $sarifFile,
    '--summary', $summaryFile
)

if (-not [string]::IsNullOrWhiteSpace($policyPath)) {
    $scanArgs += @('--policy', $policyPath)
}

if ($noSnippets) {
    $scanArgs += '--no-snippets'
}

Write-Host "Running Cerbi Scanner against '$scanPath' with fail-on '$failOn'."
& $scannerExecutable @scanArgs
$scannerExitCode = $LASTEXITCODE

# Cerbi.Scanner 1.1.0 can emit empty SARIF fix entries. GitHub rejects those,
# so normalize only that invalid shape and leave the rest of the report intact.
if (Test-Path $sarifFile) {
    try {
        $sarif = Get-Content -Raw -Path $sarifFile | ConvertFrom-Json -Depth 100
        $removedFixes = 0

        foreach ($run in @($sarif.runs)) {
            foreach ($result in @($run.results)) {
                if ($null -eq $result.fixes) {
                    continue
                }

                $validFixes = @()
                foreach ($fix in @($result.fixes)) {
                    if ($null -ne $fix -and $null -ne $fix.artifactChanges -and @($fix.artifactChanges).Count -gt 0) {
                        $validFixes += $fix
                    }
                    else {
                        $removedFixes++
                    }
                }

                if ($validFixes.Count -gt 0) {
                    $result.fixes = $validFixes
                }
                else {
                    $result.PSObject.Properties.Remove('fixes')
                }
            }
        }

        $sarif | ConvertTo-Json -Depth 100 | Set-Content -Path $sarifFile -Encoding utf8
        if ($removedFixes -gt 0) {
            Write-Host "Normalized SARIF by removing $removedFixes incomplete fix entr$(if ($removedFixes -eq 1) { 'y' } else { 'ies' })."
        }
    }
    catch {
        Write-Warning "Unable to normalize SARIF output: $($_.Exception.Message)"
    }
}

$sarifExists = Test-Path $sarifFile

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "json-file=$jsonFile"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "sarif-file=$sarifFile"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "summary-file=$summaryFile"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "sarif-exists=$($sarifExists.ToString().ToLowerInvariant())"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "scanner-exit-code=$scannerExitCode"
}

if ((Test-Path $summaryFile) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value "`n"
    Get-Content -Raw -Path $summaryFile | Add-Content -Path $env:GITHUB_STEP_SUMMARY
}

Write-Host "JSON:    $jsonFile"
Write-Host "SARIF:   $sarifFile"
Write-Host "Summary: $summaryFile"
Write-Host "Cerbi Scanner exit code: $scannerExitCode"

# Do not fail this step yet. The composite action uploads SARIF first, then
# deliberately replays the scanner exit code in the final enforcement step.
exit 0
