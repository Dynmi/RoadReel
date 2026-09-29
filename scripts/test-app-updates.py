#!/usr/bin/env python3
"""Exercise the real Sparkle installer in disposable, sandboxed app bundles."""
import functools
import http.server
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid

repo = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve()
sparkle = repo / "build/SourcePackages/artifacts/sparkle/Sparkle/bin"
root = Path(tempfile.mkdtemp(prefix="updater-tests-", dir=repo / "build"))
print(f"Test artifacts: {root}", flush=True)
log = (root / "commands.log").open("w")


def run(*args):
    subprocess.run(args, check=True, stdout=log, stderr=subprocess.STDOUT)


run("swiftc", "-parse-as-library", "-target", f"{os.uname().machine}-apple-macosx14.0",
    "-F", str(app.parent), "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker",
    "@executable_path/../Frameworks", str(repo / "RoadReel/AppLanguage.swift"),
    str(repo / "RoadReel/AppUpdater.swift"), str(repo / "scripts/test-app-updates.swift"),
    "-o", str(root / "UpdateTests"))


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def copyfile(self, source, outputfile):
        if "/cancel" in self.path and self.path.endswith(".dmg"):
            try:
                while chunk := source.read(4096):
                    outputfile.write(chunk)
                    outputfile.flush()
                    time.sleep(0.02)
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            super().copyfile(source, outputfile)


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=str(root)))
threading.Thread(target=server.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{server.server_port}"


def fixture(destination, bundle_id, scenario, role):
    run("ditto", str(app), str(destination))
    plist = destination / "Contents/Info.plist"
    info = plistlib.loads(plist.read_bytes())
    info.update(CFBundleIdentifier=bundle_id, CFBundleName="RoadReel Update Test",
                CFBundleDisplayName="RoadReel Update Test", CFBundleExecutable="UpdateTests",
                CFBundleVersion="2" if role == "target" or scenario == "current" else "1",
                SUFeedURL=f"{base}/{scenario}/{'missing' if scenario == 'offline' and role == 'source' else 'appcast'}.xml",
                NSAppTransportSecurity={"NSAllowsArbitraryLoads": True},
                UpdateTestScenario=scenario, UpdateTestRole=role)
    plist.write_bytes(plistlib.dumps(info))
    (destination / "Contents/MacOS/RoadReel").unlink()
    shutil.copy2(root / "UpdateTests", destination / "Contents/MacOS/UpdateTests")
    run(str(repo / "scripts/sign-app.sh"), str(destination))


try:
    for scenario in (sys.argv[2:] or ["success", "corrupt", "cancel", "cancel-retry", "current", "offline", "feed-corrupt"]):
        print(f"Running {scenario}…", flush=True)
        folder = root / scenario
        folder.mkdir()
        bundle_id = "io.github.Dynmi.RoadReel.UpdateTest." + uuid.uuid4().hex
        installed = folder / "installed/RoadReel.app"
        staged = folder / "staging/RoadReel.app"
        fixture(installed, bundle_id, scenario, "source")
        fixture(staged, bundle_id, scenario, "target")
        run("hdiutil", "create", "-srcfolder", str(staged.parent), "-volname", "RoadReel Update Test",
            "-format", "UDZO", "-ov", str(folder / "RoadReel.dmg"))
        run(str(sparkle / "generate_appcast"), "--account", "io.github.Dynmi.RoadReel",
            "--download-url-prefix", f"{base}/{scenario}/", "--maximum-deltas", "0", str(folder))
        if scenario == "corrupt":
            with (folder / "RoadReel.dmg").open("ab") as damaged:
                damaged.write(b"intentionally-corrupted-test-copy")
        elif scenario == "feed-corrupt":
            feed = folder / "appcast.xml"
            feed.write_bytes(feed.read_bytes().replace(b"<title>1.0.0</title>", b"<title>tampered</title>"))

        result = Path.home() / f"Library/Containers/{bundle_id}/Data/Library/Application Support/updater-test-result.txt"
        expected = {
            "success": "PASS installed build 2 and relaunched",
            "corrupt": "PASS rejected corrupt update",
            "cancel": "PASS cancelled download; original intact; retry available",
            "cancel-retry": "PASS installed build 2 and relaunched",
            "current": "PASS current build does not offer downgrade",
            "offline": "PASS manual check reports unavailable feed",
            "feed-corrupt": "PASS manual check reports unavailable feed",
        }[scenario]
        run("open", "-n", str(installed))
        deadline = time.monotonic() + 55
        text = ""
        while time.monotonic() < deadline:
            if result.exists():
                text = result.read_text()
                if expected in text or "FAIL" in text:
                    break
            time.sleep(0.2)
        (folder / "result.txt").write_text(text)
        print(text, flush=True)
        assert expected in text and "FAIL" not in text, f"{scenario} failed; see {folder}"
        info = plistlib.loads((installed / "Contents/Info.plist").read_bytes())
        assert info["CFBundleVersion"] == ("2" if scenario in ("success", "cancel-retry", "current") else "1")
        run("codesign", "--verify", "--deep", "--strict", str(installed))
        print(f"PASS {scenario}: installed app signature and version verified", flush=True)
finally:
    server.shutdown()
    log.close()
