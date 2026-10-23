#!/usr/bin/env python3
"""Checks that a waking tab's cover stays until first paint and clicks do not drop it.
Requires ./build.sh first.
"""
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("wake-cover-0028")


class SlowHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/slow.css":
            time.sleep(0.8)
            body = b"body { background: #123456; }"
            self.send_response(200)
            self.send_header("Content-Type", "text/css")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/slow":
            body = b"<!doctype html><html><head><link rel='stylesheet' href='/slow.css'></head><body><h1>Slow Page</h1></body></html>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            body = b"<!doctype html><html><body><h1>Other</h1></body></html>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def log_message(self, *a):
        pass


def find_tab(tabs, tab_id):
    for tab in tabs:
        if tab["id"] == tab_id or tab["id"] == tab_id[:8]:
            return tab
    return None


def main():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), SlowHandler)
    server_thread = threading.Thread(target=srv.serve_forever, daemon=True)
    server_thread.start()
    base_url = f"http://127.0.0.1:{srv.server_port}"

    t = sv.T()
    try:
        sv.setup()
        sv.launch()

        # Open slow page tab
        res1 = sv.sp("open", url=f"{base_url}/slow")
        tab_slow = res1["resultID"]
        time.sleep(1.5)

        # Open second tab to background the slow page
        res2 = sv.sp("open", url=f"{base_url}/other")
        tab_other = res2["resultID"]
        time.sleep(0.5)

        # Put the slow tab to sleep
        sleep_res = sv.cmd({"do": "sleep", "id": tab_slow})
        time.sleep(0.5)
        tabs = sv.cmd({"do": "tabs"})["tabs"]
        slow_info = find_tab(tabs, tab_slow)
        t.ok("fixture: slow tab is asleep", slow_info is not None and slow_info.get("asleep") is True, slow_info)

        # Test 1: Wake the slow tab and sample bench state over time
        sv.cmd({"do": "select", "id": tab_slow})
        start_time = time.time()
        samples = []
        while time.time() - start_time < 1.4:
            tabs_state = sv.cmd({"do": "tabs"})["tabs"]
            info = find_tab(tabs_state, tab_slow)
            if info:
                samples.append({
                    "t": time.time() - start_time,
                    "cover": info.get("cover", False),
                    "unpainted": info.get("unpainted", False),
                    "asleep": info.get("asleep", False),
                })
            time.sleep(0.025)

        # The cover must be present initially while waking
        had_cover = any(s["cover"] for s in samples)
        t.ok("waking tab shows snapshot cover initially", had_cover, samples[:5])

        # Bug in un-fixed code: cover drops before first paint (didCommit uncover(after: 0.45) fires while unpainted is True)
        premature_drops = [s for s in samples if (not s["cover"]) and s["unpainted"]]
        t.ok("cover stays until first paint (never drops while unpainted is True)", len(premature_drops) == 0, premature_drops)

        # Test 2: Click on a waking tab must not drop cover before first paint
        # Background slow tab again by selecting the other tab
        sv.cmd({"do": "select", "id": tab_other})
        time.sleep(0.5)
        sv.cmd({"do": "sleep", "id": tab_slow})
        time.sleep(0.5)

        tabs = sv.cmd({"do": "tabs"})["tabs"]
        slow_info = find_tab(tabs, tab_slow)
        t.ok("fixture: slow tab asleep again for click test", slow_info is not None and slow_info.get("asleep") is True, slow_info)

        # Wake slow tab and click it while still unpainted
        sv.cmd({"do": "select", "id": tab_slow})
        time.sleep(0.08)
        # Click on the waking tab
        sv.cmd({"do": "hit", "x": 300, "y": 300, "press": True})
        after_click = find_tab(sv.cmd({"do": "tabs"})["tabs"], tab_slow)
        t.ok(
            "click on waking tab does not drop cover before first paint",
            after_click is not None and after_click.get("cover") is True and after_click.get("unpainted") is True,
            after_click,
        )

        sv.quit()
    finally:
        t.done()
        sv.finish()
        srv.shutdown()

    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
