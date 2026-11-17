"""Save actual tracked/untracked source and root specifications, without caches.

Snapshots are private local evidence: existing application configs may contain secrets.
Never overwrite a snapshot or publish its full contents without redaction.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def git(cwd, *args):
    return subprocess.check_output(["git", *args], cwd=cwd)


def save(destination):
    destination = destination.resolve()
    destination.relative_to(ROOT / "work")
    destination.mkdir(parents=True, exist_ok=False)
    entries = []
    repositories = {}
    for scope in ("backend", "web"):
        source = ROOT / "apps" / scope
        repositories[scope] = {"head": git(source, "rev-parse", "HEAD").decode().strip()}
        for name, args in {
            "status.txt": ("status", "--short", "--untracked-files=all"),
            "working.patch": ("diff", "--binary", "HEAD"),
            "index.patch": ("diff", "--cached", "--binary"),
        }.items():
            (destination / f"{scope}-{name}").write_bytes(git(source, *args))
        names = git(source, "ls-files", "-z", "--cached", "--others", "--exclude-standard").decode("utf-8").split("\0")
        for name in sorted(set(filter(None, names))):
            path = source / name
            if path.is_file():
                entries.append(copy(path, destination / scope / name, scope, name))
    roots = [ROOT / "AGENTS.md", ROOT / "README.md"]
    roots += sorted(ROOT.glob("*.cmd"))
    for folder in ("scripts", "specs"):
        roots += sorted(p for p in (ROOT / folder).rglob("*") if p.is_file() and "__pycache__" not in p.parts)
    roots += [ROOT / "docs" / "本机环境与启动.md"]
    for path in roots:
        name = path.relative_to(ROOT).as_posix()
        entries.append(copy(path, destination / "root" / name, "root", name))
    manifest = {"repositories": repositories, "files": entries, "privacy": "local-only; configs/patches require redaction before sharing"}
    (destination / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"snapshot": str(destination), "counts": {s: sum(e["scope"] == s for e in entries) for s in ("backend", "web", "root")}, "manifest_sha256": hashlib.sha256((destination / "manifest.json").read_bytes()).hexdigest()}


def copy(source, target, scope, name):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    return {"scope": scope, "path": name, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "bytes": target.stat().st_size}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=Path)
    print(json.dumps(save(parser.parse_args().destination), ensure_ascii=False))
