# TokenCoffee forecast source

The Swift files in `Sources/BrrainzTools/TokenCoffeeForecast` are a pinned source
copy from Andreas Pardeike's TokenCoffee repository, revision
`e1b47ee4db299f87c4b065d2b02c900c4fafe627`.

- `QuotaForecastKit.swift`: the complete file from
  `Packages/QuotaForecastKit/Sources/QuotaForecastKit/QuotaForecastKit.swift`.
- `QuotaForecastKitAdapter.swift`: the complete file from
  `Sources/TokenCoffeeCore/QuotaForecastKitAdapter.swift`, with only the
  `import QuotaForecastKit` line removed because both files build in one module.
- `QuotaForecastModels.swift`: the `QuotaCycleRunForecast`, line segment, run
  and corridor types from `Sources/TokenCoffeeCore/QuotaProjection.swift`.
- `Tests/BrrainzToolsTests/QuotaForecasterTests.swift`: upstream engine tests,
  with the module import changed to BrrainzTools.

This preserves TokenCoffee's adjusted graph scenarios without depending on a
neighboring checkout, its app target, CloudKit, or its credentials. Update the
copy and revision together when adopting upstream forecast changes. The method
identifier in usage JSON records the source revision and integration version.
TokenCoffee remains the owner of collection, credentials and CloudKit writes.

`UsageForecast.swift` owns file reading, matching a live weekly window, freshness
and evidence checks, consumption-rate calculation, and 100% crossing timestamps.
Its minimal `QuotaSample` decoder reads the existing JSONL format. Upstream
forecast calculations are kept separate from these CLI decisions.

The v2 integration adopts the account registry, SHA256 scope filenames, Claude
`general` and `model:`/`model-name:` scopes from TokenCoffee commit `77bc2b4`.
The forecast engine and adapter are unchanged from the pinned revision above.
Per-account cloud-state lookup follows `LinkedHistoryCloudSync.swift` in that
checkout. It reads sync metadata only when the cloud environment is unambiguous.

The v3 integration vendors `Sources/TokenCoffeeCore/UsageHistoryContract.swift`
unchanged from TokenCoffee revision `9ba32f142a10a5973974bf919b8038d02c081d8b`,
together with its tests, changing only the test module
import. Contract version 1 defines five-second reset matching and canonical Claude
organization/account identity. It changes neither the JSONL schema nor the forecast
engine. The CLI discovers Claude identity with its own credential; it never reads
TokenCoffee's credentials. Freshness diagnostics distinguish the newest stored
sample from the newest matching sample. The 30-minute freshness cutoff is unchanged.

Run `TOKENCOFFEE_SOURCE_DIRECTORY=/path/to/TokenCoffee Scripts/verify.sh` when
updating both repositories. This checks the vendored contract and tests against
upstream before testing. Standalone builds do not require a neighboring checkout.
