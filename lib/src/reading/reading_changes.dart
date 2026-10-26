import 'package:flutter/foundation.dart';

class ReadingChanges extends ChangeNotifier {
  static final _owners = Expando<ReadingChanges>();
  static ReadingChanges forOwner(Object owner) =>
      _owners[owner] ??= ReadingChanges();
  void changed() => notifyListeners();
}
