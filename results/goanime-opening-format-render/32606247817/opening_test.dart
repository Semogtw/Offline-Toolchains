import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/widgets/goanime_opening.dart';

void main() {
  setUp(GoAnimeOpening.resetSessionForTesting);

  testWidgets('opening keeps app mounted underneath and removes itself', (
    tester,
  ) async {
    const childKey = Key('loaded_app');

    await tester.pumpWidget(
      const MaterialApp(
        home: GoAnimeOpening(
          duration: Duration(milliseconds: 100),
          playOncePerProcess: false,
          child: SizedBox(key: childKey),
        ),
      ),
    );

    expect(find.byKey(childKey), findsOneWidget);
    expect(find.byKey(GoAnimeOpening.openingOverlayKey), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();

    expect(find.byKey(childKey), findsOneWidget);
    expect(find.byKey(GoAnimeOpening.openingOverlayKey), findsNothing);
  });

  testWidgets('opening preserves state identity when overlay disappears', (
    tester,
  ) async {
    var initCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: GoAnimeOpening(
          duration: const Duration(milliseconds: 100),
          playOncePerProcess: false,
          child: _StateProbe(onInit: () => initCount += 1),
        ),
      ),
    );

    expect(initCount, 1);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();

    expect(find.byType(_StateProbe), findsOneWidget);
    expect(initCount, 1);
  });

  testWidgets('opening absorbs input until the reveal finishes', (
    tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: GoAnimeOpening(
          duration: const Duration(milliseconds: 100),
          playOncePerProcess: false,
          child: Center(
            child: FilledButton(
              onPressed: () => tapCount += 1,
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'), warnIfMissed: false);
    expect(tapCount, 0);

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    await tester.tap(find.text('Open'));

    expect(tapCount, 1);
  });

  testWidgets('opening hides underlying semantics until reveal finishes', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    addTearDown(semanticsHandle.dispose);

    await tester.pumpWidget(
      const MaterialApp(
        home: GoAnimeOpening(
          duration: Duration(milliseconds: 100),
          playOncePerProcess: false,
          child: Semantics(label: 'Ready app', child: SizedBox.expand()),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Ready app'), findsNothing);

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();

    expect(find.bySemanticsLabel('Ready app'), findsOneWidget);
  });

  testWidgets('opening pauses underlying tickers until reveal finishes', (
    tester,
  ) async {
    bool? tickersEnabled;

    await tester.pumpWidget(
      MaterialApp(
        home: GoAnimeOpening(
          duration: const Duration(milliseconds: 100),
          playOncePerProcess: false,
          child: Builder(
            builder: (context) {
              tickersEnabled = TickerMode.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    expect(tickersEnabled, isFalse);

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();

    expect(tickersEnabled, isTrue);
  });

  testWidgets('opening is skipped when reduced motion is requested', (
    tester,
  ) async {
    const childKey = Key('reduced_motion_app');

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: GoAnimeOpening(
            playOncePerProcess: false,
            child: SizedBox(key: childKey),
          ),
        ),
      ),
    );

    expect(find.byKey(childKey), findsOneWidget);
    expect(find.byKey(GoAnimeOpening.openingOverlayKey), findsNothing);
  });

  testWidgets('opening only plays once per process by default', (tester) async {
    const child = SizedBox(key: Key('session_app'));

    await tester.pumpWidget(
      const MaterialApp(
        home: GoAnimeOpening(
          duration: Duration(milliseconds: 50),
          child: child,
        ),
      ),
    );
    expect(find.byKey(GoAnimeOpening.openingOverlayKey), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 70));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      const MaterialApp(
        home: GoAnimeOpening(
          duration: Duration(milliseconds: 50),
          child: child,
        ),
      ),
    );

    expect(find.byKey(GoAnimeOpening.openingOverlayKey), findsNothing);
    expect(find.byKey(const Key('session_app')), findsOneWidget);
  });
}

class _StateProbe extends StatefulWidget {
  const _StateProbe({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
