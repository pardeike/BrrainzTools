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
TokenCoffee itself is not modified by this integration.

`UsageForecast.swift` owns file reading, matching a live weekly window, freshness
and evidence checks, consumption-rate calculation, and 100% crossing timestamps.
Its minimal `QuotaSample` decoder reads the existing JSONL format. Upstream
forecast calculations are kept separate from these CLI decisions.
