import 'package:flutter_test/flutter_test.dart';
import 'package:smart_books/core/config/pdf_upload_config.dart';

void main() {
  test('maxCloudMegabytes por defecto 500', () {
    expect(PdfUploadConfig.maxCloudMegabytes, 500);
    expect(PdfUploadConfig.maxCloudBytes, 500 * 1024 * 1024);
  });
}
