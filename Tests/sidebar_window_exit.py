#!/usr/bin/env python3
"""Checks that finishing an address edit keeps the sidebar open when the pointer is off the window.
Requires ./build.sh first. Runs hidden in its own profile and never moves the real pointer.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("sidebar-window-exit")


def run_sequence(sidebar):
    sv.setup(sidebar=sidebar)
    sv.launch()
    sv.page("a")
    sv.cmd({"do": "pages", "on": True})
    sv.cmd({"do": "ui", "folded": True})
    time.sleep(0.3)
    sv.cmd({"do": "ui", "peek": True})
    sv.cmd({"do": "ui", "edittab": ""})
    time.sleep(0.3)
    return sv.cmd({"do": "probe"})


def main():
    t = sv.T()
    try:
        before = run_sequence(True)
        t.ok("sidebar fixture: folded and peeking", before["folded"] and before["peeking"], before)
        sv.cmd({"do": "ui", "finishedit": True})
        time.sleep(0.5)
        after = sv.cmd({"do": "probe"})
        t.ok("sidebar revealed, pointer off the window: finishing an address edit keeps it open", after["peeking"] is True, after["peeking"])
        sv.quit()

        before = run_sequence(False)
        t.ok("control fixture: folded and peeking", before["folded"] and before["peeking"], before)
        sv.cmd({"do": "ui", "finishedit": True})
        time.sleep(0.5)
        after = sv.cmd({"do": "probe"})
        t.ok("tabs across the top: the strip still goes back in when the edit ends", after["peeking"] is False, after["peeking"])
        sv.quit()
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
