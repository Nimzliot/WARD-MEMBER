import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../services/chat_service.dart';
import 'format.dart';

/// Editable AI summary of resident conversations (what goes into the PDF).
class ChatSummary {
  ChatSummary({
    required this.headline,
    required this.overview,
    required this.issues,
    required this.requests,
    required this.urgent,
    required this.sentiment,
    required this.followUps,
    required this.wardName,
    required this.conversations,
    required this.generatedAt,
  });

  factory ChatSummary.fromMap(Map<String, dynamic> m) {
    List<String> list(String k) => [for (final x in (m[k] as List? ?? const [])) '$x'];
    return ChatSummary(
      headline: m['headline'] as String? ?? '',
      overview: m['overview'] as String? ?? '',
      issues: [
        for (final i in (m['key_issues'] as List? ?? const []))
          '${(i as Map)['issue']} (${i['residents']} resident${i['residents'] == 1 ? '' : 's'})',
      ],
      requests: list('requests'),
      urgent: list('urgent'),
      sentiment: '${m['sentiment'] ?? 'mixed'}: ${m['sentiment_note'] ?? ''}'.trim(),
      followUps: list('follow_ups'),
      wardName: m['ward_name'] as String? ?? '',
      conversations: (m['conversations'] as num?)?.toInt() ?? 0,
      generatedAt: DateTime.tryParse(m['generated_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
    );
  }

  String headline;
  String overview;
  List<String> issues;
  List<String> requests;
  List<String> urgent;
  String sentiment;
  List<String> followUps;
  final String wardName;
  final int conversations;
  final DateTime generatedAt;
}

const _forest = PdfColor.fromInt(0xFF0B5D3B);
const _forestDark = PdfColor.fromInt(0xFF06402A);
const _mint = PdfColor.fromInt(0xFFE8F5EE);
const _muted = PdfColor.fromInt(0xFF5A6E63);
const _red = PdfColor.fromInt(0xFF9B1C1C);

/// Builds the summary PDF (A4) with the app's fonts, optional transcripts.
Future<Uint8List> buildSummaryPdf(
  ChatSummary s, {
  List<({String resident, List<ChatMessage> messages})>? transcripts,
}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-Bold.ttf'));
  final doc = pw.Document(
    title: 'Resident conversations summary · ${s.wardName}',
    author: 'Makkal Budget (Ward Admin + Ward Assistant AI)',
  );

  pw.Widget heading(String t, {PdfColor color = _forestDark}) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(t.toUpperCase(),
            style: pw.TextStyle(font: bold, fontSize: 10, color: color, letterSpacing: 1.1)),
      );
  pw.Widget bullets(List<String> items, {PdfColor dot = _forest}) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final i in items.where((e) => e.trim().isNotEmpty))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Container(
                  width: 5,
                  height: 5,
                  margin: const pw.EdgeInsets.only(top: 5, right: 8),
                  decoration: pw.BoxDecoration(color: dot, shape: pw.BoxShape.circle),
                ),
                pw.Expanded(child: pw.Text(i, style: const pw.TextStyle(fontSize: 11, lineSpacing: 2))),
              ]),
            ),
        ],
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 36),
    header: (ctx) => ctx.pageNumber == 1
        ? pw.SizedBox()
        : pw.Text('Resident conversations · ${s.wardName}', style: const pw.TextStyle(fontSize: 9, color: _muted)),
    footer: (ctx) => pw.Row(children: [
      pw.Expanded(
        child: pw.Text(
          'Makkal Budget · SDG 11 prototype · not an official Government of Tamil Nadu document',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ),
      pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
    ]),
    build: (ctx) => [
      // Tricolour strip + green title band
      pw.Row(children: [
        pw.Expanded(child: pw.Container(height: 4, color: const PdfColor.fromInt(0xFFFF9933))),
        pw.Expanded(child: pw.Container(height: 4, color: PdfColors.white)),
        pw.Expanded(child: pw.Container(height: 4, color: const PdfColor.fromInt(0xFF138808))),
      ]),
      pw.Container(
        padding: const pw.EdgeInsets.all(18),
        decoration: const pw.BoxDecoration(color: _forest),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('TAMIL NADU · PARTICIPATORY BUDGETING',
              style: pw.TextStyle(font: bold, fontSize: 8.5, color: PdfColors.white, letterSpacing: 1.2)),
          pw.SizedBox(height: 6),
          pw.Text('Resident conversations: summary',
              style: pw.TextStyle(font: bold, fontSize: 20, color: PdfColors.white)),
          pw.SizedBox(height: 4),
          pw.Text(
            '${s.wardName} · ${s.conversations} conversation${s.conversations == 1 ? '' : 's'} · ${formatDateTime(s.generatedAt)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
          ),
        ]),
      ),
      pw.SizedBox(height: 10),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(color: _mint, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Text(
          'Drafted by Ward Assistant (AI) from end-to-end encrypted chats decrypted on the Ward Admin\'s phone, '
          'then reviewed and edited by the Ward Admin.',
          style: const pw.TextStyle(fontSize: 9, color: _forestDark),
        ),
      ),
      pw.SizedBox(height: 12),
      pw.Text(s.headline, style: pw.TextStyle(font: bold, fontSize: 16, color: _forestDark)),
      pw.SizedBox(height: 6),
      pw.Text(s.overview, style: const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
      if (s.urgent.any((e) => e.trim().isNotEmpty)) ...[heading('Urgent', color: _red), bullets(s.urgent, dot: _red)],
      if (s.issues.isNotEmpty) ...[heading('Key issues'), bullets(s.issues)],
      if (s.requests.isNotEmpty) ...[heading('Requests'), bullets(s.requests)],
      heading('Mood of residents'),
      pw.Text(s.sentiment, style: const pw.TextStyle(fontSize: 11)),
      if (s.followUps.isNotEmpty) ...[heading('Suggested follow-ups'), bullets(s.followUps)],
      if (transcripts != null && transcripts.isNotEmpty) ...[
        pw.NewPage(),
        pw.Text('Transcripts', style: pw.TextStyle(font: bold, fontSize: 16, color: _forestDark)),
        for (final t in transcripts) ...[
          heading('Conversation with ${t.resident}'),
          for (final m in t.messages.where((m) => m.text != null))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.RichText(
                text: pw.TextSpan(children: [
                  pw.TextSpan(
                    text: '${m.mine ? 'Ward Admin' : t.resident} · ${formatDateTime(m.createdAt)}\n',
                    style: pw.TextStyle(font: bold, fontSize: 8.5, color: _muted),
                  ),
                  pw.TextSpan(text: m.text, style: const pw.TextStyle(fontSize: 10.5)),
                ]),
              ),
            ),
        ],
      ],
    ],
  ));
  return doc.save();
}
