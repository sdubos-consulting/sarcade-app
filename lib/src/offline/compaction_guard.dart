/// Compaction of the local storage out of the writes (card « Windows :
/// pastille de liaison grise alors que le Diagnostic dit « Tout
/// fonctionne » », lot 19, point 3).
///
/// Hive compacts a box inside a write, by renaming its `.hivec` copy over
/// the box file. On Windows the rename fails (« Accès refusé »,
/// PathAccessException) when another process still holds the file, and the
/// error came out of the write itself. Now Hive never compacts on its own:
/// the box is only marked, compacted a few seconds later here, and a failure
/// is written to the startup log and tried again later, never stopping the
/// app. A `.hivec` left by an interrupted compaction is dealt with by Hive
/// when the box opens (kept when the box file is missing, deleted
/// otherwise).
library;

import 'dart:async';

class CompactionGuard {
  CompactionGuard({required this.compact,this.log,this.delay=const Duration(seconds:5),this.retryAfter=const Duration(minutes:10)});

  /// Compacts the box of this name.
  final Future<void> Function(String box) compact;
  /// Startup log (StartupReport.note).
  final void Function(String line)? log;
  final Duration delay, retryAfter;

  final _pending=<String>{};
  Timer? _timer;
  bool _running=false;

  /// Boxes waiting for a compaction.
  Set<String> get pending=>Set.unmodifiable(_pending);

  /// Rule of the default strategy of Hive.
  static bool needed(int entries,int deletedEntries)=>
    deletedEntries>60&&entries>0&&deletedEntries/entries>0.15;

  /// Strategy given to Hive for [box]: never compacts inside a write, marks
  /// the box instead.
  bool Function(int entries,int deletedEntries) strategyFor(String box)=>(entries,deletedEntries){
    if(needed(entries,deletedEntries))mark(box);
    return false;
  };

  void mark(String box){_pending.add(box);_schedule(delay);}

  void _schedule(Duration after){
    if(_timer?.isActive??false)return;
    _timer=Timer(after,()=>unawaited(run()));
  }

  /// Compacts the marked boxes; a failure is logged and tried again after
  /// [retryAfter].
  Future<void> run() async {
    if(_running)return;
    _running=true;
    final failed=<String>[];
    try{
      for(final box in _pending.toList()){
        _pending.remove(box);
        try{
          await compact(box);
        }catch(e){
          failed.add(box);
          log?.call('stockage local : compactage de « $box » reporté, nouvel essai dans ${retryAfter.inMinutes} min ($e)');
        }
      }
    }finally{
      _running=false;
    }
    if(failed.isNotEmpty){
      _pending.addAll(failed);
      _timer?.cancel();
      _timer=Timer(retryAfter,()=>unawaited(run()));
    }
  }

  void dispose(){_timer?.cancel();_timer=null;}
}
