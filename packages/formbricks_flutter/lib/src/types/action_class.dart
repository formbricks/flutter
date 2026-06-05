/// Workspace action-class model, ported from the React Native SDK's
/// `TWorkspaceStateActionClass` (`types/config.ts` / `types/action-class.ts`).
///
/// Only the fields `track` needs are modelled: [type] (we match `'code'`),
/// [key] (the code the host passes), and [name] (used to match survey
/// triggers). [type] stays a plain `String` for forward-compat with any future
/// server-side action-class type.
library;

/// A cached workspace action class.
class TActionClass {
  /// Creates an action class.
  const TActionClass({
    required this.id,
    required this.name,
    required this.type,
    this.key,
  });

  /// Builds a [TActionClass] from decoded JSON.
  factory TActionClass.fromJson(Map<String, dynamic> json) => TActionClass(
        id: json['id'] as String? ?? '',
        name: json['name'] as String,
        type: json['type'] as String? ?? '',
        key: json['key'] as String?,
      );

  /// The action-class id.
  final String id;

  /// The action-class name; survey triggers reference this.
  final String name;

  /// Either `'code'` or `'noCode'`.
  final String type;

  /// The code key for `'code'` actions; null for `'noCode'`.
  final String? key;
}
