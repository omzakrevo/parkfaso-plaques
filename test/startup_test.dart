import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkfaso_plaque/main.dart';

void main() {
  testWidgets('démarrage en échec : message + Réessayer, pas de fermeture', (tester) async {
    // En test, la base sqflite native n'existe pas : le démarrage échoue
    // exactement comme une erreur réelle sur téléphone.
    await tester.pumpWidget(const ParkfasoApp(home: StartupGate()));
    expect(find.text('PARKFASO'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Démarrage impossible'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Démarrage impossible'), findsOneWidget);
  });
}
