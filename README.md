# Space Engineers 2 on Proton: pink/purple materials and loading hang fix

An unofficial workaround for **Space Engineers 2 4.0.0.3151** ("Hostile Encounters") on Linux with
Proton / vkd3d-proton. Neither Keen Software House nor the vkd3d-proton project made it or endorses it.

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
Proton-CachyOS), and the same error is reported on AMD/RADV in vkd3d-proton#3384. Clearing shader
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
reports `ViewInstancingTier` below Tier 1. No launch option, game setting or vkd3d-proton
environment variable can switch the game to it. The `ForceCubeShadowFallback` shadow setting is not
enough, because materials still build the view-instanced variants.

Upstream report: [vkd3d-proton#3384](https://github.com/HansKristian-Work/vkd3d-proton/issues/3384).

## The fix

`se2-viewinstancing-fix.py` patches **your own copy** of `Game2/VRage.Render12.dll`. It changes 12
bytes of IL in `DeviceWrap`'s constructor so that `IsViewInstancingSupported` is always `false`, and
the renderer takes its own fallback path. No game files are distributed here.

The script:
- finds the game through your Steam libraries, or takes `--game-dir`,
- refuses to touch any DLL whose SHA-256 is not the known 4.0.0.3151 build,
- keeps the original as `VRage.Render12.dll.orig` and can restore it.

## Usage

Requires Python 3, which ships with most Linux distributions. Close the game first.

```sh
git clone https://github.com/nirnx/se2-proton-viewinstancing-fix
cd se2-proton-viewinstancing-fix
./se2-viewinstancing-fix.py
```

Then set the game's **Launch Options** in Steam (right-click Space Engineers 2 → Properties →
General):

```
DOTNET_ReadyToRunExcludeList=VRage.Render12 %command%
```

This variable is **required**. `VRage.Render12.dll` ships precompiled (ReadyToRun), and without it
.NET runs the precompiled native code and ignores the patched IL. The variable only makes .NET JIT
this one assembly, so the first start of the renderer is a little slower.

Use Proton Experimental or a recent GE-Proton. The patch was tested on Proton Experimental
11.0-20261014 with an RTX 5090.

Other commands:

```sh
./se2-viewinstancing-fix.py --status    # show whether the DLL is original or patched
./se2-viewinstancing-fix.py --restore   # put the original DLL back
```

If the game is installed somewhere unusual:

```sh
./se2-viewinstancing-fix.py --game-dir /path/to/steamapps/common/SpaceEngineers2
```

## Notes

- **Game updates and "Verify integrity of game files" replace the DLL** and remove the patch. If the
  game was updated, the script refuses to patch the new build. Check whether the bug is fixed first.
  If not, the patch site needs to be found again for the new build.
- Point-light cube shadows use the game's fallback path instead of view instancing. Expect at most a
  small performance difference in scenes with many shadowed point lights.
- To undo, run `--restore` (or verify the game files in Steam) and remove the launch option.
- Once Keen or vkd3d-proton fixes this, stop using the patch.

## License

The script is MIT-licensed (see `LICENSE`). Space Engineers 2 and `VRage.Render12.dll` belong to Keen
Software House. This repository contains none of their files.
