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

# Known game build 4.0.0.3151.
BUILD="4.0.0.3151"
ORIGINAL_SHA="33e7dded4218720ddb50ac2410c2da037ca39de91ec9933d47be3363b5fdcb8e"
PATCHED_SHA="eba4d503a669a9e73e7aab4729db6a531f18e2b26cdae28f3fb68e211694b489"
OFFSET=$((0x47F88B))
# ldarg.0; ldloc.s V_6; ldfld ViewInstancingTier; ldc.i4.1; clt; ldc.i4.0; ceq
EXPECTED="0211067b701e000a17fe0416fe01"
# ldarg.0; ldc.i4.0; nop x12
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

current="$(sha "$dll")"
case "$current" in
    "$ORIGINAL_SHA") state="original" ;;
    "$PATCHED_SHA")  state="patched" ;;
    *)               state="unknown" ;;
esac

case "$mode" in
    status)
        echo "DLL:    $dll"
        echo "State:  $state$([[ $state != unknown ]] && echo " (build $BUILD)")"
        echo "Backup: $([[ -f "$backup" ]] && echo present || echo none)"
        exit 0
        ;;
    restore)
        [[ -f "$backup" ]] || die "No backup found. Use Steam's 'Verify integrity of game files' instead."
        cp -p "$backup" "$dll"
        rm -f "$backup"
        echo "Original DLL restored. Remove the DOTNET_ReadyToRunExcludeList launch option in Steam."
        exit 0
        ;;
esac

echo "DLL: $dll"
if [[ "$state" == "patched" ]]; then
    echo "Already patched. Nothing to do."
    print_launch_options
    exit 0
fi
[[ "$state" == "original" ]] || die "Unknown VRage.Render12.dll (the game was probably updated).
This fix only supports build $BUILD. Nothing was changed."

actual="$(od -An -tx1 -v -j "$OFFSET" -N $(( ${#EXPECTED} / 2 )) "$dll" | tr -d ' \n')"
[[ "$actual" == "$EXPECTED" ]] || die "Unexpected bytes at the patch site. Nothing was changed."

tmp="$dll.tmp.$$"
trap 'rm -f "$tmp"' EXIT
cp -p "$dll" "$tmp"
printf "$REPLACEMENT" | dd of="$tmp" bs=1 seek="$OFFSET" conv=notrunc status=none
[[ "$(sha "$tmp")" == "$PATCHED_SHA" ]] || die "Patched file has an unexpected hash. Nothing was changed."

cp -p "$dll" "$backup"
mv "$tmp" "$dll"
echo "Done. Original saved as VRage.Render12.dll.orig."
print_launch_options
