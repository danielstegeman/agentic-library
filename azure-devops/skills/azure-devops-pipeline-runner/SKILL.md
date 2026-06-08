---
name: azure-devops-pipeline-runner
description: 'Run, monitor, and analyze Azure DevOps pipelines via fire-and-forget scripts. Generates a YAML run-config from the pipeline definition, triggers the run, then processes the completed run into a failure-focused markdown report. USE FOR: run a pipeline, trigger a build, kick off a deployment, re-run a failed pipeline, resume pipeline run, process pipeline log, what failed in build, generate pipeline report, pipeline failure report, analyze the run of build <number>. DO NOT USE FOR: creating new pipeline definitions (use azure-devops-pipelines), reviewing pipeline YAML (use pipeline-yaml-review).'
---

# Azure DevOps Pipeline Runner

Run and report on Azure DevOps pipelines from the command line using three artifacts in this folder:

| Script / file | Purpose |
|---|---|
| `scripts/PipelineRunner.psm1` | Shared helpers (YAML parsing, git, az wrapper, paths) |
| `scripts/New-PipelineRunConfig.ps1` | Generate a pre-filled `run-config.yml` from a pipeline definition |
| `scripts/Invoke-PipelineRun.ps1` | Trigger a run (mode 1) **or** produce a report from a completed run (mode 2) |
| `examples/run-config.example.yml` | Example of an edited run-config |

The flow is intentionally **fire-and-forget**: the agent does not block on long-running pipelines. After triggering, the user re-invokes the agent once the run finishes, and the same script produces the report.

## When to use this skill

- "Run the `my-pipeline` pipeline on this branch"
- "Trigger `my-build` with these parameters"
- "Pipeline build 20260604.3 is done — what happened?"
- "Process the latest run and tell me what failed"

**Do not use for**: creating new pipeline YAML, editing pipeline definitions, or reviewing existing pipeline files.

## Prerequisites

| Tool | Install |
|---|---|
| `az` CLI | https://learn.microsoft.com/cli/azure/install-azure-cli |
| `azure-devops` extension | `az extension add --name azure-devops` |
| `powershell-yaml` module | `Install-Module powershell-yaml -Scope CurrentUser` |
| Authenticated session | `az login` |

The scripts call `Assert-Prerequisite` at startup and fail with an actionable message if anything is missing.

## Workflow

```
┌──────────────────────────────┐
│  1. Configure                │  New-PipelineRunConfig.ps1 -PipelineName <name>
│     → run-config.yml         │
└──────────────┬───────────────┘
               ▼
┌──────────────────────────────┐
│  2. Trigger                  │  Invoke-PipelineRun.ps1 -ConfigPath <path>
│     → run-state.json         │  (script exits immediately, prints resume command)
└──────────────┬───────────────┘
               ▼
        (user waits for the run to complete)
               │
               ▼
┌──────────────────────────────┐
│  3. Report                   │  Invoke-PipelineRun.ps1 -BuildNumber <n>
│     → report.md              │  (exits 2 if still running, exits 0/1 when done)
└──────────────────────────────┘
```

All per-run artifacts land under `<repoRoot>/.agent-artifacts/pipeline-runs/<buildNumber>/`:
- `run-config.yml` — the config used to trigger the run
- `run-state.json` — pipeline/run identifiers and submitted parameters
- `report.md` — the processed report
- `raw/` — full logs (only when `-KeepRawLogs` is passed to the report step)

## What to ask the user

1. **Pipeline name** (exact, case-sensitive YAML filename without extension). If ambiguous, list candidates from the pipelines directory and confirm.
2. **Branch** — defaults to the current git branch in the generated config; override before triggering if needed.
3. **Parameter values** — the user edits the generated `run-config.yml` directly. Do not collect parameters interactively in chat.
4. For the report step: **build number** or path to `run-state.json`.

## Step-by-step

### Step 1 — Generate the config

```powershell
& '<path-to-skill>\scripts\New-PipelineRunConfig.ps1' `
    -PipelineName <pipeline-name>
```

Output: `.agent-artifacts/pipeline-runs/_pending/run-config.yml` with every pipeline parameter pre-filled with its default, plus an inline comment showing type and allowed values.

Tell the user to open the file, edit values, and confirm the branch is correct.

### Step 2 — Trigger the run

```powershell
& '<path-to-skill>\scripts\Invoke-PipelineRun.ps1' `
    -ConfigPath '.agent-artifacts/pipeline-runs/_pending/run-config.yml'
```

The script:
1. Re-validates parameters against the pipeline YAML (rejects unknown names and out-of-set choice values)
2. Blocks on uncommitted changes (use `-AllowDirty` to override)
3. Verifies the branch exists on `origin`
4. Resolves the ADO pipeline definition id (from `pipelineId` in the config, or auto-discovers by matching the YAML filename against `az pipelines list`)
5. POSTs to `_apis/pipelines/{id}/runs?api-version=7.1-preview.1` with templateParameters/variables/branch (object and array parameters are JSON-string-encoded; see note below)
6. Writes `run-state.json` to `.agent-artifacts/pipeline-runs/<buildNumber>/`
7. Prints the build URL and the resume command, then exits

**Stop here.** Tell the user: "Re-invoke me with `process the pipeline run for build <buildNumber>` once it finishes."

### Step 3 — Process the result

```powershell
& '<path-to-skill>\scripts\Invoke-PipelineRun.ps1' `
    -BuildNumber 20260604.3
```

Exit codes:
- `0` — run completed successfully, `report.md` written
- `1` — run completed but failed, `report.md` written
- `2` — run still in flight; ask the user to wait and re-invoke

`report.md` contains five sections:

| Section | Content |
|---|---|
| **Summary** | Pipeline, build #, branch, status, result, duration, URL, submitted parameters |
| **Failures** | One subsection per failed task with stage/job/task path, duration, log URL, and an error snippet with ±20 lines of context |
| **Failed tests** | Test name, error message, stack trace (from `_apis/test/runs`) |
| **Warnings** | All `##[warning]` lines extracted from failed-task logs |
| **Timing** | Stage/job duration table + top 5 slowest jobs |

Pass `-KeepRawLogs` to also save complete logs under `raw/`.

After the script finishes, **read `report.md`** and summarize the key findings to the user (don't paste the whole file).

## Run config format

```yaml
pipeline: my-pipeline-name             # YAML filename without extension
pipelineId: 1234                       # optional: ADO definition id (use when the
                                       # ADO display name differs from the YAML filename)
branch: feature/my-branch              # short branch name; refs/heads/ added automatically
parameters:
  Environment: Dev                     # values are validated against the pipeline's allowed set
  Force: true                          # scalars passed as-is
  pipelineDebugOptions:                # object/array params: pass natively in YAML; the
    skipArtifactsDownload: false       # script JSON-encodes them before POST (see below)
    continueOnError: true
variables: {}                          # optional: variable overrides ({key: "value"} or
                                       # {key: {value: "...", isSecret: true}})
stagesToSkip: []                       # optional: stage names to skip
```

Unknown parameter names cause a hard error. Choice values are validated against the pipeline's `values:` list. Missing parameters fall back to the pipeline's defaults — they don't have to appear in the config.

### `pipelineId` field

ADO does not require the YAML filename to match the pipeline's display name. When the script triggers a run it needs the **numeric definition id**, not the YAML name. `New-PipelineRunConfig.ps1` auto-discovers the id by scanning `az pipelines list` for a definition whose `yamlFilename` ends with `<pipeline>.yml` and writes it into the generated config. Override with `pipelineId: <n>` if discovery is wrong or the YAML lives under multiple definitions.

### Object and array parameters

ADO's `POST /_apis/pipelines/{id}/runs` endpoint rejects non-preview runs whose `templateParameters` contain JSON objects or arrays with:

```
Value cannot be null. Parameter name: runParameters
```

The pipeline runtime, however, accepts these values when they are **JSON-encoded strings**. The script detects object/array values in `parameters:` and serializes them with `ConvertTo-Json -Compress` before POSTing. Authors keep writing native YAML; the wire format is handled transparently.

### Why REST instead of `az pipelines run`

`az pipelines run --parameters key=value` only accepts string-typed parameters and silently truncates anything that looks like JSON (single quotes get parsed away on Windows). The script bypasses `az pipelines run` for triggers and calls the pipelines REST API directly via `Invoke-RestMethod` with a bearer token from `az account get-access-token`. `az` is still used for discovery (`az pipelines list`) and for reads where it works correctly.

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `az CLI is not installed` | `az` not on PATH | Install Azure CLI |
| `azure-devops extension is not installed` | Extension missing | `az extension add --name azure-devops` |
| `powershell-yaml module is not installed` | Module missing | `Install-Module powershell-yaml -Scope CurrentUser` |
| `powershell-yaml.psm1 is not digitally signed` | Restrictive execution policy | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` (or `Bypass` for the current process only) |
| `Not inside a git repository` | Script run outside repo | `cd` into the target repo first |
| `Pipeline YAML not found for '<name>'` | Wrong name or wrong subdir | Verify file under `OpsObjects/`; pipeline name is case-sensitive |
| `Pipeline '<name>' is not registered` | YAML exists but no pipeline definition | Create the pipeline in Azure DevOps first |
| `Uncommitted changes detected` | Dirty working tree | Commit first, or pass `-AllowDirty` |
| `Branch '<x>' not found on remote` | Branch not pushed | `git push -u origin <branch>` |
| `Parameter '<x>' is not defined in <pipeline>.yml` | Typo in config or stale config | Regenerate with `New-PipelineRunConfig.ps1` |
| `Parameter '<x>' value '<v>' is not in allowed set` | Choice violation | Use one of the values from the inline comment |
| Run-state.json missing for build | Build was not triggered via `Invoke-PipelineRun.ps1` | Pass `-RunStateFile` pointing at the JSON, or re-trigger via this skill |
| Report exits with code 2 | Run still queued/running | Wait, then re-run the report command |
| `Value cannot be null. Parameter name: runParameters` | Object/array parameter sent as native JSON to a non-preview run | Fixed in current version (script auto-stringifies); upgrade if you see this |
| Trigger fails with no pipeline-id error | YAML filename does not match the ADO definition name | Add `pipelineId: <n>` to the config, or regenerate it (auto-discovery is on by default) |

## Related skills

- `azure-devops-pipelines` — create new pipeline definitions
- `pipeline-yaml-review` — review pipeline YAML for conventions
- `agent-artifacts` — manage the `.agent-artifacts/` working folder
