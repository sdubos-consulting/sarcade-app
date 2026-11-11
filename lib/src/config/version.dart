/// Version of the client application, sent to the server (heartbeat and
/// minimal version check). Keep in step with `version:` in pubspec.yaml;
/// release builds override it with --dart-define=SARCADE_APP_VERSION=x.y.z.
const appVersion=String.fromEnvironment('SARCADE_APP_VERSION',defaultValue:'0.1.0');
/// Branch and commit of a test build (« feat/x@1a2b3c4 »), set by the CI:
/// tells test APKs apart, all numbered 0.1.0-dev.
const appBuild=String.fromEnvironment('SARCADE_BUILD');
/// Build number of the CI run (« 415 »), empty for a local build.
const appBuildNumber=String.fromEnvironment('SARCADE_BUILD_NUMBER');
/// « 0.1.0+415 »: version and build, sent to the server and shown in the
/// operator sheet (« Version de l'application et connexions »).
const appVersionFull=appBuildNumber==''?appVersion:'$appVersion+$appBuildNumber';
/// Label of the reference version (« v0.1.0-exercice1 », card
/// « Consolidation : version de référence », lot 28) when the build comes
/// from it: --dart-define=SARCADE_TAG, set by the CI once the project
/// holder has decided the label.
const appTag=String.fromEnvironment('SARCADE_TAG');

/// Reference version of this build: the label when there is one (also a
/// build whose branch is a label, « v0.1.0-exercice1@1a2b3c4 »), else
/// « main@1a2b3c4 » ([appBuild]), else « dev » (local build).
String appReference({String tag=appTag,String build=appBuild}){
  if(tag.isNotEmpty)return tag;
  final at=build.indexOf('@');
  if(at>0&&RegExp(r'^v\d').hasMatch(build))return build.substring(0,at);
  return build.isEmpty?'dev':build;
}
