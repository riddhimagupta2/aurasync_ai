import 'package:flutter_test/flutter_test.dart';
import 'package:aurasync_ai/main.dart';
import 'package:camera/camera.dart';

void main() {
  testWidgets('App should load', (WidgetTester tester) async {
    // Create a fake camera description
    const camera = CameraDescription(
      name: '0',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 0,
    );

    // Build our app and trigger a frame.
    await tester.pumpWidget(AuraSyncApp(cameras: [camera]));
  });
}
