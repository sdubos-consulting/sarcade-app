/// One « Ma position » button (card « Carte, boutons Recentrer et Ma
/// position fusionnés », decision of 30 Oct 2026, 2 h 54): each touch goes
/// to the next mode, no long press: centred on me → follow → compass →
/// every operator → centred on me.
library;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

/// [course] (card « Tesla : le mode boussole ne tourne pas la carte », lot
/// 29.6): the map turns with the direction of travel (GPS), north up when
/// stopped; it replaces the compass where there is none (Tesla, computer).
enum LocateMode { idle, me, follow, compass, course, all }

/// Mode after a touch; [compass] false (computer, refused) skips the
/// compass; [course] true puts « Cap de route » in its place.
LocateMode nextLocateMode(LocateMode m,{bool compass=true,bool course=false})=>switch(m){
  LocateMode.idle=>LocateMode.me,
  LocateMode.me=>LocateMode.follow,
  LocateMode.follow=>compass?LocateMode.compass:course?LocateMode.course:LocateMode.all,
  LocateMode.compass||LocateMode.course=>LocateMode.all,
  LocateMode.all=>LocateMode.me,
};

IconData locateIcon(LocateMode m)=>switch(m){
  LocateMode.idle=>Icons.location_searching,
  LocateMode.me=>Icons.my_location,
  LocateMode.follow=>Icons.navigation,
  LocateMode.compass=>Icons.explore,
  LocateMode.course=>Icons.assistant_navigation,
  LocateMode.all=>Icons.zoom_out_map,
};

String locateTooltip(LocateMode m)=>S.t(switch(m){
  LocateMode.idle||LocateMode.me=>'map.myPosition',
  LocateMode.follow=>'map.followMeOn',
  LocateMode.compass=>'map.compassOn',
  LocateMode.course=>'map.courseOn',
  LocateMode.all=>'map.fit',
});

/// Short label shown 2 s when the mode changes (none for « centred on me »).
String? locateLabel(LocateMode m)=>switch(m){
  LocateMode.follow=>S.t('locate.followNorth'),
  LocateMode.compass=>S.t('locate.compass'),
  LocateMode.course=>S.t('locate.course'),
  LocateMode.all=>S.t('locate.all'),
  _=>null,
};
