"""Exercise Pi Chat's macOS command policy without Pi, a model, or credentials."""
from pathlib import Path
import socket
import subprocess
import sys
import tempfile


if sys.platform != "darwin" or not Path("/usr/bin/sandbox-exec").is_file():
    print("Skipped: macOS sandbox-exec required")
    sys.exit(0)

source = Path(__file__).resolve().parents[2] / "scripts/ai/pi-chat-tools.ts"
policy = source.read_text().split("const sandboxPolicy = String.raw`", 1)[1].split("`;", 1)[0]
with tempfile.TemporaryDirectory() as temp:
    root, scratch = (Path(temp).resolve() / name for name in ("workspace", "scratch"))
    root.mkdir()
    scratch.mkdir()
    source_file = root / "fixture.txt"
    source_file.write_text("workspace fixture\n")
    (root / ".env").write_text("must not be read")
    outside = root.parent / "outside.txt"
    outside.write_text("must not be read")
    (root / "link").symlink_to(outside)
    runtime = root.parent / "python-runtime"
    runtime.mkdir()
    (runtime / "stdlib.txt").write_text("runtime fixture\n")
    start = ["/usr/bin/sandbox-exec", "-D", f"ROOT={root}", "-D", f"SCRATCH={scratch}",
             "-D", f"PYTHON_RUNTIME={runtime}", "-p", policy]

    def run(command):
        return subprocess.run(start + ["/bin/sh", "-c", command], cwd=root,
                              env={"PATH": "/usr/bin:/bin", "HOME": str(scratch), "TMPDIR": str(scratch)},
                              capture_output=True, text=True, timeout=5, check=False)

    assert run("cat fixture.txt").stdout == "workspace fixture\n"
    assert run('echo ok > "$TMPDIR/probe" && cat "$TMPDIR/probe"').stdout == "ok\n"
    assert run("cat ../python-runtime/stdlib.txt").stdout == "runtime fixture\n"
    assert run("echo changed > ../python-runtime/stdlib.txt").returncode != 0
    assert run("echo changed > fixture.txt").returncode != 0
    assert source_file.read_text() == "workspace fixture\n"
    for path in ("../outside.txt", "link", ".env"):
        result = run(f"cat {path}")
        assert result.returncode != 0 and not result.stdout
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        port = listener.getsockname()[1]
        command = ["/usr/bin/nc", "-z", "-w", "1", "127.0.0.1", str(port)]
        assert subprocess.run(command, capture_output=True, timeout=4).returncode == 0
        denied = subprocess.run(start + command, cwd=root, capture_output=True, text=True, timeout=4)
        assert denied.returncode != 0, "Sandbox allowed a network connection"

print("Pi Chat command sandbox: runtime/workspace reads, scratch, write denial, outside/secret denial, and network denial passed")
