import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;

import '../types/config.dart';
import '../types/errors.dart';
import 'result.dart';

/// Thin wrapper over `package:http` for the two client endpoints the SDK needs.
///
/// Ported from the RN `ApiClient` / `makeRequest` (`lib/common/api.ts`). The
/// `http.Client` is injectable so tests can swap in a mock; no `dio`, to keep
/// the dependency graph minimal.
class ApiClient {
  /// Creates an API client for [appUrl] / [workspaceId].
  ApiClient({
    required this.appUrl,
    required this.workspaceId,
    http.Client? client,
    this.isDebug = false,
  }) : _client = client ?? http.Client();

  /// The base app URL (Formbricks Cloud or self-hosted).
  final String appUrl;

  /// The workspace scope for all requests.
  final String workspaceId;

  /// When true, adds `Cache-Control: no-cache` to every request.
  final bool isDebug;

  final http.Client _client;

  /// Shared request helper: builds headers, performs the call, decodes JSON, and
  /// normalizes failures into an [ApiErrorResponse].
  ///
  /// Error mapping: a thrown transport error (e.g. `SocketException`,
  /// `ClientException`) → `network_error`; a 4xx (incl. 404) or a body
  /// `code: "forbidden"` → `forbidden`; any other non-2xx → `network_error`.
  Future<Result<T, ApiErrorResponse>> _request<T>({
    required String method,
    required String endpoint,
    required T Function(Map<String, dynamic> data) parse,
    Object? body,
  }) async {
    final url = Uri.parse('$appUrl$endpoint');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (isDebug) 'Cache-Control': 'no-cache',
    };

    http.Response response;
    try {
      response = method == 'GET'
          ? await _client.get(url, headers: headers)
          : await _client.post(
              url,
              headers: headers,
              body: body == null ? null : jsonEncode(body),
            );
    } catch (e) {
      return Result.err(
        ApiErrorResponse(
          code: 'network_error',
          status: 500,
          message: 'Something went wrong',
          url: url,
          responseMessage: e.toString(),
        ),
      );
    }

    final status = response.statusCode;
    Map<String, dynamic>? json;
    try {
      json = response.body.isEmpty
          ? null
          : jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      json = null;
    }

    if (status < 200 || status >= 300) {
      final serverCode = json?['code'] as String?;
      final isForbidden =
          serverCode == 'forbidden' || (status >= 400 && status < 500);
      final details = (json?['details'] as Map?)?.cast<String, Object?>();
      return Result.err(
        ApiErrorResponse(
          code: isForbidden ? 'forbidden' : 'network_error',
          status: status,
          message: (json?['message'] as String?) ?? 'Something went wrong',
          url: url,
          responseMessage: json?['message'] as String?,
          details: (details?.isNotEmpty ?? false) ? details : null,
        ),
      );
    }

    final data =
        (json?['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return Result.ok(parse(data));
  }

  /// Fetches workspace state via `GET /api/v2/client/{workspaceId}/environment`.
  ///
  /// Normalizes the legacy field name: the server may return the settings object
  /// under `data.settings` (new), `data.workspace`, or legacy `data.project`.
  /// All three are mapped to `data.settings` (port of `workspace/state.ts`).
  Future<Result<TWorkspaceState, ApiErrorResponse>> getWorkspaceState() {
    return _request<TWorkspaceState>(
      method: 'GET',
      endpoint:
          '/api/v2/client/$workspaceId/environment?rand=${clock.now().millisecondsSinceEpoch}',
      parse: (data) {
        final inner =
            (data['data'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        if (inner['settings'] == null) {
          if (inner['workspace'] != null) {
            inner['settings'] = inner['workspace'];
            inner.remove('workspace');
          } else if (inner['project'] != null) {
            inner['settings'] = inner['project'];
            inner.remove('project');
          }
        }
        return TWorkspaceState.fromJson({
          'expiresAt': data['expiresAt'],
          'data': inner,
        });
      },
    );
  }

  /// Creates or updates a user via `POST /api/v2/client/{workspaceId}/user`.
  ///
  /// Attributes are passed through as-is so `num` types stay numbers (the
  /// backend infers the attribute type from the JSON type). Any `DateTime`
  /// attribute must already be an ISO string before reaching this layer.
  Future<Result<CreateOrUpdateUserResponse, ApiErrorResponse>>
  createOrUpdateUser({
    required String userId,
    Map<String, Object?>? attributes,
  }) {
    return _request<CreateOrUpdateUserResponse>(
      method: 'POST',
      endpoint: '/api/v2/client/$workspaceId/user',
      body: {'userId': userId, 'attributes': ?attributes},
      parse: CreateOrUpdateUserResponse.fromJson,
    );
  }

  /// Closes the underlying HTTP client.
  void close() => _client.close();
}
