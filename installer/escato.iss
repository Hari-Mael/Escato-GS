; Installateur Windows autonome pour ESCATO — Gestion scolaire.
; Aucune ressource n'est téléchargée à l'installation : tous les fichiers (exécutable,
; DLL Qt, plugins) doivent déjà être présents dans le dossier {#SourceDir} avant compilation
; (résultat de windeployqt). L'installateur produit fonctionne donc entièrement hors ligne.

#define MyAppName "ESCATO"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Ecole Sacre-Coeur - Tolagnaro"
#define MyAppExeName "escato_app.exe"
#ifndef SourceDir
  #define SourceDir "..\dist"
#endif

[Setup]
AppId={{E1460545-28CE-465F-9168-093DBD843524}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist-installer
OutputBaseFilename=ESCATO-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
; Aucune étape de téléchargement : tout est inclus dans le paquet local ci-dessous.
DisableWelcomePage=no
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; GroupDescription: "Icônes supplémentaires :"

[Files]
; Reprend l'intégralité du dossier produit par windeployqt (exe + Qt5Core.dll, plugins/, qml/, etc.)
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Désinstaller {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Lancer {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; La base de données de l'utilisateur (%APPDATA%\ESCATO) n'est volontairement PAS supprimée
; à la désinstallation, pour ne jamais effacer les données scolaires par erreur.
