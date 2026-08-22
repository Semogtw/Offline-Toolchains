import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const Curve _premiumOut = Cubic(0.16, 1, 0.3, 1);
const Curve _premiumIn = Cubic(0.7, 0, 0.84, 0);
const Color _brandOrange = Color(0xFFFF5A00);
const Color _brandOrangeLight = Color(0xFFFF9A58);
const AssetImage _openingLogo = AssetImage('web/icons/Icon-512.png');

double _phase(double progress, double begin, double end, Curve curve) {
  return curve.transform(
    ((progress - begin) / (end - begin)).clamp(0.0, 1.0).toDouble(),
  );
}

/// Short, non-blocking brand opening shown over an already-built application.
///
/// The real application remains mounted underneath from the first Flutter frame.
/// The opening is skipped when reduced motion is requested and, by default, only
/// plays once per Dart process so activity/widget recreation does not replay a
/// long brand sequence.
class GoAnimeOpening extends StatefulWidget {
  const GoAnimeOpening({
    required this.child,
    this.duration = const Duration(milliseconds: 1320),
    this.playOncePerProcess = true,
    super.key,
  });

  static const openingOverlayKey = Key('goanime_opening_overlay');
  static bool _hasPlayedInProcess = false;

  final Widget child;
  final Duration duration;
  final bool playOncePerProcess;

  @visibleForTesting
  static void resetSessionForTesting() {
    _hasPlayedInProcess = false;
  }

  @override
  State<GoAnimeOpening> createState() => _GoAnimeOpeningState();
}

class _GoAnimeOpeningState extends State<GoAnimeOpening>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (widget.playOncePerProcess && GoAnimeOpening._hasPlayedInProcess) {
      _visible = false;
      return;
    }

    if (widget.playOncePerProcess) {
      GoAnimeOpening._hasPlayedInProcess = true;
    }

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _visible = false;
      return;
    }

    // Warm the local logo before the first animated tick. The first Flutter
    // frame stays visually aligned with the native splash while this happens.
    unawaited(precacheImage(_openingLogo, context));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_visible) return;
      unawaited(
        _controller.forward().whenComplete(() {
          if (!mounted) return;
          setState(() => _visible = false);
        }),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep this structural wrapper after the opening disappears. The Navigator
    // never changes parent, preserving its element/state identity exactly.
    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !_visible,
          child: ExcludeFocus(
            excluding: _visible,
            child: ExcludeSemantics(
              excluding: _visible,
              child: RepaintBoundary(child: widget.child),
            ),
          ),
        ),
        if (_visible)
          Positioned.fill(
            child: ExcludeSemantics(
              child: AbsorbPointer(
                child: RepaintBoundary(
                  child: _OpeningFrame(
                    key: GoAnimeOpening.openingOverlayKey,
                    animation: _controller,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _OpeningFrame extends StatelessWidget {
  const _OpeningFrame({required this.animation, super.key});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _OpeningBackdropPainter(animation: animation)),
        SafeArea(
          child: Center(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  return _OpeningBrandCluster(progress: animation.value);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OpeningBrandCluster extends StatelessWidget {
  const _OpeningBrandCluster({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final markIn = _phase(progress, 0.02, 0.30, _premiumOut);
    final wordIn = _phase(progress, 0.25, 0.52, _premiumOut);
    final accentIn = _phase(progress, 0.38, 0.60, _premiumOut);
    final subtitleIn = _phase(progress, 0.46, 0.66, _premiumOut);
    final exit = _phase(progress, 0.79, 1.0, _premiumIn);
    final brandOpacity = 1 - exit;

    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final responsiveScale = (shortestSide / 390).clamp(0.90, 1.14).toDouble();
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final logoCacheWidth = (82 * responsiveScale * devicePixelRatio)
        .round()
        .clamp(128, 512)
        .toInt();

    final entranceScale = 0.965 + (0.035 * markIn);
    final exitScale = 1 + (0.018 * exit);
    final translateY = (7 * (1 - markIn)) - (4 * exit);

    return Opacity(
      opacity: brandOpacity,
      child: Transform.translate(
        offset: Offset(0, translateY),
        child: Transform.scale(
          scale: responsiveScale * entranceScale * exitScale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 148,
                child: CustomPaint(
                  painter: _OpeningMarkPainter(progress: progress),
                  child: Center(
                    child: Transform.scale(
                      scale: 0.90 + (0.10 * markIn),
                      child: Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: 0.045 + (0.04 * markIn),
                            ),
                            width: 0.7,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _brandOrange.withValues(
                                alpha: 0.08 + (0.20 * markIn),
                              ),
                              blurRadius: 34,
                              spreadRadius: 1.5,
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.50),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CustomPaint(
                            foregroundPainter: _LogoSheenPainter(
                              progress: progress,
                            ),
                            child: Image.asset(
                              _openingLogo.assetName,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                              gaplessPlayback: true,
                              cacheWidth: logoCacheWidth,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 246,
                height: 42,
                child: Opacity(
                  opacity: wordIn,
                  child: Transform.translate(
                    offset: Offset(8 * (1 - wordIn), 0),
                    child: ClipRect(
                      child: Align(
                        widthFactor: math.max(wordIn, 0.001),
                        alignment: Alignment.centerLeft,
                        child: const _OpeningWordmark(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Opacity(
                opacity: accentIn * 0.78,
                child: Container(
                  width: 92 * accentIn,
                  height: 1,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        _brandOrange,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Opacity(
                opacity: subtitleIn * 0.66,
                child: Transform.translate(
                  offset: Offset(0, 4 * (1 - subtitleIn)),
                  child: Text(
                    'ANIME  •  MANGA',
                    textAlign: TextAlign.center,
                    style:
                        (Theme.of(context).textTheme.labelSmall ??
                                const TextStyle())
                            .copyWith(
                              color: const Color(0xFFD1D1D1),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3.0,
                              height: 1,
                            ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpeningWordmark extends StatelessWidget {
  const _OpeningWordmark();

  @override
  Widget build(BuildContext context) {
    final style =
        (Theme.of(context).textTheme.headlineLarge ?? const TextStyle())
            .copyWith(
              fontSize: 34,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            );

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text.rich(
        const TextSpan(
          children: [
            TextSpan(
              text: 'GO',
              style: TextStyle(color: Colors.white),
            ),
            TextSpan(
              text: 'ANIME',
              style: TextStyle(color: _brandOrange),
            ),
          ],
        ),
        maxLines: 1,
        style: style,
      ),
    );
  }
}

class _OpeningMarkPainter extends CustomPainter {
  const _OpeningMarkPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final sweep = _phase(progress, 0.0, 0.38, _premiumOut);
    final secondary = _phase(progress, 0.11, 0.44, _premiumOut);
    final settle = _phase(progress, 0.42, 0.70, _premiumOut);
    final fade = 1 - _phase(progress, 0.72, 0.94, _premiumIn);

    final primaryRect = Rect.fromCircle(
      center: center,
      radius: 55 + (settle * 6),
    );
    final primaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.8 - (settle * 1.7)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..shader = SweepGradient(
        colors: [
          _brandOrange.withValues(alpha: 0.72 * fade),
          _brandOrangeLight.withValues(alpha: fade),
          _brandOrange.withValues(alpha: 0.94 * fade),
        ],
        stops: const [0, 0.55, 1],
        transform: GradientRotation((-0.18 + (progress * 0.08)) * math.pi),
      ).createShader(primaryRect);

    canvas.drawArc(
      primaryRect,
      -math.pi * 0.67,
      math.pi * 1.82 * sweep,
      false,
      primaryPaint,
    );

    final secondaryRect = Rect.fromCircle(center: center, radius: 65);
    final secondaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = Colors.white.withValues(alpha: 0.48 * secondary * fade);
    canvas.drawArc(
      secondaryRect,
      math.pi * 0.38,
      -math.pi * 1.12 * secondary,
      false,
      secondaryPaint,
    );

    if (sweep > 0.02 && sweep < 0.99) {
      final angle = -math.pi * 0.67 + (math.pi * 1.82 * sweep);
      final radius = primaryRect.width / 2;
      final dot = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawCircle(
        dot,
        4.2,
        Paint()
          ..isAntiAlias = true
          ..color = _brandOrangeLight.withValues(alpha: 0.82 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        dot,
        1.9,
        Paint()
          ..isAntiAlias = true
          ..color = Colors.white.withValues(alpha: 0.94 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OpeningMarkPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _LogoSheenPainter extends CustomPainter {
  const _LogoSheenPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final travel = _phase(progress, 0.42, 0.70, _premiumOut);
    if (travel <= 0 || travel >= 1) return;

    final bandWidth = size.width * 0.48;
    final left =
        (-bandWidth * 1.2) + ((size.width + (bandWidth * 2.4)) * travel);
    final bandRect = Rect.fromLTWH(
      left,
      -size.height * 0.25,
      bandWidth,
      size.height * 1.5,
    );

    final paint = Paint()
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.02),
          Colors.white.withValues(alpha: 0.24),
          _brandOrangeLight.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0, 0.32, 0.50, 0.62, 1],
      ).createShader(bandRect);
    canvas.drawRect(bandRect, paint);
  }

  @override
  bool shouldRepaint(covariant _LogoSheenPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _OpeningBackdropPainter extends CustomPainter {
  _OpeningBackdropPainter({required this.animation})
    : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = animation.value;
    final reveal = _phase(progress, 0.03, 0.44, _premiumOut);
    final exit = _phase(progress, 0.78, 1.0, _premiumIn);
    final sceneOpacity = 1 - exit;
    final bounds = Offset.zero & size;

    canvas.drawRect(
      bounds,
      Paint()..color = Colors.black.withValues(alpha: sceneOpacity),
    );

    final ambientGlow = RadialGradient(
      center: const Alignment(0, -0.06),
      radius: 0.78 + (reveal * 0.12),
      colors: [
        const Color(0xFF351204).withValues(alpha: 0.74 * sceneOpacity),
        const Color(0xFF120703).withValues(alpha: 0.62 * sceneOpacity),
        Colors.transparent,
      ],
      stops: const [0, 0.43, 1],
    ).createShader(bounds);
    canvas.drawRect(bounds, Paint()..shader = ambientGlow);

    final center = size.center(Offset.zero);
    final shortest = math.min(size.width, size.height);
    final detailAlpha = reveal * sceneOpacity;

    final linePaint = Paint()
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (var i = 0; i < 10; i++) {
      final direction = i.isEven ? 1.0 : -1.0;
      final angle = (-1.16 + (i * 0.255)) + (progress * 0.055 * direction);
      final inner = shortest * (0.20 + ((i % 3) * 0.024));
      final outer = inner + shortest * (0.075 + ((i % 2) * 0.022)) * reveal;
      final start = Offset(
        center.dx + math.cos(angle) * inner,
        center.dy + math.sin(angle) * inner,
      );
      final end = Offset(
        center.dx + math.cos(angle) * outer,
        center.dy + math.sin(angle) * outer,
      );
      linePaint
        ..strokeWidth = i.isEven ? 1.05 : 0.65
        ..color = (i % 3 == 0 ? _brandOrange : Colors.white).withValues(
          alpha: detailAlpha * (i % 3 == 0 ? 0.13 : 0.045),
        );
      canvas.drawLine(start, end, linePaint);
    }

    final particlePaint = Paint()..isAntiAlias = true;
    for (var i = 0; i < 8; i++) {
      final angle = -1.35 + (i * 0.41) + (progress * (i.isEven ? 0.06 : -0.04));
      final distance =
          shortest *
          (0.18 + ((i % 4) * 0.035) + (reveal * (0.018 + i * 0.0015)));
      final point = Offset(
        center.dx + math.cos(angle) * distance,
        center.dy + math.sin(angle) * distance,
      );
      final isWarm = i % 3 == 0;
      particlePaint.color = (isWarm ? _brandOrangeLight : Colors.white)
          .withValues(alpha: detailAlpha * (isWarm ? 0.18 : 0.075));
      canvas.drawCircle(point, isWarm ? 1.15 : 0.72, particlePaint);
    }

    canvas.drawCircle(
      center,
      shortest * (0.30 + (progress * 0.018)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.65
        ..isAntiAlias = true
        ..color = _brandOrange.withValues(alpha: detailAlpha * 0.07),
    );

    final vignette = RadialGradient(
      radius: 0.92,
      colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.38 * sceneOpacity),
      ],
      stops: const [0.55, 1],
    ).createShader(bounds);
    canvas.drawRect(bounds, Paint()..shader = vignette);
  }

  @override
  bool shouldRepaint(covariant _OpeningBackdropPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}
