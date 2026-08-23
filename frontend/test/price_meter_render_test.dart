import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cropsphere_app/widgets/price_comparison_card.dart';
import 'package:cropsphere_app/models/api_models.dart';

// Renders the real card with a stubbed result so the meter geometry is
// exercised at the widths and languages it actually ships to.
Widget harness(double width, Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  // Widths: smallest supported phone -> tablet column cap.
  const widths = [300.0, 340.0, 420.0, 560.0, 640.0];
  const langs = ['en', 'si', 'ta'];

  for (final w in widths) {
    for (final lang in langs) {
      testWidgets('meter renders without overflow @${w}px lang=$lang', (
        tester,
      ) async {
        await tester.pumpWidget(
          harness(
            w,
            PriceComparisonCardView(
              result: PriceResponse(
                crop: 'Green gram',
                district: 'Batticaloa',
                predictedFarmgatePriceLkrKg: 32,
                predictedRetailPriceLkrKg: 48,
                averageFarmgatePriceLkrKg: 224.09,
                averagePriceSource: AveragePriceSource.real,
                confidence: 'medium',
              ),
              langKey: lang,
              onSeeFull: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('price above average still fits', (tester) async {
    await tester.pumpWidget(
      harness(
        300,
        PriceComparisonCardView(
          result: PriceResponse(
            crop: 'Carrot',
            district: 'Jaffna',
            predictedFarmgatePriceLkrKg: 320,
            predictedRetailPriceLkrKg: 400,
            averageFarmgatePriceLkrKg: 224.09,
            averagePriceSource: AveragePriceSource.synthetic,
            confidence: 'medium',
          ),
          langKey: 'si',
          onSeeFull: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
