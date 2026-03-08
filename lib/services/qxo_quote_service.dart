import 'package:cloud_functions/cloud_functions.dart';

class QxoQuoteService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<Map<String, dynamic>> submitQuote({
    required String projectName,
    required List<Map<String, dynamic>> items,
  }) async {
    final result = await _functions
        .httpsCallable('submitQxoQuote')
        .call({
          'projectName': projectName,
          'items': items,
        });
    return Map<String, dynamic>.from(result.data);
  }
}
