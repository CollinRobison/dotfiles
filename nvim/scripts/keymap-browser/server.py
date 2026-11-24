"""Launch the local Neovim keybinding browser or regenerate its PDF atlas."""
import argparse
import contextlib
import hashlib
import hmac
import json
import os
import secrets
import stat
import subprocess
import sys
import tempfile
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

from catalog import ATLAS, CONFIG, HERE, Catalog, nvim_bin, nvim_env, public_row
from smart_search import SearchUnavailable, smart_options, smart_search

STATE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "nvim-keymaps"
ASSETS = {"/": ("index.html", "text/html; charset=utf-8"),
          "/app.js": ("app.js", "text/javascript; charset=utf-8"),
          "/style.css": ("style.css", "text/css; charset=utf-8")}
PDF = CONFIG / "docs" / "Nvim-Dark-Complete-Atlas.pdf"


class StaleEdit(ValueError):
    pass


@contextlib.contextmanager
def config_lock():
    # The config may be open in several independently launched browser sessions.
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    ident = hashlib.sha256(os.fsencode(CONFIG)).hexdigest()[:20]
    with (STATE / f"{ident}.lock").open("a+b") as handle:
        if os.name == "nt":
            import msvcrt
            if not handle.tell():
                handle.write(b"\0")
                handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        yield


def regenerate():
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    result = subprocess.run([sys.executable, str(ATLAS), "--non-interactive"],
                            env=env, capture_output=True, text=True, timeout=180)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "Atlas generation failed")
    return result.stdout.strip()


def replace_binding(row, value):
    path = (CONFIG / row["file"]).resolve(strict=True)
    if not path.is_relative_to(CONFIG.resolve()):
        raise ValueError("This declaration is outside your Neovim configuration.")
    original = path.read_bytes()
    if hashlib.sha256(original).hexdigest() != row["digest"]:
        raise StaleEdit("The file changed on disk. Refresh the list and review the shortcut again.")
    start, finish = row["start"], row["finish"]
    old = original[start:finish]
    quote = chr(old[0]) if old[:1] in (b'"', b"'") else '"'
    literal = quote + value.replace("\\", "\\\\").replace(quote, "\\" + quote) + quote
    if row["style"] == "field":
        literal = "[" + literal + "]"
    updated = original[:start] + literal.encode("utf-8") + original[finish:]
    stage = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, suffix=".tmp", delete=False) as handle:
            stage = Path(handle.name)
            handle.write(updated)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(stage, stat.S_IMODE(path.stat().st_mode))
        env = nvim_env(KEYMAP_CHECK_FILE=str(stage))
        checked = subprocess.run(
            [nvim_bin(), "--clean", "--headless", "-c",
             'lua if not loadfile(vim.env.KEYMAP_CHECK_FILE) then vim.cmd("cquit 1") end', "-c", "qa!"],
            env=env, capture_output=True, timeout=5)
        if checked.returncode:
            raise ValueError("Neovim could not parse the proposed Lua change.")
        if path.read_bytes() != original:
            raise StaleEdit("The file changed on disk. Refresh the list and review the shortcut again.")
        os.replace(stage, path)
    finally:
        if stage:
            stage.unlink(missing_ok=True)


class LocalBrowser(ThreadingHTTPServer):
    def __init__(self, args, live):
        self.catalog = Catalog(CONFIG, live)
        self.secret = secrets.token_urlsafe(32)
        self.guard = threading.Lock()
        self.search_guard = threading.Lock()
        self.last_request = time.monotonic()
        self.idle_seconds = args.idle_seconds
        super().__init__(("127.0.0.1", 0), Handler)
        self.host = f"127.0.0.1:{self.server_port}"
        self.origin = "http://" + self.host

    def inventory(self):
        c = self.catalog
        return {"rows": [public_row(row) for row in c.rows], "warnings": c.warnings,
                "leader": c.leader, "localleader": c.localleader, "config": str(CONFIG),
                "live": bool(c.live)}

    def review(self, data):
        self.catalog.refresh(probe=True)
        ident = data.get("id")
        if not isinstance(ident, str):
            raise ValueError("Choose a Neovim configuration mapping.")
        row = self.catalog.by_id.get(ident)
        if not row or not row["editable"]:
            raise StaleEdit("The declaration changed on disk. Refresh the list and select the mapping again.")
        if str(CONFIG / row["file"]) in self.catalog.live.get("modified", []):
            raise StaleEdit("This file has unsaved changes in the Neovim session. Save it there and reopen Keymaps.")
        new = data.get("key")
        conflicts = self.catalog.propose(row, new)
        digest = hmac.digest(self.secret.encode(), json.dumps([ident, new, conflicts, self.catalog.warnings],
                                                              sort_keys=True).encode(), "sha256").hex()
        return row, {"conflicts": conflicts, "review": digest, "warnings": self.catalog.warnings}

    def save(self, data):
        with config_lock():
            row, reviewed = self.review(data)
            if data.get("review") != reviewed["review"]:
                raise StaleEdit("The conflict check changed. Review the shortcut again before saving.")
            replace_binding(row, data["key"])
            self.catalog.retired.append((row["chords"], row["modes"], row["scope"]))
            inventory = None
            try:
                self.catalog.refresh(probe=True)
                inventory = self.inventory()
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
                # The change is already on disk even when post-save discovery fails.
                pass
            return {"inventory": inventory, "file": row["file"], "line": row["line"],
                    "key": data["key"], "start": row["start"]}

    def rank_shortcuts(self, data):
        with self.guard:
            catalog = self.catalog
            rows, leader, localleader = catalog.rows, catalog.leader, catalog.localleader
            context = {key: catalog.live[key] for key in ("filetype", "buffer_lsp") if key in catalog.live}
        result = smart_search(data, rows, leader, localleader, context)
        with self.guard:
            if rows is not self.catalog.rows:
                raise StaleEdit("Keybindings changed during the search. Run Smart search again.")
        return result

    def watch_idle(self):
        while not threading.Event().wait(min(self.idle_seconds, 30)):
            if (time.monotonic() - self.last_request > self.idle_seconds
                    and not self.guard.locked() and not self.search_guard.locked()):
                self.shutdown()
                return


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def reply(self, data, content_type, status=200, **headers):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy",
                         "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; "
                         "base-uri 'none'; frame-ancestors 'none'; form-action 'none'")
        for key, value in headers.items():
            self.send_header(key.replace("_", "-"), value)
        self.end_headers()
        if data:
            with contextlib.suppress(BrokenPipeError, ConnectionResetError):
                self.wfile.write(data)

    def json(self, data, status=200):
        self.reply(json.dumps(data, ensure_ascii=False).encode(), "application/json", status)

    def allowed(self, api=False):
        if self.headers.get("Host") != self.server.host:
            return False
        if not api:
            return True
        origin = self.headers.get("Origin")
        return ((origin is None or origin == self.server.origin)
                and self.headers.get("X-Keymaps-Session") == self.server.secret)

    def do_GET(self):
        path = urlsplit(self.path).path
        if not self.allowed(api=path.startswith("/api/")):
            self.json({"error": "Invalid local session. Launch nvim-keymaps again."}, 403)
            return
        self.server.last_request = time.monotonic()
        if path in ASSETS:
            filename, media_type = ASSETS[path]
            self.reply((HERE / filename).read_bytes(), media_type)
        elif path == "/api/catalog":
            with self.server.guard:
                self.json(self.server.inventory())
        elif path == "/api/smart-options":
            try:
                self.json(smart_options())
            except SearchUnavailable as error:
                self.json({"error": str(error)}, 503)
        elif path == "/api/ping":
            self.reply(b"", "text/plain", 204)
        else:
            self.json({"error": "Page not found."}, 404)

    def do_POST(self):
        path = urlsplit(self.path).path
        if not self.allowed(api=True):
            self.json({"error": "Invalid local session. Launch nvim-keymaps again."}, 403)
            return
        self.server.last_request = time.monotonic()
        try:
            length = int(self.headers.get("Content-Length", "-1"))
            if not 0 < length <= 8192 or self.headers.get_content_type() != "application/json":
                raise ValueError("Invalid request")
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict):
                raise ValueError("Invalid request")
            if path == "/api/smart-search":
                if not self.server.search_guard.acquire(blocking=False):
                    self.json({"error": "Pi is finishing another search. Try again in a moment."}, 429)
                    return
                try:
                    self.json(self.server.rank_shortcuts(data))
                finally:
                    self.server.search_guard.release()
                return
            with self.server.guard:
                if path == "/api/refresh":
                    self.server.catalog.refresh(probe=True)
                    self.json(self.server.inventory())
                elif path == "/api/review":
                    self.json(self.server.review(data)[1])
                elif path == "/api/save":
                    self.json(self.server.save(data))
                elif path == "/api/atlas":
                    with config_lock():
                        regenerate()
                        self.reply(PDF.read_bytes(), "application/pdf",
                                   Content_Disposition=f'attachment; filename="{PDF.name}"')
                else:
                    self.json({"error": "Action not found."}, 404)
        except SearchUnavailable as error:
            self.json({"error": str(error)}, 503)
        except StaleEdit as error:
            self.json({"error": str(error)}, 409)
        except ValueError as error:
            self.json({"error": str(error)}, 400)
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            self.json({"error": str(error)[-2400:]}, 500)
        finally:
            self.server.last_request = time.monotonic()


def open_url(url):
    if sys.platform == "darwin":
        subprocess.run(["open", url], check=True)
    elif os.name == "nt" and not url.startswith("http"):
        os.startfile(url)
    elif not webbrowser.open(url, new=2):
        raise RuntimeError("Could not open the browser. Copy the local URL into a browser.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--atlas", action="store_true", help="Regenerate the PDF without starting the browser app")
    parser.add_argument("--open", action="store_true", help="Open the PDF after --atlas")
    parser.add_argument("--json", action="store_true", help="Print the current inventory as JSON")
    parser.add_argument("--foreground", action="store_true", help="Keep the local service in this terminal")
    parser.add_argument("--no-open", action="store_true", help="Print the URL without launching a browser")
    parser.add_argument("--snapshot", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--idle-seconds", type=int, default=1200, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.atlas:
        with config_lock():
            print(regenerate())
        if args.open:
            open_url(str(PDF))
        return
    if not (args.foreground or args.no_open or args.json or args.snapshot):
        options = {"creationflags": subprocess.DETACHED_PROCESS} if os.name == "nt" else {"start_new_session": True}
        with tempfile.TemporaryFile() as errors:
            child = subprocess.Popen([sys.executable, "-B", __file__, *sys.argv[1:], "--foreground"],
                                     stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=errors, **options)
            line = child.stdout.readline().decode(errors="replace").strip()
            child.stdout.close()
            if not line:
                errors.seek(0)
                raise RuntimeError(errors.read().decode(errors="replace").strip() or "The local server did not start")
            print(line)
        return
    live = None
    if args.snapshot:
        try:
            live = json.loads(args.snapshot.read_bytes())
        finally:
            args.snapshot.unlink(missing_ok=True)
    if args.json:
        catalog = Catalog(CONFIG, live)
        print(json.dumps({"rows": [public_row(row) for row in catalog.rows], "warnings": catalog.warnings}))
        return
    with LocalBrowser(args, live) as server:
        url = server.origin + "/#" + server.secret
        if not args.no_open:
            open_url(url)
        print(url, flush=True)
        threading.Thread(target=server.watch_idle, daemon=True).start()
        server.serve_forever()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
