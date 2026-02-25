# run-unit-tests-docker

## Purpose

Runs LabVIEW unit tests inside a Docker container with automated setup of VI Package Manager (VIPM) and LUnit for G-CLI.

This action:

1. Pulls the specified LabVIEW Docker image
2. Installs VIPM inside the container
3. Installs LUnit for G-CLI package
4. Executes unit tests using g-cli
5. Generates test reports

## Parameters

Common parameters are described in [Common parameters](../common-parameters.md).

### Required

- **DockerImage** (`string`): Docker image to use (e.g., `nationalinstruments/labview:2026q1-windows`).
- **LVVersion** (`string`): LabVIEW version (e.g., `2026`).
- **LVBitness** (`string`): LabVIEW bitness (`32` or `64`).

### Optional

- **ProjectPath** (`string`): Path to LabVIEW project file (*.lvproj) relative to workspace. If not provided, the script searches for exactly one .lvproj file.
- **WorkspacePath** (`string`): Path to mount as workspace in the container. Defaults to current directory.
- **OpenProjectBeforeRun** (`switch`): If set, runs OpenProj.vi before executing tests.

### GitHub Action inputs

| Input | CLI parameter | Description |
| --- | --- | --- |
| `docker_image` | `DockerImage` | Docker image to use. |
| `lv_version` | `LVVersion` | LabVIEW version. |
| `lv_bitness` | `LVBitness` | LabVIEW bitness (32 or 64). |
| `project_path` | `ProjectPath` | Path to .lvproj file. |
| `workspace_path` | `WorkspacePath` | Workspace mount path. |
| `open_project_before_run` | `OpenProjectBeforeRun` | Open project before tests. |
| `working_directory` | `WorkingDirectory` | Base directory for the action. |
| `log_level` | `LogLevel` | Verbosity level (ERROR\|WARN\|INFO\|DEBUG). |
| `dry_run` | `DryRun` | If true, simulate without side effects. |

## Examples

### CLI

```powershell
pwsh -File actions/Invoke-OSAction.ps1 -ActionName run-unit-tests-docker -ArgsJson '{
  "DockerImage": "nationalinstruments/labview:2026q1-windows",
  "LVVersion": "2026",
  "LVBitness": "64"
}'
```

### GitHub Action

```yaml
- name: Run LabVIEW tests in Docker
  uses: owner/repo/run-unit-tests-docker@v1
  with:
    docker_image: nationalinstruments/labview:2026q1-windows
    lv_version: '2026'
    lv_bitness: '64'
    project_path: MyProject.lvproj
```

## Return Codes

- `0` – Tests passed successfully
- `1` – Setup or execution error
- `2` – Tests executed but some failed
- `3` – Project file not found

## Requirements

- Docker must be installed and accessible
- The specified Docker image must be available (pulled automatically)
- Windows containers are required for Windows-based LabVIEW images

## See also

- [run-unit-tests](run-unit-tests.md) - Standalone unit test runner
- [Architecture documentation](../architecture.md)
