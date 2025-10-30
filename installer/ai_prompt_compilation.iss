; Inno Setup script for AI Prompt Compilation (Windows setup.exe)
; 输出：dist\AI-Prompt-Compilation-Setup.exe

[Setup]
AppId={{B34A3B7D-1F1C-4B66-9D4B-AC2A33D20A11}}
AppName=AI Prompt Compilation
AppVersion=1.0.0
AppPublisher=AI Prompt Dev
DefaultDirName={userappdata}\AI Prompt Compilation
DefaultGroupName=AI Prompt Compilation
OutputBaseFilename=AI-Prompt-Compilation-Setup
OutputDir=dist
ArchitecturesInstallIn64BitMode=x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
SetupIconFile=windows\runner\resources\app_icon.ico

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AI Prompt Compilation"; Filename: "{app}\ai_prompt_compilation.exe"; IconFilename: "windows\runner\resources\app_icon.ico"
Name: "{commondesktop}\AI Prompt Compilation"; Filename: "{app}\ai_prompt_compilation.exe"; Tasks: desktopicon; IconFilename: "windows\runner\resources\app_icon.ico"

[Run]
Filename: "{app}\ai_prompt_compilation.exe"; Description: "运行 AI Prompt Compilation"; Flags: nowait postinstall skipifsilent