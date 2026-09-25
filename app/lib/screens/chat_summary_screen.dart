import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/chat_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/summary_pdf.dart';
import '../widgets/ai_widgets.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/failure_view.dart';

/// Ward Admin: AI summary of decrypted conversations → edit → download PDF.
class ChatSummaryScreen extends StatefulWidget {
  const ChatSummaryScreen({super.key, required this.conversations});

  final List<({String resident, List<ChatMessage> messages})> conversations;

  @override
  State<ChatSummaryScreen> createState() => _ChatSummaryScreenState();
}

class _ChatSummaryScreenState extends State<ChatSummaryScreen> {
  ChatSummary? _summary;
  Object? _error;
  bool _includeTranscript = false;
  bool _exporting = false;

  final _headline = TextEditingController();
  final _overview = TextEditingController();
  final _issues = TextEditingController();
  final _requests = TextEditingController();
  final _urgent = TextEditingController();
  final _sentiment = TextEditingController();
  final _followUps = TextEditingController();

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    for (final c in [_headline, _overview, _issues, _requests, _urgent, _sentiment, _followUps]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _summary = null;
      _error = null;
    });
    try {
      final s = ChatSummary.fromMap(await ChatService.summarize(widget.conversations));
      if (!mounted) return;
      _headline.text = s.headline;
      _overview.text = s.overview;
      _issues.text = s.issues.join('\n');
      _requests.text = s.requests.join('\n');
      _urgent.text = s.urgent.join('\n');
      _sentiment.text = s.sentiment;
      _followUps.text = s.followUps.join('\n');
      setState(() => _summary = s);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<String> _lines(TextEditingController c) =>
      c.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  Future<void> _downloadPdf() async {
    final s = _summary!
      ..headline = _headline.text.trim()
      ..overview = _overview.text.trim()
      ..issues = _lines(_issues)
      ..requests = _lines(_requests)
      ..urgent = _lines(_urgent)
      ..sentiment = _sentiment.text.trim()
      ..followUps = _lines(_followUps);
    setState(() => _exporting = true);
    try {
      final bytes = await buildSummaryPdf(s, transcripts: _includeTranscript ? widget.conversations : null);
      final stamp = s.generatedAt.toIso8601String().substring(0, 10);
      // Android: share sheet (save to Files / Drive / WhatsApp). Web: downloads the file.
      await Printing.sharePdf(bytes: bytes, filename: 'resident-summary-$stamp.pdf');
    } catch (e) {
      if (mounted) await showFailure(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _field(String label, TextEditingController c, {int lines = 2, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines + 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, helperText: hint, alignLabelWithHint: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final count = widget.conversations.length;
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        BrandHeader(
          showBack: true,
          title: 'AI summary',
          subtitle: '$count conversation${count == 1 ? '' : 's'} · review before downloading',
          bottomPadding: 18,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: _error != null
              ? SizedBox(height: 520, child: ErrorView(error: _error, onRetry: _generate))
              : _summary == null
                  ? const AiPanel(child: AiShimmer(lines: 6, label: 'Reading the conversations…'))
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const MessageBanner(
                        'Drafted by Ward Assistant from the chats decrypted on this phone. Nothing was stored on the server. '
                        'Edit anything before you download.',
                        isError: false,
                      ),
                      const SizedBox(height: 16),
                      _field('Headline', _headline, lines: 1),
                      _field('Overview', _overview, lines: 3),
                      _field('Urgent', _urgent, hint: 'One per line · leave empty if none'),
                      _field('Key issues', _issues, lines: 3, hint: 'One per line'),
                      _field('Requests', _requests, lines: 3, hint: 'One per line'),
                      _field('Mood of residents', _sentiment, lines: 1),
                      _field('Suggested follow-ups', _followUps, lines: 3, hint: 'One per line'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _includeTranscript,
                        onChanged: (v) => setState(() => _includeTranscript = v),
                        title: const Text('Include full transcripts', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Adds every decrypted message to the PDF. Share it carefully.'),
                      ),
                      const SizedBox(height: 8),
                      PrimaryButton(
                        label: 'Download PDF',
                        icon: Icons.picture_as_pdf_rounded,
                        loading: _exporting,
                        onPressed: _downloadPdf,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _generate,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Generate again'),
                      ),
                      Text('Generated ${formatDateTime(_summary!.generatedAt)}',
                          textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
                    ]),
        ),
      ]),
    );
  }
}
