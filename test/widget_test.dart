import 'package:boxin/data/supabase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toE164', () {
    test('converts domestic mobile numbers', () {
      expect(toE164('010-1234-5678'), '+821012345678');
      expect(toE164('01012345678'), '+821012345678');
      expect(toE164('+82 10 1234 5678'), '+821012345678');
      expect(toE164('011-234-5678'), '+82112345678');
    });

    test('rejects anything that is not a mobile number', () {
      expect(toE164(''), isNull);
      expect(toE164('02-123-4567'), isNull);
      expect(toE164('010-1234'), isNull);
    });
  });
}
