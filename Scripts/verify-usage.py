#!/usr/bin/env python3
"""Verify live allowance and the forecast contract; keep the full result in the workflow log."""
import json
import os
import subprocess
import sys

binary = sys.argv[1]
provider = sys.argv[2] if len(sys.argv) > 2 else "codex"
result = subprocess.run([binary, "usage", provider], text=True, capture_output=True, timeout=75)
print(result.stdout, end="")
if result.returncode:
    raise SystemExit(f"Installed {provider} usage failed; see provider status above.")
report = json.loads(result.stdout)
providers = report["data"]["providers"]
assert len(providers) == 1 and providers[0]["provider"] == provider
assert report["ok"] and providers[0]["status"] == "ok"
matched = False
for window in providers[0]["windows"]:
    name = window["name"]
    supported = name in ("primary", "secondary") if provider == "codex" else (
        name == "seven_day" or name.startswith(("model:", "model-name:")))
    if supported and window.get("windowSeconds") == 604800:
        matched = True
        forecast = window["forecast"]
        assert forecast["historySource"] == "tokencoffee"
        assert forecast["historyContractVersion"] == 1
        if os.environ.get("REQUIRE_" + provider.upper() + "_IDENTITY") == "1":
            assert forecast["accountMatch"] == "verified", "Expected a verified account match"
        assert forecast["status"] in ("ok", "exhausted", "unavailable", "stale_history", "insufficient_history")
        if forecast["status"] in ("ok", "exhausted"):
            assert "reaches100At" in forecast["optimistic"]
            assert "reaches100At" in forecast["pessimistic"]
            if forecast["status"] == "ok":
                assert "newestStoredSampleAt" in forecast and "latestSampleAt" in forecast
                assert forecast["rejectedSampleCount"] >= 0
        else:
            print("Forecast not available:", forecast["status"], forecast.get("reason", ""))
            if os.environ.get("REQUIRE_" + provider.upper() + "_FORECAST") == "1":
                raise SystemExit(f"A working {provider} forecast is required for this verification.")
    else:
        assert "forecast" not in window

if os.environ.get("REQUIRE_" + provider.upper() + "_FORECAST") == "1" and not matched:
    raise SystemExit(f"Provider returned no supported {provider} weekly window to verify.")
