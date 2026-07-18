#!/usr/bin/env python3
"""每周同步 QQ Linux 安装包版本列表。

数据来源:
  - 官方 pcConfig (最新版)
  - https://github.com/Rodert/qq-versions/releases (历史版本)
  - https://rodert.github.io/qq-versions/

输出: data/qq_versions.json
字段: update_time, update_date, version, arch, format, url, sha256, md5, filename, size, source
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "qq_versions.json"
UA = {"User-Agent": "napcat-install-sync/1.0 (+https://github.com/Qiscard/napcat_install)"}

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


def merge(official: list[dict], historical: list[dict]) -> list[dict]:
    result = []
    seen_vaf = set()
    seen_file = set()

    for item in official + historical:
        vaf = (item["version"], item["arch"], item["format"])
        fkey = item["filename"]
        if fkey in seen_file:
            continue
        # 同版本/架构/格式优先保留先出现的 (官方在前)
        if vaf in seen_vaf:
            continue
        seen_vaf.add(vaf)
        seen_file.add(fkey)
        result.append(item)

    result.sort(
        key=lambda x: (x.get("update_time") or "", x.get("version") or "", x.get("arch") or "", x.get("format") or ""),
        reverse=True,
    )
    return result


def main() -> int:
    official = fetch_official()
    historical = fetch_rodert()
    packages = merge(official, historical)
    out = {
        "source": [
            "https://rodert.github.io/qq-versions/",
            "https://github.com/Rodert/qq-versions/releases",
            "https://im.qq.com/",
        ],
        "synced_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "count": len(packages),
        "packages": packages,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({len(packages)} packages)")
    versions = []
    for p in packages:
        if p["version"] not in versions:
            versions.append(p["version"])
    print("versions:", ", ".join(versions[:20]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
