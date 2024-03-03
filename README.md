# AlphaSolveVideo

This repo holds scripts that when combined with high quality recordings and special gecko codes in SSBM, can extract high quality transparent foreground content from the game.

To apply the technique to images instead of video recordings, see [PdnAlphaSolve](https://github.com/NeilHarbin0/PdnAlphaSolve).

**EPILEPSY WARNING: Included example videos within the Resources folder as well as videos required for this technique contain constant black and white strobing at 30Hz and may present risks to individuals with epilepsy.**

## Usage
Download the latest release zip from the [releases page](https://github.com/NeilHarbin0/AlphaSolveVideo/releases). Extract the zip to preferably a dedicated folder. 

1. You will need Dolphin emulator that supports lossless .avi output via framedump. Tested and working with Dolphin 5.0-17995. Find output path under `Options` -> `Configuration` -> `Paths` -> `Dump Path`.

2. Set up your SSBM gecko codes to include and enable all required codes (only Dreamland and BF background disabling codes included by default). [Required codes](https://github.com/NeilHarbin0/AlphaSolveVideo/blob/master/AlphaSolve/Resources/Required%20Codes.txt) can be found in the Resources folder.

    - `120 FPS` mode will allow two separate frames with different background colors without physics advancing
    - `Increase Input Timing Accuracy` will ensure black->white frame pairs always stay in the same order
    - `(EPILEPSY WARNING) Flicker Background Black/White` will flash the screen black/white each physics frame to enable the alpha solving technique
    - Disable background codes are required so that the flickering background can be seen
    - `Reduce Debug Develop` lag code ensures accurate frame information in rare situations
    - [Optional codes](https://github.com/NeilHarbin0/AlphaSolveVideo/blob/master/AlphaSolve/Resources/Optional%20Codes.txt) that can help or improve quality of documented content are also available in the same Resources folder.

3. Record gameplay via `Dolphin Movie` -> `Dump Frames`, selecting it again when you want to stop recording. The quality offered by this feature is important as the solver is sensitive to small artifacts that may appear with other recording techniques, especially when the recording is not perfectly synchronized, and frames are skipped.

4. Drag and drop the recording on one of the various `SolveTo???.bat` scripts depending on the type of output file you desire (default animated png). This will generate several files in the directory of the dragged video file for the alpha map and transparent outputs. Several intermediate files will also be created and deleted in the same location during the process.

    - Small example videos are available in the Resources folder which can be used to drag and drop

5. Hopefully wherever you plan to use the output files supports transparency for that specific file.

    - Animated png is recommended for high quality short content like documentation, though browser support varies.
    - Discord has some support for embedded webm, though the quality of the webm output often has worse artifacts than other formats.
    - Other formats are to hopefully cover various video editing software for content creators.

## The Technique
The following process is applied to each frame pair in the video.

Two source frames with black and white backgrounds are used to solve for the proper transparency of the subject.

<img src='https://github.com/NeilHarbin0/AlphaSolveVideo/blob/main/Resources/Readme%20Examples/ExSourceBlack.png?raw=true' width='400'><img src='https://github.com/NeilHarbin0/AlphaSolveVideo/blob/main/Resources/Readme%20Examples/ExSourceWhite.png?raw=true' width='400'>

The technique can produce an alpha map and the fully transparent subject.

<img src='https://github.com/NeilHarbin0/AlphaSolveVideo/blob/main/Resources/Readme%20Examples/MethodAlphaSolveMap.png?raw=true' width='400'><img src='https://github.com/NeilHarbin0/AlphaSolveVideo/blob/main/Resources/Readme%20Examples/MethodAlphaSolve.png?raw=true' width='400'>

For the video solving script, there is a bit of detection in seeing if the first frame is black or white, followed by detection of black->white or white-black pairs. With this information, the specific frames that need to be compared are known, extracted from the video, and used to generate the outputs.

![Solved Transparency](https://github.com/NeilHarbin0/AlphaSolveVideo/blob/main/Resources/Readme%20Examples/Demo.png?raw=true)

*Warning: It is possible that this detection fails, leading to strange chromatic edged outputs. I hope to improve this in the future, but if it happens to you, please notify me so I can help. Otherwise you can try swapping isBlack and isWhite tags in AlphaSolve.bat, or swapping firstPair and secondPair.*

## Other "Worse" Approaches
Below are images of other approaches which generally miss partial transparency, leading to the inability to place your transparent image onto any background with accurate color. They also tend to break down at low resolutions around the edges.

*Note: Images are displayed with a checkered background for demonstration purposes, normally they would be transparent.*

### Greenscreen

![Greenscreen Method](https://github.com/NeilHarbin0/AlphaSolveVideo/blob/main/Resources/Readme%20Examples/MethodGreenScreen.png?raw=true)
- Green edge glow
- Innacurate or missing partial transparency

### Magic Wand

![Magic Wand Method](https://github.com/NeilHarbin0/AlphaSolveVideo/blob/main/Resources/Readme%20Examples/MethodWand.png?raw=true)

- Innacurate and sometimes jagged edges
- No partial transparency
