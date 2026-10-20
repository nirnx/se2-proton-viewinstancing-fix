#!/usr/bin/env bash
# Space Engineers 2 on Proton: fix pink/purple materials and the loading hang.
#
# Patches YOUR copy of Game2/VRage.Render12.dll so the renderer reports view
# instancing as unsupported and uses its built-in fallback (see README.md).
# Needs only bash and coreutils.
#
#   se2-fix.sh [PATH]             apply the fix
#   se2-fix.sh --restore [PATH]   undo it
#   se2-fix.sh --status [PATH]    show what is installed
#
# PATH is optional and may be the VRage.Render12.dll file itself, the Game2
# folder, or the SpaceEngineers2 install folder. Without it the game is found
# through your Steam libraries (SE2_DIR=/path/to/SpaceEngineers2 also works).
set -euo pipefail

LAUNCH_OPTIONS='DOTNET_ReadyToRunExcludeList=VRage.Render12 %command%'

# Supported game builds: "version original_sha256 patched_sha256 offset expected_bytes".
# expected_bytes is the IL in DeviceWrap's constructor that computes
#   ldarg.0; ldloc.s V_6; ldfld ViewInstancingTier; ldc.i4.1; clt; ldc.i4.0; ceq
# right before `call set_IsViewInstancingSupported`.
BUILDS=(
    "4.0.0.3151 33e7dded4218720ddb50ac2410c2da037ca39de91ec9933d47be3363b5fdcb8e eba4d503a669a9e73e7aab4729db6a531f18e2b26cdae28f3fb68e211694b489 0x47F88B 0211067b701e000a17fe0416fe01"
    "4.0.0.3155 87352623f843bb7c3b7c994ff43970000ac7ceffc46bd38f2c21cc4623986e65 bdff5aa6404302e2654081a4d96c361c69120a0c0a98a46d7b69cb7d2bbf6c7a 0x47F9D3 0211067b731e000a17fe0416fe01"
)
# ldarg.0; ldc.i4.0; nop x12 (same length as expected_bytes)
REPLACEMENT='\x02\x16\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'

die() { echo "ERROR: $*" >&2; exit 1; }

find_game_dir() {
    local root vdf lib
    for root in "$HOME/.local/share/Steam" "$HOME/.steam/steam" \
                "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
        for vdf in "$root/steamapps/libraryfolders.vdf" "$root/config/libraryfolders.vdf"; do
            [[ -f "$vdf" ]] || continue
            while IFS= read -r lib; do
                if [[ -f "$lib/steamapps/common/SpaceEngineers2/Game2/VRage.Render12.dll" ]]; then
                    echo "$lib/steamapps/common/SpaceEngineers2"
                    return 0
                fi
            done < <(echo "$root"; sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$vdf")
        done
    done
    return 1
}

sha() { sha256sum "$1" | cut -d' ' -f1; }

print_launch_options() {
    cat <<EOF

Last step: in Steam, right-click Space Engineers 2 -> Properties -> General,
and put this in "Launch Options":

    $LAUNCH_OPTIONS

EOF
}

mode="apply"
target=""
for arg in "$@"; do
    case "$arg" in
        --status)  mode="status" ;;
        --restore) mode="restore" ;;
        -h|--help) sed -n '2,14p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)        die "Unknown option: $arg (use --status or --restore)" ;;
        *)         [[ -z "$target" ]] || die "Only one path can be given"; target="$arg" ;;
    esac
done

target="${target:-${SE2_DIR:-}}"
if [[ -z "$target" ]]; then
    target="$(find_game_dir)" \
        || die "Space Engineers 2 not found. Pass the path, e.g.: se2-fix.sh /path/to/SpaceEngineers2/Game2/VRage.Render12.dll"
fi
if [[ -f "$target" ]]; then
    dll="$target"
elif [[ -f "$target/VRage.Render12.dll" ]]; then
    dll="$target/VRage.Render12.dll"
elif [[ -f "$target/Game2/VRage.Render12.dll" ]]; then
    dll="$target/Game2/VRage.Render12.dll"
else
    die "VRage.Render12.dll not found at: $target"
fi
backup="$dll.orig"

if pgrep -f 'SpaceEngineers2\.exe' >/dev/null 2>&1; then
    die "Space Engineers 2 is running. Close it first."
fi

# Sets STATE (original/patched/unknown) and the BUILD_* fields for the given hash.
identify() {
    local entry version orig patched offset expected
    STATE="unknown"
    for entry in "${BUILDS[@]}"; do
        read -r version orig patched offset expected <<<"$entry"
        if [[ "$1" == "$orig" || "$1" == "$patched" ]]; then
            [[ "$1" == "$orig" ]] && STATE="original" || STATE="patched"
            BUILD_VERSION="$version" BUILD_ORIG="$orig" BUILD_PATCHED="$patched"
            BUILD_OFFSET=$((offset)) BUILD_EXPECTED="$expected"
            return 0
        fi
    done
    return 1
}

supported="$(for e in "${BUILDS[@]}"; do echo -n "${e%% *} "; done)"
BUILD_ORIG=""
identify "$(sha "$dll")" || true
state="$STATE"

# A backup only belongs to this install if it is the original DLL of the same build;
# one left over from an older build must never be restored over a newer game.
backup_state="none"
if [[ -f "$backup" ]]; then
    if [[ -n "$BUILD_ORIG" && "$(sha "$backup")" == "$BUILD_ORIG" ]]; then
        backup_state="valid"
    else
        backup_state="stale (from another game build, ignored)"
    fi
fi

case "$mode" in
    status)
        echo "DLL:    $dll"
        echo "State:  $state$([[ $state != unknown ]] && echo " (build $BUILD_VERSION)")"
        echo "Backup: $backup_state"
        [[ "$state" != unknown ]] || echo "Supported builds: $supported"
        exit 0
        ;;
    restore)
        if [[ "$state" == "original" ]]; then
            echo "The DLL is already the original. Nothing to do."
            [[ "$backup_state" == "none" ]] || rm -f "$backup"
            exit 0
        fi
        [[ "$backup_state" == "valid" ]] || die "No matching backup for this game build.
Use Steam's 'Verify integrity of game files' to get the original DLL back."
        cp -p "$backup" "$dll"
        rm -f "$backup"
        echo "Original DLL restored. Remove the DOTNET_ReadyToRunExcludeList launch option in Steam."
        exit 0
        ;;
esac

echo "DLL: $dll"
if [[ "$state" == "patched" ]]; then
    echo "Already patched (build $BUILD_VERSION). Nothing to do."
    print_launch_options
    exit 0
fi
[[ "$state" == "original" ]] || die "Unknown VRage.Render12.dll (probably a newer game build).
Supported builds: $supported
Nothing was changed. Check the repo for an update."

actual="$(od -An -tx1 -v -j "$BUILD_OFFSET" -N $(( ${#BUILD_EXPECTED} / 2 )) "$dll" | tr -d ' \n')"
[[ "$actual" == "$BUILD_EXPECTED" ]] || die "Unexpected bytes at the patch site. Nothing was changed."

tmp="$dll.tmp.$$"
trap 'rm -f "$tmp"' EXIT
cp -p "$dll" "$tmp"
printf "$REPLACEMENT" | dd of="$tmp" bs=1 seek="$BUILD_OFFSET" conv=notrunc status=none
[[ "$(sha "$tmp")" == "$BUILD_PATCHED" ]] || die "Patched file has an unexpected hash. Nothing was changed."

cp -p "$dll" "$backup"
mv "$tmp" "$dll"
echo "Done (build $BUILD_VERSION). Original saved as VRage.Render12.dll.orig."
print_launch_options
