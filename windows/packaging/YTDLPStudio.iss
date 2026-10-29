#ifndef PublishDir
  #error PublishDir must point at the complete self-contained publish directory
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef AppVersion
  #define AppVersion "1.3.0-beta.1"
#endif
[Setup]
AppId={{65863B76-8CB1-4308-81ED-FA8409CA650A}
AppName=YTDLP Studio
AppVersion={#AppVersion}
AppVerName=YTDLP Studio {#AppVersion}
AppPublisher=ZainLet
VersionInfoVersion=1.3.0.0
DefaultDirName={localappdata}\Programs\YTDLP Studio
DefaultGroupName=YTDLP Studio
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19045
OutputDir={#OutputDir}
OutputBaseFilename=YTDLP-Studio-{#AppVersion}-win-x64-Setup
SetupIconFile=..\assets\AppIcon.ico
UninstallDisplayIcon={app}\YTDLPStudio.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
DisableDirPage=no
CloseApplications=no
RestartApplications=no
Uninstallable=yes
UninstallFilesDir={app}\uninstall
ChangesAssociations=no
ChangesEnvironment=no
SetupLogging=yes

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Icons]
Name: "{userprograms}\YTDLP Studio"; Filename: "{app}\YTDLPStudio.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\YTDLP Studio"; Filename: "{app}\YTDLPStudio.exe"; WorkingDir: "{app}"; Tasks: desktopicon
