import 'package:flutter_test/flutter_test.dart';
import 'package:status_saver/models/status_item.dart';

void main() {
  test('StatusItem parses native map', () {
    final item = StatusItem.fromMap({
      'uri': 'content://x/1.mp4',
      'name': '1.mp4',
      'isVideo': true,
      'lastModified': 0,
    });
    expect(item.isVideo, isTrue);
    expect(item.heroTag, 'status-content://x/1.mp4');
  });
}
