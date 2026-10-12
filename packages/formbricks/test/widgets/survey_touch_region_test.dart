import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/src/widgets/survey_touch_region.dart';

/// A transparent full-screen WebView still swallows every pointer —
/// `pointer-events: none` is a web hit test Flutter never sees. These pin which
/// pointers the survey claims in each state, because getting it wrong is
/// invisible in review and obvious to a user: either the host app freezes, or
/// the survey itself stops responding.
void main() {
  const card = Rect.fromLTWH(0, 600, 390, 240);
  const insideCard = Offset(195, 700);
  const outsideCard = Offset(195, 200);

  group('SurveyTouchRegion', () {
    test('an overlaid survey claims every pointer', () {
      // A visible backdrop is meant to block the host app.
      expect(SurveyTouchRegion.everything.accepts(insideCard), isTrue);
      expect(SurveyTouchRegion.everything.accepts(outsideCard), isTrue);
      expect(SurveyTouchRegion.everything.accepts(Offset.zero), isTrue);
    });

    test('a reported rect claims only the card', () {
      final region = SurveyTouchRegion.forReported(card);

      expect(region, const SurveyTouchRegion.card(card));
      expect(
        region.accepts(insideCard),
        isTrue,
        reason: 'the survey must stay usable',
      );
      expect(
        region.accepts(outsideCard),
        isFalse,
        reason: 'the host app must stay usable',
      );
    });

    test('no card on screen claims nothing', () {
      final region = SurveyTouchRegion.forReported(null);

      expect(region, same(SurveyTouchRegion.nothing));
      expect(region.accepts(insideCard), isFalse);
      expect(region.accepts(outsideCard), isFalse);
    });

    test('the state before any rect arrives blocks, as the SDK always did', () {
      // An older self-hosted server serves a renderer that never calls
      // `onCardRectChange`, so no rect ever arrives. Absence of a card and
      // absence of the feature are different things: conflating them is what
      // made the card untappable when the old DOM probe stopped matching.
      expect(SurveyTouchRegion.everything.accepts(outsideCard), isTrue);
      expect(
        SurveyTouchRegion.forReported(null),
        isNot(same(SurveyTouchRegion.everything)),
      );
    });

    test('card edges follow Rect.contains', () {
      // Rect.contains excludes the far edges, so the bottom-right corner belongs
      // to the host app. Pinned because a later inset or rounding change would
      // move this silently.
      const region = SurveyTouchRegion.card(card);

      expect(region.accepts(card.topLeft), isTrue);
      expect(region.accepts(card.bottomRight), isFalse);
      expect(region.accepts(card.topLeft - const Offset(1, 0)), isFalse);
    });

    test('a zero-area card claims nothing', () {
      const region = SurveyTouchRegion.card(Rect.fromLTWH(10, 10, 0, 0));

      expect(region.accepts(const Offset(10, 10)), isFalse);
    });
  });
}
