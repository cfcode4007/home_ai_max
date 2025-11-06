import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';

class DeviceUtils {
  final VolumeController _volumeController = VolumeController.instance;
  final ScreenBrightness _screenBrightness = ScreenBrightness.instance;

  Future<void> init() async {
    // VolumeController.instance doesn't need explicit init
  }

  // Volume methods
  Future<double> getVolume() async {
    return await _volumeController.getVolume();
  }

  Future<void> setVolume(double volume) async {
    await _volumeController.setVolume(volume.clamp(0.0, 1.0));
  }

  Future<void> volumeUp() async {
    double current = await _volumeController.getVolume();
    double newVol = (current + 0.1).clamp(0.0, 1.0);
    await _volumeController.setVolume(newVol);
  }

  Future<void> volumeDown() async {
    double current = await _volumeController.getVolume();
    double newVol = (current - 0.1).clamp(0.0, 1.0);
    await _volumeController.setVolume(newVol);
  }

  // Brightness methods
  Future<double> getBrightness() async {
    return await ScreenBrightness.instance.current;
  }

  Future<void> setBrightness(double brightness) async {
    await _screenBrightness.setScreenBrightness(brightness.clamp(0.0, 1.0));
  }

  Future<void> brightnessUp() async {
    double current = await getBrightness();
    double newBrightness = (current + 0.1).clamp(0.0, 1.0);
    await setBrightness(newBrightness);
  }

  Future<void> brightnessDown() async {
    double current = await getBrightness();
    double newBrightness = (current - 0.1).clamp(0.0, 1.0);
    await setBrightness(newBrightness);
  }

  Future<void> resetBrightness() async {
    await _screenBrightness.resetScreenBrightness();
  }
}