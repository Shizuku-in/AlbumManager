#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef ReleaseTag
  #error ReleaseTag is required
#endif
#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif

[Setup]
AppId={{0D190A3D-887A-428F-AB57-0F350B93626E}
AppName=Album Manager
AppVersion={#AppVersion}
AppVerName=Album Manager {#ReleaseTag}
AppPublisher=Shizuku-in
DefaultDirName={localappdata}\Programs\Album Manager
DefaultGroupName=Album Manager
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=AlbumManager-{#ReleaseTag}-windows-x64-setup
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\album_manager.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
LicenseFile=..\LICENSE

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Album Manager"; Filename: "{app}\album_manager.exe"
Name: "{autodesktop}\Album Manager"; Filename: "{app}\album_manager.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\album_manager.exe"; Description: "{cm:LaunchProgram,Album Manager}"; Flags: nowait postinstall skipifsilent
