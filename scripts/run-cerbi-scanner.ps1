$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'

function Write-AiEvidenceSummary {
    param(
        [Parameter(Mandatory = $true)][string]$JsonFile,
        [Parameter(Mandatory = $true)][string]$OutputFile
    )

    $result = [ordered]@{
        HasAiSignals = $false
        TotalAiSignals = 0
        RawPayloadFindings = 0
        RuntimeGovernanceDetected = $false
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Cerbi AI Logging Evidence")
    $lines.Add("")
    $lines.Add("Metadata-only summary from the Cerbi Scanner JSON report. Raw prompts, completions, RAG context, tool argument bodies, source snippets, and provider secrets are not included.")
    $lines.Add("")

    if (-not (Test-Path $JsonFile)) {
        $lines.Add("No scanner JSON report was available, so AI logging evidence could not be summarized.")
        Set-Content -Path $OutputFile -Value $lines -Encoding utf8
        return [pscustomobject]$result
    }

    try {
        $report = Get-Content -Raw -Path $JsonFile | ConvertFrom-Json -Depth 100
        $evidence = Get-JsonProperty -Object $report -Name 'aiLoggingEvidence'

        if ($null -eq $evidence) {
            $lines.Add("No AI logging governance signals were reported by this scan.")
            $lines.Add("")
            $lines.Add("Use Cerbi Scanner 1.2.1 or later to emit the `aiLoggingEvidence` section when AI provider SDKs, MCP configuration, vector stores, agent frameworks, raw AI-adjacent payload logging, or Cerbi runtime governance markers are detected in the explicit scan root.")
            Set-Content -Path $OutputFile -Value $lines -Encoding utf8
            return [pscustomobject]$result
        }

        $coverage = Get-JsonProperty -Object $evidence -Name 'coverageSummary'
        $runtimeGovernedSystems = [int](Get-NumberProperty -Object $coverage -Name 'runtimeGovernedSystems')
        $result.HasAiSignals = [bool](Get-BoolProperty -Object $evidence -Name 'hasAiSignals')
        $result.TotalAiSignals = [int](Get-NumberProperty -Object $evidence -Name 'totalAiSignals')
        $result.RawPayloadFindings = [int](Get-NumberProperty -Object $evidence -Name 'rawPayloadFindings')
        $result.RuntimeGovernanceDetected = $runtimeGovernedSystems -gt 0

        $lines.Add("| Metric | Value |")
        $lines.Add("| --- | ---: |")
        $lines.Add("| AI signals | $($result.TotalAiSignals) |")
        $lines.Add("| Raw AI-adjacent payload findings | $($result.RawPayloadFindings) |")
        $lines.Add("| Runtime-governed systems | $runtimeGovernedSystems |")
        $lines.Add("| Scanner-only systems | $(Get-NumberProperty -Object $coverage -Name 'scannerOnlySystems') |")
        $lines.Add("| Untagged signals | $(Get-NumberProperty -Object $coverage -Name 'untaggedSignals') |")
        $lines.Add("")

        $providers = Format-ArrayProperty -Object $evidence -Name 'providers'
        $sourceKinds = Format-ArrayProperty -Object $evidence -Name 'sourceKinds'
        $lines.Add("* Providers/frameworks: $providers")
        $lines.Add("* Signal types: $sourceKinds")
        $lines.Add("* Coverage status: $(Escape-Markdown (Get-StringProperty -Object $coverage -Name 'coverageStatus'))")
        $lines.Add("* Next action: $(Escape-Markdown (Get-StringProperty -Object $coverage -Name 'nextAction'))")
        $lines.Add("")

        Write-TableSection -Lines $lines -Title "Source onboarding" -Rows (Get-ArrayProperty -Object $evidence -Name 'sourceOnboarding') -Columns @('name', 'status', 'owner', 'action')
        Write-TableSection -Lines $lines -Title "AI asset inventory" -Rows (Get-ArrayProperty -Object $evidence -Name 'assetInventory') -Columns @('name', 'kind', 'provider', 'evidenceSource', 'policyOutcome')
        Write-TableSection -Lines $lines -Title "Payload exposure controls" -Rows (Get-ArrayProperty -Object $evidence -Name 'protectedPayloads') -Columns @('name', 'findings', 'status', 'action')
        Write-TableSection -Lines $lines -Title "Agent and tool evidence" -Rows (Get-ArrayProperty -Object $evidence -Name 'agentToolEvidence') -Columns @('agentName', 'toolName', 'actionType', 'policyOutcome', 'control')
        Write-TableSection -Lines $lines -Title "Recommendations" -Rows (Get-ArrayProperty -Object $evidence -Name 'recommendations') -Columns @('severity', 'title', 'detail')

        $packet = Get-JsonProperty -Object $evidence -Name 'evidencePacket'
        $lines.Add("## Evidence packet")
        $lines.Add("")
        $lines.Add("* Export mode: ``$(Get-StringProperty -Object $packet -Name 'exportMode')``")
        $lines.Add("* Raw payloads included: ``$(Get-BoolProperty -Object $packet -Name 'rawPayloadsIncluded')``")
        $lines.Add("* Retention: $(Escape-Markdown (Get-StringProperty -Object $packet -Name 'retention'))")
        $lines.Add("* Provider invoice note: $(Escape-Markdown (Get-StringProperty -Object $packet -Name 'providerInvoiceAuthority'))")
    }
    catch {
        $lines.Add("The scanner JSON report could not be parsed for AI logging evidence.")
        $lines.Add("")
        $lines.Add("Error: $(Escape-Markdown $_.Exception.Message)")
    }

    Set-Content -Path $OutputFile -Value $lines -Encoding utf8
    return [pscustomobject]$result
}

function Get-JsonProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-StringProperty {
    param($Object, [string]$Name)
    $value = Get-JsonProperty -Object $Object -Name $Name
    if ($null -eq $value) { return '' }
    return [string]$value
}

function Get-NumberProperty {
    param($Object, [string]$Name)
    $value = Get-JsonProperty -Object $Object -Name $Name
    if ($null -eq $value) { return 0 }
    return [int]$value
}

function Get-BoolProperty {
    param($Object, [string]$Name)
    $value = Get-JsonProperty -Object $Object -Name $Name
    if ($null -eq $value) { return $false }
    return [bool]$value
}

function Get-ArrayProperty {
    param($Object, [string]$Name)
    $value = Get-JsonProperty -Object $Object -Name $Name
    if ($null -eq $value) { return @() }
    return @($value)
}

function Format-ArrayProperty {
    param($Object, [string]$Name)
    $items = Get-ArrayProperty -Object $Object -Name $Name
    if ($items.Count -eq 0) { return "none reported" }
    return ($items | ForEach-Object { Escape-Markdown ([string]$_) }) -join ", "
}

function Write-TableSection {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Title,
        $Rows,
        [string[]]$Columns
    )

    $rowsArray = @($Rows)
    if ($rowsArray.Count -eq 0) { return }

    $Lines.Add("## $Title")
    $Lines.Add("")
    $Lines.Add("| $($Columns -join ' | ') |")
    $Lines.Add("| $((@('---') * $Columns.Count) -join ' | ') |")
    foreach ($row in $rowsArray | Select-Object -First 8) {
        $values = foreach ($column in $Columns) {
            Escape-Markdown (Get-StringProperty -Object $row -Name $column)
        }
        $Lines.Add("| $($values -join ' | ') |")
    }
    $Lines.Add("")
}

function Escape-Markdown {
    param([string]$Value)
    return $Value.Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

$scanPath = if ([string]::IsNullOrWhiteSpace($env:CERBI_SCAN_PATH)) { '.' } else { $env:CERBI_SCAN_PATH }
$policyPath = $env:CERBI_POLICY
$failOn = if ([string]::IsNullOrWhiteSpace($env:CERBI_FAIL_ON)) { 'none' } else { $env:CERBI_FAIL_ON }
$scannerVersion = if ([string]::IsNullOrWhiteSpace($env:CERBI_SCANNER_VERSION)) { '1.2.1' } else { $env:CERBI_SCANNER_VERSION }
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
$aiEvidenceFile = Join-Path $outputDirectory 'ai-logging-evidence.md'

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

# Some scanner versions can emit empty SARIF fix entries. GitHub rejects those,
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
$aiEvidence = Write-AiEvidenceSummary -JsonFile $jsonFile -OutputFile $aiEvidenceFile

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "json-file=$jsonFile"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "sarif-file=$sarifFile"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "summary-file=$summaryFile"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "ai-evidence-file=$aiEvidenceFile"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "ai-evidence-exists=$((Test-Path $aiEvidenceFile).ToString().ToLowerInvariant())"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "ai-signals=$($aiEvidence.TotalAiSignals)"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "ai-raw-payload-findings=$($aiEvidence.RawPayloadFindings)"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "ai-runtime-governance-detected=$($aiEvidence.RuntimeGovernanceDetected.ToString().ToLowerInvariant())"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "sarif-exists=$($sarifExists.ToString().ToLowerInvariant())"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "scanner-exit-code=$scannerExitCode"
}

if ((Test-Path $summaryFile) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value "`n"
    Get-Content -Raw -Path $summaryFile | Add-Content -Path $env:GITHUB_STEP_SUMMARY
}

if ((Test-Path $aiEvidenceFile) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value "`n"
    Get-Content -Raw -Path $aiEvidenceFile | Add-Content -Path $env:GITHUB_STEP_SUMMARY
}

Write-Host "JSON:    $jsonFile"
Write-Host "SARIF:   $sarifFile"
Write-Host "Summary: $summaryFile"
Write-Host "AI evidence: $aiEvidenceFile"
Write-Host "AI signals: $($aiEvidence.TotalAiSignals); raw payload findings: $($aiEvidence.RawPayloadFindings); runtime governance detected: $($aiEvidence.RuntimeGovernanceDetected.ToString().ToLowerInvariant())"
Write-Host "Cerbi Scanner exit code: $scannerExitCode"

# Do not fail this step yet. The composite action uploads SARIF first, then
# deliberately replays the scanner exit code in the final enforcement step.
exit 0
