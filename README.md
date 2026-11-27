# AlphaSolveVideo

This repo holds scripts that, when combined with high quality recordings and special gecko codes in SSBM, can extract high quality transparent foreground content from the game.

![Animated gif example of Battlefield](Resources/Readme%20Examples/sideBySide.gif)

To apply the technique to images instead of video recordings, see [PdnAlphaSolve](https://github.com/NeilHarbin0/PdnAlphaSolve).

**EPILEPSY WARNING: Included example videos within the Resources folder as well as videos required for this technique contain constant black and white strobing at 30Hz and may present risks to individuals with epilepsy.**

## Automated Headless `.slp` Rendering (Windows, macOS, Linux)

Render Slippi `.slp` replays directly to transparent (or opaque) video without opening a flashing Dolphin window and **without Python or Node.js installed at runtime**.

### Modes & Stage Support

| Mode | Stage | HUD | Transparent? | Stage Coverage | Codes Used |
|---|---|---|---|---|---|
| `--no-stage --no-hud` *(default)* | Hidden | Hidden | Yes | **All stages** | [Required](Resources/Required%20Codes.txt) + [Characters Only](Resources/Characters%20Only%20Codes.txt) |
| `--no-stage --hud` | Hidden | Kept | Yes | **All stages** | Same, without `Hide HUD and Overlays` |
| `--stage --no-hud` | Kept | Hidden | Yes | Dream Land, Battlefield | Input Timing + Flicker + DL/BF BG disable + `Hide HUD and Overlays` |
| `--stage --hud` | Kept | Kept | Yes | Dream Land, Battlefield | Input Timing + Flicker + DL/BF BG disable |
| `--opaque` *(+ `--no-hud` optional)* | Kept | Kept / Hidden | No (`fullOpaque`) | **All stages** | Input Timing (+ optional `Hide HUD and Overlays`) |
| `--no-gecko` | Kept | Kept | No (`fullOpaque`) | **All stages** | None of AlphaSolve's codes (Slippi's built-in playback codes only) |

> **Note on `--no-gecko`:** True alpha-solved transparency requires the flicker and background-hiding Gecko codes; without them, Melee draws an opaque 3D stage background and Dolphin's frame dump has no alpha channel, so `--no-gecko` outputs a standard opaque video (`fullOpaque - <name>.<ext>`).

### Setup
1. **FFmpeg:**
   - **Windows:** Place `ffmpeg.exe` in the repo root, `packages\ffmpeg\`, `packages\ffmpeg-6.0-full_build\bin\`, or on your `PATH`.
   - **macOS / Linux:** Install `ffmpeg` (e.g. `brew install ffmpeg` on macOS, or place `ffmpeg` in the repo root, `packages/ffmpeg/`, or `PATH`).
2. **Headless Playback Dolphin (`dolphin-emu-nogui`):**
   Download the artifact for your platform from GitHub Actions (or build locally with `tools/dolphin-build/`):
   - **Windows:** Run the `Windows playback Dolphin` workflow and unpack `slippi-playback-mainline-windows` into `packages\slippi-playback-mainline\` (`dolphin-emu-nogui.exe`).
   - **macOS (Apple Silicon):** Run `macOS playback Dolphin` and unpack `slippi-playback-mainline-macos-arm64.tar.gz` into `packages/slippi-playback-mainline/` (`Slippi Dolphin.app`), or build locally with `tools/dolphin-build/build-mac-mainline.sh`.
   - **Linux (`x86_64` / `aarch64`):** Run `Linux playback Dolphin` and extract `slippi-playback-mainline-linux-<arch>.tar.gz` into `packages/`, or build locally with `python3 tools/dolphin-build/build-linux-mainline.py`.
3. **Melee NTSC 1.02 ISO:** Detected automatically from Slippi Launcher's `Settings`, or passed via `--iso PATH` / `MELEE_ISO`.

*(Platform status: tested end-to-end on macOS Apple Silicon across all modes; Windows `.bat` scripts and Linux/Windows/macOS CI workflows have not been executed on Windows or Linux machines yet.)*

### Windows (Batch Scripts)
Drag and drop a `.slp` file onto one of the preset scripts in `Scripts\`, or run [RenderSlp.bat](Scripts/RenderSlp.bat) from Command Prompt:
- [RenderNoStageNoHUD.bat](Scripts/RenderNoStageNoHUD.bat) — characters/items/effects only, no HUD (all stages)
- [RenderNoStageWithHUD.bat](Scripts/RenderNoStageWithHUD.bat) — characters/items/effects only, with HUD (all stages)
- [RenderWithStageNoHUD.bat](Scripts/RenderWithStageNoHUD.bat) — stage geometry kept, no HUD (Dream Land, Battlefield)
- [RenderWithStageWithHUD.bat](Scripts/RenderWithStageWithHUD.bat) — stage geometry kept, with HUD (Dream Land, Battlefield)
- [RenderNoGecko.bat](Scripts/RenderNoGecko.bat) — opaque render with no AlphaSolve Gecko codes (all stages)

Optional second argument sets output format (default `png`), or use flags directly:
```bat
Scripts\RenderSlp.bat replay.slp --no-stage --no-hud --format png
Scripts\RenderSlp.bat replay.slp --stage --hud --format prores --scale 2
Scripts\RenderSlp.bat replay.slp --no-gecko --format mp4
```

### macOS & Linux (Shell Scripts)
```sh
Scripts/renderslp.sh replay.slp --no-stage --no-hud --format mov
Scripts/renderslp.sh replay.slp --stage --hud --format png --scale 2
Scripts/renderslp.sh replay.slp --no-gecko --format mp4
```

Common options for both [RenderSlp.bat](Scripts/RenderSlp.bat) and [renderslp.sh](Scripts/renderslp.sh):
- `--format EXT`: `png` (default APNG), `prores`, `mov`, `mkv`, `avi`, `webm`, `gif` (plus `mp4` with `--opaque` / `--no-gecko`)
- `--scale N`: internal resolution multiplier `1`–`4` (default `1`)
- `--raw`: dump unstretched `640x480 * scale` instead of aspect-corrected `640x528`
- `--out DIR`: output directory (default: next to the replay)
- `--backend NAME`: `D3D` / `D3D12` / `Vulkan` / `OGL` on Windows, `Metal` on macOS, `Vulkan` / `OGL` on Linux

You can also solve any pre-recorded `.avi`/`.mkv` flicker video directly with [AlphaSolve.bat](Scripts/AlphaSolve.bat) (Windows) or [alphasolve.sh](Scripts/alphasolve.sh) (macOS/Linux).

## Manual Usage (Video Recordings)
Download the latest release zip from the [releases page](https://github.com/NeilHarbin0/AlphaSolveVideo/releases). Extract the zip to preferably a dedicated folder. 

1. You will need Dolphin emulator that supports lossless .avi output via framedump. Tested and working with Dolphin 5.0-17995. Find output path under `Options` -> `Configuration` -> `Paths` -> `Dump Path`.

2. Set up your SSBM gecko codes to include and enable all required codes (only Dreamland and BF background disabling codes included by default). [Required codes](Resources/Required%20Codes.txt) can be found in the Resources folder.

    - `Increase Input Timing Accuracy` will ensure black->white frame pairs always stay in the same order
    - `(EPILEPSY WARNING) Flicker Background Black/White` will flash the screen black/white each physics frame to enable the alpha solving technique
      - This code includes a modified 120 FPS mode code to allow two separate frames with different background colors without physics advancing, as the normal 120 FPS code doesn't work with Slippi playback
    - Disable background codes are required so that the flickering background can be seen
    - `Reduce Debug Develop` lag code ensures accurate frame information in rare situations
    - [Optional codes](Resources/Optional%20Codes.txt) that can help or improve quality of documented content are also available in the same Resources folder.

3. Record gameplay via `Dolphin Movie` -> `Dump Frames`, selecting it again when you want to stop recording. The quality offered by this feature is important as the solver is sensitive to small artifacts that may appear with other recording techniques, especially when the recording is not perfectly synchronized, and frames are skipped.

   - `Use Lossless Codec (FFV1)` or similar should be enabled in `Options` -> `Graphics Settings` -> `Advanced` -> `Frame Dumping` if it is not already checked by default
     - If using Slippi Dolphin, you can enable FFV1 in the `GFX.ini` located in the applications config folder `%AppData%\Slippi Launcher\playback\User\Config` like `UseFFV1 = True`
   - Ensure the first few frames show at least a miniscule physics change visible to the naked eye. Do not begin the recording in frame advance mode, paused, or in a near motionless animation.
   - Ensure the first two frames contain at least a small portion of background color visible. Do not begin the recording in menus, or extremely zoomed into to stage/character geometry.

4. Drag and drop the recording on one of the various `SolveTo???.bat` scripts depending on the type of output file you desire (default animated png). This will generate several files in the directory of the dragged video file for the alpha map and transparent outputs. Several intermediate files will also be created and deleted in the same location during the process.

    - Small example videos are available in the Resources folder which can be used to drag and drop

5. Hopefully wherever you plan to use the output files supports transparency for that specific file.

    - Animated png is recommended for high quality short content like documentation, though browser support varies.
    - Discord has some support for embedded webm, though the quality of the webm output often has worse artifacts than other formats.
    - Other formats are to hopefully cover various video editing software for content creators.
  
## Optional

1. Set Dolphin `Options` -> `Configuration` -> `General` -> `Speed Limit` to 200%. This will allow the game to run at seemingly normal speed aside from audio, and can help reduce the harshness of the strobing effect to the eye as long as your monitor supports the higher fps. Unfortunately, dumping frames will likely tank FPS back down substantially.
2. Reduce Dolphin window size to a smaller reasonable resolution, or dump at a smaller internal resolution via `Options` -> `Graphics Settings` -> `Enhancements`-> `Internal Resolutions` and `Options` -> `Graphics Settings` -> `Advanced` -> `Frame Dumping` -> `Dump at Internal Resolution`. A 30 second 720p frame dumped video can be around 250MB, with higher resolutions costing even more. Large resolutions will work, it will just make large files that take much longer to process.

## The Technique
The following process is applied to each frame pair in the video.

Two source frames with black and white backgrounds are used to solve for the proper transparency of the subject.

<img src='Resources/Readme%20Examples/ExSourceBlack.png?raw=true' width='400'><img src='Resources/Readme%20Examples/ExSourceWhite.png?raw=true' width='400'>

The technique can produce an alpha map and the fully transparent subject.

<img src='Resources/Readme%20Examples/MethodAlphaSolveMap.png?raw=true' width='400'><img src='Resources/Readme%20Examples/MethodAlphaSolve.png?raw=true' width='400'>

For the video solving script, there is a bit of detection in seeing if the first frame is black or white, followed by detection of black->white or white->black pairs. With this information, the specific frames that need to be compared are known, extracted from the video, and used to generate the outputs.

![Solved Transparency](Resources/Readme%20Examples/Demo.png?raw=true)

*Warning: It is possible that pair detection fails, leading to strange chromatic edged outputs or ghosting. Please ensure the first 3 frames of the video contain at least a tiny bit of visible physics change. Otherwise you can try temporarily swapping swapping :firstPair and :secondPair labels in AlphaSolve.bat.*

*Warning: It is possible that background color detection can fail. This can lead to strange white outlines around subject content, and certain particle effects losing all of their color. If this happens to you, please let me know. Otherwise you can try temporarily swapping swapping :isBlack and :isWhite labels in AlphaSolve.bat.*

## Other "Worse" Approaches
Below are images of other approaches which generally miss partial transparency, leading to the inability to place your transparent image onto any background with accurate color. They also tend to break down at low resolutions around the edges.

*Note: Images are displayed with a checkered background for demonstration purposes, normally they would be transparent.*

### Greenscreen

![Greenscreen Method](Resources/Readme%20Examples/MethodGreenScreen.png?raw=true)
- Green edge glow
- Innacurate or missing partial transparency

### Magic Wand

![Magic Wand Method](Resources/Readme%20Examples/MethodWand.png?raw=true)

- Innacurate and sometimes jagged edges
- No partial transparency
