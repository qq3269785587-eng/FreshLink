"""Check redacted evidence against local secrets, without printing any values."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "work/fresh-acceptance/P0/attempt-01"


def main():
    secrets = set()
    config = ROOT / "runtime/config"
    mysql = config / "mysql-local-credentials.txt"
    for line in mysql.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("password="):
            secrets.add(line.split("=", 1)[1])
    for path in config.glob("p0-*.json"):
        value = json.loads(path.read_text(encoding="utf-8-sig"))
        for key, item in value.items():
            if any(word in key.lower() for word in ("password", "token", "secret")) and isinstance(item, str):
                secrets.add(item)
    needles = {value.encode("utf-8") for value in secrets if len(value) >= 6}
    findings = []
    checked = 0
    for path in EVIDENCE.parent.rglob("*"):
        if not path.is_file() or path.suffix.lower() in {".jpg", ".png"}:
            continue
        checked += 1
        data = path.read_bytes()
        if any(value in data for value in needles):
            findings.append(path.relative_to(EVIDENCE.parent).as_posix())
    report = {"checked_text_files": checked, "known_local_secret_matches": findings, "limitations": "Exact known-value scan; does not prove absence of every secret or inspect image pixels. Raw runtime auth/vendor logs and backups remain private outside the evidence directory."}
    (EVIDENCE / "privacy-check.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return bool(findings)


if __name__ == "__main__":
    raise SystemExit(main())
