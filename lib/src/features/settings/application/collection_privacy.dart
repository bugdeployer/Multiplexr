abstract interface class CollectionPrivacy {
  Future<void> collectionPrivacy(bool enabled);
  Future<bool> authenticate();
}
