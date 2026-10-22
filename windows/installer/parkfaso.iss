; PARKFASO — Installateur Windows (Inno Setup 6)
; Compilé automatiquement par GitHub Actions :
;   ISCC.exe /DAppVersion=1.0.12 windows\installer\parkfaso.iss

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{DE6EC318-AD69-4899-806E-4AC18490A5D3}
AppName=PARKFASO
AppVersion={#AppVersion}
AppVerName=PARKFASO {#AppVersion}
AppPublisher=OMZAKREVO INFORMATIQUE
AppPublisherURL=https://github.com/omzakrevo/parkfaso-plaques
AppSupportURL=https://github.com/omzakrevo/parkfaso-plaques
DefaultDirName={autopf}\PARKFASO
DefaultGroupName=PARKFASO
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=PARKFASO-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\PARKFASO.exe
UninstallDisplayName=PARKFASO
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installation possible sans droits administrateur (choix proposé).
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\PARKFASO"; Filename: "{app}\PARKFASO.exe"
Name: "{group}\{cm:UninstallProgram,PARKFASO}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\PARKFASO"; Filename: "{app}\PARKFASO.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\PARKFASO.exe"; Description: "{cm:LaunchProgram,PARKFASO}"; Flags: nowait postinstall skipifsilent

; Les données (parkings, entrées, licence) sont dans %APPDATA% : elles sont
; conservées lors d'une mise à jour ou d'une désinstallation.
