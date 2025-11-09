import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:town_pass/page/game/model/attraction.dart';
import 'package:town_pass/page/game/model/game_question.dart';

class AttractionService {
  AttractionService({http.Client? client}) : _client = client ?? http.Client();

  static const String _endpointBase = 'https://taipei-attractions-information.vercel.app/attractions/random';
  static const int _minAttractions = 5;
  static const int _maxAttempts = 8;

  final http.Client _client;

  Future<GameQuestion> fetchQuestion({required String languageCode}) async {
    int attempt = 0;
    final Uri endpoint = Uri.parse('$_endpointBase/$languageCode');

    while (attempt < _maxAttempts) {
      attempt++;
      try {
        final http.Response response = await _client.get(endpoint);

        if (response.statusCode != 200) {
          if (attempt >= _maxAttempts) {
            throw Exception('取得景點資料失敗 (${response.statusCode})');
          }
          continue;
        }

        final GameQuestion? question = _parseQuestion(response.bodyBytes);
        if (question != null) {
          return question;
        }
      } catch (error) {
        if (attempt >= _maxAttempts) {
          rethrow;
        }
      }
    }

    throw Exception('無法取得足夠的景點資料，請稍後再試');
  }

  GameQuestion? _parseQuestion(List<int> bodyBytes) {
    final String responseBody = utf8.decode(bodyBytes);
    final dynamic jsonBody = jsonDecode(responseBody);
    final List<dynamic> data = (jsonBody is Map<String, dynamic> ? jsonBody['data'] : null) as List<dynamic>? ?? <dynamic>[];

    final List<Attraction> attractions = data
        .whereType<Map<String, dynamic>>()
        .map(Attraction.tryParse)
        .whereType<Attraction>()
        .toList();

    if (attractions.length < _minAttractions) {
      return null;
    }

    attractions.shuffle();
    final Attraction target = attractions.removeAt(0);
    final List<GameOption> options = attractions.take(4).map((attraction) {
      final double distanceScore = _distanceBetweenKm(target, attraction);
      return GameOption(attraction: attraction, distanceScore: distanceScore);
    }).toList();

    if (options.length < 4) {
      return null;
    }

    int correctIndex = 0;
    double bestScore = options.first.distanceScore;
    for (int i = 1; i < options.length; i++) {
      if (options[i].distanceScore < bestScore) {
        bestScore = options[i].distanceScore;
        correctIndex = i;
      }
    }

    return GameQuestion(
      target: target,
      options: options,
      correctIndex: correctIndex,
    );
  }

  double _distanceBetweenKm(Attraction a, Attraction b) {
    const double earthRadiusKm = 6371;
    final double dLat = _degToRad(b.latitude - a.latitude);
    final double dLon = _degToRad(b.longitude - a.longitude);
    final double lat1 = _degToRad(a.latitude);
    final double lat2 = _degToRad(b.latitude);
    final double sinLat = math.sin(dLat / 2);
    final double sinLon = math.sin(dLon / 2);
    final double h = sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLon * sinLon;
    final double c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadiusKm * c;
  }

  double _degToRad(double deg) => deg * math.pi / 180;

  void dispose() {
    _client.close();
  }
}
