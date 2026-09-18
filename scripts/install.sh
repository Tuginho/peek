#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build.sh

pkill -x Peek || true
sleep 1

rm -rf /Applications/Peek.app
ditto build/Peek.app /Applications/Peek.app

open /Applications/Peek.app
