"""Bind local source snapshot, build artifacts and redacted P0 evidence by hash."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "work/fresh-acceptance/P0/attempt-01"
BEFORE = ROOT / "work/fresh-baseline/codex-p0-20261117-before"
AFTER = ROOT / "work/fresh-baseline/codex-p0-20261117-delivery-v2"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def item(path):
    return {"path": path.relative_to(ROOT).as_posix(), "sha256": sha(path), "bytes": path.stat().st_size}


def finalize():
    before = json.loads((BEFORE / "manifest.json").read_text(encoding="utf-8"))
    after = json.loads((AFTER / "manifest.json").read_text(encoding="utf-8"))
    original = {(x["scope"], x["path"]): x["sha256"] for x in before["files"]}
    final = {(x["scope"], x["path"]): x["sha256"] for x in after["files"]}
    changes = {
        "changed": [f"{s}/{p}" for (s, p), h in original.items() if (s, p) in final and final[(s, p)] != h],
        "missing": [f"{s}/{p}" for s, p in original if (s, p) not in final],
        "added": [f"{s}/{p}" for s, p in final if (s, p) not in original],
    }
    (EVIDENCE / "source-changes.json").write_text(json.dumps(changes, ensure_ascii=False, indent=2), encoding="utf-8")
    if changes["missing"]:
        raise RuntimeError("Original source files are missing; inspect source-changes.json")
    artifacts = [ROOT / "apps/backend/jeecg-module-system/jeecg-system-start/target/jeecg-system-start-3.8.1.jar", ROOT / "runtime/run/p0/jeecg-system-start.jar"]
    dist = ROOT / "apps/web/dist"
    build = [item(p) for p in artifacts] + [item(p) for p in sorted(dist.rglob("*")) if p.is_file()]
    if build[0]["sha256"] != build[1]["sha256"]:
        raise RuntimeError("Target and isolated runtime JAR hashes differ")
    (EVIDENCE / "build-manifest.json").write_text(json.dumps(build, ensure_ascii=False, indent=2), encoding="utf-8")
    manifest = {
        "stage": "P0", "status": "self-test complete; pending independent acceptance",
        "before_snapshot": item(BEFORE / "manifest.json"), "delivery_snapshot": item(AFTER / "manifest.json"),
        "repositories": after["repositories"],
        "evidence": [item(p) for p in sorted(EVIDENCE.parent.rglob("*")) if p.is_file() and p.name != "manifest.json"],
        "privacy": "No runtime/config files, raw DB backups, source snapshots or legacy vendor reports are bundled here.",
    }
    (EVIDENCE / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"evidence_files": len(manifest["evidence"]), "build_files": len(build), "changes": changes, "jar_sha256": build[0]["sha256"]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    finalize()
