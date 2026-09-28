# ESCATO — C++ / Qt 6 / QML / SQLite

Cette base est une réimplémentation desktop du périmètre fonctionnel trouvé dans l'archive
`MS.zip`, organisée comme un **monolithe modulaire**.

## Modules repris du projet source

- Authentification et rôles : administrateur, enseignant, élève, parent, comptable
- Tableau de bord
- Élèves :
  - inscription
  - liste
  - recherche
  - filtre par classe
  - fiche
  - modification/suppression logique
  - diplômé
  - blocage/déblocage
  - impression de liste
- Enseignants :
  - création
  - fiche
  - informations professionnelles
  - recherche
  - impression de liste
- Cours :
  - création/modification/suppression
  - affectation enseignant
  - ressources PDF/vidéo/quiz (métadonnées)
- Examens :
  - planification
  - période d'examen
  - saisie des notes
  - calcul du bulletin par matière et moyenne générale
- Finance :
  - paiements
  - méthodes MVola / Orange Money / Airtel Money / virement / espèces
  - frais mensuels
  - génération mensuelle des factures
  - statuts pending / paid / late
  - rappels de paiement
- Communication :
  - messages
  - annonces / événements
  - notifications/audit préparés dans la base
- Retards
- Comptes :
  - création
  - rôles
  - blocage/déblocage
  - réinitialisation de mot de passe
- SQLite local
- Impression A4 de listes élèves/enseignants

## Classes prévues

6ème 1, 6ème 2, 6ème 3, 6ème 4,
5ème 1, 5ème 2, 5ème 3,
4ème 1, 4ème 2, 4ème 3,
3ème 1, 3ème 2, 3ème 3,
2nde 1, 2nde 2, 2nde 3, 2nde 4,
1ère S1, 1ère S2, 1ère L1, 1ère L2,
T L1, T L2, T S1, T S2.

## Compilation

Installer Qt 6 avec :
- Qt Quick
- Qt SQL
- Qt PrintSupport
- CMake
- compilateur C++17

Puis :

    cmake -S . -B build
    cmake --build build

Lancer l'exécutable produit.

## Premier lancement

Aucun compte n'est créé d'avance. Au premier lancement, ESCATO affiche un écran de configuration :
le compte que vous créez devient **administrateur** et a le contrôle complet de l'application
(création des comptes enseignants, comptables, etc.). Cet écran n'est plus proposé dès qu'un
administrateur actif existe.

Les bases créées par d'anciennes versions contenaient un compte par défaut ; il est automatiquement
désactivé tant qu'il porte encore son mot de passe d'origine.

## Emplacement de la base

SQLite est créé automatiquement dans le dossier AppData de l'application sous :

    escato.sqlite

## Architecture

Monolithe modulaire, une seule base SQLite :

    src/main.cpp            point d'entrée (QApplication + QML)
    src/core/               SchoolApp (logique métier exposée à QML), Database (schéma, migration, seed), PrintManager (PDF / impression)
    qml/                    Main.qml, pages/, components/
    assets/                 logo de l'établissement

Le découpage en `src/modules/*` (students, teachers, finance, ...) est prévu mais pas encore réalisé.

## Important

C'est une **base de développement fonctionnelle**, pas encore une version production.
Avant une mise en production, il faudra notamment :
- remplacer le stockage de mot de passe de démonstration par une politique de hash/KDF robuste ;
- ajouter une vraie gestion des permissions par action ;
- ajouter sauvegarde/restauration ;
- chiffrer les données sensibles si nécessaire ;
- compléter les écrans parent/élève/comptable ;
- ajouter génération de carte élève avec QR code ;
- ajouter import/export ;
- compléter les documents PDF (bulletins, reçus, attestations, permissions) ;
- gérer les fichiers réels des ressources de cours ;
- ajouter tests unitaires et tests d'intégration.


## Identité officielle des documents imprimés

Tous les documents administratifs actuellement pris en charge par le moteur d'impression utilisent l'en-tête officiel suivant :

- Logo ESCATO fourni par l'établissement
- École Sacre Coeur
- BP 85 Tolagnaro
- 034 52 812 71

L'en-tête est centralisé dans `src/core/PrintManager.cpp`, afin que les futurs bulletins, reçus, attestations, permissions et autres paperasses administratives puissent réutiliser exactement la même identité graphique.

## Comptabilité intégrée

Le module **Comptabilité** est maintenant intégré à ESCATO sans séparer la base SQLite :
- tableau de bord caisse / banque / écolages / dépenses / impayés ;
- plan comptable et journal en partie double ;
- écritures automatiques pour les paiements et les dépenses ;
- balance générale et API du grand livre ;
- exports CSV UTF-8 directement ouvrables dans **Microsoft Excel** ;
- exports structurés **Sage 100** et **Odoo** pour échange/import après mapping selon la version et le paramétrage du logiciel comptable ;
- dossier d'export par défaut : `Documents/ESCATO_Comptabilite`.

Le détail du module est dans `ACCOUNTING.md`.
