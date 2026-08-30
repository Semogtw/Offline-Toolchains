from pathlib import Path

path = Path('goanime/docs/video_enhancement.md')
text = path.read_text(encoding='utf-8')

old_policy = """`auto` classifies conservatively from source labels plus bitrate, dimensions, FPS and codec efficiency. It never infers `noisy` from low bitrate alone. Settings expose all four modes so a known encode can override the classifier.
"""
new_policy = """`auto` classifies conservatively from source labels plus bitrate, dimensions, FPS and codec efficiency. It never infers `noisy` from low bitrate alone. Settings expose all four modes so a known encode can override the classifier.

The 720p calibration ladder stays inside the same stable ArtCNN treatment family:

| Runtime tier | Model family | Behavior |
| --- | --- | --- |
| `MAX` / tier 2 | C4F32 Neutral/DN/DS | Highest stable realtime quality for the selected source treatment. |
| `SAFE` / tier 1 | C4F16 Neutral/DN/DS | Same source-treatment semantics with the smaller stable ArtCNN network when render telemetry shows deadline pressure. |
| `MIN` / tier 0 | Clamp + native/libplacebo scaler | Final realtime fallback when even the learned SAFE tier cannot sustain presentation deadlines. |

A fallback therefore does not silently change a clean source into a denoise/sharpen profile or a noisy source into a neutral profile. Calibration changes network capacity while preserving the selected treatment.
"""
if text.count(old_policy) != 1:
    raise SystemExit('720p policy anchor mismatch')
text = text.replace(old_policy, new_policy, 1)

old_rows = """| `ArtCNN_C4F32.glsl` | `Artoriuz/ArtCNN`, `GLSL/ArtCNN_C4F32.glsl` | `00a487233c1d77a35b7084d395efcbde21fbffef` | Stable realtime C4F32 neutral model; exact upstream MIT-licensed blob. |
"""
new_rows = """| `ArtCNN_C4F16.glsl` | `Artoriuz/ArtCNN`, `GLSL/ArtCNN_C4F16.glsl` | `4086dce92db6c1d9d81d3e396aa94d35a1e389a8` | Stable realtime C4F16 neutral fallback; exact upstream MIT-licensed blob. |
| `ArtCNN_C4F16_DN.glsl` | `Artoriuz/ArtCNN`, `GLSL/ArtCNN_C4F16_DN.glsl` | `12f9fec62bc17391a8c67ea98e5fc798d8beec4d` | Stable realtime C4F16 denoise/soften fallback; exact upstream MIT-licensed blob. |
| `ArtCNN_C4F16_DS.glsl` | `Artoriuz/ArtCNN`, `GLSL/ArtCNN_C4F16_DS.glsl` | `69d1a95818e9a57723e609eda7e860a45b0c873b` | Stable realtime C4F16 denoise/sharpen fallback; exact upstream MIT-licensed blob. |
| `ArtCNN_C4F32.glsl` | `Artoriuz/ArtCNN`, `GLSL/ArtCNN_C4F32.glsl` | `00a487233c1d77a35b7084d395efcbde21fbffef` | Stable realtime C4F32 neutral model; exact upstream MIT-licensed blob. |
"""
if text.count(old_rows) != 1:
    raise SystemExit('provenance anchor mismatch')
text = text.replace(old_rows, new_rows, 1)

old_status = """All stable realtime items identified for this branch are implemented: stable ArtCNN C4F32 Neutral/DN/DS selection, explicit mpv/libplacebo scaler tuning, render/drop telemetry, evidence-driven fallback tiers, persistent local calibration and user controls.
"""
new_status = """All stable realtime items identified for this branch are implemented: stable ArtCNN C4F32 Neutral/DN/DS maximum tiers, matching C4F16 Neutral/DN/DS safe fallbacks, explicit mpv/libplacebo scaler tuning, render/drop telemetry, evidence-driven fallback tiers, persistent local calibration and user controls.
"""
if text.count(old_status) != 1:
    raise SystemExit('stable status anchor mismatch')
text = text.replace(old_status, new_status, 1)

path.write_text(text, encoding='utf-8')
