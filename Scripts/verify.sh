#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/Scripts/quiet-workflow.sh"
if [[ -n "${TOKENCOFFEE_SOURCE_DIRECTORY:-}" ]]; then
  run_step 'TokenCoffee history contract parity' cmp \
    "$TOKENCOFFEE_SOURCE_DIRECTORY/Sources/TokenCoffeeCore/UsageHistoryContract.swift" \
    "$project_dir/Sources/BrrainzTools/TokenCoffeeForecast/UsageHistoryContract.swift"
  workflow_step='TokenCoffee history contract test parity'
  sed 's/@testable import TokenCoffeeCore/@testable import BrrainzTools/' \
    "$TOKENCOFFEE_SOURCE_DIRECTORY/Tests/TokenCoffeeCoreTests/UsageHistoryContractTests.swift" > "$workflow_log.contract-tests"
  run_step 'TokenCoffee history contract test parity' cmp "$workflow_log.contract-tests" \
    "$project_dir/Tests/BrrainzToolsTests/UsageHistoryContractTests.swift"
fi
run_step 'focused tests' swift test --package-path "$project_dir" --filter "${TEST_FILTER:-Usage|QuotaForecaster|Doctor}"
