# Space Engineers 2 on Proton: pink/purple materials and loading hang fix

An unofficial workaround for **Space Engineers 2** ("Hostile Encounters" update; supported builds: **4.0.0.3151, 4.0.0.3155**) on Linux with
Proton / vkd3d-proton. Neither Keen Software House nor the vkd3d-proton project made it or endorses it.

## Contents

- [Symptoms](#symptoms)
- [Cause](#cause)
  - [Why older Proton (Proton 10 / GE-Proton10-34) works](#why-older-proton-proton-10--ge-proton10-34-works)
- [The fix](#the-fix)
- [How to use it](#how-to-use-it)
  - [Undo / check](#undo--check)
  - [Manual mode (without curl, or with a specific file)](#manual-mode-without-curl-or-with-a-specific-file)
- [Notes](#notes)
- [License](#license)

## Symptoms

- Most of the world renders **pink/purple** after loading a save.
- Often the game also **hangs at the end of world loading**. The game's watchdog logs
  `[Watchdog]: Still frozen (StartingGame)`.
- `Render12.log` (in `.../AppData/Roaming/SpaceEngineers2/Temp/Logs/`) is full of
  `Error: Can't compile pso Material ... [...ViewInstanced, ...]` and
  `Model ... could not use material ... Compilation failed`.
- With `VKD3D_DEBUG=warn`, the Proton log shows:
  ```
  d3d12_pipeline_state_validate_view_instancing: The same RenderTargetArrayIndex 0 is used for multiple ViewIDs. This is unsupported.
  d3d12_pipeline_state_init_graphics_create_info: Unsupported view instancing configuration used.
  ```

This affected every Proton build tried on NVIDIA (Proton Experimental 11.0-20261014, GE-Proton 11,
Proton-CachyOS), and the same error is reported on AMD/RADV in [vkd3d-proton#3384](https://github.com/HansKristian-Work/vkd3d-proton/issues/3384). Clearing shader
caches does not help.

## Cause

Build 4.0 renders cube shadows (point lights) with D3D12 **view instancing**. In
`ViewInstancedGraphicsPipeline.Create` the game creates its view-instanced pipeline states with an
all-zero `ViewInstanceLocation` array, so every view targets `RenderTargetArrayIndex 0`, and the
shader picks the cube face itself. Windows drivers accept this. vkd3d-proton
reports `ViewInstancingTier` 2 but does not support this configuration, so it rejects the pipeline
states.

When pipeline creation fails, the game marks every material that needs one of these variants as
failed and draws it with the pink error material. The shadow passes that depend on them also stall
the end of loading.

The game already contains a non-view-instanced fallback. It uses that fallback when the device
reports `ViewInstancingTier` below Tier 1. On current Proton, no launch option, game setting or
vkd3d-proton environment variable can switch the game to it. The `ForceCubeShadowFallback` shadow
setting is not enough, because materials still build the view-instanced variants.

Upstream report: [vkd3d-proton#3384](https://github.com/HansKristian-Work/vkd3d-proton/issues/3384).

### Why older Proton (Proton 10 / GE-Proton10-34) works

Players report that rolling back to Proton 10 or GE-Proton10-34 fixes the pink screen. That works
for the same reason this patch does. In vkd3d-proton **v3.0.1** and earlier, view instancing was
only advertised for games with a per-application override or with
`VKD3D_CONFIG=enable_experimental_features`. For every other game, `ViewInstancingTier` was reported
as `NOT_SUPPORTED` (the source comment says "Currently not supported"), so SE2 took its fallback
path. Later vkd3d-proton (the build in Proton Experimental 11.0-20261014 is `0bb64c5`) advertises
Tier 2 unconditionally whenever the Vulkan features are present. SE2 then takes the view-instanced
path, which vkd3d-proton can't handle yet.

So you have two options:
- **Stay on an older Proton** that ships vkd3d-proton ≤ 3.0.1. No game files are modified, but you
  lose newer Proton fixes. Players have reported other problems on those versions (crashes,
  fullscreen issues).
- **Use this patch** to stay on current Proton.

## The fix

`se2-fix.sh` patches **your own copy** of `Game2/VRage.Render12.dll`. It changes 12 bytes of IL in
`DeviceWrap`'s constructor so that `IsViewInstancingSupported` is always `false`, and the renderer
takes its own fallback path. No game files are distributed here.

The script needs only bash and coreutils (present on any Linux distro and on the Steam Deck). It:
- finds the game in your Steam libraries (native or Flatpak Steam),
- refuses to touch any DLL whose SHA-256 is not a known build (4.0.0.3151, 4.0.0.3155),
- keeps the original as `VRage.Render12.dll.orig` and can restore it.

## How to use it

**1.** Close the game. Open a terminal (on the Steam Deck: Desktop Mode → Konsole) and run:

```sh
curl -fsSL https://raw.githubusercontent.com/nirnx/se2-proton-viewinstancing-fix/main/se2-fix.sh | bash
```

**2.** In Steam, right-click **Space Engineers 2** → **Properties** → **General**, and put this in
**Launch Options**:

```
DOTNET_ReadyToRunExcludeList=VRage.Render12 %command%
```

**3.** Play. Use Proton Experimental or a recent GE-Proton. The fix was tested on Proton
Experimental 11.0-20261014 with an RTX 5090.

The launch option is **required**. `VRage.Render12.dll` ships precompiled (ReadyToRun), and without
it .NET runs the precompiled native code and ignores the patch. It only makes .NET JIT this one
assembly, so the first start of the renderer is a little slower.

### Undo / check

```sh
curl -fsSL https://raw.githubusercontent.com/nirnx/se2-proton-viewinstancing-fix/main/se2-fix.sh | bash -s -- --restore
curl -fsSL https://raw.githubusercontent.com/nirnx/se2-proton-viewinstancing-fix/main/se2-fix.sh | bash -s -- --status
```

### Manual mode (without curl, or with a specific file)

Download [`se2-fix.sh`](se2-fix.sh) (or `git clone` this repo), read it if you like, and pass the
DLL to patch. The path can be the DLL itself, the `Game2` folder or the `SpaceEngineers2` folder:

```sh
bash se2-fix.sh ~/.local/share/Steam/steamapps/common/SpaceEngineers2/Game2/VRage.Render12.dll
bash se2-fix.sh --status /path/to/SpaceEngineers2
bash se2-fix.sh --restore /path/to/SpaceEngineers2/Game2
```

Without a path, the script finds the game in your Steam libraries, just like the one-liner.
In Steam you can find the folder via **Manage → Browse local files**.

## Notes

- **Game updates and "Verify integrity of game files" replace the DLL** and remove the patch. If the
  game was updated, just run the one-liner again: if the new build is supported, it patches it.
  If the build is not supported yet, the script changes nothing and lists the supported builds.
  Support for a new build is added here when it comes out, unless Keen or vkd3d-proton has fixed
  the bug by then. A backup left over from an older build is never restored over a newer game.
- Point-light cube shadows use the game's fallback path instead of view instancing. Expect at most a
  small performance difference in scenes with many shadowed point lights.
- To undo, run the undo command (or verify the game files in Steam) and remove the launch option.
- Once Keen or vkd3d-proton fixes this, stop using the patch.

## License

The script is MIT-licensed (see `LICENSE`). Space Engineers 2 and `VRage.Render12.dll` belong to Keen
Software House. This repository contains none of their files.
