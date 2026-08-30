from pathlib import Path

ROOT = Path('goanime')


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one match, found {count}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'lib/platform/desktop/screens/desktop_video_player_screen_methods_1.dart',
    """      if (_enhancementLevel == 'ultra') {
        final contextFuture = _enhancementContextFuture ??=
            _resolveUltraEnhancementContext(player);
        await contextFuture;
      }
""",
    """      if (_enhancementLevel == 'ultra') {
        final existingContextFuture = _enhancementContextFuture;
        if (existingContextFuture != null) {
          await existingContextFuture;
        } else {
          final newContextFuture = _resolveUltraEnhancementContext(player);
          _enhancementContextFuture = newContextFuture;
          await newContextFuture;
        }
      }
""",
)

validator_path = ROOT / 'tools/validate_video_enhancement_state_safety.py'
source = validator_path.read_text(encoding='utf-8')
source = source.replace(
    """CURRENT_OPERATION_GUARD = re.compile(
    r\"bool\\s+_isCurrentPreferenceOperation\\(int generation\\)\\s*\\{\\s*\"
    r\"return\\s+mounted\\s*&&\\s*generation\\s*==\\s*_preferenceGeneration;\\s*\\}\",
    re.DOTALL,
)
""",
    """CURRENT_OPERATION_GUARD = re.compile(
    r\"bool\\s+_isCurrentPreferenceOperation\\(int generation\\)\\s*\\{\\s*\"
    r\"return\\s+mounted\\s*&&\\s*generation\\s*==\\s*_preferenceGeneration;\\s*\\}\",
    re.DOTALL,
)
LOAD_STATE_UPDATE = re.compile(
    r\"setState\\(\\(\\)\\s*\\{\\s*\"
    r\"_level\\s*=\\s*nextLevel;\\s*\"
    r\"_sourceProfile\\s*=\\s*nextSourceProfile;\\s*\"
    r\"\\}\\);\",
    re.DOTALL,
)
""",
    1,
)
source = source.replace(
    """        (CURRENT_OPERATION_GUARD, \"mounted generation ownership guard\"),
""",
    """        (CURRENT_OPERATION_GUARD, \"mounted generation ownership guard\"),
        (LOAD_STATE_UPDATE, \"atomic level/source-profile load state update\"),
""",
    1,
)
source = source.replace(
    """        \"setState(() => _level = nextLevel);\",\n""",
    "",
    1,
)
if 'LOAD_STATE_UPDATE = re.compile(' not in source:
    raise SystemExit('failed to add LOAD_STATE_UPDATE guard')
if 'setState(() => _level = nextLevel);' in source:
    raise SystemExit('stale one-line load-state requirement remains')
validator_path.write_text(source, encoding='utf-8')
