#!/usr/bin/env bash
# ------------------------------------------------------------------
# ESCATO — recrée le projet complet (C++ / Qt 6 / QML / SQLite)
# puis initialise le dépôt Git.
#
# Usage :
#   bash setup_escato.sh              -> crée ./escato_work + dépôt Git local
# Ensuite (voir la fin du script) : lier à GitHub et pousser.
# ------------------------------------------------------------------
set -euo pipefail

PROJECT_DIR="escato_work"
if [ -e "$PROJECT_DIR" ]; then
  echo "Le dossier $PROJECT_DIR existe déjà : renomme-le ou supprime-le avant de relancer." >&2
  exit 1
fi
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

cat > ".gitignore" <<'ESCATO_EOF'
build/
build-*/
.qtcreator/
*.user
CMakeLists.txt.user*
*.sqlite
*.sqlite-wal
*.sqlite-shm
ESCATO_EOF
cat > "ACCOUNTING.md" <<'ESCATO_EOF'
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
ESCATO_EOF
cat > "CMakeLists.txt" <<'ESCATO_EOF'
cmake_minimum_required(VERSION 3.21)
project(ESCATO LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Sql PrintSupport Widgets)

qt_standard_project_setup()

qt_add_executable(ESCATO
    src/main.cpp
    src/core/SchoolApp.cpp
    src/core/SchoolApp.h
    src/core/Database.cpp
    src/core/Database.h
    src/core/PrintManager.cpp
    src/core/PrintManager.h
)

qt_add_qml_module(ESCATO
    URI ESCATO
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/Sidebar.qml
        qml/components/StatCard.qml
        qml/components/Toast.qml
        qml/pages/LoginPage.qml
        qml/pages/SetupPage.qml
        qml/pages/DashboardPage.qml
        qml/pages/StudentsPage.qml
        qml/pages/StudentFormPage.qml
        qml/pages/StudentDetailPage.qml
        qml/pages/TeachersPage.qml
        qml/pages/TeacherFormPage.qml
        qml/pages/CoursesPage.qml
        qml/pages/ExamsPage.qml
        qml/pages/GradesPage.qml
        qml/pages/FinancePage.qml
        qml/pages/AccountingPage.qml
        qml/pages/CommunicationPage.qml
        qml/pages/AccountsPage.qml
        qml/pages/BulletinPage.qml
)

qt_add_resources(ESCATO "escato_resources"
    PREFIX "/"
    FILES
        assets/logo.png
)

target_include_directories(ESCATO PRIVATE src)

target_link_libraries(ESCATO
    PRIVATE Qt6::Quick Qt6::Sql Qt6::PrintSupport Qt6::Widgets
)
ESCATO_EOF
cat > "README.md" <<'ESCATO_EOF'
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
ESCATO_EOF
mkdir -p "qml"
cat > "qml/Main.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ESCATO

ApplicationWindow {
    id: win
    width: 1440
    height: 900
    visible: true
    title: "ESCATO — Gestion scolaire"
    color: "#F4F7FA"

    Loader {
        anchors.fill: parent
        sourceComponent: school.loggedIn ? appComponent : (school.needsSetup ? setupComponent : loginComponent)
    }

    Component {
        id: loginComponent
        LoginPage { onSuccess: {} }
    }

    Component {
        id: setupComponent
        SetupPage {}
    }

    Component {
        id: appComponent
        RowLayout {
            spacing: 0
            Sidebar {
                id: side
                currentPage: win.page
                Layout.preferredWidth: 240
                Layout.fillHeight: true
                onNavigate: function(target) { win.page = target }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StackLayout {
                    id: pages
                    anchors.fill: parent
                    anchors.margins: 28
                    currentIndex: {
                        var map={"dashboard":0,"students":1,"studentForm":2,"studentDetail":3,"teachers":4,"teacherForm":5,"courses":6,"exams":7,"finance":8,"accounting":9,"communication":10,"accounts":11,"bulletin":12}
                        return map[win.page]===undefined?0:map[win.page]
                    }

                    DashboardPage {}

                    StudentsPage {
                        onRegisterRequested: win.page="studentForm"
                        onDetailRequested: function(id){ win.studentDetailId=id; win.page="studentDetail" }
                    }

                    StudentFormPage { onSaved: win.page="students" }

                    StudentDetailPage {
                        studentId: win.studentDetailId
                        onBack: win.page="students"
                    }

                    TeachersPage { onCreateRequested: win.page="teacherForm" }
                    TeacherFormPage { onSaved: win.page="teachers" }
                    CoursesPage {}
                    ExamsPage {}
                    FinancePage {}
                    AccountingPage {}
                    CommunicationPage {}
                    AccountsPage {}
                    BulletinPage {}
                }
            }
        }
    }

    property string page: "dashboard"
    property int studentDetailId: 0

    Toast { id: toast }

    Connections {
        target: school
        function onErrorOccurred(message) { toast.message = message; toast.open() }
        function onSessionChanged() {
            if (!school.loggedIn) win.page = "dashboard"
        }
    }
}
ESCATO_EOF
mkdir -p "qml/components"
cat > "qml/components/Sidebar.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#092B45"
    property string currentPage: "dashboard"
    signal navigate(string page)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 6

        Label {
            text: "ESCATO"
            color: "white"
            font.pixelSize: 22
            font.bold: true
            Layout.bottomMargin: 18
        }

        Label {
            text: school.currentUser
            color: "#B9D7EF"
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.bottomMargin: 12
        }

        Repeater {
            model: [
                ["dashboard","Tableau de bord","⌂"],
                ["students","Élèves","👨‍🎓"],
                ["teachers","Enseignants","👨‍🏫"],
                ["courses","Cours","📚"],
                ["exams","Examens & notes","📝"],
                ["finance","Paiements / factures","💰"],
                ["accounting","Comptabilité","🧾"],
                ["communication","Messages / annonces","💬"],
                ["accounts","Comptes / sécurité","🔐"],
                ["bulletin","Bulletins","📄"]
            ]
            delegate: Button {
                Layout.fillWidth: true
                text: modelData[2] + "  " + modelData[1]
                highlighted: root.currentPage === modelData[0]
                onClicked: root.navigate(modelData[0])
            }
        }

        Item { Layout.fillHeight: true }

        Button {
            Layout.fillWidth: true
            text: "Déconnexion"
            onClicked: school.logout()
        }
    }
}
ESCATO_EOF
mkdir -p "qml/components"
cat > "qml/components/StatCard.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls

Rectangle {
    property string title
    property string value
    implicitWidth: 210
    implicitHeight: 105
    radius: 14
    color: "white"
    border.color: "#E4EAF0"
    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 8
        Label { text: title; color: "#667085" }
        Label { text: value; font.pixelSize: 27; font.bold: true; color: "#0B2A43" }
    }
}
ESCATO_EOF
mkdir -p "qml/components"
cat > "qml/components/Toast.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls

Popup {
    id: toast
    property string message: ""
    modal: false
    padding: 14
    x: parent ? parent.width - width - 25 : 0
    y: 25
    background: Rectangle { radius: 10; color: "#0B2A43" }
    contentItem: Label { text: toast.message; color: "white" }
    Timer { interval: 2500; running: toast.opened; onTriggered: toast.close() }
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/AccountingPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    property var dash: ({})
    property var accounts: []
    property var expenseAccounts: []
    property bool messageOk: true
    property var expensesModel: []
    property var journalModel: []
    property var balanceModel: []
    property string message: ""

    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Comptabilité"; font.pixelSize: 28; font.bold: true }
            Item { Layout.fillWidth: true }
            Button { text: "Actualiser"; onClicked: refresh() }
        }

        RowLayout {
            Layout.fillWidth: true
            Repeater {
                model: [
                    ["Caisse", dash.cash || 0],
                    ["Banque", dash.bank || 0],
                    ["Écolages", dash.revenue || 0],
                    ["Dépenses", dash.expenses || 0],
                    ["Impayés", dash.receivables || 0]
                ]
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 82
                    radius: 10
                    color: "white"
                    border.color: "#DCE5ED"
                    Column { anchors.centerIn: parent; spacing: 4; Label { text: modelData[0]; color: "#637381" }; Label { text: Number(modelData[1]).toLocaleString(Qt.locale(), 'f', 0) + " Ar"; font.pixelSize: 20; font.bold: true } }
                }
            }
        }

        TabBar {
            id: tabs
            Layout.fillWidth: true
            TabButton { text: "Dépenses" }
            TabButton { text: "Journal" }
            TabButton { text: "Balance" }
            TabButton { text: "Plan comptable" }
            TabButton { text: "Excel / Sage / Odoo" }
        }

        StackLayout {
            currentIndex: tabs.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                ColumnLayout { anchors.fill: parent; spacing: 10
                    RowLayout { Layout.fillWidth: true
                        TextField { id: cat; placeholderText: "Catégorie"; Layout.preferredWidth: 150 }
                        TextField { id: desc; placeholderText: "Description"; Layout.fillWidth: true }
                        TextField { id: amount; placeholderText: "Montant"; inputMethodHints: Qt.ImhDigitsOnly; Layout.preferredWidth: 120 }
                        ComboBox { id: method; model: ["especes","virement","mvola","orange_money","airtel_money"] }
                        ComboBox { id: acct; model: expenseAccounts; textRole: "label"; Layout.preferredWidth: 220 }
                        Button { text: "Enregistrer"; onClicked: { var a = Number(amount.text.replace(',', '.')); if (!cat.text || !desc.text || !(a > 0)) { messageOk = false; message = 'Catégorie, description et montant (> 0) sont obligatoires.'; return } if (school.addExpense({date: Qt.formatDate(new Date(), 'yyyy-MM-dd'), category: cat.text, description: desc.text, amount: a, method: method.currentText, accountCode: acct.currentIndex >= 0 ? expenseAccounts[acct.currentIndex].code : '606000'})) { cat.text=''; desc.text=''; amount.text=''; messageOk = true; message='Dépense enregistrée' } else { messageOk = false; message = 'Échec de l\'enregistrement de la dépense.' } } }
                    }
                    Label { text: message; color: messageOk ? "#2E7D32" : "#C62828" }
                    ListView { Layout.fillWidth: true; Layout.fillHeight: true; model: expensesModel; clip: true
                        delegate: Rectangle { width: parent.width; height: 48; color: index % 2 ? "#FAFBFC" : "white"; RowLayout { anchors.fill: parent; anchors.margins: 10; Label { text: modelData.date; Layout.preferredWidth: 100 }; Label { text: modelData.category; Layout.preferredWidth: 130 }; Label { text: modelData.description; Layout.fillWidth: true }; Label { text: Number(modelData.amount).toLocaleString(Qt.locale(), 'f', 0) + " Ar"; Layout.preferredWidth: 130 }; Label { text: modelData.method; Layout.preferredWidth: 120 }; Label { text: modelData.accountCode; Layout.preferredWidth: 90 } } }
                    }
                }
            }

            Item {
                ListView { anchors.fill: parent; model: journalModel; clip: true
                    delegate: Rectangle { width: parent.width; height: 54; color: index % 2 ? "#FAFBFC" : "white"; RowLayout { anchors.fill: parent; anchors.margins: 10; Label { text: modelData.date; Layout.preferredWidth: 100 }; Label { text: modelData.journal; Layout.preferredWidth: 90 }; Label { text: modelData.accountCode; Layout.preferredWidth: 90 }; Label { text: modelData.lineLabel; Layout.fillWidth: true }; Label { text: Number(modelData.debit).toLocaleString(Qt.locale(), 'f', 0); Layout.preferredWidth: 120 }; Label { text: Number(modelData.credit).toLocaleString(Qt.locale(), 'f', 0); Layout.preferredWidth: 120 } } }
                }
            }

            Item {
                ListView { anchors.fill: parent; model: balanceModel; clip: true
                    delegate: Rectangle { width: parent.width; height: 52; color: index % 2 ? "#FAFBFC" : "white"; RowLayout { anchors.fill: parent; anchors.margins: 10; Label { text: modelData.code; Layout.preferredWidth: 90 }; Label { text: modelData.label; Layout.fillWidth: true }; Label { text: Number(modelData.debit).toLocaleString(Qt.locale(), 'f', 0); Layout.preferredWidth: 130 }; Label { text: Number(modelData.credit).toLocaleString(Qt.locale(), 'f', 0); Layout.preferredWidth: 130 }; Label { text: Number(modelData.balance).toLocaleString(Qt.locale(), 'f', 0); Layout.preferredWidth: 130 } } }
                }
            }

            Item {
                ListView { anchors.fill: parent; model: accounts; clip: true
                    delegate: Rectangle { width: parent.width; height: 50; color: index % 2 ? "#FAFBFC" : "white"; RowLayout { anchors.fill: parent; anchors.margins: 10; Label { text: modelData.code; Layout.preferredWidth: 100 }; Label { text: modelData.label; Layout.fillWidth: true }; Label { text: modelData.type; Layout.preferredWidth: 120 } } }
                }
            }

            Item {
                ColumnLayout { anchors.fill: parent; spacing: 12
                    Label { text: "Exports compatibles avec Microsoft Excel et formats d'échange comptable"; font.pixelSize: 18; font.bold: true }
                    Label { text: "Les exports sont enregistrés dans : " + school.accountingExportDirectory(); wrapMode: Text.Wrap; Layout.fillWidth: true; color: "#637381" }
                    Flow { Layout.fillWidth: true; spacing: 10
                        Button { text: "Paiements → Excel (CSV)"; onClicked: exportKind("payments") }
                        Button { text: "Dépenses → Excel (CSV)"; onClicked: exportKind("expenses") }
                        Button { text: "Journal → Excel (CSV)"; onClicked: exportKind("journal") }
                        Button { text: "Balance → Excel (CSV)"; onClicked: exportKind("trial_balance") }
                        Button { text: "Export Sage 100 (CSV)"; onClicked: exportKind("sage100") }
                        Button { text: "Export Odoo (CSV)"; onClicked: exportKind("odoo") }
                    }
                    Label { text: message; color: messageOk ? "#2E7D32" : "#C62828"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Label { text: "Remarque : les formats Sage 100 et Odoo sont des exports structurés à mapper/importer selon la version et le paramétrage du logiciel comptable."; color: "#637381"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    function refresh() {
        dash = school.accountingDashboard()
        accounts = school.chartOfAccounts()
        expenseAccounts = accounts.filter(function(a) { return a.type === 'expense' })
        expensesModel = school.expenses()
        journalModel = school.journal()
        balanceModel = school.trialBalance()
    }
    function exportKind(kind) {
        messageOk = school.exportAccountingCsv(kind)
        message = messageOk ? "Export " + kind + " terminé dans : " + school.accountingExportDirectory() : "Échec de l'export " + kind
    }
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/AccountsPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    property var rows:[]
    Component.onCompleted:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ColumnLayout{anchors.fill:parent;spacing:15
        RowLayout{Label{text:"Comptes & sécurité";font.pixelSize:28;font.bold:true};Item{Layout.fillWidth:true};Button{text:"Créer un compte";onClicked:create.open()}}
        ListView{Layout.fillWidth:true;Layout.fillHeight:true;model:rows
            delegate:Rectangle{width:parent.width;height:65;color:index%2?"#FAFBFC":"white"
                Row{anchors.fill:parent;anchors.margins:12;spacing:25
                    Label{text:modelData.name;width:180};Label{text:modelData.email;width:220};Label{text:modelData.role;width:130};Label{text:modelData.status;width:100};Label{text:modelData.blockedReason;width:250}
                    Button{text:"Bloquer";enabled:modelData.status==="active";onClicked:school.blockUser(modelData.id,"administratif","Blocage administratif")}
                    Button{text:"Débloquer";enabled:modelData.status!=="active";onClicked:school.unblockUser(modelData.id)}
                }
            }
        }
    }
    Dialog{id:create;title:"Créer un compte";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:400
            TextField{id:name;placeholderText:"Nom"}
            TextField{id:email;placeholderText:"E-mail"}
            TextField{id:password;placeholderText:"Mot de passe";echoMode:TextInput.Password}
            ComboBox{id:role;model:school.roles()}
        }
        onAccepted:school.createUser({name:name.text,email:email.text,password:password.text,role:role.currentText})
    }
    function refresh(){rows=school.users()}
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/BulletinPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    property var rows:[]
    property var result:({})
    ColumnLayout{anchors.fill:parent;spacing:15
        Label{text:"Bulletins";font.pixelSize:28;font.bold:true}
        RowLayout{ComboBox{id:students;model:rows;Layout.fillWidth:true;textRole:"label";valueRole:"value"};ComboBox{id:term;model:school.terms()};Button{text:"Générer";onClicked:result=school.bulletin(students.currentValue,term.currentText)}}
        Rectangle{Layout.fillWidth:true;Layout.fillHeight:true;color:"white";radius:14
            Column{anchors.fill:parent;anchors.margins:20;spacing:12
                Label{text:result.student ? result.student.firstName+" "+result.student.lastName : "Sélectionnez un élève";font.pixelSize:24;font.bold:true}
                Label{text:result.generalAverage ? "Moyenne générale : "+result.generalAverage+"/20" : ""}
                Repeater{model:result.subjects||[];delegate:Label{text:modelData.subject+" : "+modelData.average+"/20"}}
            }
        }
    }
    Connections{target:school;function onDataChanged(){loadStudents()}}
    Component.onCompleted:loadStudents()
    function loadStudents(){
        var s=school.students();var a=[];for(var i=0;i<s.length;i++)a.push({label:s[i].firstName+" "+s[i].lastName+" — "+s[i].className,value:s[i].id});rows=a
    }
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/CommunicationPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    property var msgs:[]
    property var anns:[]
    property var userList:[]
    Component.onCompleted:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ColumnLayout{anchors.fill:parent;spacing:15
        RowLayout{Label{text:"Communication";font.pixelSize:28;font.bold:true};Item{Layout.fillWidth:true};Button{text:"Nouveau message";onClicked:message.open()};Button{text:"Nouvelle annonce";onClicked:announcement.open()}}
        TabBar{id:tabs;TabButton{text:"Messages"};TabButton{text:"Annonces"}}
        StackLayout{currentIndex:tabs.currentIndex;Layout.fillWidth:true;Layout.fillHeight:true
            ListView{model:msgs;delegate:Rectangle{width:parent.width;height:75;color:index%2?"#FAFBFC":"white";Column{anchors.fill:parent;anchors.margins:12;Label{text:modelData.subject;font.bold:true};Label{text:modelData.sender+" → "+modelData.recipient};Label{text:modelData.body;elide:Text.ElideRight;width:parent.width}}}}
            ListView{model:anns;delegate:Rectangle{width:parent.width;height:90;color:index%2?"#FAFBFC":"white";Column{anchors.fill:parent;anchors.margins:12;Label{text:modelData.title;font.bold:true};Label{text:modelData.body;elide:Text.ElideRight};Label{text:modelData.eventDate}}}}
        }
    }
    Dialog{id:message;title:"Envoyer un message";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:450
            ComboBox{id:recipientBox;width:parent.width;model:userList;textRole:"label";valueRole:"value"}
            TextField{id:msgSubject;placeholderText:"Objet"}
            TextArea{id:msgBody;placeholderText:"Message";width:450;height:160}
        }
        onAccepted:{if(recipientBox.currentValue===undefined||!msgSubject.text||!msgBody.text)return;school.sendMessage(recipientBox.currentValue,msgSubject.text,msgBody.text);msgSubject.text="";msgBody.text=""}
    }
    Dialog{id:announcement;title:"Nouvelle annonce";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:450
            TextField{id:annTitle;placeholderText:"Titre"}
            TextField{id:eventDate;placeholderText:"Date événement"}
            TextArea{id:annBody;placeholderText:"Contenu";width:450;height:160}
        }
        onAccepted:{if(!annTitle.text||!annBody.text)return;school.addAnnouncement({title:annTitle.text,body:annBody.text,eventDate:eventDate.text});annTitle.text="";annBody.text="";eventDate.text=""}
    }
    function refresh(){msgs=school.messages();anns=school.announcements();var u=school.users(),l=[];for(var i=0;i<u.length;i++)l.push({label:u[i].name+" ("+u[i].role+")",value:u[i].id});userList=l}
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/CoursesPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    property var rows:[]
    property var teacherList:[]
    Component.onCompleted:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ColumnLayout{anchors.fill:parent;spacing:15
        RowLayout{Label{text:"Cours";font.pixelSize:28;font.bold:true};Item{Layout.fillWidth:true};Button{text:"➕ Créer un cours";onClicked:form.open()}}
        ComboBox{id:filter;model:["Toutes les classes"].concat(school.classes());onCurrentTextChanged:refresh()}
        ListView{Layout.fillWidth:true;Layout.fillHeight:true;model:rows
            delegate:Rectangle{width:parent.width;height:65;color:index%2?"#FAFBFC":"white"
                Row{anchors.fill:parent;anchors.margins:12;spacing:20
                    Label{text:modelData.className;width:110}
                    Label{text:modelData.subject;width:150}
                    Label{text:modelData.title;width:220}
                    Label{text:modelData.teacher;width:170}
                    Label{text:modelData.description;width:250}
                }
            }
        }
    }
    Dialog{id:form;title:"Créer un cours";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:400
            TextField{id:title;placeholderText:"Titre"}
            TextField{id:subject;placeholderText:"Matière"}
            ComboBox{id:classBox;model:school.classes()}
            TextArea{id:description;placeholderText:"Description"}
            ComboBox{id:teacherBox;width:parent.width;model:teacherList;textRole:"label";valueRole:"value"}
        }
        onAccepted:{if(!title.text||!subject.text)return;school.addCourse({title:title.text,subject:subject.text,className:classBox.currentText,description:description.text,teacherId:teacherBox.currentValue>0?teacherBox.currentValue:null});title.text="";subject.text="";description.text=""}
    }
    function refresh(){rows=school.courses(filter.currentIndex>0?filter.currentText:"");var t=[{label:"Non affecté",value:0}],ts=school.teachers();for(var i=0;i<ts.length;i++)t.push({label:ts[i].name,value:ts[i].id});teacherList=t}
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/DashboardPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ESCATO

ScrollView {
    clip: true
    ColumnLayout {
        width: parent.width
        spacing: 22

        Label { text: "Tableau de bord"; font.pixelSize: 30; font.bold: true }
        Label { text: "Vue centralisée de l'établissement"; color: "#667085" }

        RowLayout {
            spacing: 15
            StatCard { title: "Élèves"; value: school.studentCount }
            StatCard { title: "Enseignants"; value: school.teacherCount }
            StatCard { title: "Cours"; value: school.courseCount }
            StatCard { title: "Factures en attente"; value: school.pendingInvoiceCount }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 170
            radius: 16
            color: "#0B2A43"
            Column {
                anchors.fill: parent; anchors.margins: 25; spacing: 10
                Label { text: "Gestion centralisée"; color: "white"; font.pixelSize: 23; font.bold: true }
                Label { text: "Élèves • Enseignants • Cours • Examens • Paiements • Communication"; color: "#D9EAF7" }
                Label { text: "Les modules sont séparés dans le code tout en partageant la même base SQLite."; color: "#B9D7EF" }
            }
        }
    }
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/ExamsPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    property var rows:[]
    property var courseList:[]
    Component.onCompleted:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ColumnLayout{anchors.fill:parent;spacing:15
        RowLayout{Label{text:"Examens";font.pixelSize:28;font.bold:true};Item{Layout.fillWidth:true};Button{text:"➕ Planifier";onClicked:form.open()}}
        ListView{Layout.fillWidth:true;Layout.fillHeight:true;model:rows
            delegate:Rectangle{width:parent.width;height:62;color:index%2?"#FAFBFC":"white"
                Row{anchors.fill:parent;anchors.margins:12;spacing:20
                    Label{text:modelData.date;width:110};Label{text:modelData.className;width:100};Label{text:modelData.subject;width:150};Label{text:modelData.title;width:200};Label{text:modelData.term;width:120};Label{text:"/ "+modelData.maxScore;width:70}
                    Button{text:"Notes";onClicked:{gradeExamId=modelData.id;grades.open()}}
                }
            }
        }
    }
    property int gradeExamId:0
    Dialog{id:form;title:"Planifier un examen";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:400
            ComboBox{id:courseBox;width:parent.width;model:courseList;textRole:"label";valueRole:"id"}
            TextField{id:title;placeholderText:"Titre"}
            ComboBox{id:term;model:school.terms()}
            TextField{id:date;placeholderText:"AAAA-MM-JJ"}
            SpinBox{id:maxScore;from:1;to:100;value:20}
        }
        onAccepted:{if(courseBox.currentValue===undefined||!title.text||!/^\d{4}-\d{2}-\d{2}$/.test(date.text))return;school.addExam({courseId:courseBox.currentValue,title:title.text,term:term.currentText,date:date.text,maxScore:maxScore.value});title.text="";date.text=""}
    }
    Dialog{id:grades;title:"Saisie des notes";modal:true;anchors.centerIn:Overlay.overlay;width:900;height:600;standardButtons:Dialog.Close
        GradesPage{anchors.fill:parent;examId:gradeExamId}
    }
    function refresh(){rows=school.exams();var c=school.courses(),l=[];for(var i=0;i<c.length;i++)l.push({label:c[i].className+" — "+c[i].subject+" — "+c[i].title,id:c[i].id});courseList=l}
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/FinancePage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    property var inv:[]
    property var pays:[]
    property var studentList:[]
    Component.onCompleted:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ColumnLayout{anchors.fill:parent;spacing:15
        RowLayout{Label{text:"Paiements & factures";font.pixelSize:28;font.bold:true};Item{Layout.fillWidth:true};Button{text:"Nouveau paiement";highlighted:true;onClicked:payDialog.open()};Button{text:"Tarif mensuel";onClicked:feeDialog.open()};Button{text:"Générer factures du mois";onClicked:school.generateMonthlyInvoices(Qt.formatDate(new Date(),"yyyy-MM"))};Button{text:"Traiter rappels";onClicked:school.processPaymentReminders()}}
        TabBar{id:tabs;TabButton{text:"Factures"};TabButton{text:"Paiements"}}
        StackLayout{currentIndex:tabs.currentIndex;Layout.fillWidth:true;Layout.fillHeight:true
            ListView{model:inv;delegate:Rectangle{width:parent.width;height:55;color:index%2?"#FAFBFC":"white";Row{anchors.fill:parent;anchors.margins:12;spacing:30;Label{text:modelData.student;width:220};Label{text:modelData.month;width:110};Label{text:modelData.dueDate;width:110};Label{text:modelData.amount+" Ar";width:120};Label{text:modelData.status}}}}
            ListView{model:pays;delegate:Rectangle{width:parent.width;height:55;color:index%2?"#FAFBFC":"white";Row{anchors.fill:parent;anchors.margins:12;spacing:30;Label{text:modelData.student;width:220};Label{text:modelData.amount+" Ar";width:120};Label{text:modelData.method;width:130};Label{text:modelData.paidAt;width:120};Label{text:modelData.payerRole}}}}
        }
    }
    Dialog{id:payDialog;title:"Enregistrer un paiement";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:400
            ComboBox{id:payStudent;width:parent.width;model:studentList;textRole:"label";valueRole:"value"}
            TextField{id:payAmount;width:parent.width;placeholderText:"Montant (Ar)"}
            ComboBox{id:payMethod;width:parent.width;model:school.paymentMethods()}
            TextField{id:payRef;width:parent.width;placeholderText:"Référence (facultatif)"}
        }
        onAccepted:{
            var a=parseFloat(payAmount.text.replace(",","."))
            if(payStudent.currentValue===undefined||!(a>0))return
            school.addPayment({studentId:payStudent.currentValue,amount:a,method:payMethod.currentText,reference:payRef.text,paidAt:Qt.formatDateTime(new Date(),"yyyy-MM-dd hh:mm:ss"),notes:""})
            payAmount.text="";payRef.text=""
        }
    }
    Dialog{id:feeDialog;title:"Tarif mensuel d'un élève";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:400
            ComboBox{id:feeStudent;width:parent.width;model:studentList;textRole:"label";valueRole:"value"}
            TextField{id:feeAmount;width:parent.width;placeholderText:"Montant mensuel (Ar)"}
        }
        onAccepted:{
            var a=parseFloat(feeAmount.text.replace(",","."))
            if(feeStudent.currentValue===undefined||!(a>0))return
            school.setStudentFee(feeStudent.currentValue,a)
            feeAmount.text=""
        }
    }
    function refresh(){
        inv=school.invoices();pays=school.payments()
        var s=school.students(),l=[]
        for(var i=0;i<s.length;i++)l.push({label:s[i].lastName+" "+s[i].firstName+" — "+s[i].className,value:s[i].id})
        studentList=l
    }
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/GradesPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    property int examId:0
    property var rows:[]
    Component.onCompleted:refresh()
    onExamIdChanged:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ListView{anchors.fill:parent;model:rows
        delegate:RowLayout{width:parent.width;height:50
            Label{text:modelData.lastName+" "+modelData.firstName;Layout.preferredWidth:240}
            TextField{id:score;Layout.preferredWidth:100;placeholderText:"Note";text:(modelData.score===undefined||modelData.score===null||modelData.score==="")?"":String(modelData.score)}
            TextField{id:comment;Layout.fillWidth:true;placeholderText:"Commentaire";text:modelData.comment||""}
            Button{text:"Enregistrer";enabled:score.text!=="";onClicked:school.saveGrade(examId,modelData.studentId,parseFloat(score.text.replace(",",".")),comment.text)}
        }
    }
    function refresh(){rows=school.grades(examId)}
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/LoginPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    color: "#EEF4F8"
    signal success()

    Rectangle {
        width: 420; height: 400
        anchors.centerIn: parent
        radius: 22
        color: "white"
        border.color: "#E1E8EF"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 38
            spacing: 18

            Label { text: "ESCATO"; font.pixelSize: 30; font.bold: true; color: "#0B2A43"; Layout.alignment: Qt.AlignHCenter }
            Label { text: "Accédez à votre espace de travail"; color: "#667085"; Layout.alignment: Qt.AlignHCenter }

            TextField { id: email; Layout.fillWidth: true; placeholderText: "Adresse e-mail" }
            TextField { id: password; Layout.fillWidth: true; placeholderText: "Mot de passe"; echoMode: TextInput.Password; onAccepted: doLogin() }

            Button {
                Layout.fillWidth: true
                text: "Se connecter"
                highlighted: true
                onClicked: doLogin()
            }

            Label { id: error; color: "#C62828"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
    }

    function doLogin() {
        error.text = ""
        if (school.login(email.text, password.text)) success()
        else error.text = "Identifiants incorrects ou compte bloqué."
    }
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/SetupPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Affiché uniquement tant qu'aucun administrateur n'existe (premier lancement).
Rectangle {
    color: "#EEF4F8"

    Rectangle {
        width: 460; height: 590
        anchors.centerIn: parent
        radius: 22
        color: "white"
        border.color: "#E1E8EF"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 38
            spacing: 14

            Label { text: "ESCATO"; font.pixelSize: 30; font.bold: true; color: "#0B2A43"; Layout.alignment: Qt.AlignHCenter }
            Label { text: "Première configuration"; font.pixelSize: 18; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Label {
                text: "Créez le compte administrateur. Il aura le contrôle complet de l'application et pourra ensuite créer tous les autres comptes."
                color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }

            TextField { id: fullName; Layout.fillWidth: true; placeholderText: "Nom complet" }
            TextField { id: adminEmail; Layout.fillWidth: true; placeholderText: "Adresse e-mail"; inputMethodHints: Qt.ImhEmailCharactersOnly }
            TextField { id: pwd; Layout.fillWidth: true; placeholderText: "Mot de passe (8 caractères minimum)"; echoMode: TextInput.Password }
            TextField { id: pwd2; Layout.fillWidth: true; placeholderText: "Confirmer le mot de passe"; echoMode: TextInput.Password; onAccepted: submit() }

            Button {
                Layout.fillWidth: true
                text: "Créer le compte administrateur"
                highlighted: true
                onClicked: submit()
            }

            Label { id: error; color: "#C62828"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Item { Layout.fillHeight: true }
        }
    }

    function submit() {
        error.text = ""
        if (!fullName.text.trim() || !adminEmail.text.trim()) { error.text = "Le nom et l'adresse e-mail sont obligatoires."; return }
        if (pwd.text.length < 8) { error.text = "Le mot de passe doit contenir au moins 8 caractères."; return }
        if (pwd.text !== pwd2.text) { error.text = "Les deux mots de passe ne correspondent pas."; return }
        // En cas de succès, la session s'ouvre automatiquement et Main.qml affiche l'application.
        school.createFirstAdmin(fullName.text, adminEmail.text, pwd.text)
    }
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/StudentDetailPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    property int studentId: 0
    signal back()

    ColumnLayout {
        anchors.fill: parent; spacing:16
        RowLayout {
            Label{text:"Fiche élève";font.pixelSize:28;font.bold:true}
            Item{Layout.fillWidth:true}
            Button{text:"← Retour";onClicked:back()}
            Button{text:"🖨 Imprimer la liste";onClicked:printer.printStudentList(info.className)}
        }
        Rectangle {
            Layout.fillWidth:true; Layout.fillHeight:true; radius:16; color:"white"
            Column {
                anchors.fill:parent; anchors.margins:25; spacing:12
                Label{text:info.firstName+" "+info.lastName; font.pixelSize:28;font.bold:true;color:"#0B2A43"}
                Label{text:"Matricule : "+info.matricule}
                Label{text:"Classe : "+info.className}
                Label{text:"Date de naissance : "+info.birthDate+" — "+info.birthPlace}
                Label{text:"Téléphone parent : "+info.parentPhone}
                Label{text:"E-mail parent : "+info.parentEmail}
                Label{text:"Adresse : "+info.address}
                Label{text:"Ancienne école : "+info.previousSchool}
                Label{text:"Projet : "+info.desiredCareer}
                Label{text:"Paiements manqués consécutifs : "+info.missedPayments}
                Label{text:"Statut du compte : "+info.accountStatus}
                Row {
                    spacing:8
                    Button{text:"Diplômé";onClicked:school.graduateStudent(studentId)}
                    Button{text:"Bloquer";onClicked:school.blockStudent(studentId,"Blocage administratif")}
                    Button{text:"Débloquer";onClicked:school.unblockStudent(studentId)}
                }
            }
        }
    }
    property var info: ({})
    onStudentIdChanged: refresh()
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }
    function refresh() { info = school.student(studentId) }
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/StudentFormPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    signal saved()
    property int editingId: 0

    ColumnLayout {
        anchors.fill: parent; spacing: 16
        RowLayout {
            Label { text: editingId ? "Modifier l'élève" : "Inscrire un élève"; font.pixelSize:28; font.bold:true }
            Item { Layout.fillWidth:true }
            Button { text:"← Retour"; onClicked:saved() }
        }

        ScrollView {
            Layout.fillWidth:true; Layout.fillHeight:true
            GridLayout {
                width: parent.width; columns:2; columnSpacing:20; rowSpacing:14

                Label{text:"Nom *"}; TextField{id: lastName; Layout.fillWidth:true}
                Label{text:"Prénom *"}; TextField{id: firstName; Layout.fillWidth:true}
                Label{text:"Date de naissance *"}; TextField{id: birthDate; placeholderText:"AAAA-MM-JJ"; Layout.fillWidth:true}
                Label{text:"Lieu de naissance"}; TextField{id: birthPlace; Layout.fillWidth:true}
                Label{text:"Père"}; TextField{id: father; Layout.fillWidth:true}
                Label{text:"Profession du père"}; TextField{id: fatherJob; Layout.fillWidth:true}
                Label{text:"Mère"}; TextField{id: mother; Layout.fillWidth:true}
                Label{text:"Profession de la mère"}; TextField{id: motherJob; Layout.fillWidth:true}
                Label{text:"Téléphone parent *"}; TextField{id: parentPhone; Layout.fillWidth:true}
                Label{text:"E-mail parent"}; TextField{id: parentEmail; Layout.fillWidth:true}
                Label{text:"Adresse *"}; TextField{id: address; Layout.fillWidth:true}
                Label{text:"Ancienne école"}; TextField{id: previousSchool; Layout.fillWidth:true}
                Label{text:"Ancienne classe"}; TextField{id: previousClass; Layout.fillWidth:true}
                Label{text:"Classe actuelle *"}
                ComboBox { id: classBox; model:school.classes(); Layout.fillWidth:true }
                Label{text:"Projet / carrière"}; TextField{id: career; Layout.fillWidth:true}

                Label { id: formError; Layout.columnSpan:2; color:"#C62828"; visible: text !== "" }

                Button {
                    Layout.columnSpan:2; Layout.alignment:Qt.AlignRight
                    text:editingId?"Enregistrer les modifications":"Enregistrer l'élève"
                    highlighted:true
                    onClicked: save()
                }
            }
        }
    }

    function formData() {
        return {
            lastName:lastName.text, firstName:firstName.text, birthDate:birthDate.text,
            birthPlace:birthPlace.text, fatherName:father.text, fatherJob:fatherJob.text,
            motherName:mother.text, motherJob:motherJob.text, parentPhone:parentPhone.text,
            parentEmail:parentEmail.text, address:address.text, previousSchool:previousSchool.text,
            previousClass:previousClass.text, className:classBox.currentText,
            desiredCareer:career.text, photo:""
        }
    }

    function save() {
        formError.text = ""
        if (!lastName.text || !firstName.text || !birthDate.text || !parentPhone.text || !address.text || classBox.currentIndex < 0) {
            formError.text = "Merci de remplir tous les champs marqués d'un *."
            return
        }
        if (!/^\d{4}-\d{2}-\d{2}$/.test(birthDate.text)) {
            formError.text = "La date de naissance doit être au format AAAA-MM-JJ."
            return
        }
        var ok = editingId ? school.updateStudent(editingId,formData()) : school.addStudent(formData())
        if(ok) { reset(); saved() }
    }

    function reset() {
        [lastName, firstName, birthDate, birthPlace, father, fatherJob, mother, motherJob,
         parentPhone, parentEmail, address, previousSchool, previousClass, career].forEach(function(f){ f.text = "" })
        classBox.currentIndex = 0
        formError.text = ""
    }
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/StudentsPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    signal registerRequested()
    signal detailRequested(int id)
    property string selectedClass: ""
    property string searchText: ""
    property var rows: []

    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ColumnLayout {
        anchors.fill: parent; spacing: 15

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Liste des élèves"; font.pixelSize: 28; font.bold: true }
            Item { Layout.fillWidth: true }
            Button { text: "➕ Inscrire un élève"; highlighted: true; onClicked: registerRequested() }
            Button { text: "🖨 Print list"; onClicked: printer.printStudentList(selectedClass) }
        }

        RowLayout {
            Layout.fillWidth: true
            TextField { Layout.fillWidth: true; placeholderText: "Rechercher nom, prénom ou matricule"; onTextChanged: { searchText=text; refresh() } }
            ComboBox { model: ["Toutes les classes"].concat(school.classes()); onCurrentTextChanged: { selectedClass=currentIndex===0?"":currentText; refresh() } }
            Button { text: "Actualiser"; onClicked: refresh() }
        }

        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; radius: 14; color: "white"; border.color: "#E3E8EE"
            ListView {
                id: list; anchors.fill: parent; anchors.margins: 12; clip: true; model: rows
                header: Rectangle {
                    width: list.width; height: 45; color: "#EEF3F7"
                    Row { anchors.fill: parent; anchors.leftMargin: 12
                        Label { text:"Matricule"; width:130; font.bold:true }
                        Label { text:"Nom"; width:150; font.bold:true }
                        Label { text:"Prénom"; width:150; font.bold:true }
                        Label { text:"Classe"; width:110; font.bold:true }
                        Label { text:"Téléphone parent"; width:150; font.bold:true }
                        Label { text:""; width:100 }
                    }
                }
                delegate: Rectangle {
                    width:list.width; height:55; color:index%2?"#FAFBFC":"white"
                    Row { anchors.fill:parent; anchors.leftMargin:12
                        Label { text:modelData.matricule; width:130 }
                        Label { text:modelData.lastName; width:150 }
                        Label { text:modelData.firstName; width:150 }
                        Label { text:modelData.className; width:110; font.bold:true }
                        Label { text:modelData.parentPhone; width:150 }
                        Button { text:"Profil"; onClicked: detailRequested(modelData.id) }
                    }
                }
            }
        }
    }

    function refresh() { rows = school.students(selectedClass, searchText) }
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/TeacherFormPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    signal saved()
    ColumnLayout{anchors.fill:parent;spacing:14
        RowLayout{Label{text:"Nouvel enseignant";font.pixelSize:28;font.bold:true};Item{Layout.fillWidth:true};Button{text:"← Retour";onClicked:saved()}}
        ScrollView{Layout.fillWidth:true;Layout.fillHeight:true
            GridLayout{width:parent.width;columns:2;columnSpacing:18;rowSpacing:12
                Label{text:"Nom *"};TextField{id:name;Layout.fillWidth:true}
                Label{text:"E-mail *"};TextField{id:email;Layout.fillWidth:true}
                Label{text:"Mot de passe * (8 car. min.)"};TextField{id:password;echoMode:TextInput.Password;Layout.fillWidth:true}
                Label{text:"CIN *"};TextField{id:cin;Layout.fillWidth:true}
                Label{text:"CNaPS"};TextField{id:cnaps;Layout.fillWidth:true}
                Label{text:"Matricule"};TextField{id:mle;Layout.fillWidth:true}
                Label{text:"Téléphone *"};TextField{id:contact;Layout.fillWidth:true}
                Label{text:"Adresse"};TextField{id:address;Layout.fillWidth:true}
                Label{text:"Date de naissance"};TextField{id:dob;Layout.fillWidth:true}
                Label{text:"Lieu de naissance"};TextField{id:birthPlace;Layout.fillWidth:true}
                Label{text:"Nombre d'enfants"};SpinBox{id:childCount;from:0;to:30;Layout.fillWidth:true}
                Label{text:"Situation familiale"};TextField{id:maritalStatus;Layout.fillWidth:true}
                Label{text:"Religion"};TextField{id:religion;Layout.fillWidth:true}
                Label{text:"Matière *"};TextField{id:subject;Layout.fillWidth:true}
                Label{text:"Fonction"};TextField{id:occupation;Layout.fillWidth:true}
                Label{text:"Type de contrat"};ComboBox{id:employmentType;model:["cdi","cdd"];Layout.fillWidth:true}
                Label{text:"Date d'embauche"};TextField{id:hiringDate;Layout.fillWidth:true}
                Label{text:"Fin de contrat"};TextField{id:contractEndDate;Layout.fillWidth:true}
                Label{text:"Commentaire"};TextArea{id:comment;Layout.fillWidth:true}
                Label{id:formError;Layout.columnSpan:2;color:"#C62828";visible:text!==""}
                Button{Layout.columnSpan:2;Layout.alignment:Qt.AlignRight;text:"Enregistrer";highlighted:true;onClicked:save()}
            }
        }
    }
    function save(){
        formError.text=""
        if(!name.text||!email.text||!cin.text||!contact.text||!subject.text||password.text.length<8){formError.text="Merci de remplir les champs marqués d'un * (mot de passe : 8 caractères minimum).";return}
        if(school.addTeacher(formData())){reset();saved()}
    }
    function reset(){
        [name,email,password,cin,cnaps,mle,contact,address,dob,birthPlace,maritalStatus,religion,subject,occupation,hiringDate,contractEndDate,comment].forEach(function(f){f.text=""})
        childCount.value=0;employmentType.currentIndex=0;formError.text=""
    }
    function formData(){return{name:name.text,email:email.text,password:password.text,cin:cin.text,cnaps:cnaps.text,mle:mle.text,contact:contact.text,address:address.text,dob:dob.text,birthPlace:birthPlace.text,children:childCount.value,maritalStatus:maritalStatus.text,religion:religion.text,subject:subject.text,occupation:occupation.text,employmentType:employmentType.currentText,hiringDate:hiringDate.text,contractEndDate:contractEndDate.text,comment:comment.text,photo:""}}
}
ESCATO_EOF
mkdir -p "qml/pages"
cat > "qml/pages/TeachersPage.qml" <<'ESCATO_EOF'
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item {
    signal createRequested()
    property var rows: []
    property string searchText:""
    Component.onCompleted:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ColumnLayout{
        anchors.fill:parent;spacing:15
        RowLayout{Layout.fillWidth:true;Label{text:"Enseignants";font.pixelSize:28;font.bold:true};Item{Layout.fillWidth:true};Button{text:"➕ Ajouter";onClicked:createRequested()};Button{text:"🖨 Imprimer";onClicked:printer.printTeacherList()}}
        TextField{Layout.fillWidth:true;placeholderText:"Rechercher enseignant, matière, CIN...";onTextChanged:searchText=text;onEditingFinished:refresh()}
        ListView{
            Layout.fillWidth:true;Layout.fillHeight:true;model:rows;clip:true
            delegate:Rectangle{width:parent.width;height:65;color:index%2?"#FAFBFC":"white"
                Row{anchors.fill:parent;anchors.margins:12
                    Label{text:modelData.name;width:170}
                    Label{text:modelData.email;width:210}
                    Label{text:modelData.subject;width:160}
                    Label{text:modelData.contact;width:140}
                    Label{text:modelData.status;width:100}
                }
            }
        }
    }
    function refresh(){rows=school.teachers(searchText)}
}
ESCATO_EOF
mkdir -p "src/core"
cat > "src/core/Database.cpp" <<'ESCATO_EOF'
#include "Database.h"
#include <QStandardPaths>
#include <QDir>
#include <QSqlQuery>
#include <QSqlError>
#include <QCryptographicHash>
#include <QDebug>

static QString hashPassword(const QString &s)
{
    return QString(QCryptographicHash::hash(s.toUtf8(), QCryptographicHash::Sha256).toHex());
}

Database::Database(QObject *parent) : QObject(parent)
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    m_db = QSqlDatabase::addDatabase("QSQLITE");
    m_db.setDatabaseName(dir + "/escato.sqlite");
}

bool Database::open()
{
    if (!m_db.open()) {
        qWarning() << m_db.lastError().text();
        return false;
    }
    exec("PRAGMA foreign_keys = ON");
    exec("PRAGMA journal_mode = WAL");
    return createSchema() && migrate() && seed();
}

QString Database::lastError() const { return m_db.lastError().text(); }

bool Database::exec(const QString &sql)
{
    QSqlQuery q(m_db);
    if (!q.exec(sql)) {
        qWarning() << q.lastError().text() << sql;
        return false;
    }
    return true;
}

bool Database::createSchema()
{
    const QStringList schema = {
        R"(CREATE TABLE IF NOT EXISTS users(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL CHECK(role IN('administrateur','enseignant','eleve','parent','comptable')),
            account_status TEXT NOT NULL DEFAULT 'active',
            suspended_until TEXT,
            blocked_reason TEXT,
            blocked_category TEXT,
            exam_dates_hidden INTEGER NOT NULL DEFAULT 0,
            requires_password_reset INTEGER NOT NULL DEFAULT 0,
            deleted_at TEXT
        ))",

        R"(CREATE TABLE IF NOT EXISTS students(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            parent_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            matricule TEXT UNIQUE,
            last_name TEXT NOT NULL,
            first_name TEXT NOT NULL,
            birth_date TEXT NOT NULL,
            birth_place TEXT,
            father_name TEXT,
            father_job TEXT,
            mother_name TEXT,
            mother_job TEXT,
            parent_phone TEXT NOT NULL,
            parent_email TEXT,
            address TEXT NOT NULL,
            previous_school TEXT,
            previous_class TEXT,
            current_class TEXT NOT NULL,
            desired_career TEXT,
            graduated_at TEXT,
            consecutive_missed_payments INTEGER NOT NULL DEFAULT 0,
            photo TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
            deleted_at TEXT
        ))",

        R"(CREATE TABLE IF NOT EXISTS teacher_profiles(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
            identity_number TEXT,
            cnaps_number TEXT,
            mle_number TEXT,
            contact TEXT,
            address TEXT,
            dob TEXT,
            place_of_birth TEXT,
            number_of_children INTEGER,
            marital_status TEXT,
            religion TEXT,
            subject TEXT,
            occupation TEXT,
            employment_type TEXT,
            hiring_date TEXT,
            contract_end_date TEXT,
            comment TEXT,
            photo TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS courses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            subject TEXT NOT NULL,
            class_name TEXT NOT NULL,
            description TEXT,
            teacher_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS course_resources(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            course_id INTEGER NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            type TEXT NOT NULL CHECK(type IN('pdf','video','quiz')),
            file_path TEXT,
            url TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS exams(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            course_id INTEGER NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            term TEXT NOT NULL,
            exam_date TEXT NOT NULL,
            max_score INTEGER NOT NULL DEFAULT 20,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS grades(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            exam_id INTEGER NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            score REAL,
            comment TEXT,
            UNIQUE(exam_id, student_id)
        ))",

        R"(CREATE TABLE IF NOT EXISTS payments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            recorded_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            amount REAL NOT NULL,
            method TEXT NOT NULL,
            payer_role TEXT NOT NULL DEFAULT 'eleve',
            reference TEXT,
            paid_at TEXT NOT NULL,
            notes TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS student_fees(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            monthly_amount REAL NOT NULL,
            set_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS invoices(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            period_month TEXT NOT NULL,
            due_date TEXT NOT NULL,
            amount REAL NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            payment_id INTEGER REFERENCES payments(id) ON DELETE SET NULL,
            reminder_before_sent_at TEXT,
            reminder_late_sent_at TEXT,
            UNIQUE(student_id, period_month)
        ))",

        R"(CREATE TABLE IF NOT EXISTS messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            recipient_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
            subject TEXT NOT NULL,
            body TEXT NOT NULL,
            read_at TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS announcements(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            event_date TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS exam_periods(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT,
            start_date TEXT,
            end_date TEXT,
            is_active INTEGER NOT NULL DEFAULT 0,
            activated_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS tardiness_records(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL REFERENCES students(id) ON DELETE CASCADE,
            recorded_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            occurred_at TEXT NOT NULL,
            note TEXT
        ))",

        R"(CREATE TABLE IF NOT EXISTS notifications(
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            data TEXT NOT NULL,
            read_at TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS audit_logs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            action TEXT NOT NULL,
            entity TEXT,
            entity_id INTEGER,
            details TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS chart_of_accounts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL UNIQUE,
            label TEXT NOT NULL,
            account_type TEXT NOT NULL DEFAULT 'general',
            active INTEGER NOT NULL DEFAULT 1
        ))",

        R"(CREATE TABLE IF NOT EXISTS journal_entries(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_date TEXT NOT NULL,
            journal_code TEXT NOT NULL,
            reference TEXT,
            description TEXT NOT NULL,
            source_type TEXT,
            source_id INTEGER,
            created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS journal_lines(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_id INTEGER NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
            account_code TEXT NOT NULL,
            label TEXT,
            debit REAL NOT NULL DEFAULT 0,
            credit REAL NOT NULL DEFAULT 0
        ))",

        R"(CREATE TABLE IF NOT EXISTS expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            expense_date TEXT NOT NULL,
            category TEXT NOT NULL,
            description TEXT NOT NULL,
            amount REAL NOT NULL,
            payment_method TEXT NOT NULL,
            reference TEXT,
            account_code TEXT NOT NULL DEFAULT '606000',
            recorded_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ))",

        R"(CREATE TABLE IF NOT EXISTS accounting_periods(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT NOT NULL UNIQUE,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            closed INTEGER NOT NULL DEFAULT 0,
            closed_at TEXT
        ))"
    };

    for (const auto &sql : schema)
        if (!exec(sql)) return false;

    return true;
}

bool Database::migrate()
{
    // Bases existantes : students.deleted_at n'existait pas (suppression logique cassée).
    QSqlQuery q(m_db);
    if (!q.exec("PRAGMA table_info(students)")) return false;
    bool hasDeletedAt = false;
    while (q.next())
        if (q.value(1).toString() == "deleted_at") hasDeletedAt = true;
    if (!hasDeletedAt && !exec("ALTER TABLE students ADD COLUMN deleted_at TEXT"))
        return false;

    // Anciennes versions : un compte administrateur codé en dur (admin@myschool.local / mot de passe
    // par défaut) était créé automatiquement. Tant qu'il porte encore le mot de passe par défaut,
    // on le retire (suppression logique + e-mail libéré) : l'écran de première configuration
    // s'affichera si plus aucun administrateur actif n'existe.
    QSqlQuery legacy(m_db);
    legacy.prepare("UPDATE users SET deleted_at=CURRENT_TIMESTAMP, account_status='blocked', "
                   "email='supprime+'||id||'@invalide.local' "
                   "WHERE email='admin@myschool.local' AND password_hash=? AND deleted_at IS NULL");
    legacy.addBindValue(hashPassword(QStringLiteral("admin123")));
    if (!legacy.exec()) {
        qWarning() << legacy.lastError().text();
        return false;
    }
    return true;
}

bool Database::seed()
{
    const QStringList accounts = {
        "411000|Parents / familles|client",
        "401000|Fournisseurs|supplier",
        "512000|Banque|bank",
        "531000|Caisse|cash",
        "580000|Transferts internes|treasury",
        "606000|Achats et charges diverses|expense",
        "641000|Salaires et charges|expense",
        "706000|Écolages / prestations scolaires|revenue",
        "758000|Autres produits|revenue"
    };
    for (const auto &a : accounts) {
        const auto parts = a.split('|');
        QSqlQuery aq(m_db);
        aq.prepare("INSERT OR IGNORE INTO chart_of_accounts(code,label,account_type) VALUES(?,?,?)");
        aq.addBindValue(parts.value(0));
        aq.addBindValue(parts.value(1));
        aq.addBindValue(parts.value(2));
        if (!aq.exec()) return false;
    }

    return true;
}
ESCATO_EOF
mkdir -p "src/core"
cat > "src/core/Database.h" <<'ESCATO_EOF'
#pragma once
#include <QObject>
#include <QSqlDatabase>
#include <QString>

class Database : public QObject
{
    Q_OBJECT
public:
    explicit Database(QObject *parent = nullptr);
    bool open();
    bool exec(const QString &sql);
    QSqlDatabase db() const { return m_db; }
    QString lastError() const;

private:
    QSqlDatabase m_db;
    bool createSchema();
    bool migrate();
    bool seed();
};
ESCATO_EOF
mkdir -p "src/core"
cat > "src/core/PrintManager.cpp" <<'ESCATO_EOF'
#include "PrintManager.h"
#include <QPrinter>
#include <QPrintDialog>
#include <QPainter>
#include <QPageSize>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QPixmap>
#include <QFontMetrics>
#include <QDialog>
#include <functional>

namespace {

// Toute la mise en page est exprimée en points (A4 = 595 x 842). Elle est convertie en pixels
// périphérique via K = résolution / 72, ce qui garde texte (en pt) et coordonnées cohérents
// quelle que soit la résolution de l'imprimante ou du PDF.
struct Page
{
    QPrinter &printer;
    QPainter &p;
    double k;
    Page(QPrinter &pr, QPainter &pa) : printer(pr), p(pa), k(pr.resolution() / 72.0) {}
    int px(double v) const { return qRound(v * k); }
    void text(double x, double y, const QString &t) { p.drawText(px(x), px(y), t); }
    void cell(double x, double y, double w, const QString &t)
    {
        p.drawText(px(x), px(y), QFontMetrics(p.font(), p.device()).elidedText(t, Qt::ElideRight, px(w)));
    }
};

// En-tête officiel utilisé par les documents administratifs imprimés par ESCATO.
// Le logo fourni par l'établissement est embarqué dans l'exécutable sous :/assets/logo.png.
double drawOfficialHeader(Page &pg, const QString &documentTitle)
{
    QPainter &p = pg.p;
    const double left = 45, right = 555, top = 35;

    const QPixmap logo(":/assets/logo.png");
    if (!logo.isNull()) {
        const int size = pg.px(82);
        p.drawPixmap(pg.px(left), pg.px(top), logo.scaled(size, size, Qt::KeepAspectRatio, Qt::SmoothTransformation));
    }

    p.setPen(Qt::black);
    p.setFont(QFont("Arial", 15, QFont::Bold));
    pg.text(left + 95, top + 24, "École Sacre Coeur");

    p.setFont(QFont("Arial", 10));
    pg.text(left + 95, top + 45, "BP 85 Tolagnaro");
    pg.text(left + 95, top + 63, "034 52 812 71");

    p.setPen(QPen(QColor("#B7B7B7"), 1));
    p.drawLine(pg.px(left), pg.px(top + 94), pg.px(right), pg.px(top + 94));

    p.setPen(Qt::black);
    p.setFont(QFont("Arial", 16, QFont::Bold));
    pg.text(left, top + 122, documentTitle);

    return top + 155;
}

void drawFooter(Page &pg)
{
    pg.p.setPen(QPen(QColor("#B7B7B7"), 1));
    pg.p.drawLine(pg.px(45), pg.px(805), pg.px(555), pg.px(805));
    pg.p.setPen(QColor("#555555"));
    pg.p.setFont(QFont("Arial", 8));
    pg.text(45, 823, "ESCATO — École Sacre Coeur — Document administratif");
}

struct Column { double x, w; QString title; };

// Tableau paginé : en-tête officiel + titres de colonnes répétés sur chaque page.
void drawTable(Page &pg, const QString &title, const QList<Column> &cols, QSqlQuery &q)
{
    auto startPage = [&]() {
        double y = drawOfficialHeader(pg, title);
        pg.p.setPen(Qt::black);
        pg.p.setFont(QFont("Arial", 9, QFont::Bold));
        for (const auto &c : cols) pg.cell(c.x, y, c.w, c.title);
        pg.p.setFont(QFont("Arial", 9));
        return y + 22;
    };

    double y = startPage();
    while (q.next()) {
        if (y > 790) {
            drawFooter(pg);
            pg.printer.newPage();
            y = startPage();
        }
        for (int i = 0; i < cols.size(); ++i)
            pg.cell(cols[i].x, y, cols[i].w, q.value(i).toString());
        y += 20;
    }
    drawFooter(pg);
}

void drawStudents(Page &pg, const QString &className)
{
    QSqlQuery q(QSqlDatabase::database());
    if (className.isEmpty()) {
        q.exec("SELECT matricule,last_name,first_name,current_class,parent_phone FROM students "
               "WHERE graduated_at IS NULL AND deleted_at IS NULL ORDER BY current_class,last_name");
    } else {
        q.prepare("SELECT matricule,last_name,first_name,current_class,parent_phone FROM students "
                  "WHERE current_class=? AND graduated_at IS NULL AND deleted_at IS NULL ORDER BY last_name");
        q.addBindValue(className);
        q.exec();
    }
    const QString title = className.isEmpty() ? QStringLiteral("LISTE DES ÉLÈVES")
                                              : QStringLiteral("LISTE DES ÉLÈVES — ") + className;
    drawTable(pg, title, {
        {45, 105, "Matricule"}, {155, 105, "Nom"}, {265, 110, "Prénom"},
        {380, 70, "Classe"}, {455, 100, "Téléphone parent"}
    }, q);
}

void drawTeachers(Page &pg)
{
    QSqlQuery q(QSqlDatabase::database());
    q.exec("SELECT u.name,u.email,t.identity_number,t.contact,t.subject "
           "FROM users u LEFT JOIN teacher_profiles t ON t.user_id=u.id "
           "WHERE u.role='enseignant' AND u.deleted_at IS NULL ORDER BY u.name");
    drawTable(pg, QStringLiteral("LISTE DES ENSEIGNANTS"), {
        {45, 100, "Nom"}, {150, 130, "Email"}, {285, 75, "CIN"},
        {365, 85, "Téléphone"}, {455, 100, "Matière"}
    }, q);
}

void render(QPrinter &printer, const std::function<void(Page &)> &draw)
{
    printer.setPageSize(QPageSize(QPageSize::A4));
    printer.setFullPage(true);   // l'origine (0,0) = coin du papier, la marge est gérée par la mise en page
    QPainter p(&printer);
    if (!p.isActive()) return;
    Page pg(printer, p);
    draw(pg);
    p.end();
}

}

PrintManager::PrintManager(QObject *parent) : QObject(parent) {}

bool PrintManager::printStudentList(const QString &className)
{
    QPrinter printer(QPrinter::HighResolution);
    QPrintDialog dlg(&printer);
    if (dlg.exec() != QDialog::Accepted) return false;
    render(printer, [&](Page &pg) { drawStudents(pg, className); });
    return true;
}

bool PrintManager::exportStudentsPdf(const QString &path, const QString &className)
{
    if (path.isEmpty()) return false;
    QPrinter printer(QPrinter::HighResolution);
    printer.setOutputFormat(QPrinter::PdfFormat);
    printer.setOutputFileName(path);
    render(printer, [&](Page &pg) { drawStudents(pg, className); });
    return true;
}

bool PrintManager::printTeacherList()
{
    QPrinter printer(QPrinter::HighResolution);
    QPrintDialog dlg(&printer);
    if (dlg.exec() != QDialog::Accepted) return false;
    render(printer, [&](Page &pg) { drawTeachers(pg); });
    return true;
}
ESCATO_EOF
mkdir -p "src/core"
cat > "src/core/PrintManager.h" <<'ESCATO_EOF'
#pragma once
#include <QObject>
#include <QString>
class PrintManager : public QObject
{
    Q_OBJECT
public:
    explicit PrintManager(QObject *parent = nullptr);
    Q_INVOKABLE bool printStudentList(const QString &className = QString());
    Q_INVOKABLE bool printTeacherList();
    Q_INVOKABLE bool exportStudentsPdf(const QString &path, const QString &className = QString());
};
ESCATO_EOF
mkdir -p "src/core"
cat > "src/core/SchoolApp.cpp" <<'ESCATO_EOF'
#include "SchoolApp.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QDate>
#include <QDateTime>
#include <QCryptographicHash>
#include <QUuid>
#include <QDebug>
#include <QFile>
#include <QTextStream>
#include <QStandardPaths>
#include <QDir>
#include <QStringConverter>

static constexpr int kMinPasswordLength = 8;

SchoolApp::SchoolApp(QObject *parent) : QObject(parent)
{
    if (!m_db.open())
        emit errorOccurred(m_db.lastError());
}

QString SchoolApp::passwordHash(const QString &password) const
{
    return QString(QCryptographicHash::hash(password.toUtf8(), QCryptographicHash::Sha256).toHex());
}

bool SchoolApp::needsSetup() const
{
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT COUNT(*) FROM users WHERE role='administrateur' AND account_status='active' AND deleted_at IS NULL") || !q.next())
        return false;
    return q.value(0).toInt() == 0;
}

bool SchoolApp::createFirstAdmin(const QString &name, const QString &email, const QString &password)
{
    if (!needsSetup()) {
        emit errorOccurred(QStringLiteral("Un administrateur existe déjà : la configuration initiale n'est plus disponible."));
        return false;
    }
    const QString n = name.trimmed();
    const QString e = email.trimmed();
    if (n.isEmpty() || !e.contains('@') || e.startsWith('@') || e.endsWith('@')) {
        emit errorOccurred(QStringLiteral("Nom et adresse e-mail valides requis."));
        return false;
    }
    if (password.size() < kMinPasswordLength) {
        emit errorOccurred(QStringLiteral("Le mot de passe doit contenir au moins %1 caractères.").arg(kMinPasswordLength));
        return false;
    }

    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return false;

    // Revérification dans la transaction : un seul administrateur initial, même en cas de double clic.
    QSqlQuery c(db);
    if (!c.exec("SELECT COUNT(*) FROM users WHERE role='administrateur' AND account_status='active' AND deleted_at IS NULL")
        || !c.next() || c.value(0).toInt() != 0) {
        db.rollback();
        return false;
    }

    QSqlQuery q(db);
    q.prepare("INSERT INTO users(name,email,password_hash,role) VALUES(?,?,?,'administrateur')");
    q.addBindValue(n); q.addBindValue(e); q.addBindValue(passwordHash(password));
    if (!q.exec()) {
        db.rollback();
        emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette adresse e-mail est déjà utilisée.") : q.lastError().text());
        return false;
    }
    const int id = q.lastInsertId().toInt();
    if (!db.commit()) return false;

    // Connexion automatique du nouvel administrateur.
    m_userId = id; m_userName = n; m_role = QStringLiteral("administrateur");
    audit("setup", "users", id, "Création du premier administrateur");
    emit sessionChanged();
    emit dataChanged();
    return true;
}

bool SchoolApp::login(const QString &email, const QString &password)
{
    QSqlQuery q(m_db.db());
    q.prepare("SELECT id,name,role,account_status,requires_password_reset FROM users WHERE lower(email)=lower(?) AND deleted_at IS NULL");
    q.addBindValue(email.trimmed());
    if (!q.exec() || !q.next()) return false;
    if (q.value(3).toString() != "active") return false;
    QSqlQuery p(m_db.db());
    p.prepare("SELECT password_hash FROM users WHERE id=?");
    p.addBindValue(q.value(0));
    if (!p.exec() || !p.next() || p.value(0).toString() != passwordHash(password)) return false;

    m_userId = q.value(0).toInt();
    m_userName = q.value(1).toString();
    m_role = q.value(2).toString();
    audit("login","users",m_userId);
    emit sessionChanged();
    return true;
}

void SchoolApp::logout()
{
    if (m_userId) audit("logout","users",m_userId);
    m_userId = 0; m_userName.clear(); m_role.clear();
    emit sessionChanged();
}

int SchoolApp::studentCount() const { QSqlQuery q(m_db.db()); q.exec("SELECT COUNT(*) FROM students WHERE deleted_at IS NULL AND graduated_at IS NULL"); return q.next()?q.value(0).toInt():0; }
int SchoolApp::teacherCount() const { QSqlQuery q(m_db.db()); q.exec("SELECT COUNT(*) FROM users WHERE role='enseignant' AND deleted_at IS NULL"); return q.next()?q.value(0).toInt():0; }
int SchoolApp::courseCount() const { QSqlQuery q(m_db.db()); q.exec("SELECT COUNT(*) FROM courses"); return q.next()?q.value(0).toInt():0; }
int SchoolApp::pendingInvoiceCount() const { QSqlQuery q(m_db.db()); q.exec("SELECT COUNT(*) FROM invoices WHERE status IN('pending','late')"); return q.next()?q.value(0).toInt():0; }

QStringList SchoolApp::classes() const {
    return {"6ème 1","6ème 2","6ème 3","6ème 4","5ème 1","5ème 2","5ème 3","4ème 1","4ème 2","4ème 3","3ème 1","3ème 2","3ème 3","2nde 1","2nde 2","2nde 3","2nde 4","1ère S1","1ère S2","1ère L1","1ère L2","T L1","T L2","T S1","T S2"};
}
QStringList SchoolApp::roles() const { return {"administrateur","enseignant","eleve","parent","comptable"}; }
QStringList SchoolApp::paymentMethods() const { return {"mvola","orange_money","airtel_money","virement","especes"}; }
QStringList SchoolApp::terms() const { return {"Trimestre 1","Trimestre 2","Trimestre 3"}; }

bool SchoolApp::allowed(const QStringList &rs) const { return m_userId > 0 && rs.contains(m_role); }

void SchoolApp::audit(const QString &action, const QString &entity, int entityId, const QString &details)
{
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO audit_logs(user_id,action,entity,entity_id,details) VALUES(?,?,?,?,?)");
    q.addBindValue(m_userId); q.addBindValue(action); q.addBindValue(entity); q.addBindValue(entityId); q.addBindValue(details);
    q.exec();
}

bool SchoolApp::execute(const QString &sql, const QVariantList &bind)
{
    QSqlQuery q(m_db.db()); q.prepare(sql);
    for (const auto &v: bind) q.addBindValue(v);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    emit dataChanged(); return true;
}

QVariantList SchoolApp::students(const QString &className, const QString &search) const
{
    QVariantList out; QSqlQuery q(m_db.db());
    QString sql="SELECT s.id,s.matricule,s.last_name,s.first_name,s.birth_date,s.birth_place,s.current_class,s.parent_phone,s.parent_email,s.address,s.previous_school,s.previous_class,s.desired_career,s.graduated_at,s.consecutive_missed_payments,u.account_status FROM students s LEFT JOIN users u ON u.id=s.user_id WHERE s.deleted_at IS NULL";
    if(!className.isEmpty()) sql+=" AND current_class=?";
    if(!search.isEmpty()) sql+=" AND (last_name LIKE ? OR first_name LIKE ? OR matricule LIKE ?)";
    sql+=" ORDER BY current_class,last_name,first_name";
    q.prepare(sql); if(!className.isEmpty()) q.addBindValue(className); if(!search.isEmpty()){QString x="%"+search+"%";q.addBindValue(x);q.addBindValue(x);q.addBindValue(x);}
    if(!q.exec()) return out;
    while(q.next()){ QVariantMap m; QStringList keys={"id","matricule","lastName","firstName","birthDate","birthPlace","className","parentPhone","parentEmail","address","previousSchool","previousClass","desiredCareer","graduatedAt","missedPayments","accountStatus"}; for(int i=0;i<keys.size();++i)m[keys[i]]=q.value(i); out<<m; } return out;
}

QVariantMap SchoolApp::student(int id) const
{
    auto list=students(); for(const auto &v:list){auto m=v.toMap();if(m["id"].toInt()==id)return m;} return {};
}

bool SchoolApp::addStudent(const QVariantMap &v)
{
    if(!allowed({"administrateur","enseignant"})) return false;
    QSqlDatabase db=m_db.db(); db.transaction();
    QSqlQuery q(db);
    QString matricule="ELV-"+QDateTime::currentDateTime().toString("yyyyMMddhhmmsszzz");
    q.prepare(R"(INSERT INTO students(matricule,last_name,first_name,birth_date,birth_place,father_name,father_job,mother_name,mother_job,parent_phone,parent_email,address,previous_school,previous_class,current_class,desired_career,photo) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?))");
    QStringList k={"lastName","firstName","birthDate","birthPlace","fatherName","fatherJob","motherName","motherJob","parentPhone","parentEmail","address","previousSchool","previousClass","className","desiredCareer","photo"};
    q.addBindValue(matricule); for(auto &x:k) q.addBindValue(v.value(x));
    if(!q.exec()){db.rollback();emit errorOccurred(q.lastError().text());return false;}
    db.commit(); audit("create","student",q.lastInsertId().toInt()); emit dataChanged(); return true;
}

bool SchoolApp::updateStudent(int id,const QVariantMap &v)
{
    if(!allowed({"administrateur","enseignant"}))return false;
    QSqlQuery q(m_db.db()); q.prepare(R"(UPDATE students SET last_name=?,first_name=?,birth_date=?,birth_place=?,father_name=?,father_job=?,mother_name=?,mother_job=?,parent_phone=?,parent_email=?,address=?,previous_school=?,previous_class=?,current_class=?,desired_career=?,photo=?,updated_at=CURRENT_TIMESTAMP WHERE id=?)");
    QStringList k={"lastName","firstName","birthDate","birthPlace","fatherName","fatherJob","motherName","motherJob","parentPhone","parentEmail","address","previousSchool","previousClass","className","desiredCareer","photo"}; for(auto &x:k)q.addBindValue(v.value(x));q.addBindValue(id); if(!q.exec())return false;audit("update","student",id);emit dataChanged();return true;
}

bool SchoolApp::deleteStudent(int id){ if(!allowed({"administrateur"}))return false; return execute("UPDATE students SET deleted_at=CURRENT_TIMESTAMP WHERE id=?",{id}); }
bool SchoolApp::graduateStudent(int id){ if(!allowed({"administrateur"}))return false; return execute("UPDATE students SET graduated_at=DATE('now') WHERE id=?",{id}); }
bool SchoolApp::blockStudent(int id,const QString &reason)
{
    if(!allowed({"administrateur","enseignant"}))return false;
    QSqlQuery q(m_db.db());q.prepare("SELECT user_id FROM students WHERE id=?");q.addBindValue(id);if(!q.exec()||!q.next()||q.value(0).isNull())return false;
    return blockUser(q.value(0).toInt(),"discipline",reason);
}
bool SchoolApp::unblockStudent(int id)
{
    QSqlQuery q(m_db.db());q.prepare("SELECT user_id FROM students WHERE id=?");q.addBindValue(id);if(!q.exec()||!q.next()||q.value(0).isNull())return false;return unblockUser(q.value(0).toInt());
}

QVariantList SchoolApp::teachers(const QString &search) const
{
    QVariantList out;QSqlQuery q(m_db.db());
    QString sql="SELECT u.id,u.name,u.email,u.account_status,t.identity_number,t.cnaps_number,t.mle_number,t.contact,t.address,t.dob,t.place_of_birth,t.number_of_children,t.marital_status,t.religion,t.subject,t.occupation,t.employment_type,t.hiring_date,t.contract_end_date,t.comment,t.photo FROM users u LEFT JOIN teacher_profiles t ON t.user_id=u.id WHERE u.role='enseignant' AND u.deleted_at IS NULL";
    if(!search.isEmpty())sql+=" AND (u.name LIKE ? OR u.email LIKE ? OR t.subject LIKE ? OR t.contact LIKE ? OR t.identity_number LIKE ?)";
    sql+=" ORDER BY u.name";q.prepare(sql);if(!search.isEmpty()){QString x="%"+search+"%";for(int i=0;i<5;i++)q.addBindValue(x);}if(!q.exec())return out;
    while(q.next()){QVariantMap m;QStringList k={"id","name","email","status","cin","cnaps","mle","contact","address","dob","birthPlace","children","maritalStatus","religion","subject","occupation","employmentType","hiringDate","contractEndDate","comment","photo"};for(int i=0;i<k.size();++i)m[k[i]]=q.value(i);out<<m;}return out;
}

bool SchoolApp::addTeacher(const QVariantMap &v)
{
    if(!allowed({"administrateur"}))return false;
    if(v.value("password").toString().size()<kMinPasswordLength){emit errorOccurred(QStringLiteral("Le mot de passe doit contenir au moins %1 caractères.").arg(kMinPasswordLength));return false;}
    QSqlDatabase db=m_db.db();db.transaction();QSqlQuery q(db);
    q.prepare("INSERT INTO users(name,email,password_hash,role) VALUES(?,?,?, 'enseignant')");q.addBindValue(v["name"]);q.addBindValue(v["email"]);q.addBindValue(passwordHash(v.value("password").toString()));
    if(!q.exec()){db.rollback();return false;}int uid=q.lastInsertId().toInt();
    q.prepare(R"(INSERT INTO teacher_profiles(user_id,identity_number,cnaps_number,mle_number,contact,address,dob,place_of_birth,number_of_children,marital_status,religion,subject,occupation,employment_type,hiring_date,contract_end_date,comment,photo) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?))");
    QStringList k={"cin","cnaps","mle","contact","address","dob","birthPlace","children","maritalStatus","religion","subject","occupation","employmentType","hiringDate","contractEndDate","comment","photo"};q.addBindValue(uid);for(auto &x:k)q.addBindValue(v.value(x));if(!q.exec()){db.rollback();return false;}db.commit();audit("create","teacher",uid);emit dataChanged();return true;
}

bool SchoolApp::updateTeacher(int id,const QVariantMap &v)
{
    if(!allowed({"administrateur"}))return false;QSqlQuery q(m_db.db());q.prepare("UPDATE users SET name=?,email=? WHERE id=?");q.addBindValue(v["name"]);q.addBindValue(v["email"]);q.addBindValue(id);if(!q.exec())return false;
    q.prepare(R"(UPDATE teacher_profiles SET identity_number=?,cnaps_number=?,mle_number=?,contact=?,address=?,dob=?,place_of_birth=?,number_of_children=?,marital_status=?,religion=?,subject=?,occupation=?,employment_type=?,hiring_date=?,contract_end_date=?,comment=?,photo=? WHERE user_id=?)");
    QStringList k={"cin","cnaps","mle","contact","address","dob","birthPlace","children","maritalStatus","religion","subject","occupation","employmentType","hiringDate","contractEndDate","comment","photo"};for(auto &x:k)q.addBindValue(v.value(x));q.addBindValue(id);if(!q.exec())return false;emit dataChanged();return true;
}
bool SchoolApp::deleteTeacher(int id){if(!allowed({"administrateur"}))return false;return execute("UPDATE users SET deleted_at=CURRENT_TIMESTAMP WHERE id=? AND role='enseignant'",{id});}

QVariantList SchoolApp::courses(const QString &className) const
{
    QVariantList out;QSqlQuery q(m_db.db());QString sql="SELECT c.id,c.title,c.subject,c.class_name,c.description,c.teacher_id,COALESCE(u.name,'Non affecté') FROM courses c LEFT JOIN users u ON u.id=c.teacher_id";if(!className.isEmpty())sql+=" WHERE c.class_name=?";sql+=" ORDER BY c.class_name,c.subject";q.prepare(sql);if(!className.isEmpty())q.addBindValue(className);q.exec();while(q.next()){QVariantMap m;m["id"]=q.value(0);m["title"]=q.value(1);m["subject"]=q.value(2);m["className"]=q.value(3);m["description"]=q.value(4);m["teacherId"]=q.value(5);m["teacher"]=q.value(6);out<<m;}return out;
}
bool SchoolApp::addCourse(const QVariantMap &v){if(!allowed({"administrateur","enseignant"}))return false;return execute("INSERT INTO courses(title,subject,class_name,description,teacher_id) VALUES(?,?,?,?,?)",{v["title"],v["subject"],v["className"],v["description"],v["teacherId"]});}
bool SchoolApp::updateCourse(int id,const QVariantMap &v){if(!allowed({"administrateur","enseignant"}))return false;return execute("UPDATE courses SET title=?,subject=?,class_name=?,description=?,teacher_id=? WHERE id=?", {v["title"],v["subject"],v["className"],v["description"],v["teacherId"],id});}
bool SchoolApp::deleteCourse(int id){if(!allowed({"administrateur","enseignant"}))return false;return execute("DELETE FROM courses WHERE id=?",{id});}

QVariantList SchoolApp::resources(int courseId) const
{
    QVariantList out;QSqlQuery q(m_db.db());q.prepare("SELECT id,title,type,file_path,url FROM course_resources WHERE course_id=? ORDER BY title");q.addBindValue(courseId);q.exec();while(q.next()){QVariantMap m;m["id"]=q.value(0);m["title"]=q.value(1);m["type"]=q.value(2);m["filePath"]=q.value(3);m["url"]=q.value(4);out<<m;}return out;
}
bool SchoolApp::addResource(const QVariantMap &v){if(!allowed({"administrateur","enseignant"}))return false;return execute("INSERT INTO course_resources(course_id,title,type,file_path,url) VALUES(?,?,?,?,?)",{v["courseId"],v["title"],v["type"],v["filePath"],v["url"]});}
bool SchoolApp::deleteResource(int id){if(!allowed({"administrateur","enseignant"}))return false;return execute("DELETE FROM course_resources WHERE id=?",{id});}

QVariantList SchoolApp::exams() const
{
    QVariantList out;QSqlQuery q("SELECT e.id,e.title,e.term,e.exam_date,e.max_score,e.course_id,c.title,c.subject,c.class_name FROM exams e JOIN courses c ON c.id=e.course_id ORDER BY e.exam_date DESC");while(q.next()){QVariantMap m;m["id"]=q.value(0);m["title"]=q.value(1);m["term"]=q.value(2);m["date"]=q.value(3);m["maxScore"]=q.value(4);m["courseId"]=q.value(5);m["course"]=q.value(6);m["subject"]=q.value(7);m["className"]=q.value(8);out<<m;}return out;
}
bool SchoolApp::addExam(const QVariantMap &v){if(!allowed({"administrateur","enseignant"}))return false;return execute("INSERT INTO exams(course_id,title,term,exam_date,max_score) VALUES(?,?,?,?,?)",{v["courseId"],v["title"],v["term"],v["date"],v["maxScore"]});}
bool SchoolApp::updateExam(int id,const QVariantMap &v){if(!allowed({"administrateur","enseignant"}))return false;return execute("UPDATE exams SET course_id=?,title=?,term=?,exam_date=?,max_score=? WHERE id=?", {v["courseId"],v["title"],v["term"],v["date"],v["maxScore"],id});}
bool SchoolApp::deleteExam(int id){if(!allowed({"administrateur","enseignant"}))return false;return execute("DELETE FROM exams WHERE id=?",{id});}

QVariantList SchoolApp::grades(int examId) const
{
    QVariantList out;QSqlQuery q(m_db.db());q.prepare(R"(SELECT s.id,s.matricule,s.last_name,s.first_name,s.current_class,g.score,g.comment FROM students s JOIN exams e ON e.id=? LEFT JOIN grades g ON g.student_id=s.id AND g.exam_id=e.id WHERE s.current_class=(SELECT c.class_name FROM courses c JOIN exams e2 ON e2.course_id=c.id WHERE e2.id=?) AND s.deleted_at IS NULL ORDER BY s.last_name)");q.addBindValue(examId);q.addBindValue(examId);q.exec();while(q.next()){QVariantMap m;m["studentId"]=q.value(0);m["matricule"]=q.value(1);m["lastName"]=q.value(2);m["firstName"]=q.value(3);m["className"]=q.value(4);m["score"]=q.value(5).isNull()?QVariant():q.value(5);m["comment"]=q.value(6);out<<m;}return out;
}
bool SchoolApp::saveGrade(int examId,int studentId,double score,const QString &comment){
    if(!allowed({"administrateur","enseignant"}))return false;
    QSqlQuery mq(m_db.db());mq.prepare("SELECT max_score FROM exams WHERE id=?");mq.addBindValue(examId);
    if(!mq.exec()||!mq.next())return false;
    if(!(score>=0.0 && score<=mq.value(0).toDouble())){emit errorOccurred(QStringLiteral("Note invalide : elle doit être comprise entre 0 et %1.").arg(mq.value(0).toInt()));return false;}
    return execute("INSERT INTO grades(exam_id,student_id,score,comment) VALUES(?,?,?,?) ON CONFLICT(exam_id,student_id) DO UPDATE SET score=excluded.score,comment=excluded.comment",{examId,studentId,score,comment});}

QVariantMap SchoolApp::bulletin(int studentId,const QString &term) const
{
    QVariantMap result;result["student"]=student(studentId);QSqlQuery q(m_db.db());q.prepare(R"(SELECT c.subject,ROUND(AVG((g.score*20.0)/e.max_score),2) FROM grades g JOIN exams e ON e.id=g.exam_id JOIN courses c ON c.id=e.course_id WHERE g.student_id=? AND e.term=? GROUP BY c.subject ORDER BY c.subject)");q.addBindValue(studentId);q.addBindValue(term);q.exec();QVariantList subjects;double sum=0;int n=0;while(q.next()){QVariantMap m;m["subject"]=q.value(0);m["average"]=q.value(1);subjects<<m;sum+=q.value(1).toDouble();n++;}result["subjects"]=subjects;result["generalAverage"]=n?QString::number(sum/n,'f',2):QString();return result;
}

QVariantList SchoolApp::payments(int studentId) const
{
    QVariantList out;QString sql="SELECT p.id,p.student_id,s.last_name||' '||s.first_name,p.amount,p.method,p.payer_role,p.reference,p.paid_at,p.notes FROM payments p JOIN students s ON s.id=p.student_id";if(studentId)sql+=" WHERE p.student_id=?";sql+=" ORDER BY p.paid_at DESC";QSqlQuery q(m_db.db());q.prepare(sql);if(studentId)q.addBindValue(studentId);q.exec();while(q.next()){QVariantMap m;QStringList k={"id","studentId","student","amount","method","payerRole","reference","paidAt","notes"};for(int i=0;i<k.size();i++)m[k[i]]=q.value(i);out<<m;}return out;
}
bool SchoolApp::addPayment(const QVariantMap &v)
{
    if(!allowed({"administrateur","comptable"})) return false;
    const double amount = v.value("amount").toDouble();
    if(amount <= 0.0) return false;
    QSqlDatabase db=m_db.db();
    if(!db.transaction()) return false;

    QSqlQuery q(db);
    q.prepare("INSERT INTO payments(student_id,recorded_by,amount,method,payer_role,reference,paid_at,notes) VALUES(?,?,?,?,?,?,?,?)");
    q.addBindValue(v.value("studentId")); q.addBindValue(m_userId); q.addBindValue(amount);
    const QString paidAt = v.value("paidAt").toString().isEmpty() ? QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss") : v.value("paidAt").toString();
    const QString payerRole = v.value("payerRole").toString().isEmpty() ? QStringLiteral("eleve") : v.value("payerRole").toString();
    q.addBindValue(v.value("method")); q.addBindValue(payerRole); q.addBindValue(v.value("reference"));
    q.addBindValue(paidAt); q.addBindValue(v.value("notes"));
    if(!q.exec()){ db.rollback(); emit errorOccurred(q.lastError().text()); return false; }
    const int pid=q.lastInsertId().toInt();

    QSqlQuery inv(db);
    inv.prepare("SELECT id,amount FROM invoices WHERE student_id=? AND status IN('pending','late') ORDER BY due_date LIMIT 1");
    inv.addBindValue(v.value("studentId"));
    if(inv.exec() && inv.next() && amount + 0.005 >= inv.value(1).toDouble()){
        QSqlQuery u(db); u.prepare("UPDATE invoices SET status='paid',payment_id=? WHERE id=?");
        u.addBindValue(pid); u.addBindValue(inv.value(0)); u.exec();
    }
    QSqlQuery st(db); st.prepare("UPDATE students SET consecutive_missed_payments=0 WHERE id=?");
    st.addBindValue(v.value("studentId")); st.exec();

    const QString debitAccount = (v.value("method").toString()=="especes") ? "531000" : "512000";
    QSqlQuery je(db);
    je.prepare("INSERT INTO journal_entries(entry_date,journal_code,reference,description,source_type,source_id,created_by) VALUES(?,?,?,?,?,?,?)");
    je.addBindValue(paidAt.left(10)); je.addBindValue(v.value("method").toString()=="especes" ? "CAISSE" : "BANQUE");
    je.addBindValue(v.value("reference")); je.addBindValue("Encaissement écolage"); je.addBindValue("payment"); je.addBindValue(pid); je.addBindValue(m_userId);
    if(!je.exec()){ db.rollback(); emit errorOccurred(je.lastError().text()); return false; }
    const int eid=je.lastInsertId().toInt();
    QSqlQuery jl(db);
    jl.prepare("INSERT INTO journal_lines(entry_id,account_code,label,debit,credit) VALUES(?,?,?,?,?)");
    jl.addBindValue(eid); jl.addBindValue(debitAccount); jl.addBindValue("Encaissement écolage"); jl.addBindValue(amount); jl.addBindValue(0.0);
    if(!jl.exec()){ db.rollback(); return false; }
    jl.prepare("INSERT INTO journal_lines(entry_id,account_code,label,debit,credit) VALUES(?,?,?,?,?)");
    jl.addBindValue(eid); jl.addBindValue("706000"); jl.addBindValue("Écolages / prestations scolaires"); jl.addBindValue(0.0); jl.addBindValue(amount);
    if(!jl.exec()){ db.rollback(); return false; }

    if(!db.commit()) return false;
    audit("payment","payments",pid,"Journal comptable créé automatiquement");
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::invoices(const QString &status) const
{
    QVariantList out;QString sql="SELECT i.id,i.student_id,s.last_name||' '||s.first_name,i.period_month,i.due_date,i.amount,i.status FROM invoices i JOIN students s ON s.id=i.student_id";if(!status.isEmpty())sql+=" WHERE i.status=?";sql+=" ORDER BY i.due_date DESC";QSqlQuery q(m_db.db());q.prepare(sql);if(!status.isEmpty())q.addBindValue(status);q.exec();while(q.next()){QVariantMap m;QStringList k={"id","studentId","student","month","dueDate","amount","status"};for(int i=0;i<k.size();i++)m[k[i]]=q.value(i);out<<m;}return out;
}
QVariantList SchoolApp::studentInvoices(int studentId) const
{
    QVariantList out;QSqlQuery q(m_db.db());q.prepare("SELECT id,period_month,due_date,amount,status,payment_id FROM invoices WHERE student_id=? ORDER BY due_date DESC");q.addBindValue(studentId);q.exec();while(q.next()){QVariantMap m;QStringList k={"id","month","dueDate","amount","status","paymentId"};for(int i=0;i<k.size();i++)m[k[i]]=q.value(i);out<<m;}return out;
}
bool SchoolApp::setStudentFee(int studentId,double amount){if(!allowed({"administrateur"}))return false;return execute("INSERT INTO student_fees(student_id,monthly_amount,set_by) VALUES(?,?,?)",{studentId,amount,m_userId});}
bool SchoolApp::generateMonthlyInvoices(const QString &month)
{
    if(!allowed({"administrateur","comptable"}))return false;
    QSqlQuery s(m_db.db());s.exec("SELECT id FROM students WHERE graduated_at IS NULL AND deleted_at IS NULL");
    while(s.next()){QSqlQuery f(m_db.db());f.prepare("SELECT monthly_amount FROM student_fees WHERE student_id=? ORDER BY id DESC LIMIT 1");f.addBindValue(s.value(0));if(f.exec()&&f.next()){QDate d=QDate::fromString(month+"-01","yyyy-MM-dd");if(!d.isValid())continue;QSqlQuery i(m_db.db());i.prepare("INSERT OR IGNORE INTO invoices(student_id,period_month,due_date,amount,status) VALUES(?,?,?,?, 'pending')");i.addBindValue(s.value(0));i.addBindValue(d.toString("yyyy-MM-dd"));i.addBindValue(d.addDays(9).toString("yyyy-MM-dd"));i.addBindValue(f.value(0));i.exec();}}
    emit dataChanged();return true;
}
bool SchoolApp::processPaymentReminders()
{
    if(!allowed({"administrateur","comptable"}))return false;
    QSqlQuery q(m_db.db());q.exec("UPDATE invoices SET reminder_before_sent_at=COALESCE(reminder_before_sent_at,CURRENT_TIMESTAMP) WHERE status='pending' AND due_date=DATE('now','+3 day')");q.exec("UPDATE invoices SET status='late',reminder_late_sent_at=COALESCE(reminder_late_sent_at,CURRENT_TIMESTAMP) WHERE status='pending' AND due_date<DATE('now')");emit dataChanged();return true;
}


static QString csvField(const QVariant &value)
{
    QString s=value.toString();
    s.replace('"','""');
    return QString("\"") + s + QString("\"");
}

QVariantMap SchoolApp::accountingDashboard() const
{
    QVariantMap m;
    auto scalar=[&](const QString &sql){ QSqlQuery x(m_db.db()); x.exec(sql); return x.next()?x.value(0):QVariant(0); };
    m["cash"] = scalar("SELECT COALESCE(SUM(debit-credit),0) FROM journal_lines WHERE account_code='531000'");
    m["bank"] = scalar("SELECT COALESCE(SUM(debit-credit),0) FROM journal_lines WHERE account_code='512000'");
    m["revenue"] = scalar("SELECT COALESCE(SUM(credit-debit),0) FROM journal_lines WHERE account_code='706000'");
    m["expenses"] = scalar("SELECT COALESCE(SUM(debit-credit),0) FROM journal_lines WHERE account_code IN(SELECT code FROM chart_of_accounts WHERE account_type='expense')");
    m["receivables"] = scalar("SELECT COALESCE(SUM(amount),0) FROM invoices WHERE status IN('pending','late')");
    m["paymentsMonth"] = scalar("SELECT COALESCE(SUM(amount),0) FROM payments WHERE strftime('%Y-%m',paid_at)=strftime('%Y-%m','now')");
    return m;
}

QVariantList SchoolApp::chartOfAccounts() const
{
    QVariantList out; QSqlQuery q(m_db.db());
    q.exec("SELECT code,label,account_type,active FROM chart_of_accounts WHERE active=1 ORDER BY code");
    while(q.next()){ QVariantMap m; m["code"]=q.value(0); m["label"]=q.value(1); m["type"]=q.value(2); m["active"]=q.value(3); out<<m; }
    return out;
}

bool SchoolApp::addAccount(const QString &code, const QString &label, const QString &type)
{
    if(!allowed({"administrateur","comptable"}) || code.trimmed().isEmpty() || label.trimmed().isEmpty()) return false;
    return execute("INSERT INTO chart_of_accounts(code,label,account_type) VALUES(?,?,?)",{code.trimmed(),label.trimmed(),type.trimmed().isEmpty()?"general":type.trimmed()});
}

QVariantList SchoolApp::expenses() const
{
    QVariantList out; QSqlQuery q(m_db.db());
    q.exec("SELECT e.id,e.expense_date,e.category,e.description,e.amount,e.payment_method,e.reference,e.account_code,COALESCE(u.name,'') FROM expenses e LEFT JOIN users u ON u.id=e.recorded_by ORDER BY e.expense_date DESC,e.id DESC");
    while(q.next()){ QVariantMap m; QStringList k={"id","date","category","description","amount","method","reference","accountCode","recordedBy"}; for(int i=0;i<k.size();++i)m[k[i]]=q.value(i); out<<m; }
    return out;
}

bool SchoolApp::addExpense(const QVariantMap &v)
{
    if(!allowed({"administrateur","comptable"})) return false;
    const double amount=v.value("amount").toDouble(); if(amount<=0) return false;
    QSqlDatabase db=m_db.db(); if(!db.transaction()) return false;
    QSqlQuery q(db); q.prepare("INSERT INTO expenses(expense_date,category,description,amount,payment_method,reference,account_code,recorded_by) VALUES(?,?,?,?,?,?,?,?)");
    q.addBindValue(v.value("date")); q.addBindValue(v.value("category")); q.addBindValue(v.value("description")); q.addBindValue(amount);
    q.addBindValue(v.value("method")); q.addBindValue(v.value("reference")); q.addBindValue(v.value("accountCode").toString().isEmpty()?"606000":v.value("accountCode")); q.addBindValue(m_userId);
    if(!q.exec()){db.rollback();emit errorOccurred(q.lastError().text());return false;}
    const int xid=q.lastInsertId().toInt();
    const QString creditAccount=(v.value("method").toString()=="especes")?"531000":"512000";
    QSqlQuery je(db); je.prepare("INSERT INTO journal_entries(entry_date,journal_code,reference,description,source_type,source_id,created_by) VALUES(?,?,?,?,?,?,?)");
    je.addBindValue(v.value("date"));je.addBindValue("ACHAT");je.addBindValue(v.value("reference"));je.addBindValue(v.value("description"));je.addBindValue("expense");je.addBindValue(xid);je.addBindValue(m_userId);
    if(!je.exec()){db.rollback();return false;} const int eid=je.lastInsertId().toInt();
    QSqlQuery jl(db); jl.prepare("INSERT INTO journal_lines(entry_id,account_code,label,debit,credit) VALUES(?,?,?,?,?)");
    jl.addBindValue(eid);jl.addBindValue(v.value("accountCode").toString().isEmpty()?"606000":v.value("accountCode"));jl.addBindValue(v.value("description"));jl.addBindValue(amount);jl.addBindValue(0.0);if(!jl.exec()){db.rollback();return false;}
    jl.prepare("INSERT INTO journal_lines(entry_id,account_code,label,debit,credit) VALUES(?,?,?,?,?)");
    jl.addBindValue(eid);jl.addBindValue(creditAccount);jl.addBindValue("Règlement dépense");jl.addBindValue(0.0);jl.addBindValue(amount);if(!jl.exec()){db.rollback();return false;}
    if(!db.commit()) return false; audit("expense","expenses",xid); emit dataChanged(); return true;
}

QVariantList SchoolApp::journal(const QString &fromDate, const QString &toDate) const
{
    QVariantList out; QString sql="SELECT j.id,j.entry_date,j.journal_code,j.reference,j.description,l.account_code,COALESCE(a.label,''),l.label,l.debit,l.credit FROM journal_entries j JOIN journal_lines l ON l.entry_id=j.id LEFT JOIN chart_of_accounts a ON a.code=l.account_code WHERE 1=1";
    if(!fromDate.isEmpty()) sql+=" AND j.entry_date>=?"; if(!toDate.isEmpty()) sql+=" AND j.entry_date<=?"; sql+=" ORDER BY j.entry_date DESC,j.id DESC,l.id";
    QSqlQuery q(m_db.db());q.prepare(sql);if(!fromDate.isEmpty())q.addBindValue(fromDate);if(!toDate.isEmpty())q.addBindValue(toDate);q.exec();
    while(q.next()){QVariantMap m;QStringList k={"id","date","journal","reference","description","accountCode","accountLabel","lineLabel","debit","credit"};for(int i=0;i<k.size();++i)m[k[i]]=q.value(i);out<<m;}return out;
}

QVariantList SchoolApp::trialBalance(const QString &fromDate, const QString &toDate) const
{
    QVariantList out; QString sql="SELECT a.code,a.label,COALESCE(SUM(l.debit),0),COALESCE(SUM(l.credit),0),COALESCE(SUM(l.debit-l.credit),0) FROM chart_of_accounts a LEFT JOIN journal_lines l ON l.account_code=a.code LEFT JOIN journal_entries j ON j.id=l.entry_id";
    QStringList where; if(!fromDate.isEmpty())where<<"j.entry_date>=?";if(!toDate.isEmpty())where<<"j.entry_date<=?";if(!where.isEmpty())sql+=" WHERE "+where.join(" AND ");sql+=" GROUP BY a.code,a.label ORDER BY a.code";
    QSqlQuery q(m_db.db());q.prepare(sql);if(!fromDate.isEmpty())q.addBindValue(fromDate);if(!toDate.isEmpty())q.addBindValue(toDate);q.exec();
    while(q.next()){QVariantMap m;m["code"]=q.value(0);m["label"]=q.value(1);m["debit"]=q.value(2);m["credit"]=q.value(3);m["balance"]=q.value(4);out<<m;}return out;
}

QVariantList SchoolApp::generalLedger(const QString &accountCode, const QString &fromDate, const QString &toDate) const
{
    QVariantList out; QString sql="SELECT j.entry_date,j.journal_code,j.reference,j.description,l.debit,l.credit FROM journal_entries j JOIN journal_lines l ON l.entry_id=j.id WHERE l.account_code=?";
    if(!fromDate.isEmpty())sql+=" AND j.entry_date>=?";if(!toDate.isEmpty())sql+=" AND j.entry_date<=?";sql+=" ORDER BY j.entry_date,j.id,l.id";
    QSqlQuery q(m_db.db());q.prepare(sql);q.addBindValue(accountCode);if(!fromDate.isEmpty())q.addBindValue(fromDate);if(!toDate.isEmpty())q.addBindValue(toDate);q.exec();double balance=0;
    while(q.next()){balance+=q.value(4).toDouble()-q.value(5).toDouble();QVariantMap m;m["date"]=q.value(0);m["journal"]=q.value(1);m["reference"]=q.value(2);m["description"]=q.value(3);m["debit"]=q.value(4);m["credit"]=q.value(5);m["balance"]=balance;out<<m;}return out;
}

QString SchoolApp::accountingExportDirectory() const
{
    QString dir=QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)+"/ESCATO_Comptabilite";QDir().mkpath(dir);return dir;
}

bool SchoolApp::exportAccountingCsv(const QString &kind, const QString &filePath) const
{
    if(!allowed({"administrateur","comptable"}))return false;
    QString path=filePath.trimmed(); if(path.isEmpty()){QString ext="csv";path=accountingExportDirectory()+"/ESCATO_"+kind+"_"+QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss")+"."+ext;}
    QFile f(path);if(!f.open(QIODevice::WriteOnly|QIODevice::Text))return false;QTextStream out(&f);out.setEncoding(QStringConverter::Utf8);out<<QChar(0xFEFF);
    if(kind=="payments"){
        out<<QString::fromUtf8("ID;Date;Elève;Montant;Mode;Référence\n");for(const auto &v:payments()){auto m=v.toMap();out<<csvField(m["id"])<<';'<<csvField(m["paidAt"])<<';'<<csvField(m["student"])<<';'<<csvField(m["amount"])<<';'<<csvField(m["method"])<<';'<<csvField(m["reference"])<<"\n";}
    } else if(kind=="expenses"){
        out<<QString::fromUtf8("ID;Date;Catégorie;Description;Montant;Mode;Référence;Compte\n");for(const auto &v:expenses()){auto m=v.toMap();out<<csvField(m["id"])<<';'<<csvField(m["date"])<<';'<<csvField(m["category"])<<';'<<csvField(m["description"])<<';'<<csvField(m["amount"])<<';'<<csvField(m["method"])<<';'<<csvField(m["reference"])<<';'<<csvField(m["accountCode"])<<"\n";}
    } else if(kind=="journal" || kind=="sage100" || kind=="odoo") {
        const bool sage=kind=="sage100", odoo=kind=="odoo";
        if(sage) out<<QString::fromUtf8("Date;Journal;Compte;Libellé;Débit;Crédit;Référence\n");
        else if(odoo) out<<QString::fromUtf8("date;journal;account_code;label;debit;credit;reference\n");
        else out<<QString::fromUtf8("Date;Journal;Compte;Libellé;Débit;Crédit;Référence\n");
        for(const auto &v:journal()){auto m=v.toMap();out<<csvField(m["date"])<<';'<<csvField(m["journal"])<<';'<<csvField(m["accountCode"])<<';'<<csvField(m["lineLabel"])<<';'<<csvField(m["debit"])<<';'<<csvField(m["credit"])<<';'<<csvField(m["reference"])<<"\n";}
    } else if(kind=="trial_balance"){
        out<<QString::fromUtf8("Compte;Libellé;Débit;Crédit;Solde\n");for(const auto &v:trialBalance()){auto m=v.toMap();out<<csvField(m["code"])<<';'<<csvField(m["label"])<<';'<<csvField(m["debit"])<<';'<<csvField(m["credit"])<<';'<<csvField(m["balance"])<<"\n";}
    } else return false;
    f.close();return true;
}

QVariantList SchoolApp::messages() const
{
    QVariantList out;QSqlQuery q(m_db.db());q.prepare(R"(SELECT m.id,m.sender_id,COALESCE(s.name,'Supprimé'),m.recipient_id,COALESCE(r.name,'Supprimé'),m.subject,m.body,m.read_at,m.created_at FROM messages m LEFT JOIN users s ON s.id=m.sender_id LEFT JOIN users r ON r.id=m.recipient_id WHERE m.sender_id=? OR m.recipient_id=? ORDER BY m.created_at DESC)");q.addBindValue(m_userId);q.addBindValue(m_userId);q.exec();while(q.next()){QVariantMap m;QStringList k={"id","senderId","sender","recipientId","recipient","subject","body","readAt","createdAt"};for(int i=0;i<k.size();i++)m[k[i]]=q.value(i);out<<m;}return out;
}
bool SchoolApp::sendMessage(int recipientId,const QString &subject,const QString &body){if(!m_userId)return false;return execute("INSERT INTO messages(sender_id,recipient_id,subject,body) VALUES(?,?,?,?)",{m_userId,recipientId,subject,body});}

QVariantList SchoolApp::users(const QString &role) const
{
    QVariantList out;QSqlQuery q(m_db.db());QString sql="SELECT id,name,email,role,account_status,blocked_reason,blocked_category,requires_password_reset FROM users WHERE deleted_at IS NULL";if(!role.isEmpty())sql+=" AND role=?";sql+=" ORDER BY name";q.prepare(sql);if(!role.isEmpty())q.addBindValue(role);q.exec();while(q.next()){QVariantMap m;QStringList k={"id","name","email","role","status","blockedReason","blockedCategory","requiresPasswordReset"};for(int i=0;i<k.size();i++)m[k[i]]=q.value(i);out<<m;}return out;
}
bool SchoolApp::createUser(const QVariantMap &v){
    if(!allowed({"administrateur"}))return false;
    if(v.value("name").toString().trimmed().isEmpty()||v.value("email").toString().trimmed().isEmpty()||!roles().contains(v.value("role").toString())){emit errorOccurred(QStringLiteral("Nom, e-mail et rôle valides requis."));return false;}
    if(v.value("password").toString().size()<kMinPasswordLength){emit errorOccurred(QStringLiteral("Le mot de passe doit contenir au moins %1 caractères.").arg(kMinPasswordLength));return false;}
    return execute("INSERT INTO users(name,email,password_hash,role) VALUES(?,?,?,?)",{v["name"],v["email"],passwordHash(v["password"].toString()),v["role"]});}
bool SchoolApp::updateUserRole(int id,const QString &role){if(!allowed({"administrateur"})||id==m_userId)return false;return execute("UPDATE users SET role=? WHERE id=?",{role,id});}
bool SchoolApp::blockUser(int id,const QString &category,const QString &reason){if(!allowed({"administrateur","comptable","enseignant"})||id==m_userId)return false;return execute("UPDATE users SET account_status='blocked',blocked_category=?,blocked_reason=? WHERE id=?", {category,reason,id});}
bool SchoolApp::unblockUser(int id){if(!allowed({"administrateur","comptable"}))return false;return execute("UPDATE users SET account_status='active',blocked_category=NULL,blocked_reason=NULL,requires_password_reset=1 WHERE id=?", {id});}
bool SchoolApp::resetPassword(int userId,const QString &newPassword){if(!allowed({"administrateur"}))return false;if(newPassword.size()<kMinPasswordLength){emit errorOccurred(QStringLiteral("Le mot de passe doit contenir au moins %1 caractères.").arg(kMinPasswordLength));return false;}return execute("UPDATE users SET password_hash=?,requires_password_reset=0 WHERE id=?", {passwordHash(newPassword),userId});}

QVariantList SchoolApp::announcements() const
{
    QVariantList out;QSqlQuery q("SELECT a.id,a.title,a.body,a.event_date,a.created_at,COALESCE(u.name,'') FROM announcements a LEFT JOIN users u ON u.id=a.created_by ORDER BY a.created_at DESC");while(q.next()){QVariantMap m;m["id"]=q.value(0);m["title"]=q.value(1);m["body"]=q.value(2);m["eventDate"]=q.value(3);m["createdAt"]=q.value(4);m["creator"]=q.value(5);out<<m;}return out;
}
bool SchoolApp::addAnnouncement(const QVariantMap &v){if(!allowed({"administrateur"}))return false;return execute("INSERT INTO announcements(created_by,title,body,event_date) VALUES(?,?,?,?)",{m_userId,v["title"],v["body"],v["eventDate"]});}
bool SchoolApp::deleteAnnouncement(int id){if(!allowed({"administrateur"}))return false;return execute("DELETE FROM announcements WHERE id=?",{id});}

QVariantList SchoolApp::tardiness() const
{
    QVariantList out;QSqlQuery q("SELECT t.id,t.student_id,s.last_name||' '||s.first_name,t.occurred_at,t.note FROM tardiness_records t JOIN students s ON s.id=t.student_id ORDER BY t.occurred_at DESC");while(q.next()){QVariantMap m;m["id"]=q.value(0);m["studentId"]=q.value(1);m["student"]=q.value(2);m["date"]=q.value(3);m["note"]=q.value(4);out<<m;}return out;
}
bool SchoolApp::addTardiness(const QVariantMap &v){if(!allowed({"administrateur","enseignant"}))return false;return execute("INSERT INTO tardiness_records(student_id,recorded_by,occurred_at,note) VALUES(?,?,?,?)",{v["studentId"],m_userId,v["date"],v["note"]});}

QVariantList SchoolApp::examPeriods() const
{
    QVariantList out;QSqlQuery q("SELECT id,label,start_date,end_date,is_active FROM exam_periods ORDER BY start_date DESC");while(q.next()){QVariantMap m;m["id"]=q.value(0);m["label"]=q.value(1);m["startDate"]=q.value(2);m["endDate"]=q.value(3);m["active"]=q.value(4).toBool();out<<m;}return out;
}
bool SchoolApp::addExamPeriod(const QVariantMap &v){if(!allowed({"administrateur"}))return false;return execute("INSERT INTO exam_periods(label,start_date,end_date,is_active,activated_by) VALUES(?,?,?,?,?)",{v["label"],v["startDate"],v["endDate"],v["active"].toBool(),m_userId});}
bool SchoolApp::toggleExamPeriod(int id){if(!allowed({"administrateur"}))return false;execute("UPDATE exam_periods SET is_active=0");return execute("UPDATE exam_periods SET is_active=1,activated_by=? WHERE id=?",{m_userId,id});}

QVariantList SchoolApp::dashboard() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    q.exec("SELECT COUNT(*) FROM students WHERE deleted_at IS NULL AND graduated_at IS NULL");q.next();QVariantMap a;a["label"]="Élèves";a["value"]=q.value(0);out<<a;
    q.exec("SELECT COUNT(*) FROM users WHERE role='enseignant' AND deleted_at IS NULL");q.next();QVariantMap b;b["label"]="Enseignants";b["value"]=q.value(0);out<<b;
    q.exec("SELECT COUNT(*) FROM courses");q.next();QVariantMap c;c["label"]="Cours";c["value"]=q.value(0);out<<c;
    q.exec("SELECT COALESCE(SUM(amount),0) FROM payments WHERE strftime('%Y-%m',paid_at)=strftime('%Y-%m','now')");q.next();QVariantMap d;d["label"]="Paiements ce mois";d["value"]=q.value(0);out<<d;
    return out;
}
ESCATO_EOF
mkdir -p "src/core"
cat > "src/core/SchoolApp.h" <<'ESCATO_EOF'
#pragma once
#include <QObject>
#include <QVariantList>
#include <QStringList>
#include "Database.h"

class SchoolApp : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool loggedIn READ loggedIn NOTIFY sessionChanged)
    Q_PROPERTY(QString currentUser READ currentUser NOTIFY sessionChanged)
    Q_PROPERTY(QString currentRole READ currentRole NOTIFY sessionChanged)
    Q_PROPERTY(bool needsSetup READ needsSetup NOTIFY sessionChanged)
    Q_PROPERTY(int studentCount READ studentCount NOTIFY dataChanged)
    Q_PROPERTY(int teacherCount READ teacherCount NOTIFY dataChanged)
    Q_PROPERTY(int courseCount READ courseCount NOTIFY dataChanged)
    Q_PROPERTY(int pendingInvoiceCount READ pendingInvoiceCount NOTIFY dataChanged)

public:
    explicit SchoolApp(QObject *parent = nullptr);

    bool loggedIn() const { return m_userId > 0; }
    QString currentUser() const { return m_userName; }
    QString currentRole() const { return m_role; }
    // Vrai tant qu'aucun administrateur actif n'existe : l'application propose alors de le créer.
    bool needsSetup() const;

    int studentCount() const;
    int teacherCount() const;
    int courseCount() const;
    int pendingInvoiceCount() const;

    Q_INVOKABLE bool createFirstAdmin(const QString &name, const QString &email, const QString &password);
    Q_INVOKABLE bool login(const QString &email, const QString &password);
    Q_INVOKABLE void logout();

    Q_INVOKABLE QStringList classes() const;
    Q_INVOKABLE QStringList roles() const;
    Q_INVOKABLE QStringList paymentMethods() const;
    Q_INVOKABLE QStringList terms() const;

    Q_INVOKABLE QVariantList students(const QString &className = QString(), const QString &search = QString()) const;
    Q_INVOKABLE QVariantMap student(int id) const;
    Q_INVOKABLE bool addStudent(const QVariantMap &v);
    Q_INVOKABLE bool updateStudent(int id, const QVariantMap &v);
    Q_INVOKABLE bool deleteStudent(int id);
    Q_INVOKABLE bool graduateStudent(int id);
    Q_INVOKABLE bool blockStudent(int id, const QString &reason);
    Q_INVOKABLE bool unblockStudent(int id);

    Q_INVOKABLE QVariantList teachers(const QString &search = QString()) const;
    Q_INVOKABLE bool addTeacher(const QVariantMap &v);
    Q_INVOKABLE bool updateTeacher(int id, const QVariantMap &v);
    Q_INVOKABLE bool deleteTeacher(int id);

    Q_INVOKABLE QVariantList courses(const QString &className = QString()) const;
    Q_INVOKABLE bool addCourse(const QVariantMap &v);
    Q_INVOKABLE bool updateCourse(int id, const QVariantMap &v);
    Q_INVOKABLE bool deleteCourse(int id);

    Q_INVOKABLE QVariantList resources(int courseId) const;
    Q_INVOKABLE bool addResource(const QVariantMap &v);
    Q_INVOKABLE bool deleteResource(int id);

    Q_INVOKABLE QVariantList exams() const;
    Q_INVOKABLE bool addExam(const QVariantMap &v);
    Q_INVOKABLE bool updateExam(int id, const QVariantMap &v);
    Q_INVOKABLE bool deleteExam(int id);

    Q_INVOKABLE QVariantList grades(int examId) const;
    Q_INVOKABLE bool saveGrade(int examId, int studentId, double score, const QString &comment);
    Q_INVOKABLE QVariantMap bulletin(int studentId, const QString &term) const;

    Q_INVOKABLE QVariantList payments(int studentId = 0) const;
    Q_INVOKABLE bool addPayment(const QVariantMap &v);
    Q_INVOKABLE QVariantList invoices(const QString &status = QString()) const;
    Q_INVOKABLE QVariantList studentInvoices(int studentId) const;
    Q_INVOKABLE bool setStudentFee(int studentId, double amount);
    Q_INVOKABLE bool generateMonthlyInvoices(const QString &month);
    Q_INVOKABLE bool processPaymentReminders();

    // Comptabilité : caisse, banque, journal, plan comptable et exports
    Q_INVOKABLE QVariantMap accountingDashboard() const;
    Q_INVOKABLE QVariantList chartOfAccounts() const;
    Q_INVOKABLE bool addAccount(const QString &code, const QString &label, const QString &type);
    Q_INVOKABLE QVariantList expenses() const;
    Q_INVOKABLE bool addExpense(const QVariantMap &v);
    Q_INVOKABLE QVariantList journal(const QString &fromDate = QString(), const QString &toDate = QString()) const;
    Q_INVOKABLE QVariantList trialBalance(const QString &fromDate = QString(), const QString &toDate = QString()) const;
    Q_INVOKABLE QVariantList generalLedger(const QString &accountCode, const QString &fromDate = QString(), const QString &toDate = QString()) const;
    Q_INVOKABLE QString accountingExportDirectory() const;
    Q_INVOKABLE bool exportAccountingCsv(const QString &kind, const QString &filePath = QString()) const;

    Q_INVOKABLE QVariantList messages() const;
    Q_INVOKABLE bool sendMessage(int recipientId, const QString &subject, const QString &body);
    Q_INVOKABLE QVariantList users(const QString &role = QString()) const;
    Q_INVOKABLE bool createUser(const QVariantMap &v);
    Q_INVOKABLE bool updateUserRole(int id, const QString &role);
    Q_INVOKABLE bool blockUser(int id, const QString &category, const QString &reason);
    Q_INVOKABLE bool unblockUser(int id);

    Q_INVOKABLE QVariantList announcements() const;
    Q_INVOKABLE bool addAnnouncement(const QVariantMap &v);
    Q_INVOKABLE bool deleteAnnouncement(int id);

    Q_INVOKABLE QVariantList tardiness() const;
    Q_INVOKABLE bool addTardiness(const QVariantMap &v);

    Q_INVOKABLE QVariantList examPeriods() const;
    Q_INVOKABLE bool addExamPeriod(const QVariantMap &v);
    Q_INVOKABLE bool toggleExamPeriod(int id);

    Q_INVOKABLE QVariantList dashboard() const;
    Q_INVOKABLE bool resetPassword(int userId, const QString &newPassword);

signals:
    void sessionChanged();
    void dataChanged();
    void errorOccurred(const QString &message);

private:
    Database m_db;
    int m_userId = 0;
    QString m_userName;
    QString m_role;

    QString passwordHash(const QString &password) const;
    bool allowed(const QStringList &roles) const;
    void audit(const QString &action, const QString &entity, int entityId, const QString &details = QString());
    bool execute(const QString &sql, const QVariantList &bind = {});
};
ESCATO_EOF
mkdir -p "src"
cat > "src/main.cpp" <<'ESCATO_EOF'
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>
#include "core/SchoolApp.h"
#include "core/PrintManager.h"

int main(int argc, char *argv[])
{
    // QApplication (et non QGuiApplication) : QPrintDialog est un widget.
    QApplication app(argc, argv);
    QApplication::setOrganizationName("ESCATO");
    QApplication::setApplicationName("ESCATO");
    QApplication::setApplicationVersion("1.0.0");

    SchoolApp school;
    PrintManager printer;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("school", &school);
    engine.rootContext()->setContextProperty("printer", &printer);

    const QUrl url(QStringLiteral("qrc:/qt/qml/ESCATO/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [] { QCoreApplication::exit(-1); },
                     Qt::QueuedConnection);
    engine.load(url);
    return app.exec();
}
ESCATO_EOF
mkdir -p "assets"
base64 -d > "assets/logo.png" <<'ESCATO_EOF'
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
Hj169OjRB44ePXr06NEHjh49evTo0aMPHD169OjRow8cPXr06NGjDxw9evTo0aMPHD169OjRow8c
PXr06NGjDxw9evTo0aNHHzh69OjRo0cfOHr06NGjRx84evTo0aNHHzh69OjRo0cfOHr06NGjR48+
cPTo0aNHjz5w9OjRo0ePPnD06NGjR48+cPTo0aNHjz5w9OjRo0ePPnD06NGjR48efeDo0aNHjx59
4OjRo0ePHn3g6NGjR48efeDo0aNHjx594OjRo0ePHn3g6NGjR48ePfrA0aNHjx49+sDRo0ePHj36
wNGjR48ePfrA0aNHjx49+sDRo0ePHj36wNGjR48ePXr0gaNHjx49evSBo0ePHj169IGjR48ePXrc
WogALo67gxsOIICDICDSP6UePXr0eDvCvQQDXwQFHIhRwFVpRFl2CGokVXCIbqQSW3rcLEj3xr32
X3ZvaI9+ffxAn9yvnx7fGyv2cwdUAiIZRRAUEEQgDj0wtSFXdAkfBtydRgOCEzzjkgH/gZdmj7d0
KoBr9za+zlss9hYOjh639/r4Po6Ifv30+N5V1QUPBa9AMuJO0hXGyYgOcoTK7xgFTsWMti2CklVw
ccAIXi4180ylx5/2Oyjfx+bv35t+fbyF+2W/fnq8xrISB3Elq3VXk8BFU56fJeK4imy871Hue/A+
UtPiJiABl4zhqMc+nb2p72J6k30f3sKNs8dtvz7eNG7066fH6weQ4JBCwqVlKJH04ks8+bWvEyvN
/Nxf/Dn+b//4/07TZAZx2KXABmq4Ot4vrJsHD2/y7ub+GfXr4y2cDv366fE6S8OFkAMZSDSM6pp/
+b/9c77wtceJJs5wNGB9fZPcZkKMpZM+z1XU+id40+P+G/Q4+hpDvz7eSo+jXz893ggWCqnKQCqI
VUTdiY1AkgAueM6YZFwMUDDB31LzrcdbR+INWVX070+/Pt4Cq6pfPz1e91rhIDPUBbKiIZACNGpE
cwgeQCCIdhlGd4sRRfsLyc29TXp844xD/PAvPgTpDjf/odyUe+yjeoNSw/eRcUi/wXu8/gJKmlEU
F0FUMMuYOVFax72Uo0wgUB3YztIvrENRiniDv5PDS4nxLnC4gJqiGKZGFhCPBNP9l9gvsz/ZkvCy
X5OCOsSuouxSKLZi4TWDg9ywng73+ulxsxGIXhQcczlf8ICYEOVVG/17D6r+Vnho48Yhf48EUHEM
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
kLIQeh+VAAAAAElFTkSuQmCC
ESCATO_EOF

echo "Fichiers créés dans $(pwd)"

# ---------------- Dépôt Git local ----------------
git init -b main
git add .
git commit -m "feat: import initial du projet ESCATO (C++/Qt6/QML/SQLite) avec correctifs"

cat <<'MSG'

=== Dépôt local prêt ===

1) Lier à GitHub (crée d'abord un dépôt VIDE sur github.com, sans README) :

     git remote add origin https://github.com/VOTRE_UTILISATEUR/ESCATO.git
     git push -u origin main

   ou, avec GitHub CLI (gh) :

     gh repo create ESCATO --private --source=. --remote=origin --push

2) Compiler et tester (Qt 6 avec Quick, Sql, PrintSupport, Widgets + CMake) :

     cmake -S . -B build
     cmake --build build

   Au premier lancement, l'écran « Première configuration » permet de créer
   le compte administrateur (aucun compte n'est créé d'avance).

MSG

