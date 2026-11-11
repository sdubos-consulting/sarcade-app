/// Base maps (note « Choix du fond de carte »): catalog of the server,
/// with the four layers of the first version known offline. Pure code.
library;

const _ignWmts='https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER={layer}'
  '&STYLE=normal&TILEMATRIXSET=PM&FORMAT={fmt}&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}';

/// Deepest zoom of the map (street, building). Beyond the zoom of its base
/// map the last images are enlarged, never removed (card « Carte : fond
/// gris quand on zoome trop », validated on 9 Nov 2026).
const mapMaxZoom = 20.0;

/// Last zoom for which [b] has images of its own (its maxNativeZoom).
int basemapNativeZoom(Basemap b) => b.maxZoom.clamp(1, mapMaxZoom.toInt());

/// Offline package of a base map on the SARCADE server (MBTiles): zone and
/// zooms, to keep it on the phone (card « Cartes hors connexion sur le
/// téléphone », 9 Nov 2026).
class OfflinePackage {
  /// West, south, east, north; null when the server does not give them.
  final List<double>? bounds;
  final int minZoom, maxZoom, tiles, sizeBytes;
  const OfflinePackage({this.bounds,this.minZoom=0,this.maxZoom=0,this.tiles=0,this.sizeBytes=0});
  static OfflinePackage? fromJson(Object? j){
    if(j is! Map)return null;
    final b=(j['bounds'] as String?)?.split(',').map((v)=>double.tryParse(v.trim())).toList();
    return OfflinePackage(bounds:b!=null&&b.length==4&&!b.contains(null)?b.cast<double>():null,
      minZoom:(j['min_zoom'] as num?)?.toInt()??0,maxZoom:(j['max_zoom'] as num?)?.toInt()??0,
      tiles:(j['tiles'] as num?)?.toInt()??0,sizeBytes:(j['size_bytes'] as num?)?.toInt()??0);
  }
  Map<String,dynamic> toJson()=>{'bounds':bounds?.join(','),'min_zoom':minZoom,'max_zoom':maxZoom,'tiles':tiles,'size_bytes':sizeBytes};
  /// Can be kept on the phone: zone and zooms known.
  bool get keepable=>bounds!=null&&maxZoom>=minZoom&&maxZoom>0;
}

class Basemap {
  final String id, name, attribution; final String? url; final int maxZoom;
  final bool hasOfflinePackage, custom;
  final OfflinePackage? package;
  const Basemap({required this.id,required this.name,required this.attribution,this.url,this.maxZoom=19,
    this.hasOfflinePackage=false,this.custom=false,this.package});

  factory Basemap.fromJson(Map<String,dynamic> j)=>Basemap(
    id:j['id'] as String,name:(j['name'] as String?)??(j['id'] as String),
    attribution:(j['attribution'] as String?)??'',url:j['url'] as String?,
    maxZoom:(j['max_zoom'] as num?)?.toInt()??19,
    hasOfflinePackage:j['offline_package'] is Map,custom:j['custom']==true,package:OfflinePackage.fromJson(j['offline_package']));

  Map<String,dynamic> toJson()=>{'id':id,'name':name,'attribution':attribution,'url':url,'max_zoom':maxZoom,
    'offline_package':hasOfflinePackage?(package?.toJson()??{}):null,'custom':custom};

  /// Tiles served by the SARCADE server from the offline package (local
  /// network, no Internet needed).
  String offlineUrl(String serverUrl)=>'$serverUrl/api/v0.1/basemaps/$id/tiles/{z}/{x}/{y}';

  /// URL used by the map: the offline package when asked or when the layer
  /// only exists offline, else the online layer.
  String? tileUrl(String serverUrl,{required bool preferOffline}){
    if(hasOfflinePackage&&(preferOffline||url==null))return offlineUrl(serverUrl);
    return url;
  }
}

/// The four layers of the first version, same as the server catalog.
final builtInBasemaps=[
  const Basemap(id:'osm',name:'OpenStreetMap',attribution:'© OpenStreetMap contributors',url:'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
  const Basemap(id:'topo',name:'Topographique',attribution:'© OpenStreetMap contributors, SRTM | © OpenTopoMap (CC-BY-SA)',url:'https://tile.opentopomap.org/{z}/{x}/{y}.png',maxZoom:17),
  Basemap(id:'ign-plan',name:'Plan IGN',attribution:'© IGN, Géoplateforme',url:_ignWmts.replaceFirst('{layer}','GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2').replaceFirst('{fmt}','image/png')),
  Basemap(id:'ign-photos',name:'Photographies aériennes IGN',attribution:'© IGN, Géoplateforme',url:_ignWmts.replaceFirst('{layer}','ORTHOIMAGERY.ORTHOPHOTOS').replaceFirst('{fmt}','image/jpeg')),
];

/// Catalog from the server, else the built-in layers.
List<Basemap> mergeCatalog(List<Basemap> fromServer)=>fromServer.isEmpty?builtInBasemaps:fromServer;

/// Layer shown: the operator's choice, else the event default chosen by the
/// PCO, else OpenStreetMap.
Basemap pickBasemap(List<Basemap> catalog,{String? operatorChoice,String? eventDefault}){
  for(final id in [operatorChoice,eventDefault,'osm']){
    if(id==null)continue;
    for(final b in catalog){if(b.id==id)return b;}
  }
  return catalog.isNotEmpty?catalog.first:builtInBasemaps.first;
}
