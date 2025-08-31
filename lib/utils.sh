#!/bin/bash
set -euo pipefail

# 🎨 Color Variables
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
NC='\033[0m' # No color

source_as() {
  local file_path=$1
  local alias_name=$2

  if [ -f "$file_path" ]; then
    source "$file_path"

    eval "
      function $alias_name() {
        local func_call=\$1
        shift
        \$func_call \"\$@\"
      }
    "
  else
    echo "The file $file_path does not exists."
    exit 1
  fi
}