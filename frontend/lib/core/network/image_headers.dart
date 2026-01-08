/// Utility helpers for building HTTP headers for protected media requests.
Map<String, String>? buildImageHeaders({
  required String imageUrl,
  required String baseUrl,
  required String? apiToken,
}) {
  if (imageUrl.isEmpty || apiToken == null || apiToken.isEmpty) {
    return null;
  }

  Uri? imageUri;
  Uri? baseUri;
  try {
    imageUri = Uri.parse(imageUrl);
    baseUri = Uri.parse(baseUrl);
  } catch (_) {
    return null;
  }

  if (!_isSameOrigin(imageUri, baseUri)) {
    return null;
  }

  return {'X-API-Token': apiToken};
}

bool _isSameOrigin(Uri a, Uri b) {
  if (a.scheme.isEmpty || b.scheme.isEmpty) {
    return false;
  }

  return a.scheme == b.scheme &&
      a.host == b.host &&
      _resolvePort(a) == _resolvePort(b);
}

int _resolvePort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }

  return uri.scheme == 'https' ? 443 : 80;
}
