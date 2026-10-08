; Installateur Windows EN LIGNE pour ESCATO — Gestion scolaire.
; Le paquet ne contient que escato_app.exe. À l'installation, il télécharge :
;   1. le runtime Qt (DLL, plugins, qml) publié avec la release GitHub, vérifié par SHA-256 ;
;   2. le Microsoft Visual C++ Redistributable x64, s'il est absent, vérifié par signature Authenticode.
; Compilation : ISCC /DRuntimeSha256=<sha256 du zip> [/DMyAppVersion=1.0.0] [/DSourceDir=..\dist-app] installer\escato-online.iss

#define MyAppName "ESCATO"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppPublisher "Ecole Sacre-Coeur - Tolagnaro"
#define MyAppExeName "escato_app.exe"
#ifndef SourceDir
  #define SourceDir "..\dist-app"
#endif
#ifndef RuntimeSha256
  #error "RuntimeSha256 est obligatoire (SHA-256 du fichier ESCATO-runtime-win64.zip)"
#endif
#ifndef RuntimeUrl
  #define RuntimeUrl "https://github.com/Hari-Mael/Escato-GS/releases/download/v" + MyAppVersion + "/ESCATO-runtime-win64.zip"
#endif
#define VcRedistUrl "https://aka.ms/vs/17/release/vc_redist.x64.exe"

[Setup]
AppId={{E1460545-28CE-465F-9168-093DBD843524}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist-installer
OutputBaseFilename=ESCATO-Setup-Online
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; GroupDescription: "Icônes supplémentaires :"

[Files]
Source: "{#SourceDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Désinstaller {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Lancer {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Les fichiers du runtime sont extraits par le code ci-dessous et ne figurent pas dans le journal de
; désinstallation. La base de données (%APPDATA%\ESCATO) est dans un autre dossier et n'est jamais supprimée.
Type: filesandordirs; Name: "{app}"

[Code]
const
  RuntimeZip = 'escato-runtime.zip';
  VcRedistExe = 'vc_redist.x64.exe';

var
  DownloadPage: TDownloadWizardPage;
  RestartRequired: Boolean;

function VcRedistInstalled: Boolean;
var
  Installed: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed)
            and (Installed = 1);
end;

function PsQuote(const S: String): String;
begin
  Result := S;
  StringChangeEx(Result, '''', '''''', True);
end;

function RunPowerShell(const Command: String): Integer;
var
  ResultCode: Integer;
begin
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
              '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' + Command + '"',
              '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    ResultCode := -1;
  Result := ResultCode;
end;

function OnDownloadProgress(const Url, FileName: String; const Progress, ProgressMax: Int64): Boolean;
begin
  Result := True;
end;

procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage('Téléchargement des composants',
    'ESCATO télécharge les composants nécessaires à son fonctionnement. Une connexion Internet est requise.',
    @OnDownloadProgress);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpReady then
  begin
    DownloadPage.Clear;
    DownloadPage.Add('{#RuntimeUrl}', RuntimeZip, '{#RuntimeSha256}');
    if not VcRedistInstalled then
      DownloadPage.Add('{#VcRedistUrl}', VcRedistExe, '');
    DownloadPage.Show;
    try
      try
        DownloadPage.Download;
      except
        if not DownloadPage.AbortedByUser then
          SuppressibleMsgBox('Impossible de télécharger les composants nécessaires.' + #13#10 +
            'Vérifiez votre connexion Internet puis relancez l''installation.' + #13#10#13#10 +
            GetExceptionMessage, mbCriticalError, MB_OK, IDOK);
        Result := False;
      end;
    finally
      DownloadPage.Hide;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  try
    if not FileExists(ExpandConstant('{tmp}\' + RuntimeZip)) then
      DownloadTemporaryFile('{#RuntimeUrl}', RuntimeZip, '{#RuntimeSha256}', nil);
    if (not VcRedistInstalled) and (not FileExists(ExpandConstant('{tmp}\' + VcRedistExe))) then
      DownloadTemporaryFile('{#VcRedistUrl}', VcRedistExe, '', nil);
  except
    Result := 'Impossible de télécharger les composants nécessaires. Vérifiez votre connexion Internet puis relancez l''installation.'
              + #13#10#13#10 + GetExceptionMessage;
  end;
end;

procedure InstallVcRedist;
var
  Exe: String;
  ResultCode: Integer;
begin
  Exe := ExpandConstant('{tmp}\' + VcRedistExe);
  if not FileExists(Exe) then Exit;
  if RunPowerShell('$s = Get-AuthenticodeSignature -LiteralPath ''' + PsQuote(Exe) + '''; ' +
                   'if ($s.Status -eq ''Valid'' -and $s.SignerCertificate.Subject -like ''*O=Microsoft Corporation*'') { exit 0 } else { exit 1 }') <> 0 then
  begin
    MsgBox('Le composant Visual C++ téléchargé n''a pas une signature Microsoft valide. Il ne sera pas installé.', mbError, MB_OK);
    Abort;
  end;
  WizardForm.StatusLabel.Caption := 'Installation de Microsoft Visual C++ Redistributable...';
  if not Exec(Exe, '/install /quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    ResultCode := -1;
  if ResultCode = 3010 then
    RestartRequired := True
  else if (ResultCode <> 0) and (ResultCode <> 1638) then
  begin
    MsgBox('L''installation de Microsoft Visual C++ Redistributable a échoué (code ' + IntToStr(ResultCode) + ').', mbError, MB_OK);
    Abort;
  end;
end;

procedure ExtractRuntime;
var
  Zip, Dest: String;
begin
  Zip := ExpandConstant('{tmp}\' + RuntimeZip);
  Dest := ExpandConstant('{app}');
  WizardForm.StatusLabel.Caption := 'Extraction du runtime Qt...';
  if RunPowerShell('Expand-Archive -LiteralPath ''' + PsQuote(Zip) + ''' -DestinationPath ''' + PsQuote(Dest) + ''' -Force') <> 0 then
  begin
    MsgBox('L''extraction des composants a échoué. Relancez l''installation.', mbError, MB_OK);
    Abort;
  end;
  if not FileExists(Dest + '\Qt6Core.dll') then
  begin
    MsgBox('Le runtime Qt est incomplet. Relancez l''installation.', mbError, MB_OK);
    Abort;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    ExtractRuntime;
    if not VcRedistInstalled then
      InstallVcRedist;
  end;
end;

function NeedRestart: Boolean;
begin
  Result := RestartRequired;
end;
