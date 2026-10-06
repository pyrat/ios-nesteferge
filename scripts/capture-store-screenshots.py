#!/usr/bin/env python3
"""Capture real app screens from installed iOS simulators using production data.

Build a simulator .app first, then pass its path. This reinstalls the app on the
selected simulators to clear previous route selections. No physical device or
production data is modified. Screens must be visually reviewed after capture.
"""

import argparse
from datetime import datetime
from pathlib import Path
import subprocess
import time
from zoneinfo import ZoneInfo


DEVICES = {
    "iphone": "A4BD6CBD-DA1C-4C21-9AB4-E247306D0B07",
    "ipad": "D4B1EC01-499F-439B-888E-620314D97AEF",
}
ROUTES = [
    ("01-anda-lote", "61.832,6.006"),
    ("02-festoya-hundeidvika", "62.390,6.330"),
    ("03-moss-horten", "59.434,10.656"),
]
BUNDLE = "com.axb.nesteferge"


def simctl(*args, check=True):
    return subprocess.run(["xcrun", "simctl", *args], check=check)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="Path to simulator Nesteferge.app")
    parser.add_argument("--output", type=Path, default=Path("docs/app-store/screenshots"))
    parser.add_argument("--iphone", default=DEVICES["iphone"], help="iPhone simulator UDID")
    parser.add_argument("--ipad", default=DEVICES["ipad"], help="iPad simulator UDID")
    parser.add_argument("--devices", nargs="+", choices=["iphone", "ipad"], default=["iphone", "ipad"])
    parser.add_argument("--languages", nargs="+", choices=["nb", "en"], default=["nb", "en"])
    parser.add_argument("--routes", nargs="+", choices=[name for name, _ in ROUTES])
    args = parser.parse_args()
    if not args.app.is_dir():
        parser.error("Simulator app bundle does not exist")

    for kind, device in [("iphone", args.iphone), ("ipad", args.ipad)]:
        if kind not in args.devices:
            continue
        simctl("bootstatus", device, "-b")
        simctl("ui", device, "appearance", "dark")
        for language in args.languages:
            folder = args.output / language / kind
            folder.mkdir(parents=True, exist_ok=True)
            for name, coordinates in ROUTES:
                if args.routes and name not in args.routes:
                    continue
                simctl("uninstall", device, BUNDLE, check=False)
                simctl("install", device, str(args.app.resolve()))
                simctl("privacy", device, "grant", "location", BUNDLE)
                simctl("location", device, "set", coordinates)
                simctl("launch", device, BUNDLE, "-AppleLanguages", f"({language})",
                       "-AppleLocale", "nb_NO" if language == "nb" else "en_GB")
                # Allow the location fix, API requests and UI animations to finish.
                time.sleep(8)
                simctl("status_bar", device, "override", "--time",
                       datetime.now(ZoneInfo("Europe/Oslo")).strftime("%H:%M"),
                       "--dataNetwork", "wifi", "--wifiMode", "active",
                       "--wifiBars", "3", "--cellularMode", "active",
                       "--cellularBars", "4", "--batteryState", "discharging",
                       "--batteryLevel", "100")
                simctl("io", device, "screenshot", str(folder / f"{name}.png"))
        simctl("status_bar", device, "clear")


if __name__ == "__main__":
    main()
