; SARCADE Windows installer (Inno Setup 6.3+), built by the CI from the
; release build. Per-user or per-machine install, French and English.
; Unsigned until the code signing certificate is placed in the GitHub
; secrets (WINDOWS_CERT_PFX, WINDOWS_CERT_PASSWORD): the CI then signs it.
#define AppVersion GetEnv("SARCADE_VERSION")
#if AppVersion == ""
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{5F0E7C2A-1B8D-4C3E-9A6F-2D4B8E1C7A90}
AppName=SARCADE
AppVersion={#AppVersion}
AppVerName=SARCADE {#AppVersion}
AppPublisher=ADRASEC
DefaultDirName={autopf}\SARCADE
DefaultGroupName=SARCADE
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=sarcade-windows-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; TEST BRANCH ONLY, NOT TO MERGE (card « Installeur Windows : essai du style
; classique (point 4) », lot 19): classic wizard, to see on the Surface
; whether the check boxes are drawn whole. main keeps WizardStyle=modern.
WizardStyle=classic
; A little larger wizard: room for the check boxes on high-DPI screens
; (Surface, 200 %), where they were cut on the left (31 Oct 2026).
WizardSizePercent=110
UninstallDisplayIcon={app}\sarcade_app.exe
; An update closes the running client before replacing its files.
CloseApplications=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\SARCADE"; Filename: "{app}\sarcade_app.exe"
Name: "{autodesktop}\SARCADE"; Filename: "{app}\sarcade_app.exe"; Tasks: desktopicon

[Run]
; Started with the rights of the person, never as administrator: the Windows
; notification plugin stops an elevated SARCADE (card « Client Windows :
; écran gris », 31 Oct 2026).
Filename: "{app}\sarcade_app.exe"; Description: "{cm:LaunchProgram,SARCADE}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[Code]
// Card « Installeur Windows : case encore coupée après #156 » (1 Nov 2026):
// on the Surface (200 %, ARM64, x64 installer emulated) the check box of
// « Créer une icône sur le Bureau » is still cut on the left, even with the
// larger wizard: the task list draws its box too close to its left edge.
// The list is moved to the right by a gap scaled with the screen (ScaleX)
// and made narrower by the same amount, so its right edge does not move.
// Independent of the Inno Setup version.
const
  TasksListGap = 8;

procedure InitializeWizard;
var
  Gap: Integer;
begin
  Gap := ScaleX(TasksListGap);
  WizardForm.TasksList.Left := WizardForm.TasksList.Left + Gap;
  WizardForm.TasksList.Width := WizardForm.TasksList.Width - Gap;
end;
