; Oftob Building — Windows o'rnatuvchisi (Inno Setup 6). Yig'ish: ISCC.exe windows\installer\oftob.iss
; Avval: flutter build windows --release

#define AppName "Oftob Building"
#define AppVersion "1.0.6"
#define AppExe "oftob_mobile.exe"
#define Src "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{B7E4D2A1-6C3F-4A8B-9D15-2F0E7A9C4B31}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Oftob
DefaultDirName={autopf}\Oftob Building
DefaultGroupName={#AppName}
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir=..\..\..\..\oftob-release
OutputBaseFilename=Oftob-Building-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; administrator parolisiz: faqat shu foydalanuvchi uchun (xohlasa — hamma foydalanuvchilar uchun, oynada tanlanadi)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; dastur ochiq bo'lsa — yangilashda o'zi yopiladi va qayta ochiladi (ma'lumot va navbat fayllari o'chmaydi)
CloseApplications=yes
RestartApplications=yes
AppMutex=Local\oftob.building.single

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#Src}\*"; DestDir: "{app}"; Excludes: "*.lib,*.exp,*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; O'chirishda foydalanuvchi ma'lumotlari (offline nusxa, yuborilmagan amallar) TEGILMAYDI — qayta o'rnatilsa joyida qoladi
