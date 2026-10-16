# ESCATO — Module comptabilité

Le module comptable est intégré au même projet C++17 / Qt 6 / QML / SQLite.

## Fonctions

- Tableau de bord : caisse, banque, écolages, dépenses, impayés.
- Plan comptable de base : 411000, 401000, 512000, 531000, 580000, 606000, 641000, 706000, 758000.
- Journal comptable en partie double.
- Génération automatique d'une écriture comptable lors d'un paiement d'écolage.
- Enregistrement des dépenses avec écriture automatique.
- Balance générale.
- Consultation du grand livre par compte via l'API C++.
- Exports CSV UTF-8 avec BOM, directement ouvrables dans Microsoft Excel.
- Exports structurés `Sage 100` et `Odoo` en CSV pour import/mapping selon la configuration de la version utilisée.
- Les exports sont placés par défaut dans `Documents/ESCATO_Comptabilite`.

## Flux

Paiement élève → paiement ESCATO → facture mise à jour → écriture débit caisse/banque + crédit 706000 → export Excel/Sage/Odoo.

Dépense → dépense ESCATO → écriture débit du compte de charge + crédit caisse/banque → export.

## Important

Les formats d'import Sage 100 peuvent varier selon la version, le paramétrage et les modules installés. Le fichier produit par ESCATO est donc un format d'échange structuré et non une promesse d'import automatique universel.

La configuration comptable/fiscale doit être validée par le comptable de l'établissement avant utilisation en production.
