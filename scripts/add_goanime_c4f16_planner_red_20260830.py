from pathlib import Path

path = Path('goanime/test/services/video_enhancement_planner_test.dart')
text = path.read_text(encoding='utf-8')
old = """    test('720p and SD Ultra have cheaper evidence-driven fallback tiers', () {
      expect(
        VideoEnhancementPlanner.plan(
          level: 'ultra',
          sourceHeight: 720,
          targetHeight: 1080,
          ultraQualityTier: 1,
        ).shaderAssets,
        [
          'assets/shaders/Anime4K_Clamp_Highlights.glsl',
          'assets/shaders/Anime4K_Upscale_CNN_x2_M.glsl',
        ],
      );
      expect(
        VideoEnhancementPlanner.plan(
          level: 'ultra',
          sourceHeight: 480,
          targetHeight: 1080,
          ultraQualityTier: 1,
        ).shaderAssets,
        [
          'assets/shaders/Anime4K_Clamp_Highlights.glsl',
          'assets/shaders/Anime4K_Restore_CNN_M.glsl',
          'assets/shaders/Anime4K_Upscale_CNN_x2_M.glsl',
        ],
      );
    });
"""
new = """    test('720p Ultra tier 1 stays in the ArtCNN family by source profile', () {
      expect(
        VideoEnhancementPlanner.plan(
          level: 'ultra',
          sourceHeight: 720,
          targetHeight: 1080,
          ultraQualityTier: 1,
        ).shaderAssets,
        [
          'assets/shaders/Anime4K_Clamp_Highlights.glsl',
          'assets/shaders/ArtCNN_C4F16_DS.glsl',
        ],
      );
      expect(
        VideoEnhancementPlanner.plan(
          level: 'ultra',
          sourceHeight: 720,
          targetHeight: 1080,
          ultraQualityTier: 1,
          sourceProfile: 'clean',
        ).shaderAssets,
        [
          'assets/shaders/Anime4K_Clamp_Highlights.glsl',
          'assets/shaders/ArtCNN_C4F16.glsl',
        ],
      );
      expect(
        VideoEnhancementPlanner.plan(
          level: 'ultra',
          sourceHeight: 720,
          targetHeight: 1080,
          ultraQualityTier: 1,
          sourceProfile: 'noisy',
        ).shaderAssets,
        [
          'assets/shaders/Anime4K_Clamp_Highlights.glsl',
          'assets/shaders/ArtCNN_C4F16_DN.glsl',
        ],
      );
    });

    test('SD Ultra tier 1 keeps the cheaper Anime4K recovery chain', () {
      expect(
        VideoEnhancementPlanner.plan(
          level: 'ultra',
          sourceHeight: 480,
          targetHeight: 1080,
          ultraQualityTier: 1,
        ).shaderAssets,
        [
          'assets/shaders/Anime4K_Clamp_Highlights.glsl',
          'assets/shaders/Anime4K_Restore_CNN_M.glsl',
          'assets/shaders/Anime4K_Upscale_CNN_x2_M.glsl',
        ],
      );
    });
"""
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one planner fallback test block, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
