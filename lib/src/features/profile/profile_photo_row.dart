/// Paramètres › Profil › Photo (lot 29, group 7): applied at once, not
/// with « Enregistrer ».
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/strings.dart';
import '../../offline/local_store.dart';
import '../../services/sarcade_api.dart';
import '../messages/operator_avatar.dart';
import '../tv/tv_nearby.dart';
import 'profile_photo.dart';

class ProfilePhotoRow extends StatefulWidget{
  final SarcadeApi api; final LocalStore store; final String eventId,deviceId;
  const ProfilePhotoRow({super.key,required this.api,required this.store,required this.eventId,required this.deviceId});
  @override
  State<ProfilePhotoRow> createState()=>_ProfilePhotoRowState();
}

class _ProfilePhotoRowState extends State<ProfilePhotoRow>{
  bool _busy=false;

  @override
  void initState(){super.initState();ProfilePhotos.instance.load(widget.store,widget.eventId);}

  void _say(String key){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(S.t(key))));}

  Future<void> _pick(ImageSource source) async {
    // Reduced to 256 px by the picker itself: under 50 KB in JPEG.
    final shot=await TvNearbyGate.during(()=>ImagePicker().pickImage(source:source,maxWidth:photoSide,maxHeight:photoSide,imageQuality:photoQuality));
    if(shot==null)return;
    final bytes=await shot.readAsBytes();
    if(bytes.length>photoMaxBytes){_say('profile.photoTooBig');return;}
    setState(()=>_busy=true);
    try{await ProfilePhotos.instance.setMine(widget.api,widget.store,widget.eventId,widget.deviceId,bytes);}
    catch(_){_say('profile.photoFailed');}
    if(mounted)setState(()=>_busy=false);
  }

  Future<void> _remove() async {
    setState(()=>_busy=true);
    try{await ProfilePhotos.instance.remove(widget.api,widget.store,widget.eventId,widget.deviceId);}
    catch(_){_say('profile.photoFailed');}
    if(mounted)setState(()=>_busy=false);
  }

  @override
  Widget build(BuildContext context)=>ValueListenableBuilder<Map>(valueListenable:ProfilePhotos.instance,builder:(c,v,w)=>Wrap(
    spacing:8,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
      operatorAvatar(widget.deviceId,radius:24),
      OutlinedButton.icon(key:const ValueKey('photo-gallery'),onPressed:_busy?null:()=>_pick(ImageSource.gallery),
        icon:const Icon(Icons.photo_library_outlined),label:Text(S.t('profile.photoChoose'))),
      OutlinedButton.icon(key:const ValueKey('photo-camera'),onPressed:_busy?null:()=>_pick(ImageSource.camera),
        icon:const Icon(Icons.photo_camera_outlined),label:Text(S.t('profile.photoTake'))),
      if(ProfilePhotos.instance.of(widget.deviceId)!=null)TextButton.icon(key:const ValueKey('photo-remove'),onPressed:_busy?null:_remove,
        icon:const Icon(Icons.delete_outline),label:Text(S.t('profile.photoRemove'))),
    ]));
}
