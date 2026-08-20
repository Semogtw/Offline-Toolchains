import 'package:flutter_test/flutter_test.dart';
import 'package:goanime_core/goanime_core.dart';

import 'package:goanime/models/unified_anime_model.dart';
import 'package:goanime/services/providers/goyabu_source_provider.dart';
import 'package:goanime/services/video_playback_resolver.dart';

void main() {
  const provider = GoyabuSourceProvider();

  test('propagates Full HD quality from a direct Goyabu media URL', () async {
    final stream = await provider.resolveVideoStream(
      'https://cdn.example.test/anime/episode-1080.mp4',
    );

    expect(stream.qualityLabel, '1080p');
  });

  test('infers Full HD from a GoogleVideo itag used by Goyabu', () async {
    final stream = await provider.resolveVideoStream(
      'https://redirector.googlevideo.com/videoplayback?id=fixture&itag=37',
    );

    expect(stream.qualityLabel, '1080p');
    expect(stream.isGoogleVideo, isTrue);
  });

  test('infers quality from explicit stream query metadata', () async {
    final stream = await provider.resolveVideoStream(
      'https://cdn.example.test/anime/episode.mp4?quality=1920x1080',
    );

    expect(stream.qualityLabel, '1080p');
  });

  test(
    'keeps opaque direct streams unknown instead of inventing quality',
    () async {
      final stream = await provider.resolveVideoStream(
        'https://cdn.example.test/anime/episode.mp4?token=fixture',
      );

      expect(stream.qualityLabel, isNull);
    },
  );

  test('Goyabu inferred 1080p outranks a resolved 720p provider', () async {
    final goyabuStream = await provider.resolveVideoStream(
      'https://cdn.example.test/anime/episode-1080.mp4',
    );
    final goyabu = PlaybackResolution(
      provider: EpisodeProvider(
        source: AnimeSource.goyabu,
        url: 'https://goyabu.io/?p=100',
      ),
      stream: goyabuStream,
      embedUrl: goyabuStream.url,
      playbackHeaders: goyabuStream.headers,
    );
    final animeFire720 = PlaybackResolution(
      provider: EpisodeProvider(
        source: AnimeSource.animeFire,
        url: 'https://animefire.io/episodio/1',
      ),
      stream: VideoStreamResult(
        url: 'https://cdn.example.test/animefire/episode.mp4',
        qualityLabel: '720p',
      ),
      embedUrl: 'https://animefire.io/video/1',
      playbackHeaders: const {},
    );

    final sorted = VideoPlaybackResolver.debugSortByPlaybackQuality([
      animeFire720,
      goyabu,
    ]);

    expect(sorted.first, same(goyabu));
  });
}
