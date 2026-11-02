/// Windows with text fields that own their controllers (card « Appliquer la
/// correction des fenêtres de saisie », lot 20).
///
/// A controller disposed when the Future of `showDialog` completes is freed
/// while the closing animation still draws its field: assertion
/// '_dependents.isEmpty' (Windows test of 13 Oct 2026, text tool of the
/// map). As in that first fix, the window's State creates the controllers
/// and disposes them with itself, once the route is really gone; the
/// window gives back the texts with its result.
library;

import 'package:flutter/material.dart';

/// Content of the window: [fields] belong to the window (one per initial
/// text), [setState] rebuilds it, as with a [StatefulBuilder].
typedef TextFieldsBuilder=Widget Function(BuildContext context,List<TextEditingController> fields,StateSetter setState);

/// Shows a dialog whose text fields live as long as the dialog itself.
Future<T?> showTextFieldsDialog<T>(BuildContext context,{required List<String> initial,required TextFieldsBuilder builder})=>
  showDialog<T>(context:context,builder:(_)=>TextFieldsHost(initial:initial,builder:builder));

/// Owner of the controllers, also usable in a bottom sheet.
class TextFieldsHost extends StatefulWidget {
  final List<String> initial; final TextFieldsBuilder builder;
  const TextFieldsHost({super.key,required this.initial,required this.builder});
  @override State<TextFieldsHost> createState()=>_TextFieldsHostState();
}

class _TextFieldsHostState extends State<TextFieldsHost> {
  late final List<TextEditingController> _fields=[for(final t in widget.initial)TextEditingController(text:t)];
  @override void dispose(){for(final f in _fields){f.dispose();}super.dispose();}
  @override Widget build(BuildContext context)=>widget.builder(context,_fields,setState);
}
