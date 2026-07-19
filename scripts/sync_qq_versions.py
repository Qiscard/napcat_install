#!/usr/bin/env python3
"""同步 QQ Linux 安装包版本列表，并在写入前校验下载链接。

数据来源:
  - 官方 pcConfig (最新版)
  - https://github.com/Rodert/qq-versions/releases (历史版本)
  - https://rodert.github.io/qq-versions/

规则:
  1. 拉取后对每个链接做可达性校验
  2. 失效链接丢弃；同 version+arch+format 优先保留可用源
  3. 优先顺序: official(可用) > rodert(可用)
  4. 输出 data/qq_versions.json
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "qq_versions.json"
UA = {"User-Agent": "napcat-install-sync/1.1 (+https://github.com/Qiscard/napcat_install)"}

OFFICIAL_CONFIG_URLS = [
    "https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/pcConfig.json",
    "https://im.qq.com/proxy/domain/cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/pcConfig.json",
]
RODERT_RELEASES = "https://api.github.com/repos/Rodert/qq-versions/releases?per_page=100"


def get_bytes(url: str, timeout: int = 60) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def get_json(url: str):
    return json.loads(get_bytes(url).decode("utf-8"))


def arch_norm(arch: str) -> str:
    return {
        "x86_64": "amd64",
        "amd64": "amd64",
        "aarch64": "arm64",
        "arm64": "arm64",
        "loongarch64": "loongarch64",
        "mips64el": "mips64el",
    }.get(arch, arch)


def parse_filename(name: str, published: str, url: str, size, sha256: str = "", md5: str = "", source: str = ""):
    m = re.match(r"QQ_([0-9.]+)_(\d+)_([A-Za-z0-9_]+)_\d+\.(deb|rpm)$", name)
    if m:
        version, datecode, arch, fmt = m.groups()
        if len(datecode) == 6:
            update_date = f"20{datecode[0:2]}-{datecode[2:4]}-{datecode[4:6]}"
        else:
            update_date = (published or "")[:10]
        build = datecode
    else:
        m2 = re.match(r"linuxqq_([0-9.]+)-(\d+)_(amd64|arm64|x86_64|aarch64)\.(deb|rpm)$", name)
        if not m2:
            return None
        version, build, arch, fmt = m2.groups()
        update_date = (published or "")[:10]

    return {
        "update_time": published or f"{update_date}T00:00:00Z",
        "update_date": update_date,
        "version": version,
        "build": build,
        "arch": arch_norm(arch),
        "format": fmt,
        "filename": name,
        "url": url,
        "size": size,
        "sha256": sha256 or "",
        "md5": md5 or "",
        "source": source,
        "available": None,
    }


def fetch_official() -> list[dict]:
    cfg = None
    errors = []
    for url in OFFICIAL_CONFIG_URLS:
        try:
            cfg = get_json(url)
            break
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{url}: {exc}")
    if cfg is None:
        raise RuntimeError("官方配置获取失败:\n" + "\n".join(errors))

    linux = cfg.get("Linux") or {}
    update_date = linux.get("updateDate") or datetime.now(timezone.utc).strftime("%Y-%m-%d")
    version = linux.get("version") or ""
    items = []
    pairs = []
    x64 = linux.get("x64DownloadUrl") or {}
    arm = linux.get("armDownloadUrl") or {}
    for fmt, u in (("deb", x64.get("deb")), ("rpm", x64.get("rpm"))):
        if u:
            pairs.append((u, "amd64", fmt))
    for fmt, u in (("deb", arm.get("deb")), ("rpm", arm.get("rpm"))):
        if u:
            pairs.append((u, "arm64", fmt))
    if linux.get("loongarchDownloadUrl"):
        pairs.append((linux["loongarchDownloadUrl"], "loongarch64", "deb"))
    if linux.get("mipsDownloadUrl"):
        pairs.append((linux["mipsDownloadUrl"], "mips64el", "deb"))

    for url, arch, fmt in pairs:
        name = url.rstrip("/").split("/")[-1]
        item = parse_filename(name, f"{update_date}T00:00:00Z", url, None, source="official")
        if item is None:
            item = {
                "update_time": f"{update_date}T00:00:00Z",
                "update_date": update_date,
                "version": version,
                "build": "",
                "arch": arch,
                "format": fmt,
                "filename": name,
                "url": url,
                "size": None,
                "sha256": "",
                "md5": "",
                "source": "official",
                "available": None,
            }
        items.append(item)
    return items


def fetch_rodert() -> list[dict]:
    releases = get_json(RODERT_RELEASES)
    items = []
    for rel in releases:
        published = rel.get("published_at") or rel.get("created_at") or ""
        tag = rel.get("tag_name") or ""
        assets = {a["name"]: a for a in rel.get("assets", [])}
        sums = {}
        if "SHA256SUMS.txt" in assets:
            try:
                text = get_bytes(assets["SHA256SUMS.txt"]["browser_download_url"]).decode("utf-8", "ignore")
                for line in text.splitlines():
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    parts = line.split()
                    if len(parts) >= 2:
                        sums[parts[-1].lstrip("*")] = parts[0]
            except Exception as exc:  # noqa: BLE001
                print(f"warn: SHA256SUMS {tag}: {exc}", file=sys.stderr)

        for name, asset in assets.items():
            if not (name.endswith(".deb") or name.endswith(".rpm")):
                continue
            item = parse_filename(
                name,
                published,
                asset["browser_download_url"],
                asset.get("size"),
                sha256=sums.get(name, ""),
                source=f"rodert:{tag}",
            )
            if item:
                items.append(item)
    return items


def check_url(url: str, timeout: int = 18) -> tuple[bool, str, int | None]:
    """返回 (ok, http_code, content_length_hint)."""
    cmd = [
        "curl", "-k", "-s", "-o", "/dev/null",
        "-w", "%{http_code} %{size_download}",
        "-L", "--connect-timeout", "10", "--max-time", str(min(timeout, 20)),
        "-A", "Mozilla/5.0",
        "-r", "0-2047",
        url,
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        parts = (proc.stdout or "").strip().split()
        code = parts[0] if parts else "000"
        size = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
        ok = code.isdigit() and int(code) < 400 and size > 0
        return ok, code, size if size else None
    except Exception as exc:  # noqa: BLE001
        return False, f"err:{exc}", None


def source_rank(source: str) -> int:
    if source == "official":
        return 0
    if source.startswith("rodert"):
        return 1
    return 9


def validate_and_merge(candidates: list[dict]) -> tuple[list[dict], list[dict]]:
    """校验全部候选，按 version+arch+format 选最优可用源。"""
    from concurrent.futures import ThreadPoolExecutor, as_completed

    # 同 filename 去重，保留先出现的 (official 在前)
    seen_file = set()
    uniq: list[dict] = []
    for item in candidates:
        fn = item.get("filename") or item.get("url")
        if fn in seen_file:
            continue
        seen_file.add(fn)
        uniq.append(item)

    print(f"开始并行校验 {len(uniq)} 个候选链接...")
    checked: list[dict] = []
    dead: list[dict] = []

    def work(item: dict):
        ok, code, _hint = check_url(item["url"])
        out = dict(item)
        out["available"] = ok
        out["check_code"] = code
        return out, ok

    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = [ex.submit(work, item) for item in uniq]
        for fut in as_completed(futs):
            item, ok = fut.result()
            if ok:
                checked.append(item)
                print(f"  OK  {item['version']} {item['arch']} {item['format']} [{item['source']}] {item.get('check_code')}")
            else:
                dead.append(item)
                print(f"  BAD {item['version']} {item['arch']} {item['format']} [{item['source']}] {item.get('check_code')} {item['url']}")

    best: dict[tuple, dict] = {}
    for item in checked:
        key = (item["version"], item["arch"], item["format"])
        prev = best.get(key)
        if prev is None:
            best[key] = item
            continue
        prev_rank = source_rank(str(prev.get("source") or ""))
        cur_rank = source_rank(str(item.get("source") or ""))
        if cur_rank < prev_rank:
            best[key] = item
        elif cur_rank == prev_rank and (item.get("update_time") or "") > (prev.get("update_time") or ""):
            best[key] = item

    packages = list(best.values())
    packages.sort(
        key=lambda x: (x.get("update_time") or "", x.get("version") or "", x.get("arch") or "", x.get("format") or ""),
        reverse=True,
    )
    return packages, dead


def main() -> int:
    official = fetch_official()
    historical = fetch_rodert()
    # official 在前，便于同 key 优先
    candidates = official + historical
    packages, dead = validate_and_merge(candidates)

    out = {
        "source": [
            "https://rodert.github.io/qq-versions/",
            "https://github.com/Rodert/qq-versions/releases",
            "https://im.qq.com/",
        ],
        "synced_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "count": len(packages),
        "dead_count": len(dead),
        "packages": packages,
        "dead_packages": [
            {
                "version": d.get("version"),
                "arch": d.get("arch"),
                "format": d.get("format"),
                "url": d.get("url"),
                "source": d.get("source"),
                "check_code": d.get("check_code"),
                "filename": d.get("filename"),
            }
            for d in dead
        ],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT} (available={len(packages)}, dead={len(dead)})")
    versions = []
    for p in packages:
        if p["version"] not in versions:
            versions.append(p["version"])
    print("versions:", ", ".join(versions[:20]) if versions else "(none)")
    if not packages:
        print("error: no available packages after validation", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
