#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/Scripts/quiet-workflow.sh"
run_step 'focused tests' swift test --package-path "$project_dir" --filter "${TEST_FILTER:-Usage|QuotaForecaster|Doctor}"
