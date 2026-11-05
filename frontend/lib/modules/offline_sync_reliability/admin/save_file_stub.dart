/// The support console is a web app; native builds don't offer downloads.
Future<bool> saveFile(List<int> bytes, String fileName, String contentType) async => false;
