#!/usr/bin/env python3
"""Verify live allowance and the forecast contract; keep the full result in the workflow log."""
import json
import os
import subprocess
import sys

binary = sys.argv[1]
result = subprocess.run([binary, "usage", "codex"], text=True, capture_output=True, timeout=30)
print(result.stdout, end="")
if result.returncode:
    raise SystemExit("Installed Codex usage failed; see provider status above.")
report = json.loads(result.stdout)
providers = report["data"]["providers"]
assert len(providers) == 1 and providers[0]["provider"] == "codex"
assert report["ok"] and providers[0]["status"] == "ok"
matched = False
for window in providers[0]["windows"]:
    if window["name"] in ("primary", "secondary") and window.get("windowSeconds") == 604800:
        matched = True
        forecast = window["forecast"]
        assert forecast["historySource"] == "tokencoffee"
        assert forecast["status"] in ("ok", "exhausted", "unavailable", "stale_history", "insufficient_history")
        if forecast["status"] in ("ok", "exhausted"):
            assert "reaches100At" in forecast["optimistic"]
            assert "reaches100At" in forecast["pessimistic"]
        else:
            print("Forecast not available:", forecast["status"], forecast.get("reason", ""))
            if os.environ.get("REQUIRE_CODEX_FORECAST") == "1":
                raise SystemExit("A working Codex forecast is required for this verification.")
    else:
        assert "forecast" not in window

if os.environ.get("REQUIRE_CODEX_FORECAST") == "1" and not matched:
    raise SystemExit("Provider returned no supported Codex weekly window to verify.")
