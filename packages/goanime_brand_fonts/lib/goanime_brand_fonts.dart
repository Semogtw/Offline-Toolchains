import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const goAnimeFontPackage = 'goanime_brand_fonts';
const goAnimeDisplayFontFamily = 'Epilogue';
const goAnimeBodyFontFamily = 'Manrope';

bool _licensesRegistered = false;

/// Registers the OFL license text for the bundled GoAnime font families.
///
/// Registration is idempotent and does not block startup: the license
/// assets are loaded lazily only when Flutter's license registry is read.
void registerGoAnimeBrandFontLicenses() {
  if (_licensesRegistered) return;
  _licensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    final epilogue = await rootBundle.loadString(
      'packages/goanime_brand_fonts/assets/licenses/Epilogue-OFL.txt',
    );
    yield LicenseEntryWithLineBreaks(['Epilogue'], epilogue);

    final manrope = await rootBundle.loadString(
      'packages/goanime_brand_fonts/assets/licenses/Manrope-OFL.txt',
    );
    yield LicenseEntryWithLineBreaks(['Manrope'], manrope);
  });
}
