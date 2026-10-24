#!/usr/bin/env python3
"""Real-site page navigation timing benchmark.

Measures navigation latency on real-world sites across:
- Plain WKWebView harness (Tests/plainweb/main.swift)
- Brauz baseline
- Brauz with content blocking off (shield=False)
- Brauz with extensions off (extensions.off=True)

Times from submit to didCommit, first visually non-empty layout, and didFinish
for 3 runs each (Run 1 = cold, Runs 2-3 = warm).
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Tests"))
import split_view

split_view.use("real-sites-0027")

SITES = [
    "https://en.wikipedia.org/wiki/WebKit",
    "https://github.com/WebKit/WebKit",
    "https://www.youtube.com",
    "https://www.nytimes.com",
    "https://ya.ru",
    "https://habr.com/ru/feed/",
]

PLAINWEB_SRC = ROOT / "Tests" / "plainweb" / "main.swift"
PLAINWEB_BIN = ROOT / "Tests" / "plainweb" / "plainweb"
DEVELOPER_DIR = "/Volumes/pet30-a/apps/xcode/Xcode.app/Contents/Developer"


def ensure_plainweb():
    if not PLAINWEB_BIN.exists() or PLAINWEB_SRC.stat().st_mtime > PLAINWEB_BIN.stat().st_mtime:
        print("Compiling plainweb harness...", file=sys.stderr)
        env = dict(os.environ, DEVELOPER_DIR=DEVELOPER_DIR)
        res = subprocess.run(
            ["swiftc", "-O", str(PLAINWEB_SRC), "-o", str(PLAINWEB_BIN)],
            env=env,
            capture_output=True,
            text=True,
        )
        if res.returncode != 0:
            print(f"Error compiling plainweb: {res.stderr}", file=sys.stderr)
            sys.exit(1)


def measure_plainweb():
    ensure_plainweb()
    results = {}
    print("\n--- Measuring Plain WKWebView ---")
    for url in SITES:
        print(f"  Loading {url}...", end="", flush=True)
        res = subprocess.run(
            [str(PLAINWEB_BIN), url, "3"],
            capture_output=True,
            text=True,
        )
        if res.returncode == 0 and res.stdout.strip():
            try:
                data = json.loads(res.stdout.strip().splitlines()[-1])
                results[url] = data["runs"]
                print(" done.")
            except Exception as e:
                print(f" failed to parse output ({e}): {res.stdout}", file=sys.stderr)
        else:
            print(f" failed ({res.returncode}): {res.stderr}", file=sys.stderr)
            results[url] = [{"commit": -1, "layout": -1, "finish": -1}] * 3
    return results


def measure_brauz_config(name, **prefs):
    print(f"\n--- Measuring Brauz ({name}) ---")
    split_view.setup(**prefs)
    split_view.launch(settle=2)
    results = {}
    try:
        for url in SITES:
            print(f"  Loading {url} (3 runs)...", end="", flush=True)
            runs = []
            for run_idx in range(3):
                try:
                    ans = split_view.cmd({"do": "time-nav", "url": url, "timeout": 30.0})
                    runs.append({
                        "commit": ans.get("commit", -1),
                        "layout": ans.get("layout", -1),
                        "finish": ans.get("finish", -1),
                    })
                    time.sleep(0.5)
                except Exception as e:
                    print(f" [run {run_idx+1} error: {e}]", end="", flush=True)
                    runs.append({"commit": -1, "layout": -1, "finish": -1})
            results[url] = runs
            print(" done.")
    finally:
        split_view.quit()
        time.sleep(0.5)
        split_view.wipe()
    return results


def fmt(val):
    if val is None or val < 0:
        return "-"
    return f"{val:.0f}"


def run():
    plain_results = measure_plainweb()
    brauz_base = measure_brauz_config("baseline")
    brauz_noshield = measure_brauz_config("shield off", shield=False)
    brauz_noext = measure_brauz_config("extensions off", **{"extensions.off": True})

    all_data = {
        "plain": plain_results,
        "brauz_base": brauz_base,
        "brauz_noshield": brauz_noshield,
        "brauz_noext": brauz_noext,
    }
    with open(ROOT / "Tests" / "real_site_timing_results.json", "w") as f:
        json.dump(all_data, f, indent=2)

    print("\n" + "=" * 80)
    print("TIMING RESULTS TABLE (All times in milliseconds: commit / layout / finish)")
    print("=" * 80)

    for url in SITES:
        slug = url.replace("https://", "").replace("www.", "")
        print(f"\n### {slug}")
        print("| Configuration | Cold (Run 1) | Warm (Run 2) | Warm (Run 3) | Warm Avg |")
        print("|---|---|---|---|---|")

        for label, data in [
            ("Plain WKWebView", plain_results),
            ("Brauz (baseline)", brauz_base),
            ("Brauz (shield off)", brauz_noshield),
            ("Brauz (extensions off)", brauz_noext),
        ]:
            runs = data.get(url, [])
            r1 = runs[0] if len(runs) > 0 else {}
            r2 = runs[1] if len(runs) > 1 else {}
            r3 = runs[2] if len(runs) > 2 else {}

            c1 = f"{fmt(r1.get('commit'))} / {fmt(r1.get('layout'))} / {fmt(r1.get('finish'))}"
            c2 = f"{fmt(r2.get('commit'))} / {fmt(r2.get('layout'))} / {fmt(r2.get('finish'))}"
            c3 = f"{fmt(r3.get('commit'))} / {fmt(r3.get('layout'))} / {fmt(r3.get('finish'))}"

            # Compute warm avg
            warm_commits = [r.get('commit', -1) for r in [r2, r3] if r.get('commit', -1) >= 0]
            warm_layouts = [r.get('layout', -1) for r in [r2, r3] if r.get('layout', -1) >= 0]
            warm_finishes = [r.get('finish', -1) for r in [r2, r3] if r.get('finish', -1) >= 0]

            avg_commit = sum(warm_commits) / len(warm_commits) if warm_commits else -1
            avg_layout = sum(warm_layouts) / len(warm_layouts) if warm_layouts else -1
            avg_finish = sum(warm_finishes) / len(warm_finishes) if warm_finishes else -1
            avg_str = f"{fmt(avg_commit)} / {fmt(avg_layout)} / {fmt(avg_finish)}"

            print(f"| {label} | {c1} | {c2} | {c3} | {avg_str} |")

    return all_data


if __name__ == "__main__":
    run()
