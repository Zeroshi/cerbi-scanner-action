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
| `scanner-version` | `1.2.0` | `Cerbi.Scanner` NuGet tool version. `latest` follows the newest published package. |
| `output-directory` | runner temp | Directory for JSON, SARIF, and Markdown results. |
| `no-snippets` | `true` | Requests privacy mode for report content. |
| `upload-sarif` | `false` | Upload SARIF to GitHub code scanning. Requires `security-events: write`. |

## Outputs

| Output | Description |
| --- | --- |
| `json-file` | Absolute path to `findings.json`. |
| `sarif-file` | Absolute path to `findings.sarif`. |
| `summary-file` | Absolute path to the Markdown summary. |
| `scanner-exit-code` | Scanner exit code: `0` clean, `1` threshold breached, `2` scanner/configuration error. |

The Markdown report is also appended to the GitHub Actions job summary.

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
```

## What the Scanner looks for

The current Scanner supports C#, Go, Java, JavaScript/TypeScript, and Python logging patterns. It can identify governance issues such as sensitive/disallowed fields, risky payload logging, unsafe object serialization, and policy violations. Exact rules are determined by the installed `Cerbi.Scanner` version and optional Cerbi policy file.

Scanner `1.2.0` also reports metadata-only AI integration signals from explicit repository manifests and configuration files, including AI provider SDKs, MCP configuration files, vector store dependencies, agent/orchestration frameworks, and known Cerbi AI runtime-governance instrumentation. These findings help teams see where AI logging governance may be needed; they do not claim full runtime AI execution governance by themselves.

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
