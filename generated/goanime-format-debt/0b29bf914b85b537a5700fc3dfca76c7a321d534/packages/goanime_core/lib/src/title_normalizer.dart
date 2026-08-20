class TitleNormalizer {
  static final RegExp _accentsRegExp = RegExp(r"['´`’]");
  static final RegExp _nonAlphaNumRegExp = RegExp(r'[^a-z0-9]+');
  static final RegExp _dubSubRegExp = RegExp(
    r'\b(dublado|legendado|dub|sub)\b',
  );
  static final RegExp _allEpsRegExp = RegExp(r'\btodos\s+os\s+episodios\b');
  static final RegExp _whitespaceRegExp = RegExp(r'\s+');
  static final RegExp _accentCharactersRegExp = RegExp(
    r'[àáâãäåāèéêëēìíîïīòóôõöōùúûüūçñýÿ]',
  );

  static Set<String> keysForTitle(String? title) {
    final normalized = normalize(title);
    if (normalized.isEmpty) return const {};

    final keys = <String>{normalized};
    final compact = normalized.replaceAll(' ', '');
    if (compact != normalized) {
      keys.add(compact);
    }
    return keys;
  }

  static String normalize(String? title) {
    if (title == null) return '';

    var cleaned = title.toLowerCase();
    cleaned = _stripAccents(cleaned);
    cleaned = cleaned.replaceAll('&', ' and ');
    cleaned = cleaned.replaceAll(_accentsRegExp, '');
    cleaned = cleaned.replaceAll(_nonAlphaNumRegExp, ' ');
    cleaned = cleaned.replaceAll(_dubSubRegExp, ' ');
    cleaned = cleaned.replaceAll(_allEpsRegExp, ' ');
    cleaned = cleaned.replaceAll(_whitespaceRegExp, ' ').trim();
    return cleaned;
  }

  static const Map<String, String> _accentMap = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'ā': 'a',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ē': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ī': 'i',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ō': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ū': 'u',
    'ç': 'c',
    'ñ': 'n',
    'ý': 'y',
    'ÿ': 'y',
  };

  static String _stripAccents(String value) {
    return value.replaceAllMapped(_accentCharactersRegExp, (match) {
      final character = match.group(0)!;
      return _accentMap[character] ?? character;
    });
  }
}
