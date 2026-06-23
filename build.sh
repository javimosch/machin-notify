#!/usr/bin/env bash
set -euo pipefail
MACHIN="${MACHIN:-machin}"
"$MACHIN" encode machweb.src notify.src > app.mfl
"$MACHIN" build app.mfl -o machin-notify
echo "built ./machin-notify"
