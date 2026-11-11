/// Channel models of the server (« Canaux ADRASEC », lot 29.3). The server
/// gives the channels of a model stable ids (`default_group_id`, uuid5 of
/// `sarcade:<event>:group:<key>`): the client computes the same ones to know
/// whether a model is already added (card « Messages : menu … plus soigné »,
/// choice 4: entry greyed with « Déjà ajoutés »).
library;

import 'package:uuid/uuid.dart';

/// Same keys as `TEMPLATES` of the server (groups/service.py).
const groupTemplates={'adrasec':['pco','equipes-terrain','transmissions','logistique']};

String defaultGroupId(String eventId,String key)=>const Uuid().v5(Namespace.url.value,'sarcade:$eventId:group:$key');

/// True when every channel of [template] is among [groupIds] (the server
/// adds nothing more then).
bool templateAdded(String eventId,String template,Iterable<String> groupIds){
  final keys=groupTemplates[template]; if(keys==null)return false;
  final have=groupIds.toSet();
  return keys.every((k)=>have.contains(defaultGroupId(eventId,k)));
}
