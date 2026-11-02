/// Answer of the server for the event followed by this device (card
/// « Windows : pastille de liaison grise alors que le Diagnostic dit « Tout
/// fonctionne » », lot 19, point 9). The owner's Windows PC followed an
/// event the server did not know: every changes feed was refused (404) yet
/// counted as a successful synchronisation, so the Diagnostic said « Tout
/// fonctionne » while the map never loaded.
library;

/// ok: the changes feed of the event is served; unknown: 404, the event is
/// not on this server; refused: any other refusal (403, 401, 5xx…).
enum EventAccess{ok,unknown,refused}

/// Event state for an HTTP refusal of the changes feed.
EventAccess eventAccessOf(int statusCode)=>statusCode==404?EventAccess.unknown:EventAccess.refused;
