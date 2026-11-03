/// Tree of the groups of organisation by their attachment (`parent_id`,
/// who administers), as the console shows it. Pure code.
library;

/// One line of the tree: the group and its depth (0: organisation or a
/// group whose parent is not visible to this administrator).
typedef GroupLine=({Map<String,dynamic> group,int depth});

List<GroupLine> groupTree(List<Map<String,dynamic>> groups){
  final ids={for(final g in groups)'${g['id']}'};
  final children=<String,List<Map<String,dynamic>>>{};
  final roots=<Map<String,dynamic>>[];
  for(final g in groups){
    final p=g['parent_id'];
    if(p is String&&ids.contains(p)){children.putIfAbsent(p,()=>[]).add(g);}else{roots.add(g);}
  }
  int order(Map<String,dynamic> a,Map<String,dynamic> b){
    final s=(a['system']==true?0:1).compareTo(b['system']==true?0:1);
    return s!=0?s:'${a['short_name']}'.toLowerCase().compareTo('${b['short_name']}'.toLowerCase());
  }
  final out=<GroupLine>[]; final seen=<String>{};
  void walk(Map<String,dynamic> g,int depth){
    if(!seen.add('${g['id']}'))return;
    out.add((group:g,depth:depth));
    for(final c in (children['${g['id']}']??<Map<String,dynamic>>[])..sort(order)){walk(c,depth+1);}
  }
  for(final r in roots..sort(order)){walk(r,0);}
  return out;
}

/// Groups of the list by identifier.
Map<String,Map<String,dynamic>> groupsById(List<Map<String,dynamic>> groups)=>{for(final g in groups)'${g['id']}':g};

/// « 3 membres · 1 invitation » of a line of the tree.
({int users,int invitations}) groupCounts(Map<String,dynamic> g)=>(
  users:g['users'] is num?(g['users'] as num).toInt():(g['users'] as List?)?.length??0,
  invitations:g['invitations'] is num?(g['invitations'] as num).toInt():(g['invitations'] as List?)?.length??0);
