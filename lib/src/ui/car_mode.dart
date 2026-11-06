/// Car screen (lot 29, card « Carte : boutons ronds plus petits »): the Tesla
/// browser keeps the big map buttons; phones, tablets and computers get the
/// round 44 px ones. Android Auto draws its own native screen.
library;

import '../platform/platform_services.dart';

/// True in the browser of a Tesla (its user agent carries « Tesla »).
bool teslaUserAgent(String ua)=>ua.contains('Tesla');

/// Override for the tests.
bool? carModeOverride;

/// Big buttons on a car screen.
bool get carMode=>carModeOverride??teslaUserAgent(browserUserAgent);

/// Side of a round map button: 44 px, 56 px on a car screen.
double mapButtonSize({bool? car})=>(car??carMode)?56:44;
