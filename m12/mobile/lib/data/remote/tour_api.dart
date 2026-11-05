import '../../features/tour/tour_models.dart';
import 'api_client.dart';

abstract interface class TourApi {
  Future<TourDefinition> latest();
  Future<TourProgress?> progress(String version);
  Future<void> save({required String version, required String stepId, required TourStatus status});
}

class HttpTourApi implements TourApi {
  HttpTourApi(this._client);

  final ApiClient _client;

  @override
  Future<TourDefinition> latest() async => TourDefinition.fromJson(await _client.get('/product-tour/latest'));

  @override
  Future<TourProgress?> progress(String version) async {
    final body = await _client.get('/product-tour/progress', queryParameters: {'version': version});
    final p = body['progress'] as Map<String, dynamic>?;
    return p == null ? null : TourProgress.fromJson(p);
  }

  @override
  Future<void> save({required String version, required String stepId, required TourStatus status}) =>
      _client.post('/product-tour/progress', data: {'tourVersion': version, 'stepId': stepId, 'status': status.wire});
}
