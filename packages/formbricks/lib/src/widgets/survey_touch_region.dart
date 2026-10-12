import 'dart:ui';

/// Which pointers over the survey's full-screen WebView belong to the survey,
/// and which should fall through to the host app underneath.
///
/// A platform WebView hit-tests its entire rectangle. The shared renderer sets
/// `pointer-events: none` outside the card, but that is a *web* hit test that
/// Flutter never sees, so a transparent full-screen WebView still swallows
/// every pointer and the host app appears frozen.
///
/// Three states rather than two, because "no rect has arrived" and "the card is
/// not on screen" need opposite answers. Conflating them is what made the card
/// untappable when the old DOM probe stopped matching (ENG-3155): a missing rect
/// was read as "claim nothing", so the survey itself stopped responding.
sealed class SurveyTouchRegion {
  /// Creates a region.
  const SurveyTouchRegion();

  /// Every pointer belongs to the survey.
  ///
  /// Correct for a `light` or `dark` overlay, whose visible backdrop is meant to
  /// block the host app. Also the starting state for a no-overlay survey, and it
  /// stays that way if the renderer never reports a rect — an older self-hosted
  /// server serves a bundle without `onCardRectChange`, and behaving exactly as
  /// the SDK always did is the safe answer there.
  static const SurveyTouchRegion everything = _Everything();

  /// Nothing belongs to the survey, because no card is on screen.
  ///
  /// The renderer reports this while the card animates out, and the card is
  /// hidden for a full second before the close arrives. Without it the SDK
  /// leaves a dead patch over a host app that looks perfectly usable.
  static const SurveyTouchRegion nothing = _Nothing();

  /// Maps a rect reported by the renderer onto a region. A missing rect means
  /// the card is not on screen — never "the feature is absent", which is
  /// [everything].
  static SurveyTouchRegion forReported(Rect? rect) =>
      rect == null ? nothing : SurveyTouchRegion.card(rect);

  /// Only pointers inside [rect] belong to the survey.
  const factory SurveyTouchRegion.card(Rect rect) = _Card;

  /// Whether a pointer at [position] belongs to the survey.
  bool accepts(Offset position);
}

final class _Everything extends SurveyTouchRegion {
  const _Everything();

  @override
  bool accepts(Offset position) => true;
}

final class _Nothing extends SurveyTouchRegion {
  const _Nothing();

  @override
  bool accepts(Offset position) => false;
}

final class _Card extends SurveyTouchRegion {
  const _Card(this.rect);

  final Rect rect;

  @override
  bool accepts(Offset position) => rect.contains(position);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is _Card && other.rect == rect);

  @override
  int get hashCode => rect.hashCode;
}
