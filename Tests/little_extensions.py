#!/usr/bin/env python3
"""Extensions on a little window's page (Little.swift), including first-load
startup, cookie space switching, and row keep/close lifecycle.

Checks genuine content-script -> worker -> tabs.sendMessage(sender.tab.id)
round trip across ordinary tabs, little windows, space switching, row keeps,
and immediate cold-start creation after launch(settle=0).
"""
import functools
import json
import os
import shutil
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


def get_safe_state():
    """State snapshot for diagnostics on failure, reporting no secrets."""
    info = {}
    try:
        info["little"] = sv.cmd({"do": "little", "what": "state"})
    except Exception as e:
        info["little"] = f"error: {e}"
    try:
        sp = sv.cmd({"do": "space"})
        info["space"] = {
            "current": sp.get("current"),
            "spaces": [{"name": s.get("name"), "id": s.get("id"), "shared": s.get("shared")} for s in sp.get("spaces", [])],
        }
    except Exception as e:
        info["space"] = f"error: {e}"
    try:
        exts = sv.cmd({"do": "extensions"}).get("extensions", [])
        info["extensions"] = [{"name": x.get("name"), "loaded": x.get("loaded")} for x in exts]
    except Exception as e:
        info["extensions"] = f"error: {e}"
    return info


def outcome(tab, wait=15):
    """What the page says, once it reaches a final outcome other than intermediate states."""
    said = "no script"
    deadline = time.time() + wait
    while time.time() < deadline:
        try:
            val = sv.cmd({"do": "eval", "id": tab, "js": READ}).get("value")
            if val is not None:
                said = str(val)
                if said not in ("script", "no script", "reloading", "switching"):
                    break
        except Exception as e:
            said = f"eval error: {e}"
        time.sleep(0.1)
    return said


def make_little(url, timeout=15):
    """Open a little window and poll until its ID is available."""
    deadline = time.time() + timeout
    created = False
    last_err = None
    while time.time() < deadline:
        try:
            res = sv.cmd({"do": "little", "what": url})
            if "littleIDs" in res and res["littleIDs"]:
                return res["littleIDs"][-1]
            created = True
            break
        except Exception as e:
            last_err = e
            time.sleep(0.1)
    if not created:
        raise RuntimeError(f"failed to open little window for {url}: {last_err=}, state={get_safe_state()}")

    while time.time() < deadline:
        try:
            st = sv.cmd({"do": "little", "what": "state"})
            if "littleIDs" in st and st["littleIDs"]:
                return st["littleIDs"][-1]
        except Exception as e:
            last_err = e
        time.sleep(0.1)
    raise RuntimeError(f"little window never appeared in state for {url}: {last_err=}, state={get_safe_state()}")


def create_fresh_space(name="Fresh Space", timeout=10):
    """Create a space with independent cookies and return its space ID."""
    res = sv.cmd({"do": "space", "action": "new", "name": name, "fresh": True})
    for s in res.get("spaces", []):
        if s.get("name") == name:
            return s["id"]
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            st = sv.cmd({"do": "space"})
            for s in st.get("spaces", []):
                if s.get("name") == name:
                    return s["id"]
        except Exception:
            pass
        time.sleep(0.1)
    raise RuntimeError(f"fresh space {name} not found in spaces: {res=}, state={get_safe_state()}")


def poll_little_closed(timeout=10):
    """Wait until all little windows are closed."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            st = sv.cmd({"do": "little", "what": "state"})
            if not st.get("littleIDs"):
                return True
        except Exception:
            pass
        time.sleep(0.1)
    return False


def main():
    folder = None
    pages = None
    server = None
    t = sv.T()

    try:
        folder = Path(tempfile.mkdtemp(prefix="search-little-ext-"))
        (folder / "manifest.json").write_text(json.dumps(MANIFEST))
        (folder / "page.js").write_text(PAGE_JS)
        (folder / "worker.js").write_text(WORKER_JS)

        pages = Path(tempfile.mkdtemp(prefix="search-little-pages-"))
        (pages / "login.html").write_text("<!doctype html><title>login</title><input type=password>")

        class Quiet(SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(pages)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{server.server_port}/login.html"

        # Build installed fixture profile once with spaces enabled
        sv.setup(spaces=True)
        sv.launch()
        sv.cmd({"do": "ext-folder", "path": str(folder), "yes": True})

        ext_loaded = False
        deadline = time.time() + 20
        while time.time() < deadline:
            try:
                items = sv.cmd({"do": "extensions"}).get("extensions", [])
                if any(i.get("name") == MANIFEST["name"] and i.get("loaded") for i in items):
                    ext_loaded = True
                    break
            except Exception:
                pass
            time.sleep(0.2)
        if not ext_loaded:
            sys.exit(f"the test extension never loaded: state={get_safe_state()}")

        # Check ordinary tab injection
        tab = sv.sp("open", url=url)["resultID"]
        said = outcome(tab)
        t.ok("an ordinary tab is filled", said.startswith("filled"), f"{said} state={get_safe_state()}")

        # Check little window injection
        little = make_little(url)
        said = outcome(little)
        t.ok("a little window's page is filled", said.startswith("filled"), f"{said} state={get_safe_state()}")

        # Switch little window to fresh cookie space and check round trip
        fresh_space_id = create_fresh_space("Fresh Space")
        try:
            sv.cmd({"do": "eval", "id": little, "js": "document.documentElement.dataset.ext = 'switching'; 1"})
        except Exception:
            pass
        sv.cmd({"do": "little", "what": "space", "spaceID": str(fresh_space_id)})

        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                st = sv.cmd({"do": "little", "what": "state"})
                space_ids = [str(x).lower() for x in st.get("spaceIDs", [])]
                if space_ids and space_ids[-1] == str(fresh_space_id).lower():
                    break
            except Exception:
                pass
            time.sleep(0.1)

        said = outcome(little)
        t.ok("a little window switched to a fresh cookie space is filled", said.startswith("filled"), f"{said} state={get_safe_state()}")

        # Keep into selected space and recheck injection
        sv.cmd({"do": "little", "what": "keep"})
        poll_little_closed()

        try:
            sv.cmd({"do": "eval", "id": little, "js": "document.documentElement.dataset.ext = 'reloading'; location.reload(); 1"})
        except Exception:
            pass
        said = outcome(little)
        t.ok("a little window's page kept into the row is filled", said.startswith("filled"), f"{said} state={get_safe_state()}")

        # Close without being kept, verify subsequent ordinary tab works
        to_close = make_little(url)
        said = outcome(to_close)
        t.ok("a second little window before close is filled", said.startswith("filled"), f"{said} state={get_safe_state()}")

        sv.cmd({"do": "little", "what": "close"})
        poll_little_closed()

        subsequent = sv.sp("open", url=url)["resultID"]
        said = outcome(subsequent)
        t.ok("after a little window closes, a new tab is filled", said.startswith("filled"), f"{said} state={get_safe_state()}")

        # Cold-start: preserve isolated installed extension profile, quit and relaunch with settle=0
        sv.quit()
        sv.launch(settle=0)

        cold_little = make_little(url)
        said = outcome(cold_little, wait=20)
        t.ok("cold-start first document in little window gets round trip", said.startswith("filled"), f"{said} state={get_safe_state()}")

    finally:
        t.done()
        sv.finish()
        if server is not None:
            try:
                server.shutdown()
                server.server_close()
            except Exception:
                pass
        if folder is not None and os.path.exists(folder):
            shutil.rmtree(folder, ignore_errors=True)
        if pages is not None and os.path.exists(pages):
            shutil.rmtree(pages, ignore_errors=True)

    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
