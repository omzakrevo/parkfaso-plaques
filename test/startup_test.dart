import 'package:flutter_test/flutter_test.dart';
import 'package:parkfaso_plaque/app/app_controller.dart';
import 'package:parkfaso_plaque/main.dart';

void main() {
  testWidgets('démarrage en échec : message + Réessayer, pas de fermeture', (tester) async {
    var attempts = 0;
    Future<AppController> failingInit() async {
      attempts++;
      throw Exception('Base de données inaccessible');
    }

    await tester.pumpWidget(StartupGate(init: failingInit));
    expect(find.text('PARKFASO'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Démarrage impossible'), findsOneWidget);
    expect(find.textContaining('Base de données inaccessible'), findsOneWidget);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Démarrage impossible'), findsOneWidget);
    expect(attempts, 2);
  });
}
