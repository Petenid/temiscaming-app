import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Open-Meteo gives each forecast day a WMO weather code (the day's most
/// severe condition) and no text, so the words are ours, in both languages
/// (weather spec D6). The wording follows Environment Canada's own forecasts.
enum WmoLabel {
  sunny, mainlySunny, mixSunCloud, cloudy, fog, freezingFog,
  lightDrizzle, drizzle, freezingDrizzle, lightRain, rain, heavyRain, freezingRain,
  lightSnow, snow, heavySnow, snowGrains, showers, heavyShowers, flurries, heavyFlurries,
  thunderstorm, thunderstormHail, unknown,
}

/// Every code Open-Meteo documents (same list as the backend's WMO_CODES).
const wmoCodes = <int, WmoLabel>{
  0: WmoLabel.sunny,
  1: WmoLabel.mainlySunny,
  2: WmoLabel.mixSunCloud,
  3: WmoLabel.cloudy,
  45: WmoLabel.fog,
  48: WmoLabel.freezingFog,
  51: WmoLabel.lightDrizzle,
  53: WmoLabel.drizzle,
  55: WmoLabel.drizzle,
  56: WmoLabel.freezingDrizzle,
  57: WmoLabel.freezingDrizzle,
  61: WmoLabel.lightRain,
  63: WmoLabel.rain,
  65: WmoLabel.heavyRain,
  66: WmoLabel.freezingRain,
  67: WmoLabel.freezingRain,
  71: WmoLabel.lightSnow,
  73: WmoLabel.snow,
  75: WmoLabel.heavySnow,
  77: WmoLabel.snowGrains,
  80: WmoLabel.showers,
  81: WmoLabel.showers,
  82: WmoLabel.heavyShowers,
  85: WmoLabel.flurries,
  86: WmoLabel.heavyFlurries,
  95: WmoLabel.thunderstorm,
  96: WmoLabel.thunderstormHail,
  99: WmoLabel.thunderstormHail,
};

WmoLabel wmoLabel(int code) => wmoCodes[code] ?? WmoLabel.unknown;

String wmoText(AppLocalizations l10n, int code) => switch (wmoLabel(code)) {
  WmoLabel.sunny => l10n.wmoSunny,
  WmoLabel.mainlySunny => l10n.wmoMainlySunny,
  WmoLabel.mixSunCloud => l10n.wmoMixSunCloud,
  WmoLabel.cloudy => l10n.wmoCloudy,
  WmoLabel.fog => l10n.wmoFog,
  WmoLabel.freezingFog => l10n.wmoFreezingFog,
  WmoLabel.lightDrizzle => l10n.wmoLightDrizzle,
  WmoLabel.drizzle => l10n.wmoDrizzle,
  WmoLabel.freezingDrizzle => l10n.wmoFreezingDrizzle,
  WmoLabel.lightRain => l10n.wmoLightRain,
  WmoLabel.rain => l10n.wmoRain,
  WmoLabel.heavyRain => l10n.wmoHeavyRain,
  WmoLabel.freezingRain => l10n.wmoFreezingRain,
  WmoLabel.lightSnow => l10n.wmoLightSnow,
  WmoLabel.snow => l10n.wmoSnow,
  WmoLabel.heavySnow => l10n.wmoHeavySnow,
  WmoLabel.snowGrains => l10n.wmoSnowGrains,
  WmoLabel.showers => l10n.wmoShowers,
  WmoLabel.heavyShowers => l10n.wmoHeavyShowers,
  WmoLabel.flurries => l10n.wmoFlurries,
  WmoLabel.heavyFlurries => l10n.wmoHeavyFlurries,
  WmoLabel.thunderstorm => l10n.wmoThunderstorm,
  WmoLabel.thunderstormHail => l10n.wmoThunderstormHail,
  WmoLabel.unknown => l10n.wmoUnknown,
};

/// Our own icons (ECCC's icons have usage terms, spec §2). Always shown
/// next to the words, never alone.
IconData wmoIcon(int code) => switch (wmoLabel(code)) {
  WmoLabel.sunny || WmoLabel.mainlySunny => Icons.wb_sunny_outlined,
  WmoLabel.mixSunCloud => Icons.wb_cloudy_outlined,
  WmoLabel.cloudy => Icons.cloud_outlined,
  WmoLabel.fog || WmoLabel.freezingFog => Icons.dehaze,
  WmoLabel.lightDrizzle || WmoLabel.drizzle => Icons.grain,
  WmoLabel.lightRain || WmoLabel.rain || WmoLabel.heavyRain ||
  WmoLabel.showers || WmoLabel.heavyShowers => Icons.water_drop_outlined,
  WmoLabel.freezingDrizzle || WmoLabel.freezingRain || WmoLabel.lightSnow ||
  WmoLabel.snow || WmoLabel.heavySnow || WmoLabel.snowGrains ||
  WmoLabel.flurries || WmoLabel.heavyFlurries => Icons.ac_unit,
  WmoLabel.thunderstorm || WmoLabel.thunderstormHail => Icons.flash_on,
  WmoLabel.unknown => Icons.help_outline,
};
