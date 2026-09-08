# Cerbi Logging Governance Scanner for GitHub Actions

Find risky logging and AI integration signals before they reach production.

Cerbi Scanner statically analyzes application logging calls for sensitive data exposure, unsafe payload logging, policy violations, AI dependency signals, and other logging-governance risks. It runs on the GitHub Actions runner and does not upload source code or findings to Cerbi by default.

## Quick start

Add this to a workflow after checkout:

```yaml
permissions:
  contents: read

steps:
  - uses: actions/checkout@v7

  - name: Cerbi logging governance scan
    uses: Zeroshi/cerbi-scanner-action@v1
```

The default mode reports findings but does not fail the build.

## Enforce a policy threshold

```yaml
- name: Cerbi logging governance scan
  uses: Zeroshi/cerbi-scanner-action@v1
  with:
    path: .
    policy: cerbi-policy.yml
    fail-on: high
```

`fail-on` supports `none`, `info`, `warning`, `low`, `medium`, `high`, `critical`, `error`, and `blocker`.

## Show findings in GitHub code scanning

Cerbi Scanner produces SARIF. To upload the report to GitHub code scanning, grant the workflow `security-events: write` and opt in:

```yaml
permissions:
  contents: read
  security-events: write

steps:
  - uses: actions/checkout@v7

  - name: Cerbi logging governance scan
    uses: Zeroshi/cerbi-scanner-action@v1
    with:
      upload-sarif: 'true'
```

GitHub code-scanning availability depends on the repository and GitHub plan. The Action still generates local JSON, SARIF, and Markdown reports when SARIF upload is disabled.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `path` | `.` | Repository path to scan. |
| `policy` | empty | Optional Cerbi policy file. Scanner discovery/default behavior applies when omitted. |
| `fail-on` | `none` | Minimum finding severity that fails the Action. |
| `scanner-version` | `1.2.1` | `Cerbi.Scanner` NuGet tool version. `latest` follows the newest published package. |
| `output-directory` | runner temp | Directory for JSON, SARIF, and Markdown results. |
| `no-snippets` | `true` | Requests privacy mode for report content. |
| `upload-sarif` | `false` | Upload SARIF to GitHub code scanning. Requires `security-events: write`. |

## Outputs

| Output | Description |
| --- | --- |
| `json-file` | Absolute path to `findings.json`. |
| `sarif-file` | Absolute path to `findings.sarif`. |
| `summary-file` | Absolute path to the Markdown summary. |
| `ai-evidence-file` | Absolute path to the AI Logging Evidence Markdown summary. |
| `ai-evidence-exists` | `true` when the AI Logging Evidence Markdown summary was generated. |
| `ai-signals` | Count of metadata-only AI logging governance signals detected in the explicit scan root. |
| `ai-raw-payload-findings` | Count of raw AI-adjacent payload logging findings. |
| `ai-runtime-governance-detected` | `true` when Cerbi AI runtime governance instrumentation is detected in the scan scope. |
| `scanner-exit-code` | Scanner exit code: `0` clean, `1` threshold breached, `2` scanner/configuration error. |

The Markdown report and AI Logging Evidence summary are also appended to the GitHub Actions job summary.

## AI Logging Evidence in CI

Scanner `1.2.1` and later emits a metadata-only `aiLoggingEvidence` section in the JSON report when it detects AI provider SDKs, MCP configuration, vector-store clients, agent/orchestration frameworks, raw AI-adjacent payload logging, or Cerbi runtime governance markers inside the explicit scan root.

The Action turns that JSON section into a readable `ai-logging-evidence.md` job summary. This is useful for a pull request or release gate because the team can see:

- which AI providers or frameworks were detected;
- whether runtime governance instrumentation was found;
- which systems still need app, environment, provider, model, agent, or tool tags;
- whether raw prompt, completion, RAG, or tool payload logging patterns were found;
- the next action needed to connect CerbiStream, Gateway, or a governed logging policy.

This summary does not include prompts, responses, tool argument bodies, source snippets, provider secrets, MCP server values, or raw file contents.

## Upload the generated reports as workflow artifacts

```yaml
- name: Cerbi logging governance scan
  id: cerbi
  uses: Zeroshi/cerbi-scanner-action@v1

- name: Upload Cerbi reports
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: cerbi-scan-results
    path: |
      ${{ steps.cerbi.outputs.json-file }}
      ${{ steps.cerbi.outputs.sarif-file }}
      ${{ steps.cerbi.outputs.summary-file }}
      ${{ steps.cerbi.outputs.ai-evidence-file }}
```

## What the Scanner looks for

The current Scanner supports C#, Go, Java, JavaScript/TypeScript, and Python logging patterns. It can identify governance issues such as sensitive/disallowed fields, risky payload logging, unsafe object serialization, and policy violations. Exact rules are determined by the installed `Cerbi.Scanner` version and optional Cerbi policy file.

Scanner `1.2.1` also reports metadata-only AI integration signals from explicit repository manifests and configuration files, including AI provider SDKs, MCP configuration files, vector store dependencies, agent/orchestration frameworks, and known Cerbi AI runtime-governance instrumentation. These findings help teams see where AI logging governance may be needed; they do not claim full runtime AI execution governance by themselves.

## Privacy and network behavior

- Source code is scanned on the GitHub Actions runner.
- The Action does not upload findings to Cerbi.
- Cerbi telemetry is not enabled by this Action.
- AI dependency detection reports package/configuration metadata only; it does not collect prompts, responses, MCP server values, or provider secrets.
- The Action downloads the .NET 10 SDK when needed through `actions/setup-dotnet`.
- The Action restores the `Cerbi.Scanner` tool package from NuGet.
- GitHub receives SARIF only when `upload-sarif: 'true'` is explicitly configured.

## Why this is separate from CerbiShield

Cerbi Scanner is the discovery and CI-policy layer. It can be used by itself. CerbiShield is the optional platform for organizations that need centralized policy, governance, evidence, and visibility across explicitly connected repositories and workloads.

## License

The GitHub Action wrapper is distributed under the MIT License. Cerbi Scanner package licensing remains governed by the package/repository terms for the installed scanner version.

## Links

- Product: https://www.cerbi.io/
- Scanner quickstart: https://www.cerbi.io/docs/scanner/quickstart
- Issues and support: https://github.com/Zeroshi/cerbi-scanner-action/issues
