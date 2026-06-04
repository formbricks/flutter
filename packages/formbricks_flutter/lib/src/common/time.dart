import 'package:clock/clock.dart';

/// Whether [expiresAt] is at or before "now".
///
/// Mirrors the RN SDK's `isNowExpired` (`now >= expirationDate`). Reads the
/// current time via `clock.now()` so expiry logic is deterministic under test
/// (`withClock(...)`).
bool isNowExpired(DateTime expiresAt) => !clock.now().isBefore(expiresAt);
