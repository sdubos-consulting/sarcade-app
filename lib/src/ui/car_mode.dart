/// Car screen (lot 29, card « Carte : boutons ronds plus petits »): the Tesla
/// browser keeps the big map buttons; phones, tablets and computers get the
/// round 44 px ones. Android Auto draws its own native screen.
library;

import 'package:flutter/widgets.dart';

import '../platform/platform_services.dart';

/// True in the browser of a Tesla (its user agent carries « Tesla »).
bool teslaUserAgent(String ua)=>ua.contains('Tesla');

/// Override for the tests.
bool? carModeOverride;

/// Big buttons on a car screen.
bool get carMode=>carModeOverride??teslaUserAgent(browserUserAgent);

/// Side of a round map button: 44 px, 56 px on a car screen.
double mapButtonSize({bool? car})=>(car??carMode)?56:44;

/// « PCO-iphone » → « PI », « tesla-demo » → « TD », « PIA » → « PIA »:
/// the label of an operator on a car screen (card « affichage trop touffu »).
String carInitials(String label){
  final words=label.split(RegExp(r'[\s_\-·.]+')).where((w)=>w.isNotEmpty).toList();
  if(words.length>=2)return words.take(2).map((w)=>w[0]).join().toUpperCase();
  final w=words.isEmpty?label:words.first;
  return (w.length<=3?w:w.substring(0,3)).toUpperCase();
}

/// Colours of the base map toned down on a car screen.
const _carMatrix=<double>[
  0.55,0.35,0.10,0,10,
  0.20,0.70,0.10,0,10,
  0.20,0.35,0.45,0,10,
  0,0,0,1,0,
];
Widget carTileBuilder(BuildContext context,Widget tile,dynamic _)=>ColorFiltered(colorFilter:const ColorFilter.matrix(_carMatrix),child:tile);
