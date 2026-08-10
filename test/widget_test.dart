// Smoke test: the bootstrap widget renders its loading state without
// crashing before async initialization (settings load, cache DB open,
// storage enumeration) completes. Deeper screen-level tests that don't
// depend on real platform channels live under test/ui/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dupora/main.dart';

void main() {
  testWidgets('DuporaBootstrap shows a loading indicator before init completes', (tester) async {
    await tester.pumpWidget(const DuporaBootstrap());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
