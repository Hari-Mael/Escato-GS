ESCATO — C++ / Qt 6 / QML / SQLite

La gestion de votre école, simplifiée. C'est une plateforme complète de gestion scolaire pensée pour les établissements privés : élèves, notes, paiements, communication — tout est centralisé dans un seul outil, accessible à chaque acteur de l'école selon son rôle.

À qui s'adresse ESCATO-GS

Directions d'établissement pilotage global, gestion des comptes et des accès
Comptabilité suivi des paiements, factures et retards de scolarité
Enseignants Gestion des cours, saisie des notes, suivi de l'assiduité
Élèves accès à leurs cours, notes et bulletins
Parents suivi des résultats et des paiements de leurs enfants
Fonctionnalités principales :Gestion des élèves Fiches complètes, historique de scolarité, cartes d'élève imprimables et suivi de l'assiduité.

Notes et examens Planification des examens, saisie des notes par les enseignants, génération automatique des bulletins par trimestre ou semestre.

Paiements et facturation Enregistrement des paiements de scolarité, suivi des échéances, génération de reçus, alertes en cas de retard.

Communication Messagerie interne entre l'administration, les enseignants, les élèves et les parents. Annonces et événements diffusés à toute la communauté scolaire.

Gestion des accès Chaque utilisateur ne voit que ce qui le concerne : les rôles (administration, comptabilité, enseignant, élève, parent) déterminent précisément les fonctionnalités accessibles.

Installation guidée Un assistant d'installation en quelques étapes configure automatiquement l'établissement au premier lancement — nom de l'école, base de données, création du compte administrateur.

Pourquoi ESCATO-GS

Simple une interface claire, pensée pour être prise en main sans formation
Centralisé plus besoin de jongler entre cahiers, tableurs et messages épars
Personnalisable chaque établissement configure son propre nom et ses propres données, en toute indépendance
Évolutif conçu pour grandir avec les besoins de l'établissement
Licence

Propriétaire — tous droits réservés. Toute utilisation, reproduction ou distribution sans autorisation est interdite.

Contact

Pour toute question, démonstration ou demande d'installation, contactez l'équipe ESCATO-GS

## Symptôme
Après installation via ESCATO-Setup.exe (généré par le workflow GitHub Actions), double-cliquer sur escato_app.exe (ou le raccourci) ne fait rien d'observable :
- Aucune fenêtre ne s'ouvre
- Aucune icône n'apparaît dans la barre des tâches
- Aucun message d'erreur

## Environnement
- Windows 10
- Build produit par .github/workflows/build.yml (job build-windows), Qt 6.7.x MSVC 2019 64-bit
- Installateur généré via Inno Setup (installer/escato.iss)

## Déjà corrigé (n'est pas la cause actuelle)
- [x] CMakeLists.txt : ajout de WIN32_EXECUTABLE TRUE (via set_target_properties) — supprime la fenêtre console qui flashait avant, mais le problème de fond persiste
- [x] windeployqt : ajout de --compiler-runtime pour embarquer les DLL du runtime Visual C++
- [x] Workflow CI : build + packaging + installeur passent tous au vert sur GitHub Actions

## À vérifier (prochaine étape, pas encore fait / résultat pas encore communiqué)
Lancer depuis PowerShell pour capturer un éventuel message silencieusement perdu lors d'un double-clic :
```powershell
cd "C:\Program Files\ESCATO"
.\escato_app.exe
```

Vérifier aussi :
- Présence de `platforms\qwindows.dll` dans le dossier d'installation
- Historique de protection Windows Defender (mise en quarantaine silencieuse possible)
- Observateur d'événements Windows → Journaux Windows → Application (ligne "Erreur" au moment du lancement)

## Hypothèses non encore écartées
- Plugin de plateforme Qt manquant (qwindows.dll)
- Antivirus bloquant l'exécutable non signé
- Dépendance manquante non détectée par windeployqt
