import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/features/shared/markdown_body.dart';

void main() {
  testWidgets('SmartMarkdown renderiza encabezados y listas', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmartMarkdown(data: '## Idea principal\n\n1. Punto **clave**'),
        ),
      ),
    );
    expect(find.textContaining('Idea principal'), findsOneWidget);
    expect(find.textContaining('Punto'), findsOneWidget);
  });
}
