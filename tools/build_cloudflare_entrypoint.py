#!/usr/bin/env python3
import argparse
import json
import re
import shutil
from pathlib import Path


CONFIG_RE = re.compile(r"const GODOT_CONFIG = (?P<config>\{.*?\});", re.DOTALL)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a lightweight game.meowa.ai entrypoint for the Godot web export."
    )
    parser.add_argument("--web-export-dir", required=True)
    parser.add_argument("--entrypoint-dir", required=True)
    parser.add_argument("--game-slug", required=True)
    parser.add_argument("--build-version", required=True)
    parser.add_argument("--assets-base-url", required=True)
    parser.add_argument("--r2-prefix", required=True)
    parser.add_argument("--remote-pack", action="store_true")
    return parser.parse_args()


def copy_entrypoint(web_export_dir: Path, entrypoint_dir: Path, remote_pack: bool) -> None:
    if entrypoint_dir.exists():
        shutil.rmtree(entrypoint_dir)
    entrypoint_dir.mkdir(parents=True, exist_ok=True)

    for source in web_export_dir.rglob("*"):
        if not source.is_file():
            continue

        rel = source.relative_to(web_export_dir)
        if rel.name == "_headers":
            continue
        if rel.suffix == ".wasm":
            continue
        if remote_pack and rel.name == "index.pck":
            continue

        target = entrypoint_dir / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def rewrite_index(
    web_export_dir: Path,
    entrypoint_dir: Path,
    assets_base_url: str,
    r2_prefix: str,
    build_version: str,
    remote_pack: bool,
) -> None:
    target = entrypoint_dir / "index.html"
    text = target.read_text(encoding="utf-8")

    match = CONFIG_RE.search(text)
    if not match:
        raise RuntimeError(f"Could not find GODOT_CONFIG in {target}")

    config = json.loads(match.group("config"))
    asset_prefix = f"{assets_base_url.rstrip('/')}/{r2_prefix.strip('/')}/index"

    wasm_path = web_export_dir / "index.wasm"
    pack_path = web_export_dir / "index.pck"
    if not wasm_path.is_file():
        raise FileNotFoundError(wasm_path)
    if not pack_path.is_file():
        raise FileNotFoundError(pack_path)

    config["executable"] = asset_prefix
    config["mainPack"] = f"{asset_prefix}.pck" if remote_pack else "index.pck"
    config["ensureCrossOriginIsolationHeaders"] = False
    config["fileSizes"] = {
        f"{asset_prefix}.wasm": wasm_path.stat().st_size,
        config["mainPack"]: pack_path.stat().st_size,
    }

    rewritten = CONFIG_RE.sub(
        "const GODOT_CONFIG = "
        + json.dumps(config, separators=(",", ":"), sort_keys=True)
        + ";",
        text,
        count=1,
    )
    rewritten = rewritten.replace(
        "<head>",
        f"<head>\n<!-- HD2D build version: {build_version} -->",
        1,
    )
    target.write_text(rewritten, encoding="utf-8")


def write_manifest(
    entrypoint_dir: Path,
    game_slug: str,
    build_version: str,
    assets_base_url: str,
    r2_prefix: str,
    remote_pack: bool,
) -> None:
    manifest = {
        "gameSlug": game_slug,
        "buildVersion": build_version,
        "assetsBaseUrl": assets_base_url.rstrip("/"),
        "r2Prefix": r2_prefix.strip("/"),
        "remotePack": remote_pack,
    }
    (entrypoint_dir / "deploy-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    args = parse_args()
    web_export_dir = Path(args.web_export_dir).resolve()
    entrypoint_dir = Path(args.entrypoint_dir).resolve()

    if not (web_export_dir / "index.html").is_file():
        raise FileNotFoundError(web_export_dir / "index.html")

    copy_entrypoint(web_export_dir, entrypoint_dir, args.remote_pack)
    rewrite_index(
        web_export_dir,
        entrypoint_dir,
        args.assets_base_url,
        args.r2_prefix,
        args.build_version,
        args.remote_pack,
    )
    write_manifest(
        entrypoint_dir,
        args.game_slug,
        args.build_version,
        args.assets_base_url,
        args.r2_prefix,
        args.remote_pack,
    )

    print(f"Entrypoint ready: {entrypoint_dir}")


if __name__ == "__main__":
    main()
