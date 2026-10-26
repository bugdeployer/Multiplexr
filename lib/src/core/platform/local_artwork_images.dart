import 'dart:io';

import 'package:flutter/painting.dart';

/// The host elects which local cache references its rendering tree may open.
ImageProvider<Object>? localArtworkImage(String path) {
  if (path.isEmpty || path.contains('://')) return null;
  return FileImage(File(path));
}
