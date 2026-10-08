#!/usr/bin/env python3
"""Extensions on a little window's page (Little.swift), as a password manager
fills: the page's script asks the extension's worker, and the worker answers
that tab with tabs.sendMessage(sender.tab.id). A page whose tab WebKit was
never told about gets no answer, and nothing is filled.

Build first (`./build.sh`), then `python3 Tests/little_extensions.py`. The
app is started hidden in a world of its own and driven through ./bench's
socket; the little window is made without being shown. The same page in an
ordinary tab is checked first: if that fails, the test is broken, not the
little window.
"""
import functools
import json
import sys
import tempfile
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("little-extensions")

MANIFEST = {
    "manifest_version": 3,
    "name": "Little fill test",
    "version": "1.0",
    "background": {"service_worker": "worker.js"},
    "content_scripts": [{"matches": ["<all_urls>"], "js": ["page.js"], "run_at": "document_idle"}],
    "permissions": ["tabs"],
    "host_permissions": ["<all_urls>"],
}
# What the page shows: "script" once the content script runs, "filled <id>"
# once the worker has answered its tab, "no tab" if the worker saw none.
PAGE_JS = """
const root = document.documentElement;
root.dataset.ext = "script";
chrome.runtime.onMessage.addListener(m => { if (m.fill !== undefined) root.dataset.ext = "filled " + m.fill; });
chrome.runtime.sendMessage({ hi: 1 }, r => {
  if (root.dataset.ext !== "script") return;
  if (chrome.runtime.lastError) root.dataset.ext = "no answer: " + chrome.runtime.lastError.message;
  else if (!r) root.dataset.ext = "no answer";
  else if (r.tab === null) root.dataset.ext = "no tab";
});
"""
WORKER_JS = """
chrome.runtime.onMessage.addListener((m, sender, reply) => {
  const id = sender.tab ? sender.tab.id : null;
  reply({ tab: id });
  if (id !== null) chrome.tabs.sendMessage(id, { fill: id }, { frameId: sender.frameId });
});
"""
READ = "document.documentElement.dataset.ext || 'no script'"


def outcome(tab, wait=10):
    """What the page says, once it says something other than "script"."""
    said = "no script"
    deadline = time.time() + wait
    while time.time() < deadline:
        said = sv.cmd({"do": "eval", "id": tab, "js": READ}).get("value") or "no script"
        if said != "script" and said != "no script":
            break
        time.sleep(0.3)
    return said


def main():
    folder = Path(tempfile.mkdtemp(prefix="search-little-ext-"))
    (folder / "manifest.json").write_text(json.dumps(MANIFEST))
    (folder / "page.js").write_text(PAGE_JS)
    (folder / "worker.js").write_text(WORKER_JS)

    pages = tempfile.mkdtemp(prefix="search-little-pages-")
    Path(pages, "login.html").write_text("<!doctype html><title>login</title><input type=password>")

    class Quiet(SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass
    server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=pages))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_port}/login.html"

    t = sv.T()
    try:
        sv.setup(); sv.launch()
        sv.cmd({"do": "ext-folder", "path": str(folder), "yes": True})
        for _ in range(60):
            items = sv.cmd({"do": "extensions"})["extensions"]
            if any(i["name"] == MANIFEST["name"] and i["loaded"] for i in items):
                break
            time.sleep(0.25)
        else:
            sys.exit(f"the test extension never loaded: {items}")

        tab = sv.sp("open", url=url)["resultID"]
        said = outcome(tab)
        t.ok("an ordinary tab is filled", said.startswith("filled"), said)

        little = sv.cmd({"do": "little", "what": url})["littleIDs"][-1]
        said = outcome(little)
        t.ok("a little window's page is filled", said.startswith("filled"), said)

        # Kept (Open in Search): the same tab, the same view, now a tab of the
        # window's row. Filled there once the page asks again.
        sv.cmd({"do": "little", "what": "keep"})
        time.sleep(0.5)
        sv.cmd({"do": "eval", "id": little, "js": "location.reload(); 1"})
        time.sleep(1)
        said = outcome(little)
        t.ok("a little window's page kept into the row is filled", said.startswith("filled"), said)

        # Closed without being kept: gone for WebKit, and nothing else upset.
        sv.cmd({"do": "little", "what": url})
        time.sleep(1)
        left = sv.cmd({"do": "little", "what": "close"})["littles"]
        time.sleep(0.5)
        after = sv.sp("open", url=url)["resultID"]
        said = outcome(after)
        t.ok("after a little window closes, a new tab is filled", not left and said.startswith("filled"), (left, said))
    finally:
        t.done(); sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
