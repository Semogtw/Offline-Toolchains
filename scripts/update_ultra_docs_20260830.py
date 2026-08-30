from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')
p = root / 'docs/video_enhancement.md'
text = p.read_text(encoding='utf-8')

old_perf = """The current implementation does **not** pretend to have RX 6600 timing evidence. It implements deterministic maximum-quality selection, runtime fallback tiers, and records the exact chosen chain in the UI. Hardware-specific calibration remains measurement-driven.
"""
new_perf = """The current implementation starts Ultra at the highest applicable tier unless a stable local calibration exists for the same operating system, mpv/libplacebo backend signature, source-resolution bucket, target-resolution bucket and source-treatment profile. Runtime telemetry samples mpv render-pass timing and `frame-drop-count`; repeated deadline pressure reduces the tier, while a tier is persisted as stable only after sustained headroom and zero new frame drops. GPU utilization alone never reduces quality.
"""
if old_perf not in text:
    raise SystemExit('performance status paragraph not found')
text = text.replace(old_perf, new_perf, 1)

old_720 = """```text
Anime4K_Clamp_Highlights
ArtCNN_C4F32_DS
```

The bundled ArtCNN C4F32 DS model performs learned upscale/denoise/sharpen work, after which mpv fits the result to the actual video surface.
"""
new_720 = """The stable ArtCNN C4F32 family is selected from source treatment:

| Treatment | Shader | Purpose |
| --- | --- | --- |
| `clean` | `ArtCNN_C4F32.glsl` | Neutral learned 2x path that avoids unnecessary denoise/sharpen on clean Blu-ray/remux-style material. |
| `compressed` | `ArtCNN_C4F32_DS.glsl` | Learned denoise + sharpen for typical streaming compression. |
| `noisy` | `ArtCNN_C4F32_DN.glsl` | Learned denoise + soften for deliberately noisy/grain-heavy sources. |

`auto` classifies conservatively from source labels plus bitrate, dimensions, FPS and codec efficiency. It never infers `noisy` from low bitrate alone. Settings expose all four modes so a known encode can override the classifier.
"""
if old_720 not in text:
    raise SystemExit('720p section not found')
text = text.replace(old_720, new_720, 1)

row = "| `ArtCNN_C4F32_DS.glsl` | `Artoriuz/ArtCNN`, `GLSL/ArtCNN_C4F32_DS.glsl` | `91540a6099286655798e955c6b70a7fee429eff1` | Existing bundled MIT-licensed asset; current file includes upstream MIT header. |"
rows = """| `ArtCNN_C4F32.glsl` | `Artoriuz/ArtCNN`, `GLSL/ArtCNN_C4F32.glsl` | `00a487233c1d77a35b7084d395efcbde21fbffef` | Stable realtime C4F32 neutral model; exact upstream MIT-licensed blob. |
| `ArtCNN_C4F32_DN.glsl` | `Artoriuz/ArtCNN`, `GLSL/ArtCNN_C4F32_DN.glsl` | `8a5c1ae9da03caa418cf54f07a9e5259ce73bd95` | Stable realtime C4F32 denoise/soften model; exact upstream MIT-licensed blob. |
""" + row
if row not in text:
    raise SystemExit('ArtCNN provenance row not found')
text = text.replace(row, rows, 1)

old_tests = """- `test/utils/video_enhancement_preference_test.dart`
- `test/services/video_enhancement_planner_test.dart`
- `test/screens/desktop_video_enhancement_static_test.dart`
- existing `test/screens/player_lifecycle_static_test.dart`
"""
new_tests = """- `test/utils/video_enhancement_preference_test.dart`
- `test/services/video_enhancement_planner_test.dart`
- `test/services/video_enhancement_source_classifier_test.dart`
- `test/services/video_enhancement_calibration_test.dart`
- `test/services/video_enhancement_performance_controller_test.dart`
- `test/screens/desktop_video_enhancement_static_test.dart`
- existing `test/screens/player_lifecycle_static_test.dart`
"""
if old_tests not in text:
    raise SystemExit('focused test list not found')
text = text.replace(old_tests, new_tests, 1)

heading = '## Deferred maximum-quality work'
if heading not in text:
    raise SystemExit('deferred section not found')
prefix = text.split(heading, 1)[0]
experimental_only = """## Remaining maximum-quality work: experimental only

All stable realtime items identified for this branch are implemented: stable ArtCNN C4F32 Neutral/DN/DS selection, explicit mpv/libplacebo scaler tuning, render/drop telemetry, evidence-driven fallback tiers, persistent local calibration and user controls.

The following remain intentionally unimplemented because they belong to the separately gated Experimental pipeline:

1. ArtCNN shaders under upstream `GLSL/Experiments` such as experimental YCbCr/chroma networks.
2. ONNX-only/non-realtime ArtCNN R-family models such as R8F64; these are not valid drop-in GLSL realtime assets.
3. External NCNN/Vulkan buffered inference with Real-CUGAN, Real-ESRGAN, AnimeJaNai or similarly heavy models.
4. Any ahead-of-playback AI cache/worker orchestration described in the Experimental section above.

None of those assets or preference values are exposed by the current production settings. They require their own capability probe, license/provenance review, benchmark gates and fallback contract before implementation.
"""
p.write_text(prefix + experimental_only, encoding='utf-8')
