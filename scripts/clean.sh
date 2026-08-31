#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}

for target in \
  "$PROJECT_ROOT/build" \
  "$PROJECT_ROOT/DerivedData" \
  "$PROJECT_ROOT/Herdie.xcodeproj" \
  "$PROJECT_ROOT/Frameworks" \
  "$PROJECT_ROOT/Generated" \
  "$PROJECT_ROOT/core/target"
do
  if [[ "$target" == "$PROJECT_ROOT/"* && -e "$target" ]]; then
    rm -rf "$target"
  fi
done
