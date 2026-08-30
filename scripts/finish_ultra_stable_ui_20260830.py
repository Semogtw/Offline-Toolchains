from pathlib import Path
import sys

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')


def replace_once(path: str, old: str, new: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one match, found {count}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


main = 'lib/platform/desktop/screens/desktop_video_player_screen.dart'
replace_once(
    main,
    "  String? _enhancementCalibrationKey;\n  bool _enhancementContextResolved = false;\n  String _enhancementPerformanceLabel = '';",
    "  String? _enhancementCalibrationKey;\n  Future<void>? _enhancementContextFuture;\n  String _enhancementPerformanceLabel = '';",
)

methods = 'lib/platform/desktop/screens/desktop_video_player_screen_methods_1.dart'
replace_once(
    methods,
    "    _enhancementCalibrationKey = null;\n    _enhancementContextResolved = false;\n    _enhancementPerformanceLabel = '';",
    "    _enhancementCalibrationKey = null;\n    _enhancementContextFuture = null;\n    _enhancementPerformanceLabel = '';",
)
replace_once(
    methods,
    "      if (_enhancementLevel == 'ultra' && !_enhancementContextResolved) {\n        _enhancementContextResolved = true;\n        await _resolveUltraEnhancementContext(player);\n      }",
    "      if (_enhancementLevel == 'ultra') {\n        final contextFuture = _enhancementContextFuture ??=\n            _resolveUltraEnhancementContext(player);\n        await contextFuture;\n      }",
)

settings_main = 'lib/screens/settings_screen.dart'
replace_once(
    settings_main,
    "import '../services/storage_usage_diagnostics.dart';\nimport '../utils/video_enhancement_preference.dart';",
    "import '../services/storage_usage_diagnostics.dart';\nimport '../services/video_enhancement_calibration.dart';\nimport '../utils/video_enhancement_preference.dart';",
)

settings = 'lib/screens/settings_screen_video.dart'
replace_once(
    settings,
    "  String _level = 'none';\n  bool _isSavingPreference = false;",
    "  String _level = 'none';\n  String _sourceProfile = 'auto';\n  bool _isSavingPreference = false;",
)
replace_once(
    settings,
    "      final nextLevel = normalizeVideoEnhancementLevel(\n        storedLevel,\n        legacyEnabled: prefs.getBool(_legacyPreferenceKey) ?? false,\n      );\n      if (storedLevel != nextLevel) {\n        await prefs.setString(_preferenceKey, nextLevel);\n      }\n      if (!_isCurrentPreferenceOperation(generation)) return;\n      setState(() => _level = nextLevel);",
    "      final nextLevel = normalizeVideoEnhancementLevel(\n        storedLevel,\n        legacyEnabled: prefs.getBool(_legacyPreferenceKey) ?? false,\n      );\n      final storedSourceProfile = prefs.getString(\n        'video_enhancement_source_profile',\n      );\n      final nextSourceProfile = normalizeVideoEnhancementSourceProfile(\n        storedSourceProfile,\n      );\n      if (storedLevel != nextLevel) {\n        await prefs.setString(_preferenceKey, nextLevel);\n      }\n      if (storedSourceProfile != nextSourceProfile) {\n        await prefs.setString(\n          'video_enhancement_source_profile',\n          nextSourceProfile,\n        );\n      }\n      if (!_isCurrentPreferenceOperation(generation)) return;\n      setState(() {\n        _level = nextLevel;\n        _sourceProfile = nextSourceProfile;\n      });",
)
insert_before = "  bool _isCurrentPreferenceOperation(int generation) {\n"
addition = """  Future<void> _updateSourceProfile(String? value) async {
    if (value == null || !isVideoEnhancementSourceProfile(value)) return;
    if (_isSavingPreference) return;

    final generation = ++_preferenceGeneration;
    final syncService = context.read<UserSyncService>();
    final l10n = AppLocalizations.of(context);
    setState(() => _isSavingPreference = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
        'video_enhancement_source_profile',
        value,
      );
      if (!saved) throw StateError('Source profile was not persisted.');
      if (!_isCurrentPreferenceOperation(generation)) return;
      setState(() => _sourceProfile = value);
    } catch (_) {
      if (_isCurrentPreferenceOperation(generation)) {
        _showPreferenceFeedback(
          l10n.genericFailureDescription,
          color: AppColors.error,
        );
        setState(() => _isSavingPreference = false);
      }
      return;
    }

    try {
      await syncService.recordSettings({
        'videoEnhancementSourceProfile': value,
        'settingsUpdatedAt': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      if (_isCurrentPreferenceOperation(generation)) {
        _showPreferenceFeedback(
          l10n.videoPreferenceSavedLocally,
          color: AppColors.warning,
        );
      }
    } finally {
      if (_isCurrentPreferenceOperation(generation)) {
        setState(() => _isSavingPreference = false);
      }
    }
  }

  Future<void> _resetUltraCalibration() async {
    final l10n = AppLocalizations.of(context);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(videoEnhancementCalibrationPreferenceKey);
      if (!mounted) return;
      _showPreferenceFeedback(
        l10n.videoEnhancementCalibrationResetDone,
        color: AppColors.success,
      );
    } catch (_) {
      if (!mounted) return;
      _showPreferenceFeedback(
        l10n.genericFailureDescription,
        color: AppColors.error,
      );
    }
  }

"""
replace_once(settings, insert_before, addition + insert_before)

marker = """          if (_level != 'none') ...[
            SizedBox(height: 10),
"""
source_ui = """          if (_level == 'ultra') ...[
            SizedBox(height: 12),
            Text(
              l10n.videoEnhancementSourceProfile,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              l10n.videoEnhancementSourceProfileDescription,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 12.5,
              ),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('settings-video-enhancement-source-profile'),
                  value: _sourceProfile,
                  isExpanded: true,
                  dropdownColor: AppColors.surface,
                  items: [
                    DropdownMenuItem(
                      value: 'auto',
                      child: Text(
                        l10n.videoEnhancementSourceAuto,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'clean',
                      child: Text(
                        l10n.videoEnhancementSourceClean,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'compressed',
                      child: Text(
                        l10n.videoEnhancementSourceCompressed,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'noisy',
                      child: Text(
                        l10n.videoEnhancementSourceNoisy,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                  onChanged: _isSavingPreference ? null : _updateSourceProfile,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('settings-video-enhancement-reset-calibration'),
                onPressed: _isSavingPreference
                    ? null
                    : () => unawaited(_resetUltraCalibration()),
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text(l10n.videoEnhancementResetCalibration),
              ),
            ),
          ],
          if (_level != 'none') ...[
            SizedBox(height: 10),
"""
replace_once(settings, marker, source_ui)

l10n = 'lib/l10n/ui_settings_localizations.dart'
marker_l10n = """  String get videoEnhancementUltraWarning => _isPortuguese
      ? 'Ultra prioriza a melhor qualidade visual em tempo real. Uso alto ou até 100% de GPU é aceitável; o pipeline evita upscale 2x desnecessário em vídeo 1080p e usa cadeias mais fortes em fontes de menor resolução.'
      : 'Ultra prioritizes the best real-time image quality. High or even 100% GPU use is acceptable; the pipeline avoids unnecessary 2x upscaling for 1080p video and uses stronger chains for lower-resolution sources.';
"""
new_l10n = marker_l10n + """  String get videoEnhancementSourceProfile => _isPortuguese
      ? 'Tratamento da fonte no Ultra'
      : 'Ultra source treatment';
  String get videoEnhancementSourceProfileDescription => _isPortuguese
      ? 'Automático usa bitrate, codec e rótulos da fonte; você pode forçar o tratamento quando conhecer o encode.'
      : 'Automatic uses bitrate, codec and source labels; you can override it when you know the encode.';
  String get videoEnhancementSourceAuto => _isPortuguese
      ? 'Automático (recomendado)'
      : 'Automatic (recommended)';
  String get videoEnhancementSourceClean => _isPortuguese
      ? 'Limpa / Blu-ray (preservar textura)'
      : 'Clean / Blu-ray (preserve texture)';
  String get videoEnhancementSourceCompressed => _isPortuguese
      ? 'Comprimida / streaming (denoise + nitidez)'
      : 'Compressed / streaming (denoise + sharpen)';
  String get videoEnhancementSourceNoisy => _isPortuguese
      ? 'Ruidosa / grain forte (denoise suave)'
      : 'Noisy / heavy grain (soft denoise)';
  String get videoEnhancementResetCalibration => _isPortuguese
      ? 'Recalibrar desempenho do Ultra'
      : 'Recalibrate Ultra performance';
  String get videoEnhancementCalibrationResetDone => _isPortuguese
      ? 'Calibração do Ultra apagada. O próximo vídeo começa no máximo e mede novamente.'
      : 'Ultra calibration cleared. The next video starts at maximum and measures again.';
"""
replace_once(l10n, marker_l10n, new_l10n)
