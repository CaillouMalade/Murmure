$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskPython = Join-Path $taskRoot '.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $taskPython)) {
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) { throw 'Install Python 3.12 with its Windows launcher, then run this script again.' }
    & py -3.12 -m venv (Join-Path $taskRoot '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'Creating the Python 3.12 environment failed. Check that Python 3.12 is installed.' }
}
& $taskPython -m pip install -r (Join-Path $taskRoot 'worker/requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Worker dependency installation failed. Read the error above before retrying.' }
& $taskPython (Join-Path $taskRoot 'scripts/check-worker-runtime.py')
if ($LASTEXITCODE -ne 0) { throw 'The worker audio runtime check failed. Read the error above.' }
Write-Output ('Python path for Murmure Setup: ' + $taskPython.Replace('\', '/'))
Write-Output ('Worker path for Murmure Setup: ' + (Join-Path $taskRoot 'worker/murmure_worker.py').Replace('\', '/'))
Write-Output 'No SSH configuration or model weights were changed. In Murmure Setup, test SSH, select the model, then choose Download & check model.'
