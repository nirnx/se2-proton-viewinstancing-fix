#!/usr/bin/env python3
"""Make Space Engineers 2 render correctly on Proton / vkd3d-proton.

Patches the player's own Game2/VRage.Render12.dll so the renderer reports view
instancing as unsupported and uses its built-in non-view-instanced fallback.
See README.md for the background.

Usage:
  se2-viewinstancing-fix.py [--game-dir PATH]            apply the patch
  se2-viewinstancing-fix.py [--game-dir PATH] --restore  put the original DLL back
  se2-viewinstancing-fix.py [--game-dir PATH] --status   show what is installed
"""

import argparse
import hashlib
import re
import shutil
import sys
from pathlib import Path

DLL_NAME = "VRage.Render12.dll"
BACKUP_SUFFIX = ".orig"

# One entry per supported game build. The patch replaces the IL computing
# `ViewInstancingTier >= Tier1` in DeviceWrap's constructor with `false`:
#   ldarg.0; ldloc.s V_6; ldfld ViewInstancingTier; ldc.i4.1; clt; ldc.i4.0; ceq
#   -> ldarg.0; ldc.i4.0; nop x12
BUILDS = {
    "4.0.0.3151": {
        "original_sha256": "33e7dded4218720ddb50ac2410c2da037ca39de91ec9933d47be3363b5fdcb8e",
        "patched_sha256": "eba4d503a669a9e73e7aab4729db6a531f18e2b26cdae28f3fb68e211694b489",
        "offset": 0x47F88B,
        "expected": bytes.fromhex("0211067b701e000a17fe0416fe01"),
        "replacement": bytes.fromhex("0216") + bytes(12),
    },
}

DEFAULT_STEAM_ROOTS = [
    Path.home() / ".local/share/Steam",
    Path.home() / ".steam/steam",
    Path.home() / ".var/app/com.valvesoftware.Steam/.local/share/Steam",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def find_game_dir() -> Path | None:
    for root in DEFAULT_STEAM_ROOTS:
        vdf = root / "steamapps/libraryfolders.vdf"
        if not vdf.is_file():
            vdf = root / "config/libraryfolders.vdf"
        if not vdf.is_file():
            continue
        libraries = [Path(p) for p in re.findall(r'"path"\s+"([^"]+)"', vdf.read_text(errors="replace"))]
        for lib in [root, *libraries]:
            candidate = lib / "steamapps/common/SpaceEngineers2"
            if (candidate / "Game2" / DLL_NAME).is_file():
                return candidate
    return None


def identify(path: Path):
    digest = sha256(path)
    for version, build in BUILDS.items():
        if digest == build["original_sha256"]:
            return version, "original"
        if digest == build["patched_sha256"]:
            return version, "patched"
    return None, digest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--game-dir", type=Path, help="SpaceEngineers2 install dir (auto-detected from Steam if omitted)")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--restore", action="store_true", help="restore the original DLL from the backup")
    group.add_argument("--status", action="store_true", help="only report the current state")
    args = parser.parse_args()

    game_dir = args.game_dir or find_game_dir()
    if game_dir is None:
        print("Could not find Space Engineers 2. Pass --game-dir /path/to/steamapps/common/SpaceEngineers2", file=sys.stderr)
        return 1
    dll = game_dir / "Game2" / DLL_NAME
    backup = dll.with_name(DLL_NAME + BACKUP_SUFFIX)
    if not dll.is_file():
        print(f"{dll} not found", file=sys.stderr)
        return 1

    version, state = identify(dll)
    print(f"DLL: {dll}")

    if args.status:
        print(f"State: {state}" + (f" (game build {version})" if version else " (unknown build)"))
        print(f"Backup: {'present' if backup.is_file() else 'none'}")
        return 0

    if args.restore:
        if not backup.is_file():
            print("No backup found. Use Steam's 'Verify integrity of game files' instead.", file=sys.stderr)
            return 1
        shutil.copy2(backup, dll)
        backup.unlink()
        print("Original DLL restored. You can remove DOTNET_ReadyToRunExcludeList from the launch options.")
        return 0

    if state == "patched":
        print(f"Already patched (game build {version}). Nothing to do.")
        return 0
    if version is None:
        print("Unknown VRage.Render12.dll (SHA-256 " + state + ").\n"
              "The game was probably updated; this patch only supports: " + ", ".join(BUILDS) + ".\n"
              "Nothing was changed.", file=sys.stderr)
        return 1

    build = BUILDS[version]
    data = bytearray(dll.read_bytes())
    end = build["offset"] + len(build["expected"])
    if data[build["offset"]:end] != build["expected"]:
        print("Unexpected bytes at the patch site; nothing was changed.", file=sys.stderr)
        return 1
    data[build["offset"]:end] = build["replacement"]
    if hashlib.sha256(data).hexdigest() != build["patched_sha256"]:
        print("Patched result does not match the expected hash; nothing was changed.", file=sys.stderr)
        return 1

    shutil.copy2(dll, backup)
    dll.write_bytes(data)
    print(f"Patched (game build {version}). Original saved as {backup.name}.")
    print("Now set the Steam launch options to:\n  DOTNET_ReadyToRunExcludeList=VRage.Render12 %command%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
