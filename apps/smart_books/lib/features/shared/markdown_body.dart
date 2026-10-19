import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_tokens.dart';

class SmartMarkdown extends StatelessWidget {
  const SmartMarkdown({super.key, required this.data, this.compact = false});

  final String data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final body = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final sans = GoogleFonts.sourceSans3;
    final sheet = md.MarkdownStyleSheet(
      p: body.copyWith(fontSize: compact ? 14 : 15, height: 1.48),
      h2: sans(
        fontSize: compact ? 16 : 17,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.02,
        height: 1.25,
      ),
      h3: sans(
        fontSize: compact ? 15 : 16,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      listBullet: body.copyWith(fontSize: compact ? 14 : 15),
      strong: body.copyWith(fontWeight: FontWeight.w700),
      blockquote: body.copyWith(
        fontStyle: FontStyle.italic,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppTokens.purple, width: 3)),
      ),
      code: sans(
        fontSize: 13,
        backgroundColor: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
      ),
    );

    return md.MarkdownBody(data: data, shrinkWrap: true, styleSheet: sheet);
  }
}
