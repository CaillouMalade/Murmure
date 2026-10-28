#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
TASK_PYTHON="$TASK_ROOT/.venv/bin/python"
if [ ! -x "$TASK_PYTHON" ]; then
    command -v python3 >/dev/null || { echo 'Install Python 3.11/3.12 first, then retry.' >&2; exit 1; }
    python3 -m venv "$TASK_ROOT/.venv"
fi
"$TASK_PYTHON" -m pip install -r "$TASK_ROOT/worker/requirements.txt"
"$TASK_PYTHON" "$TASK_ROOT/scripts/check-worker-runtime.py"
echo "Python path for Murmure Setup: $TASK_PYTHON"
echo "Worker path for Murmure Setup: $TASK_ROOT/worker/murmure_worker.py"
echo 'No SSH configuration or model weights were changed. Test SSH, select the model, then choose Download & check model in Murmure Setup.'
