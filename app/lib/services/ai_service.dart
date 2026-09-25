import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Languages the Ward Assistant writes in.
enum AiLang {
  en('en', 'EN', 'English'),
  ta('ta', 'தமிழ்', 'Tamil'),
  hi('hi', 'हिंदी', 'Hindi');

  const AiLang(this.code, this.short, this.label);
  final String code;
  final String short;
  final String label;
}

/// App-wide language choice for AI answers (remembered while the app runs).
final aiLanguage = ValueNotifier<AiLang>(AiLang.en);

class ProposalExplanation {
  final String summary;
  final List<String> whoBenefits;
  final String whyThisCost;
  final String tradeoff;
  final List<({String label, String value})> keyNumbers;

  ProposalExplanation.fromMap(Map<String, dynamic> m)
      : summary = m['summary'] as String? ?? '',
        whoBenefits = List<String>.from(m['who_benefits'] as List? ?? const []),
        whyThisCost = m['why_this_cost'] as String? ?? '',
        tradeoff = m['tradeoff'] as String? ?? '',
        keyNumbers = [
          for (final k in (m['key_numbers'] as List? ?? const []))
            (label: '${(k as Map)['label']}', value: '${k['value']}'),
        ];
}

class ResultsInsight {
  final String? headline;
  final String? summary;
  final List<String> highlights;

  ResultsInsight.fromMap(Map<String, dynamic> m)
      : headline = m['headline'] as String?,
        summary = m['summary'] as String?,
        highlights = List<String>.from(m['highlights'] as List? ?? const []);

  bool get isEmpty => headline == null && summary == null;
}

class ProposalDraft {
  final String title;
  final String category;
  final String description;
  final List<({String label, int amount})> items;

  ProposalDraft.fromMap(Map<String, dynamic> m)
      : title = m['title'] as String? ?? '',
        category = m['category'] as String? ?? '',
        description = m['description'] as String? ?? '',
        items = [
          for (final i in (m['items'] as List? ?? const []))
            (label: '${(i as Map)['label']}', amount: (i['amount'] as num).toInt()),
        ];
}

class ChatTurn {
  ChatTurn(this.fromUser, this.text);
  final bool fromUser;
  final String text;
}

/// Ward Assistant — Gemini via the Node API (the key never ships in the app).
class AiService {
  static Future<ProposalExplanation> explain(String proposalId, AiLang lang) async =>
      ProposalExplanation.fromMap(
          await ApiService.post('/api/ai/explain', {'proposalId': proposalId, 'lang': lang.code}));

  /// About one proposal ([proposalId]) or, without it, the resident's whole ward.
  static Future<String> ask(String question, List<ChatTurn> history, {String? proposalId}) async {
    final res = await ApiService.post('/api/ai/ask', {
      'proposalId': ?proposalId,
      'question': question,
      'history': [
        for (final t in history) {'role': t.fromUser ? 'user' : 'assistant', 'text': t.text},
      ],
    });
    return res['answer'] as String? ?? '';
  }

  static Future<ProposalDraft> draft(String idea, int wardId) async =>
      ProposalDraft.fromMap(await ApiService.post('/api/ai/draft', {'idea': idea, 'wardId': wardId}));

  static Future<ResultsInsight> insight(int wardId, AiLang lang) async =>
      ResultsInsight.fromMap(await ApiService.post('/api/ai/insight', {'wardId': wardId, 'lang': lang.code}));
}
