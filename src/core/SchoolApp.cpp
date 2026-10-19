#include <algorithm>
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
#include <QSslSocket>
#include <QTimer>
#include <QTime>
#include <QSet>
#include <QImage>
#include <QBuffer>
#include "third_party/qrcodegen/qrcodegen.hpp"
#include <QStandardPaths>
#include <QDir>
#include <QUuid>
#include <QUrl>
#include <QFile>
#include <QImage>

static constexpr int kMinPasswordLength = 8;

SchoolApp::SchoolApp(QObject *parent) : QObject(parent)
{
    m_emailTimer = new QTimer(this);
    connect(m_emailTimer, &QTimer::timeout, this, &SchoolApp::runScheduledEmails);
    m_emailTimer->start(60000);
    if (!m_db.open())
        emit errorOccurred(m_db.lastError());
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
    q.addBindValue(n); q.addBindValue(e); q.addBindValue(Database::hashPassword(password));
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
    const int uid = q.value(0).toInt();
    QSqlQuery p(m_db.db());
    p.prepare("SELECT password_hash FROM users WHERE id=?");
    p.addBindValue(uid);
    if (!p.exec() || !p.next()) return false;
    const QString stored = p.value(0).toString();
    if (!Database::verifyPassword(password, stored)) return false;

    if (Database::needsRehash(stored)) {
        QSqlQuery r(m_db.db());
        r.prepare("UPDATE users SET password_hash=? WHERE id=?");
        r.addBindValue(Database::hashPassword(password));
        r.addBindValue(uid);
        r.exec();
    }

    m_userId = uid;
    m_userName = q.value(1).toString();
    m_role = q.value(2).toString();
    audit("login","users",m_userId);
    emit sessionChanged();
    return true;
}

void SchoolApp::logout()
{
    if (m_userId) audit("logout","users",m_userId);
    m_userId = 0; m_userName.clear(); m_role.clear(); m_smtpPassword.clear();
    emit sessionChanged();
}

int SchoolApp::studentCount() const { QSqlQuery q(m_db.db()); q.exec("SELECT COUNT(*) FROM students WHERE deleted_at IS NULL AND graduated_at IS NULL"); return q.next()?q.value(0).toInt():0; }
int SchoolApp::teacherCount() const { QSqlQuery q(m_db.db()); q.exec("SELECT COUNT(*) FROM users WHERE role='enseignant' AND deleted_at IS NULL"); return q.next()?q.value(0).toInt():0; }
int SchoolApp::courseCount() const { QSqlQuery q(m_db.db()); q.exec("SELECT COUNT(*) FROM courses"); return q.next()?q.value(0).toInt():0; }
int SchoolApp::pendingInvoiceCount() const { QSqlQuery q(m_db.db()); q.exec("SELECT COUNT(*) FROM invoices WHERE status IN('pending','late')"); return q.next()?q.value(0).toInt():0; }

QStringList SchoolApp::classes() const
{
    QStringList out;
    QSqlQuery q(m_db.db());
    if (q.exec("SELECT name FROM school_classes WHERE is_active=1 ORDER BY sort_order,id")) {
        while (q.next()) out << q.value(0).toString();
    }
    return out;
}
QStringList SchoolApp::roles() const { return {"administrateur","enseignant","eleve","parent","comptable"}; }
QStringList SchoolApp::paymentMethods() const
{
    QStringList out;
    QSqlQuery q(m_db.db());
    if (q.exec("SELECT code FROM payment_methods WHERE is_active=1 ORDER BY rowid")) while (q.next()) out << q.value(0).toString();
    return out;
}
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
    if (!((can("students.view")))) return QVariantList();
    QVariantList out; QSqlQuery q(m_db.db());
    QString sql="SELECT s.id,s.matricule,s.last_name,s.first_name,s.birth_date,s.birth_place,s.current_class,s.parent_phone,s.parent_email,s.address,s.previous_school,s.previous_class,s.desired_career,s.graduated_at,s.consecutive_missed_payments,u.account_status,s.entry_date FROM students s LEFT JOIN users u ON u.id=s.user_id WHERE s.deleted_at IS NULL";
    if(!className.isEmpty()) sql+=" AND current_class=?";
    if(!search.isEmpty()) sql+=" AND (last_name LIKE ? OR first_name LIKE ? OR matricule LIKE ?)";
    sql+=" ORDER BY current_class,last_name,first_name";
    q.prepare(sql); if(!className.isEmpty()) q.addBindValue(className); if(!search.isEmpty()){QString x="%"+search+"%";q.addBindValue(x);q.addBindValue(x);q.addBindValue(x);}
    if(!q.exec()) return out;
    while(q.next()){ QVariantMap m; QStringList keys={"id","matricule","lastName","firstName","birthDate","birthPlace","className","parentPhone","parentEmail","address","previousSchool","previousClass","desiredCareer","graduatedAt","missedPayments","accountStatus","entryDate"}; for(int i=0;i<keys.size();++i)m[keys[i]]=q.value(i); out<<m; } return out;
}

QVariantMap SchoolApp::student(int id) const
{
    if (!(canViewStudent(id))) return QVariantMap();
    QSqlQuery q(m_db.db());
    q.prepare("SELECT s.id,s.matricule,s.last_name,s.first_name,s.birth_date,s.birth_place,s.current_class,s.parent_phone,s.parent_email,s.address,s.previous_school,s.previous_class,s.desired_career,s.graduated_at,s.consecutive_missed_payments,u.account_status,s.entry_date FROM students s LEFT JOIN users u ON u.id=s.user_id WHERE s.deleted_at IS NULL AND s.id=?");
    q.addBindValue(id);
    if(!q.exec() || !q.next()) return {};
    QVariantMap m; QStringList keys={"id","matricule","lastName","firstName","birthDate","birthPlace","className","parentPhone","parentEmail","address","previousSchool","previousClass","desiredCareer","graduatedAt","missedPayments","accountStatus","entryDate"};
    for(int i=0;i<keys.size();++i) m[keys[i]]=q.value(i);
    return m;
}

bool SchoolApp::addStudent(const QVariantMap &v)
{
    if(!can("students.create")) return false;
    QSqlDatabase db=m_db.db(); db.transaction();
    QSqlQuery q(db);
    QString matricule=v.value("matricule").toString().trimmed();
    if(matricule.isEmpty()) matricule="ELV-"+QDateTime::currentDateTime().toString("yyyyMMddhhmmsszzz")+"-"+QUuid::createUuid().toString(QUuid::Id128).left(4).toUpper();
    q.prepare(R"(INSERT INTO students(matricule,last_name,first_name,birth_date,birth_place,father_name,father_job,mother_name,mother_job,parent_phone,parent_email,address,previous_school,previous_class,current_class,desired_career,photo,entry_date) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?))");
    QStringList k={"lastName","firstName","birthDate","birthPlace","fatherName","fatherJob","motherName","motherJob","parentPhone","parentEmail","address","previousSchool","previousClass","className","desiredCareer","photo","entryDate"};
    q.addBindValue(matricule); for(auto &x:k) q.addBindValue(v.value(x));
    if(!q.exec()){
        db.rollback();
        emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce matricule est déjà utilisé par un autre élève.") : q.lastError().text());
        return false;
    }
    db.commit(); audit("create","student",q.lastInsertId().toInt()); emit dataChanged(); return true;
}

bool SchoolApp::updateStudent(int id,const QVariantMap &v)
{
    if(!can("students.edit"))return false;
    QSqlQuery q(m_db.db()); q.prepare(R"(UPDATE students SET last_name=?,first_name=?,birth_date=?,birth_place=?,father_name=?,father_job=?,mother_name=?,mother_job=?,parent_phone=?,parent_email=?,address=?,previous_school=?,previous_class=?,current_class=?,desired_career=?,photo=?,entry_date=?,updated_at=CURRENT_TIMESTAMP WHERE id=?)");
    QStringList k={"lastName","firstName","birthDate","birthPlace","fatherName","fatherJob","motherName","motherJob","parentPhone","parentEmail","address","previousSchool","previousClass","className","desiredCareer","photo","entryDate"}; for(auto &x:k)q.addBindValue(v.value(x));q.addBindValue(id); if(!q.exec())return false;audit("update","student",id);emit dataChanged();return true;
}

bool SchoolApp::deleteStudent(int id){ if(!can("students.delete"))return false; return execute("UPDATE students SET deleted_at=CURRENT_TIMESTAMP WHERE id=?",{id}); }
bool SchoolApp::graduateStudent(int id){ if(!can("students.delete"))return false; return execute("UPDATE students SET graduated_at=DATE('now') WHERE id=?",{id}); }
bool SchoolApp::blockStudent(int id,const QString &reason)
{
    if(!can("students.block"))return false;
    QSqlQuery q(m_db.db());q.prepare("SELECT user_id FROM students WHERE id=?");q.addBindValue(id);if(!q.exec()||!q.next()||q.value(0).isNull())return false;
    return blockUser(q.value(0).toInt(),"discipline",reason);
}
bool SchoolApp::unblockStudent(int id)
{
    if (!((can("students.block")))) return false;
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
    if(!can("teachers.manage"))return false;
    if(v.value("password").toString().size()<kMinPasswordLength){emit errorOccurred(QStringLiteral("Le mot de passe doit contenir au moins %1 caractères.").arg(kMinPasswordLength));return false;}
    QSqlDatabase db=m_db.db();db.transaction();QSqlQuery q(db);
    q.prepare("INSERT INTO users(name,email,password_hash,role) VALUES(?,?,?, 'enseignant')");q.addBindValue(v["name"]);q.addBindValue(v["email"]);q.addBindValue(Database::hashPassword(v.value("password").toString()));
    if(!q.exec()){db.rollback();emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cet e-mail est déjà utilisé par un autre compte.") : q.lastError().text());return false;}int uid=q.lastInsertId().toInt();
    q.prepare(R"(INSERT INTO teacher_profiles(user_id,identity_number,cnaps_number,mle_number,contact,address,dob,place_of_birth,number_of_children,marital_status,religion,subject,occupation,employment_type,hiring_date,contract_end_date,comment,photo) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?))");
    QStringList k={"cin","cnaps","mle","contact","address","dob","birthPlace","children","maritalStatus","religion","subject","occupation","employmentType","hiringDate","contractEndDate","comment","photo"};q.addBindValue(uid);for(auto &x:k)q.addBindValue(v.value(x));if(!q.exec()){db.rollback();return false;}db.commit();audit("create","teacher",uid);emit dataChanged();return true;
}

bool SchoolApp::updateTeacher(int id,const QVariantMap &v)
{
    if(!can("teachers.manage"))return false;QSqlQuery q(m_db.db());q.prepare("UPDATE users SET name=?,email=? WHERE id=?");q.addBindValue(v["name"]);q.addBindValue(v["email"]);q.addBindValue(id);if(!q.exec())return false;
    q.prepare(R"(UPDATE teacher_profiles SET identity_number=?,cnaps_number=?,mle_number=?,contact=?,address=?,dob=?,place_of_birth=?,number_of_children=?,marital_status=?,religion=?,subject=?,occupation=?,employment_type=?,hiring_date=?,contract_end_date=?,comment=?,photo=? WHERE user_id=?)");
    QStringList k={"cin","cnaps","mle","contact","address","dob","birthPlace","children","maritalStatus","religion","subject","occupation","employmentType","hiringDate","contractEndDate","comment","photo"};for(auto &x:k)q.addBindValue(v.value(x));q.addBindValue(id);if(!q.exec())return false;emit dataChanged();return true;
}
bool SchoolApp::deleteTeacher(int id){if(!can("teachers.manage"))return false;return execute("UPDATE users SET deleted_at=CURRENT_TIMESTAMP WHERE id=? AND role='enseignant'",{id});}

QVariantList SchoolApp::courses(const QString &className) const
{
    QVariantList out;QSqlQuery q(m_db.db());QString sql="SELECT c.id,c.title,c.subject,c.class_name,c.description,c.teacher_id,COALESCE(u.name,'Non affecté') FROM courses c LEFT JOIN users u ON u.id=c.teacher_id";if(!className.isEmpty())sql+=" WHERE c.class_name=?";sql+=" ORDER BY c.class_name,c.subject";q.prepare(sql);if(!className.isEmpty())q.addBindValue(className);q.exec();while(q.next()){QVariantMap m;m["id"]=q.value(0);m["title"]=q.value(1);m["subject"]=q.value(2);m["className"]=q.value(3);m["description"]=q.value(4);m["teacherId"]=q.value(5);m["teacher"]=q.value(6);out<<m;}return out;
}
bool SchoolApp::addCourse(const QVariantMap &v){if(!can("courses.manage"))return false;return execute("INSERT INTO courses(title,subject,class_name,description,teacher_id) VALUES(?,?,?,?,?)",{v["title"],v["subject"],v["className"],v["description"],v["teacherId"]});}
bool SchoolApp::updateCourse(int id,const QVariantMap &v){if(!can("courses.manage"))return false;return execute("UPDATE courses SET title=?,subject=?,class_name=?,description=?,teacher_id=? WHERE id=?", {v["title"],v["subject"],v["className"],v["description"],v["teacherId"],id});}
bool SchoolApp::deleteCourse(int id){if(!can("courses.manage"))return false;return execute("DELETE FROM courses WHERE id=?",{id});}

QVariantList SchoolApp::resources(int courseId) const
{
    QVariantList out;QSqlQuery q(m_db.db());q.prepare("SELECT id,title,type,file_path,url FROM course_resources WHERE course_id=? ORDER BY title");q.addBindValue(courseId);q.exec();while(q.next()){QVariantMap m;m["id"]=q.value(0);m["title"]=q.value(1);m["type"]=q.value(2);m["filePath"]=q.value(3);m["url"]=q.value(4);out<<m;}return out;
}
bool SchoolApp::addResource(const QVariantMap &v){if(!can("courses.manage"))return false;return execute("INSERT INTO course_resources(course_id,title,type,file_path,url) VALUES(?,?,?,?,?)",{v["courseId"],v["title"],v["type"],v["filePath"],v["url"]});}
bool SchoolApp::deleteResource(int id){if(!can("courses.manage"))return false;return execute("DELETE FROM course_resources WHERE id=?",{id});}

QVariantList SchoolApp::exams() const
{
    if (!((can("grades.edit") || can("deliberations.view")))) return QVariantList();
    QVariantList out;QSqlQuery q("SELECT e.id,e.title,e.term,e.exam_date,e.max_score,e.course_id,c.title,c.subject,c.class_name FROM exams e JOIN courses c ON c.id=e.course_id ORDER BY e.exam_date DESC");while(q.next()){QVariantMap m;m["id"]=q.value(0);m["title"]=q.value(1);m["term"]=q.value(2);m["date"]=q.value(3);m["maxScore"]=q.value(4);m["courseId"]=q.value(5);m["course"]=q.value(6);m["subject"]=q.value(7);m["className"]=q.value(8);out<<m;}return out;
}
bool SchoolApp::addExam(const QVariantMap &v){if(!can("exams.manage"))return false;return execute("INSERT INTO exams(course_id,title,term,exam_date,max_score) VALUES(?,?,?,?,?)",{v["courseId"],v["title"],v["term"],v["date"],v["maxScore"]});}
bool SchoolApp::updateExam(int id,const QVariantMap &v){if(!can("exams.manage"))return false;return execute("UPDATE exams SET course_id=?,title=?,term=?,exam_date=?,max_score=? WHERE id=?", {v["courseId"],v["title"],v["term"],v["date"],v["maxScore"],id});}
bool SchoolApp::deleteExam(int id){if(!can("exams.manage"))return false;return execute("DELETE FROM exams WHERE id=?",{id});}

QVariantList SchoolApp::grades(int examId) const
{
    if (!((can("grades.edit") || can("deliberations.view")))) return QVariantList();
    QVariantList out;QSqlQuery q(m_db.db());q.prepare(R"(SELECT s.id,s.matricule,s.last_name,s.first_name,s.current_class,g.score,g.comment FROM students s JOIN exams e ON e.id=? LEFT JOIN grades g ON g.student_id=s.id AND g.exam_id=e.id WHERE s.current_class=(SELECT c.class_name FROM courses c JOIN exams e2 ON e2.course_id=c.id WHERE e2.id=?) AND s.deleted_at IS NULL ORDER BY s.last_name)");q.addBindValue(examId);q.addBindValue(examId);q.exec();while(q.next()){QVariantMap m;m["studentId"]=q.value(0);m["matricule"]=q.value(1);m["lastName"]=q.value(2);m["firstName"]=q.value(3);m["className"]=q.value(4);m["score"]=q.value(5).isNull()?QVariant():q.value(5);m["comment"]=q.value(6);out<<m;}return out;
}
bool SchoolApp::saveGrade(int examId,int studentId,double score,const QString &comment){
    if(!can("grades.edit"))return false;
    QSqlQuery mq(m_db.db());mq.prepare("SELECT max_score FROM exams WHERE id=?");mq.addBindValue(examId);
    if(!mq.exec()||!mq.next())return false;
    if(!(score>=0.0 && score<=mq.value(0).toDouble())){emit errorOccurred(QStringLiteral("Note invalide : elle doit être comprise entre 0 et %1.").arg(mq.value(0).toInt()));return false;}
    return execute("INSERT INTO grades(exam_id,student_id,score,comment) VALUES(?,?,?,?) ON CONFLICT(exam_id,student_id) DO UPDATE SET score=excluded.score,comment=excluded.comment",{examId,studentId,score,comment});}

QVariantMap SchoolApp::bulletin(int studentId,const QString &term) const
{
    if (!(canViewStudent(studentId))) return QVariantMap();
    QVariantMap result;result["student"]=student(studentId);QSqlQuery q(m_db.db());q.prepare(R"(SELECT c.subject,ROUND(AVG((g.score*20.0)/e.max_score),2) FROM grades g JOIN exams e ON e.id=g.exam_id JOIN courses c ON c.id=e.course_id WHERE g.student_id=? AND e.term=? GROUP BY c.subject ORDER BY c.subject)");q.addBindValue(studentId);q.addBindValue(term);q.exec();QVariantList subjects;double sum=0;int n=0;while(q.next()){QVariantMap m;m["subject"]=q.value(0);m["average"]=q.value(1);subjects<<m;sum+=q.value(1).toDouble();n++;}result["subjects"]=subjects;result["generalAverage"]=n?QString::number(sum/n,'f',2):QString();return result;
}

QVariantList SchoolApp::payments(int studentId) const
{
    if (!(financeVisible(studentId))) return QVariantList();
    QVariantList out;QString sql="SELECT p.id,p.student_id,s.last_name||' '||s.first_name,p.amount,p.method,p.payer_role,p.reference,p.paid_at,p.notes FROM payments p JOIN students s ON s.id=p.student_id";if(studentId)sql+=" WHERE p.student_id=?";sql+=" ORDER BY p.paid_at DESC";QSqlQuery q(m_db.db());q.prepare(sql);if(studentId)q.addBindValue(studentId);q.exec();while(q.next()){QVariantMap m;QStringList k={"id","studentId","student","amount","method","payerRole","reference","paidAt","notes"};for(int i=0;i<k.size();i++)m[k[i]]=q.value(i);out<<m;}return out;
}
bool SchoolApp::addPayment(const QVariantMap &v)
{
    if(!can("payments.create")) return false;
    const double amount = v.value("amount").toDouble();
    if(amount <= 0.0) return false;
    if(!periodOpenFor(v.value("paidAt").toString())) { emit errorOccurred(QStringLiteral("Période comptable clôturée : enregistrement refusé.")); return false; }
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
    {
        const QString year = paidAt.left(4);
        QSqlQuery seq(db);
        seq.prepare("SELECT COALESCE(MAX(CAST(substr(receipt_number,-5) AS INTEGER)),0)+1 FROM payments WHERE receipt_number LIKE ?");
        seq.addBindValue(QStringLiteral("REC-%1-%").arg(year));
        const int next = seq.exec() && seq.next() ? seq.value(0).toInt() : 1;
        QSqlQuery rn(db);
        rn.prepare("UPDATE payments SET receipt_number=? WHERE id=?");
        rn.addBindValue(QStringLiteral("REC-%1-%2").arg(year).arg(next, 5, 10, QLatin1Char('0')));
        rn.addBindValue(pid);
        rn.exec();
    }

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
    if (!((can("balances.view")))) return QVariantList();
    QVariantList out;QString sql="SELECT i.id,i.student_id,s.last_name||' '||s.first_name,i.period_month,i.due_date,i.amount,i.status FROM invoices i JOIN students s ON s.id=i.student_id";if(!status.isEmpty())sql+=" WHERE i.status=?";sql+=" ORDER BY i.due_date DESC";QSqlQuery q(m_db.db());q.prepare(sql);if(!status.isEmpty())q.addBindValue(status);q.exec();while(q.next()){QVariantMap m;QStringList k={"id","studentId","student","month","dueDate","amount","status"};for(int i=0;i<k.size();i++)m[k[i]]=q.value(i);out<<m;}return out;
}
QVariantList SchoolApp::studentInvoices(int studentId) const
{
    if (!(financeVisible(studentId))) return QVariantList();
    QVariantList out;QSqlQuery q(m_db.db());q.prepare("SELECT id,period_month,due_date,amount,status,payment_id FROM invoices WHERE student_id=? ORDER BY due_date DESC");q.addBindValue(studentId);q.exec();while(q.next()){QVariantMap m;QStringList k={"id","month","dueDate","amount","status","paymentId"};for(int i=0;i<k.size();i++)m[k[i]]=q.value(i);out<<m;}return out;
}
bool SchoolApp::setStudentFee(int studentId,double amount){if(!can("fees.student"))return false;return execute("INSERT INTO student_fees(student_id,monthly_amount,set_by) VALUES(?,?,?)",{studentId,amount,m_userId});}
bool SchoolApp::generateMonthlyInvoices(const QString &month)
{
    if(!can("invoices.generate"))return false;
    QSqlQuery s(m_db.db());s.exec("SELECT id FROM students WHERE graduated_at IS NULL AND deleted_at IS NULL");
    while(s.next()){QSqlQuery f(m_db.db());f.prepare("SELECT COALESCE((SELECT monthly_amount FROM student_fees WHERE student_id=? ORDER BY id DESC LIMIT 1),(SELECT ct.monthly_amount FROM class_tuitions ct JOIN students st ON st.current_class=ct.class_name WHERE st.id=? AND ct.monthly_amount>0))");f.addBindValue(s.value(0));f.addBindValue(s.value(0));if(f.exec()&&f.next()&&!f.value(0).isNull()){QDate d=QDate::fromString(month+"-01","yyyy-MM-dd");if(!d.isValid())continue;QSqlQuery i(m_db.db());i.prepare("INSERT OR IGNORE INTO invoices(student_id,period_month,due_date,amount,status) VALUES(?,?,?,?, 'pending')");i.addBindValue(s.value(0));i.addBindValue(d.toString("yyyy-MM-dd"));i.addBindValue(d.addDays(9).toString("yyyy-MM-dd"));i.addBindValue(f.value(0).toDouble()*(1.0-scholarshipPercent(s.value(0).toInt())/100.0));i.exec();}}
    emit dataChanged();return true;
}
bool SchoolApp::processPaymentReminders()
{
    if(!can("invoices.remind"))return false;
    QSqlQuery q(m_db.db());q.exec("UPDATE invoices SET reminder_before_sent_at=COALESCE(reminder_before_sent_at,CURRENT_TIMESTAMP) WHERE status='pending' AND due_date=DATE('now','+3 day')");q.exec("UPDATE invoices SET status='late',reminder_late_sent_at=COALESCE(reminder_late_sent_at,CURRENT_TIMESTAMP) WHERE status='pending' AND due_date<DATE('now')");emit dataChanged();return true;
}


static QString csvField(const QVariant &value)
{
    QString s=value.toString();
    s.replace(QLatin1Char('"'), QLatin1String("\"\""));
    return QString("\"") + s + QString("\"");
}

QVariantMap SchoolApp::accountingDashboard() const
{
    if (!((can("finance.reports") || can("accounting.write")))) return QVariantMap();
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
    if (!((can("finance.reports") || can("accounting.write")))) return QVariantList();
    QVariantList out; QSqlQuery q(m_db.db());
    q.exec("SELECT code,label,account_type,active FROM chart_of_accounts WHERE active=1 ORDER BY code");
    while(q.next()){ QVariantMap m; m["code"]=q.value(0); m["label"]=q.value(1); m["type"]=q.value(2); m["active"]=q.value(3); out<<m; }
    return out;
}

bool SchoolApp::addAccount(const QString &code, const QString &label, const QString &type)
{
    if(!can("accounting.write") || code.trimmed().isEmpty() || label.trimmed().isEmpty()) return false;
    return execute("INSERT INTO chart_of_accounts(code,label,account_type) VALUES(?,?,?)",{code.trimmed(),label.trimmed(),type.trimmed().isEmpty()?"general":type.trimmed()});
}

QVariantList SchoolApp::expenses() const
{
    if (!((can("finance.reports") || can("accounting.write")))) return QVariantList();
    QVariantList out; QSqlQuery q(m_db.db());
    q.exec("SELECT e.id,e.expense_date,e.category,e.description,e.amount,e.payment_method,e.reference,e.account_code,COALESCE(u.name,'') FROM expenses e LEFT JOIN users u ON u.id=e.recorded_by ORDER BY e.expense_date DESC,e.id DESC");
    while(q.next()){ QVariantMap m; QStringList k={"id","date","category","description","amount","method","reference","accountCode","recordedBy"}; for(int i=0;i<k.size();++i)m[k[i]]=q.value(i); out<<m; }
    return out;
}

bool SchoolApp::addExpense(const QVariantMap &v)
{
    if(!can("accounting.write")) return false;
    const double amount=v.value("amount").toDouble(); if(amount<=0) return false;
    if(!periodOpenFor(v.value("date").toString())) { emit errorOccurred(QStringLiteral("Période comptable clôturée : dépense refusée.")); return false; }
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
    if (!((can("finance.reports") || can("accounting.write")))) return QVariantList();
    QVariantList out; QString sql="SELECT j.id,j.entry_date,j.journal_code,j.reference,j.description,l.account_code,COALESCE(a.label,''),l.label,l.debit,l.credit FROM journal_entries j JOIN journal_lines l ON l.entry_id=j.id LEFT JOIN chart_of_accounts a ON a.code=l.account_code WHERE 1=1";
    if(!fromDate.isEmpty()) sql+=" AND j.entry_date>=?"; if(!toDate.isEmpty()) sql+=" AND j.entry_date<=?"; sql+=" ORDER BY j.entry_date DESC,j.id DESC,l.id";
    QSqlQuery q(m_db.db());q.prepare(sql);if(!fromDate.isEmpty())q.addBindValue(fromDate);if(!toDate.isEmpty())q.addBindValue(toDate);q.exec();
    while(q.next()){QVariantMap m;QStringList k={"id","date","journal","reference","description","accountCode","accountLabel","lineLabel","debit","credit"};for(int i=0;i<k.size();++i)m[k[i]]=q.value(i);out<<m;}return out;
}

QVariantList SchoolApp::trialBalance(const QString &fromDate, const QString &toDate) const
{
    if (!((can("finance.reports") || can("accounting.write")))) return QVariantList();
    QVariantList out; QString sql="SELECT a.code,a.label,COALESCE(SUM(l.debit),0),COALESCE(SUM(l.credit),0),COALESCE(SUM(l.debit-l.credit),0) FROM chart_of_accounts a LEFT JOIN journal_lines l ON l.account_code=a.code LEFT JOIN journal_entries j ON j.id=l.entry_id";
    QStringList where; if(!fromDate.isEmpty())where<<"j.entry_date>=?";if(!toDate.isEmpty())where<<"j.entry_date<=?";if(!where.isEmpty())sql+=" WHERE "+where.join(" AND ");sql+=" GROUP BY a.code,a.label ORDER BY a.code";
    QSqlQuery q(m_db.db());q.prepare(sql);if(!fromDate.isEmpty())q.addBindValue(fromDate);if(!toDate.isEmpty())q.addBindValue(toDate);q.exec();
    while(q.next()){QVariantMap m;m["code"]=q.value(0);m["label"]=q.value(1);m["debit"]=q.value(2);m["credit"]=q.value(3);m["balance"]=q.value(4);out<<m;}return out;
}

QVariantList SchoolApp::generalLedger(const QString &accountCode, const QString &fromDate, const QString &toDate) const
{
    if (!((can("finance.reports") || can("accounting.write")))) return QVariantList();
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
    if(!can("accounting.export"))return false;
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
    if (m_userId <= 0) return QVariantList();
    QVariantList out;QSqlQuery q(m_db.db());QString sql="SELECT id,name,email,role,account_status,blocked_reason,blocked_category,requires_password_reset FROM users WHERE deleted_at IS NULL";if(!role.isEmpty())sql+=" AND role=?";sql+=" ORDER BY name";q.prepare(sql);if(!role.isEmpty())q.addBindValue(role);q.exec();while(q.next()){QVariantMap m;QStringList k={"id","name","email","role","status","blockedReason","blockedCategory","requiresPasswordReset"};for(int i=0;i<k.size();i++)m[k[i]]=q.value(i);if(!can("users.manage")){m.remove("email");m.remove("status");m.remove("blockedReason");m.remove("blockedCategory");m.remove("requiresPasswordReset");}out<<m;}return out;
}
bool SchoolApp::createUser(const QVariantMap &v){
    if(!can("users.manage"))return false;
    if(v.value("name").toString().trimmed().isEmpty()||v.value("email").toString().trimmed().isEmpty()||!roles().contains(v.value("role").toString())){emit errorOccurred(QStringLiteral("Nom, e-mail et rôle valides requis."));return false;}
    if(v.value("password").toString().size()<kMinPasswordLength){emit errorOccurred(QStringLiteral("Le mot de passe doit contenir au moins %1 caractères.").arg(kMinPasswordLength));return false;}
    return execute("INSERT INTO users(name,email,password_hash,role) VALUES(?,?,?,?)",{v["name"],v["email"],Database::hashPassword(v["password"].toString()),v["role"]});}
bool SchoolApp::updateUserRole(int id,const QString &role){if(!can("users.manage")||id==m_userId)return false;return execute("UPDATE users SET role=? WHERE id=?",{role,id});}
bool SchoolApp::blockUser(int id,const QString &category,const QString &reason){if(!can("users.block")||id==m_userId)return false;return execute("UPDATE users SET account_status='blocked',blocked_category=?,blocked_reason=? WHERE id=?", {category,reason,id});}
bool SchoolApp::unblockUser(int id){if(!can("users.unblock"))return false;return execute("UPDATE users SET account_status='active',blocked_category=NULL,blocked_reason=NULL,requires_password_reset=1 WHERE id=?", {id});}
bool SchoolApp::resetPassword(int userId,const QString &newPassword){if(!can("users.manage"))return false;if(newPassword.size()<kMinPasswordLength){emit errorOccurred(QStringLiteral("Le mot de passe doit contenir au moins %1 caractères.").arg(kMinPasswordLength));return false;}return execute("UPDATE users SET password_hash=?,requires_password_reset=0 WHERE id=?", {Database::hashPassword(newPassword),userId});}

QVariantList SchoolApp::announcements() const
{
    QVariantList out;QSqlQuery q("SELECT a.id,a.title,a.body,a.event_date,a.created_at,COALESCE(u.name,'') FROM announcements a LEFT JOIN users u ON u.id=a.created_by ORDER BY a.created_at DESC");while(q.next()){QVariantMap m;m["id"]=q.value(0);m["title"]=q.value(1);m["body"]=q.value(2);m["eventDate"]=q.value(3);m["createdAt"]=q.value(4);m["creator"]=q.value(5);out<<m;}return out;
}
bool SchoolApp::addAnnouncement(const QVariantMap &v){if(!can("communication.announcements"))return false;return execute("INSERT INTO announcements(created_by,title,body,event_date) VALUES(?,?,?,?)",{m_userId,v["title"],v["body"],v["eventDate"]});}
bool SchoolApp::deleteAnnouncement(int id){if(!can("communication.announcements"))return false;return execute("DELETE FROM announcements WHERE id=?",{id});}

QVariantList SchoolApp::tardiness() const
{
    if (!((can("attendance.record")))) return QVariantList();
    QVariantList out;QSqlQuery q("SELECT t.id,t.student_id,s.last_name||' '||s.first_name,t.occurred_at,t.note FROM tardiness_records t JOIN students s ON s.id=t.student_id ORDER BY t.occurred_at DESC");while(q.next()){QVariantMap m;m["id"]=q.value(0);m["studentId"]=q.value(1);m["student"]=q.value(2);m["date"]=q.value(3);m["note"]=q.value(4);out<<m;}return out;
}
bool SchoolApp::addTardiness(const QVariantMap &v){if(!can("tardiness.record"))return false;return execute("INSERT INTO tardiness_records(student_id,recorded_by,occurred_at,note) VALUES(?,?,?,?)",{v["studentId"],m_userId,v["date"],v["note"]});}

QVariantList SchoolApp::examPeriods() const
{
    QVariantList out;QSqlQuery q("SELECT id,label,start_date,end_date,is_active FROM exam_periods ORDER BY start_date DESC");while(q.next()){QVariantMap m;m["id"]=q.value(0);m["label"]=q.value(1);m["startDate"]=q.value(2);m["endDate"]=q.value(3);m["active"]=q.value(4).toBool();out<<m;}return out;
}
bool SchoolApp::addExamPeriod(const QVariantMap &v){if(!can("periods.manage"))return false;return execute("INSERT INTO exam_periods(label,start_date,end_date,is_active,activated_by) VALUES(?,?,?,?,?)",{v["label"],v["startDate"],v["endDate"],v["active"].toBool(),m_userId});}
bool SchoolApp::toggleExamPeriod(int id){if(!can("periods.manage"))return false;execute("UPDATE exam_periods SET is_active=0");return execute("UPDATE exam_periods SET is_active=1,activated_by=? WHERE id=?",{m_userId,id});}

QVariantList SchoolApp::dashboard() const
{
    if (!((can("students.view") || can("balances.view")))) return QVariantList();
    QVariantList out;
    QSqlQuery q(m_db.db());
    q.exec("SELECT COUNT(*) FROM students WHERE deleted_at IS NULL AND graduated_at IS NULL");q.next();QVariantMap a;a["label"]="Élèves";a["value"]=q.value(0);out<<a;
    q.exec("SELECT COUNT(*) FROM users WHERE role='enseignant' AND deleted_at IS NULL");q.next();QVariantMap b;b["label"]="Enseignants";b["value"]=q.value(0);out<<b;
    q.exec("SELECT COUNT(*) FROM courses");q.next();QVariantMap c;c["label"]="Cours";c["value"]=q.value(0);out<<c;
    q.exec("SELECT COALESCE(SUM(amount),0) FROM payments WHERE strftime('%Y-%m',paid_at)=strftime('%Y-%m','now')");q.next();QVariantMap d;d["label"]="Paiements ce mois";d["value"]=q.value(0);out<<d;
    return out;
}

QVariantList SchoolApp::guardians(int studentId) const
{
    QVariantList out;
    if (!can("guardians.read")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT sg.id,g.id,g.full_name,g.phone,g.email,g.relation,sg.is_primary "
              "FROM student_guardians sg JOIN guardians g ON g.id=sg.guardian_id "
              "WHERE sg.student_id=? ORDER BY sg.is_primary DESC, g.full_name");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["linkId"] = q.value(0).toInt();
        m["guardianId"] = q.value(1).toInt();
        m["fullName"] = q.value(2).toString();
        m["phone"] = q.value(3).toString();
        m["email"] = q.value(4).toString();
        m["relation"] = q.value(5).toString();
        m["isPrimary"] = q.value(6).toInt() == 1;
        out << m;
    }
    return out;
}

bool SchoolApp::addGuardian(int studentId, const QVariantMap &v)
{
    if (!can("guardians.add")) return false;
    const QString fullName = v.value("fullName").toString().trimmed();
    const QString phone = v.value("phone").toString().trimmed();
    const QString relation = v.value("relation").toString().trimmed();
    if (fullName.isEmpty() || phone.isEmpty() || relation.isEmpty()) {
        emit errorOccurred(QStringLiteral("Nom, téléphone et lien de parenté sont obligatoires."));
        return false;
    }
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return false;
    QSqlQuery g(db);
    g.prepare("INSERT INTO guardians(full_name,phone,email,relation) VALUES(?,?,?,?)");
    g.addBindValue(fullName); g.addBindValue(phone);
    g.addBindValue(v.value("email").toString().trimmed()); g.addBindValue(relation);
    if (!g.exec()) { db.rollback(); emit errorOccurred(g.lastError().text()); return false; }
    const int guardianId = g.lastInsertId().toInt();
    QSqlQuery l(db);
    l.prepare("INSERT INTO student_guardians(student_id,guardian_id,is_primary) VALUES(?,?,?)");
    l.addBindValue(studentId); l.addBindValue(guardianId); l.addBindValue(v.value("isPrimary").toBool() ? 1 : 0);
    if (!l.exec()) { db.rollback(); emit errorOccurred(l.lastError().text()); return false; }
    db.commit();
    audit("create", "guardian", guardianId, QStringLiteral("élève %1").arg(studentId));
    emit dataChanged();
    return true;
}

bool SchoolApp::removeGuardian(int linkId)
{
    if (!can("guardians.remove")) return false;
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return false;
    QSqlQuery d(db);
    d.prepare("DELETE FROM student_guardians WHERE id=?");
    d.addBindValue(linkId);
    if (!d.exec()) { db.rollback(); return false; }
    QSqlQuery c(db);
    c.exec("DELETE FROM guardians WHERE id NOT IN (SELECT guardian_id FROM student_guardians)");
    db.commit();
    audit("delete", "guardian_link", linkId);
    emit dataChanged();
    return true;
}

bool SchoolApp::canViewStudent(int studentId) const
{
    if (m_userId <= 0) return false;
    if (can("students.view")) return true;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT EXISTS(SELECT 1 FROM parent_student_links WHERE parent_user_id=? AND student_id=?) "
              "OR EXISTS(SELECT 1 FROM students WHERE id=? AND user_id=?)");
    q.addBindValue(m_userId); q.addBindValue(studentId);
    q.addBindValue(studentId); q.addBindValue(m_userId);
    return q.exec() && q.next() && q.value(0).toInt() == 1;
}

QVariantList SchoolApp::parentLinks(int studentId) const
{
    QVariantList out;
    if (!can("parents.link")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT l.id,u.id,u.name,u.email FROM parent_student_links l "
              "JOIN users u ON u.id=l.parent_user_id WHERE l.student_id=? AND u.deleted_at IS NULL ORDER BY u.name");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["linkId"] = q.value(0).toInt();
        m["parentId"] = q.value(1).toInt();
        m["name"] = q.value(2).toString();
        m["email"] = q.value(3).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::linkParentByEmail(int studentId, const QString &email)
{
    if (!can("parents.link")) return false;
    QSqlQuery u(m_db.db());
    u.prepare("SELECT id FROM users WHERE lower(email)=lower(?) AND role='parent' AND deleted_at IS NULL");
    u.addBindValue(email.trimmed());
    if (!u.exec() || !u.next()) {
        emit errorOccurred(QStringLiteral("Aucun compte parent avec cette adresse e-mail. Créez-le d'abord dans Comptes / sécurité."));
        return false;
    }
    QSqlQuery l(m_db.db());
    l.prepare("INSERT OR IGNORE INTO parent_student_links(parent_user_id,student_id) VALUES(?,?)");
    l.addBindValue(u.value(0)); l.addBindValue(studentId);
    if (!l.exec()) { emit errorOccurred(l.lastError().text()); return false; }
    audit("link", "parent", u.value(0).toInt(), QStringLiteral("élève %1").arg(studentId));
    emit dataChanged();
    return true;
}

bool SchoolApp::unlinkParent(int linkId)
{
    if (!can("parents.link")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM parent_student_links WHERE id=?");
    q.addBindValue(linkId);
    if (!q.exec()) return false;
    audit("unlink", "parent", linkId);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::myStudents() const
{
    QVariantList out;
    if (m_userId <= 0) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT s.id,s.matricule,s.last_name,s.first_name,s.current_class FROM students s "
              "WHERE s.deleted_at IS NULL AND (s.id IN (SELECT student_id FROM parent_student_links WHERE parent_user_id=?) "
              "OR s.user_id=?) ORDER BY s.last_name,s.first_name");
    q.addBindValue(m_userId); q.addBindValue(m_userId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["matricule"] = q.value(1).toString();
        m["lastName"] = q.value(2).toString();
        m["firstName"] = q.value(3).toString();
        m["className"] = q.value(4).toString();
        out << m;
    }
    return out;
}

QVariantMap SchoolApp::familyStudent(int studentId) const
{
    if (!canViewStudent(studentId)) return {};
    return student(studentId);
}

QVariantList SchoolApp::familyInvoices(int studentId) const
{
    if (!canViewStudent(studentId)) return {};
    return studentInvoices(studentId);
}

QVariantList SchoolApp::familyPayments(int studentId) const
{
    if (!canViewStudent(studentId)) return {};
    return payments(studentId);
}

QVariantMap SchoolApp::familyBulletin(int studentId, const QString &term) const
{
    if (!canViewStudent(studentId)) return {};
    return bulletin(studentId, term);
}

QVariantMap SchoolApp::monthlyStats() const
{
    if (!((can("students.view") || can("balances.view")))) return QVariantMap();
    QVariantMap m;
    QSqlQuery p(m_db.db());
    if (p.exec("SELECT COALESCE(SUM(amount),0), COUNT(*) FROM payments "
               "WHERE strftime('%Y-%m', paid_at)=strftime('%Y-%m','now','localtime')") && p.next()) {
        m["paidAmount"] = p.value(0).toDouble();
        m["paidCount"] = p.value(1).toInt();
    }
    QSqlQuery late(m_db.db());
    if (late.exec("SELECT COUNT(*), COALESCE(SUM(amount),0) FROM invoices WHERE status='late'") && late.next()) {
        m["lateCount"] = late.value(0).toInt();
        m["lateAmount"] = late.value(1).toDouble();
    }
    QSqlQuery due(m_db.db());
    if (due.exec("SELECT COALESCE(SUM(amount),0) FROM invoices WHERE status IN ('pending','late')") && due.next())
        m["dueAmount"] = due.value(0).toDouble();
    QSqlQuery tard(m_db.db());
    if (tard.exec("SELECT COUNT(*) FROM tardiness_records "
                  "WHERE strftime('%Y-%m', occurred_at)=strftime('%Y-%m','now','localtime')") && tard.next())
        m["tardinessCount"] = tard.value(0).toInt();
    return m;
}

QString SchoolApp::setting(const QString &key) const
{
    if (key.startsWith("smtp_") && !can("email.config")) return QString();
    QSqlQuery q(m_db.db());
    q.prepare("SELECT value FROM settings WHERE key=?");
    q.addBindValue(key);
    return q.exec() && q.next() ? q.value(0).toString() : QString();
}

bool SchoolApp::setSetting(const QString &key, const QString &value)
{
    if (!can("settings.manage")) return false;
    const QString k = key.trimmed();
    if (k.isEmpty()) return false;
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value");
    q.addBindValue(k);
    q.addBindValue(value.trimmed());
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("update", "setting", 0, k);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::academicPeriods() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name,start_date,end_date,is_active FROM academic_periods ORDER BY start_date DESC")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["startDate"] = q.value(2).toString();
        m["endDate"] = q.value(3).toString();
        m["isActive"] = q.value(4).toInt() == 1;
        out << m;
    }
    return out;
}

bool SchoolApp::addAcademicPeriod(const QVariantMap &v)
{
    if (!can("periods.manage")) return false;
    const QString name = v.value("name").toString().trimmed();
    const QDate start = QDate::fromString(v.value("startDate").toString().trimmed(), "yyyy-MM-dd");
    const QDate end = QDate::fromString(v.value("endDate").toString().trimmed(), "yyyy-MM-dd");
    if (name.isEmpty() || !start.isValid() || !end.isValid() || end < start) {
        emit errorOccurred(QStringLiteral("Nom, date de début et date de fin valides requis (AAAA-MM-JJ)."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO academic_periods(name,start_date,end_date,is_active) VALUES(?,?,?,0)");
    q.addBindValue(name);
    q.addBindValue(start.toString("yyyy-MM-dd"));
    q.addBindValue(end.toString("yyyy-MM-dd"));
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "academic_period", q.lastInsertId().toInt(), name);
    emit dataChanged();
    return true;
}

bool SchoolApp::setActiveAcademicPeriod(int id)
{
    if (!can("periods.manage")) return false;
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return false;
    QSqlQuery off(db);
    off.exec("UPDATE academic_periods SET is_active=0");
    QSqlQuery on(db);
    on.prepare("UPDATE academic_periods SET is_active=1 WHERE id=?");
    on.addBindValue(id);
    if (!on.exec() || on.numRowsAffected() != 1) { db.rollback(); return false; }
    db.commit();
    audit("update", "academic_period", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::auditLogs(int limit) const
{
    QVariantList out;
    if (!can("audit.view")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT a.created_at,COALESCE(u.name,'Système'),a.action,a.entity,a.entity_id,a.details "
              "FROM audit_logs a LEFT JOIN users u ON u.id=a.user_id ORDER BY a.id DESC LIMIT ?");
    q.addBindValue(limit > 0 ? limit : 200);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["createdAt"] = q.value(0).toString();
        m["user"] = q.value(1).toString();
        m["action"] = q.value(2).toString();
        m["entity"] = q.value(3).toString();
        m["entityId"] = q.value(4).toInt();
        m["details"] = q.value(5).toString();
        out << m;
    }
    return out;
}

QVariantList SchoolApp::classTuitions() const
{
    QVariantList out;
    for (const QString &c : classes()) {
        QSqlQuery q(m_db.db());
        q.prepare("SELECT monthly_amount FROM class_tuitions WHERE class_name=?");
        q.addBindValue(c);
        QVariantMap m;
        m["className"] = c;
        m["monthlyAmount"] = q.exec() && q.next() ? q.value(0).toDouble() : 0.0;
        out << m;
    }
    return out;
}

bool SchoolApp::setClassTuition(const QString &className, double monthlyAmount)
{
    if (!can("fees.tuition")) return false;
    if (!classes().contains(className) || monthlyAmount < 0) {
        emit errorOccurred(QStringLiteral("Classe inconnue ou montant négatif."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO class_tuitions(class_name,monthly_amount) VALUES(?,?) "
              "ON CONFLICT(class_name) DO UPDATE SET monthly_amount=excluded.monthly_amount");
    q.addBindValue(className);
    q.addBindValue(monthlyAmount);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("update", "class_tuition", 0, className);
    emit dataChanged();
    return true;
}

QVariantMap SchoolApp::balanceOverview(const QString &fromDate, const QString &toDate) const
{
    QVariantMap out;
    if (!can("balances.view")) return out;
    const QString from = fromDate.trimmed().isEmpty() ? QStringLiteral("0000-01-01") : fromDate.trimmed();
    const QString to = toDate.trimmed().isEmpty() ? QStringLiteral("9999-12-31") : toDate.trimmed();

    QSqlQuery b(m_db.db());
    b.prepare("SELECT COALESCE(SUM(amount),0), COALESCE(SUM(CASE WHEN status='late' THEN 1 ELSE 0 END),0) "
              "FROM invoices WHERE due_date BETWEEN ? AND ?");
    b.addBindValue(from); b.addBindValue(to);
    double billed = 0;
    if (b.exec() && b.next()) {
        billed = b.value(0).toDouble();
        out["lateCount"] = b.value(1).toInt();
    }

    QSqlQuery p(m_db.db());
    p.prepare("SELECT COALESCE(SUM(amount),0) FROM payments WHERE substr(paid_at,1,10) BETWEEN ? AND ?");
    p.addBindValue(from); p.addBindValue(to);
    QSqlQuery o(m_db.db());
    o.prepare("SELECT COALESCE(SUM(amount),0) FROM one_time_fees WHERE due_date BETWEEN ? AND ?");
    o.addBindValue(from); o.addBindValue(to);
    if (o.exec() && o.next()) billed += o.value(0).toDouble();
    double collected = 0;
    if (p.exec() && p.next()) collected = p.value(0).toDouble();

    out["billed"] = billed;
    out["collected"] = collected;
    out["balance"] = billed - collected;

    QVariantList rows;
    QSqlQuery s(m_db.db());
    s.prepare("SELECT s.id, s.last_name || ' ' || s.first_name, s.current_class, "
              "COALESCE((SELECT SUM(i.amount) FROM invoices i WHERE i.student_id=s.id AND i.due_date BETWEEN ? AND ?),0), "
              "COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.student_id=s.id AND substr(p.paid_at,1,10) BETWEEN ? AND ?),0) "
              "FROM students s WHERE s.deleted_at IS NULL AND s.graduated_at IS NULL ORDER BY s.current_class, s.last_name");
    for (int i = 0; i < 2; ++i) { s.addBindValue(from); s.addBindValue(to); }
    if (s.exec()) {
        while (s.next()) {
            QVariantMap m;
            const double sBilled = s.value(3).toDouble() + oneTimeBilled(s.value(0).toInt(), from, to);
            const double sCollected = s.value(4).toDouble();
            m["studentId"] = s.value(0).toInt();
            m["name"] = s.value(1).toString();
            m["className"] = s.value(2).toString();
            m["billed"] = sBilled;
            m["collected"] = sCollected;
            m["balance"] = sBilled - sCollected;
            rows << m;
        }
    }
    out["students"] = rows;
    return out;
}

bool SchoolApp::can(const QString &permission) const
{
    if (m_userId <= 0) return false;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT allowed FROM role_permissions WHERE role=? AND permission=?");
    q.addBindValue(m_role);
    q.addBindValue(permission);
    return q.exec() && q.next() && q.value(0).toInt() == 1;
}

QVariantList SchoolApp::permissionMatrix() const
{
    QVariantList out;
    if (!can("roles.manage")) return out;
    QSqlQuery cat(m_db.db());
    if (!cat.exec("SELECT key,label,grp FROM permissions_catalog ORDER BY grp,label")) return out;
    while (cat.next()) {
        QVariantMap row;
        row["key"] = cat.value(0).toString();
        row["label"] = cat.value(1).toString();
        row["group"] = cat.value(2).toString();
        QVariantMap roles;
        QSqlQuery r(m_db.db());
        r.prepare("SELECT role,allowed FROM role_permissions WHERE permission=?");
        r.addBindValue(row["key"].toString());
        if (r.exec()) {
            while (r.next()) roles[r.value(0).toString()] = r.value(1).toInt() == 1;
        }
        row["roles"] = roles;
        out << row;
    }
    return out;
}

bool SchoolApp::setPermission(const QString &role, const QString &permission, bool allowedValue)
{
    if (!can("roles.manage")) return false;
    if (!roles().contains(role)) {
        emit errorOccurred(QStringLiteral("Rôle inconnu."));
        return false;
    }
    if (role == QLatin1String("administrateur") && permission == QLatin1String("roles.manage") && !allowedValue) {
        emit errorOccurred(QStringLiteral("L'administrateur doit toujours pouvoir gérer les rôles et les permissions."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE role_permissions SET allowed=? WHERE role=? AND permission=?");
    q.addBindValue(allowedValue ? 1 : 0);
    q.addBindValue(role);
    q.addBindValue(permission);
    if (!q.exec() || q.numRowsAffected() != 1) {
        emit errorOccurred(QStringLiteral("Droit inconnu."));
        return false;
    }
    audit("update", "permission", 0, role + " " + permission + (allowedValue ? " = oui" : " = non"));
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::feeTypes() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name,default_amount FROM fee_types WHERE is_active=1 ORDER BY name")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["amount"] = q.value(2).toDouble();
        out << m;
    }
    return out;
}

bool SchoolApp::addFeeType(const QVariantMap &v)
{
    if (!can("fees.onetime.manage")) return false;
    const QString name = v.value("name").toString().trimmed();
    const double amount = v.value("amount").toDouble();
    if (name.isEmpty() || amount < 0) {
        emit errorOccurred(QStringLiteral("Nom et montant valides requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO fee_types(name,default_amount) VALUES(?,?)");
    q.addBindValue(name);
    q.addBindValue(amount);
    if (!q.exec()) {
        emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce type de frais existe déjà.") : q.lastError().text());
        return false;
    }
    audit("create", "fee_type", q.lastInsertId().toInt(), name);
    emit dataChanged();
    return true;
}

bool SchoolApp::assignOneTimeFeeToClass(int feeTypeId, const QString &className, double amount, const QString &dueDate)
{
    if (!can("fees.onetime.manage")) return false;
    const QDate due = QDate::fromString(dueDate.trimmed(), "yyyy-MM-dd");
    if (!due.isValid() || amount < 0 || !classes().contains(className)) {
        emit errorOccurred(QStringLiteral("Classe, montant et échéance (AAAA-MM-JJ) valides requis."));
        return false;
    }
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return false;
    QSqlQuery q(db);
    q.prepare("INSERT INTO one_time_fees(student_id,fee_type_id,amount,due_date,status) "
              "SELECT id,?,?,?,'pending' FROM students WHERE current_class=? AND deleted_at IS NULL AND graduated_at IS NULL");
    q.addBindValue(feeTypeId);
    q.addBindValue(amount);
    q.addBindValue(due.toString("yyyy-MM-dd"));
    q.addBindValue(className);
    if (!q.exec()) { db.rollback(); emit errorOccurred(q.lastError().text()); return false; }
    const int count = q.numRowsAffected();
    if (count == 0) {
        db.rollback();
        emit errorOccurred(QStringLiteral("Aucun élève inscrit dans cette classe."));
        return false;
    }
    db.commit();
    audit("create", "one_time_fee", feeTypeId, className + " (" + QString::number(count) + " élèves)");
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::studentOneTimeFees(int studentId) const
{
    QVariantList out;
    if (!canViewStudent(studentId)) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT o.id,t.name,o.amount,o.due_date,o.status,o.payment_id FROM one_time_fees o "
              "JOIN fee_types t ON t.id=o.fee_type_id WHERE o.student_id=? ORDER BY o.due_date DESC");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["amount"] = q.value(2).toDouble();
        m["dueDate"] = q.value(3).toString();
        m["status"] = q.value(4).toString();
        m["paymentId"] = q.value(5).toInt();
        out << m;
    }
    return out;
}

int SchoolApp::payOneTimeFee(int feeId, const QString &method, const QString &reference)
{
    if (!can("fees.onetime.pay")) return 0;
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return 0;

    QSqlQuery f(db);
    f.prepare("SELECT o.student_id,o.amount,t.name FROM one_time_fees o JOIN fee_types t ON t.id=o.fee_type_id "
              "WHERE o.id=? AND o.status='pending'");
    f.addBindValue(feeId);
    if (!f.exec() || !f.next()) {
        db.rollback();
        emit errorOccurred(QStringLiteral("Frais introuvable ou déjà payé."));
        return 0;
    }
    const int studentId = f.value(0).toInt();
    const double amount = f.value(1).toDouble();
    const QString name = f.value(2).toString();
    const QString paidAt = QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss");

    QSqlQuery p(db);
    p.prepare("INSERT INTO payments(student_id,recorded_by,amount,method,payer_role,reference,paid_at,notes) "
              "VALUES(?,?,?,?,'eleve',?,?,?)");
    p.addBindValue(studentId);
    p.addBindValue(m_userId);
    p.addBindValue(amount);
    p.addBindValue(method);
    p.addBindValue(reference.trimmed());
    p.addBindValue(paidAt);
    p.addBindValue(QStringLiteral("Frais ponctuel : ") + name);
    if (!p.exec()) { db.rollback(); emit errorOccurred(p.lastError().text()); return 0; }
    const int paymentId = p.lastInsertId().toInt();

    const QString year = paidAt.left(4);
    QSqlQuery seq(db);
    seq.prepare("SELECT COALESCE(MAX(CAST(substr(receipt_number,-5) AS INTEGER)),0)+1 FROM payments WHERE receipt_number LIKE ?");
    seq.addBindValue(QStringLiteral("REC-%1-%").arg(year));
    const int next = seq.exec() && seq.next() ? seq.value(0).toInt() : 1;
    QSqlQuery rn(db);
    rn.prepare("UPDATE payments SET receipt_number=? WHERE id=?");
    rn.addBindValue(QStringLiteral("REC-%1-%2").arg(year).arg(next, 5, 10, QLatin1Char('0')));
    rn.addBindValue(paymentId);
    rn.exec();

    QSqlQuery u(db);
    u.prepare("UPDATE one_time_fees SET status='paid', payment_id=? WHERE id=?");
    u.addBindValue(paymentId);
    u.addBindValue(feeId);
    if (!u.exec()) { db.rollback(); emit errorOccurred(u.lastError().text()); return 0; }

    db.commit();
    audit("create", "payment", paymentId, QStringLiteral("frais ponctuel %1").arg(feeId));
    emit dataChanged();
    return paymentId;
}

double SchoolApp::oneTimeBilled(int studentId, const QString &from, const QString &to) const
{
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COALESCE(SUM(amount),0) FROM one_time_fees WHERE student_id=? AND due_date BETWEEN ? AND ?");
    q.addBindValue(studentId);
    q.addBindValue(from);
    q.addBindValue(to);
    return q.exec() && q.next() ? q.value(0).toDouble() : 0.0;
}

QVariantList SchoolApp::subjects() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name,coefficient FROM subjects ORDER BY name")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["coefficient"] = q.value(2).toDouble();
        out << m;
    }
    return out;
}

bool SchoolApp::addSubject(const QVariantMap &v)
{
    if (!can("subjects.manage")) return false;
    const QString name = v.value("name").toString().trimmed();
    const double coef = v.value("coefficient").toDouble();
    if (name.isEmpty() || coef <= 0) {
        emit errorOccurred(QStringLiteral("Nom et coefficient (> 0) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO subjects(name,coefficient) VALUES(?,?)");
    q.addBindValue(name);
    q.addBindValue(coef);
    if (!q.exec()) {
        emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette matière existe déjà.") : q.lastError().text());
        return false;
    }
    audit("create", "subject", q.lastInsertId().toInt(), name);
    emit dataChanged();
    return true;
}

bool SchoolApp::updateSubject(int id, const QVariantMap &v)
{
    if (!can("subjects.manage")) return false;
    const QString name = v.value("name").toString().trimmed();
    const double coef = v.value("coefficient").toDouble();
    if (name.isEmpty() || coef <= 0) {
        emit errorOccurred(QStringLiteral("Nom et coefficient (> 0) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE subjects SET name=?, coefficient=? WHERE id=?");
    q.addBindValue(name);
    q.addBindValue(coef);
    q.addBindValue(id);
    if (!q.exec()) {
        emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette matière existe déjà.") : q.lastError().text());
        return false;
    }
    audit("update", "subject", id, name + " coef " + QString::number(coef));
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteSubject(int id)
{
    if (!can("subjects.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM subjects WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "subject", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::classAssignments(const QString &className) const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT a.id,a.class_name,s.id,s.name,COALESCE(u.id,0),COALESCE(u.name,'non affecté') "
              "FROM class_assignments a JOIN subjects s ON s.id=a.subject_id LEFT JOIN users u ON u.id=a.teacher_id "
              "WHERE a.class_name=? ORDER BY s.name");
    q.addBindValue(className);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["className"] = q.value(1).toString();
        m["subjectId"] = q.value(2).toInt();
        m["subject"] = q.value(3).toString();
        m["teacherId"] = q.value(4).toInt();
        m["teacher"] = q.value(5).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::setClassAssignment(const QString &className, int subjectId, int teacherId)
{
    if (!can("assignments.manage")) return false;
    if (!classes().contains(className) || subjectId <= 0) {
        emit errorOccurred(QStringLiteral("Classe et matière requises."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO class_assignments(class_name,subject_id,teacher_id) VALUES(?,?,?) "
              "ON CONFLICT(class_name,subject_id) DO UPDATE SET teacher_id=excluded.teacher_id");
    q.addBindValue(className);
    q.addBindValue(subjectId);
    q.addBindValue(teacherId > 0 ? QVariant(teacherId) : QVariant());
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("update", "assignment", subjectId, className);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteClassAssignment(int id)
{
    if (!can("assignments.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM class_assignments WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "assignment", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::timetableSlots(const QString &className) const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT t.id,t.weekday,t.start_time,t.end_time,COALESCE(s.name,''),COALESCE(t.room,'') "
              "FROM timetable_slots t LEFT JOIN subjects s ON s.id=t.subject_id WHERE t.class_name=? ORDER BY t.weekday,t.start_time");
    q.addBindValue(className);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["weekday"] = q.value(1).toInt();
        m["startTime"] = q.value(2).toString();
        m["endTime"] = q.value(3).toString();
        m["subject"] = q.value(4).toString();
        m["room"] = q.value(5).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addTimetableSlot(const QVariantMap &v)
{
    if (!can("timetable.manage")) return false;
    const QString className = v.value("className").toString();
    const int weekday = v.value("weekday").toInt();
    const QTime start = QTime::fromString(v.value("start").toString(), "HH:mm");
    const QTime end = QTime::fromString(v.value("end").toString(), "HH:mm");
    if (!classes().contains(className) || weekday < 1 || weekday > 6 || !start.isValid() || !end.isValid() || end <= start) {
        emit errorOccurred(QStringLiteral("Classe, jour (lundi à samedi) et horaires valides requis (HH:mm, fin après début)."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO timetable_slots(class_name,weekday,start_time,end_time,subject_id,room) VALUES(?,?,?,?,?,?)");
    q.addBindValue(className);
    q.addBindValue(weekday);
    q.addBindValue(start.toString("HH:mm"));
    q.addBindValue(end.toString("HH:mm"));
    const int subjectId = v.value("subjectId").toInt();
    q.addBindValue(subjectId > 0 ? QVariant(subjectId) : QVariant());
    q.addBindValue(v.value("room").toString().trimmed());
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "timetable_slot", q.lastInsertId().toInt(), className);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteTimetableSlot(int id)
{
    if (!can("timetable.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM timetable_slots WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "timetable_slot", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::attendanceFor(const QString &className, const QString &day) const
{
    QVariantList out;
    if (!can("attendance.record")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT s.id,s.last_name || ' ' || s.first_name,COALESCE(a.status,'present') FROM students s "
              "LEFT JOIN attendance a ON a.student_id=s.id AND a.day=? "
              "WHERE s.current_class=? AND s.deleted_at IS NULL AND s.graduated_at IS NULL ORDER BY s.last_name,s.first_name");
    q.addBindValue(day);
    q.addBindValue(className);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["studentId"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["status"] = q.value(2).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::setAttendance(int studentId, const QString &day, const QString &status)
{
    if (!can("attendance.record")) return false;
    if (!QDate::fromString(day, "yyyy-MM-dd").isValid()) return false;
    if (!QStringList({"present", "absent", "late", "excused"}).contains(status)) return false;
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO attendance(student_id,day,status) VALUES(?,?,?) "
              "ON CONFLICT(student_id,day) DO UPDATE SET status=excluded.status");
    q.addBindValue(studentId);
    q.addBindValue(day);
    q.addBindValue(status);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::incidents(int studentId) const
{
    QVariantList out;
    if (!canViewStudent(studentId)) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT id,incident_date,category,COALESCE(description,''),COALESCE(sanction,'') FROM incidents "
              "WHERE student_id=? ORDER BY incident_date DESC, id DESC");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["date"] = q.value(1).toString();
        m["category"] = q.value(2).toString();
        m["description"] = q.value(3).toString();
        m["sanction"] = q.value(4).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addIncident(const QVariantMap &v)
{
    if (!can("discipline.record")) return false;
    const int studentId = v.value("studentId").toInt();
    const QDate date = QDate::fromString(v.value("date").toString(), "yyyy-MM-dd");
    const QString category = v.value("category").toString().trimmed();
    if (studentId <= 0 || !date.isValid() || category.isEmpty()) {
        emit errorOccurred(QStringLiteral("Élève, date (AAAA-MM-JJ) et catégorie requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO incidents(student_id,incident_date,category,description,sanction,recorded_by) VALUES(?,?,?,?,?,?)");
    q.addBindValue(studentId);
    q.addBindValue(date.toString("yyyy-MM-dd"));
    q.addBindValue(category);
    q.addBindValue(v.value("description").toString().trimmed());
    q.addBindValue(v.value("sanction").toString().trimmed());
    q.addBindValue(m_userId);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "incident", q.lastInsertId().toInt(), category);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::deliberation(const QString &className, const QString &term) const
{
    QVariantList out;
    if (!can("deliberations.view")) return out;
    QSqlQuery st(m_db.db());
    st.prepare("SELECT id,last_name || ' ' || first_name FROM students WHERE current_class=? AND deleted_at IS NULL "
               "AND graduated_at IS NULL ORDER BY last_name,first_name");
    st.addBindValue(className);
    if (!st.exec()) return out;
    while (st.next()) {
        const int sid = st.value(0).toInt();
        QSqlQuery g(m_db.db());
        g.prepare("SELECT ROUND(AVG((gr.score*20.0)/e.max_score),2), COALESCE(sb.coefficient,1) FROM grades gr "
                  "JOIN exams e ON e.id=gr.exam_id JOIN courses c ON c.id=e.course_id "
                  "LEFT JOIN subjects sb ON sb.name=c.subject WHERE gr.student_id=? AND e.term=? "
                  "GROUP BY c.subject, COALESCE(sb.coefficient,1)");
        g.addBindValue(sid);
        g.addBindValue(term);
        double sum = 0, coefSum = 0;
        bool any = false;
        if (g.exec()) {
            while (g.next()) {
                any = true;
                sum += g.value(0).toDouble() * g.value(1).toDouble();
                coefSum += g.value(1).toDouble();
            }
        }
        QVariantMap m;
        m["studentId"] = sid;
        m["name"] = st.value(1).toString();
        if (any && coefSum > 0) {
            const double avg = sum / coefSum;
            m["average"] = QString::number(avg, 'f', 2);
            const double passMark = setting("pass_mark").isEmpty() ? 10.0 : setting("pass_mark").toDouble();
            const double retakeMark = setting("retake_mark").isEmpty() ? 8.0 : setting("retake_mark").toDouble();
            m["decision"] = avg >= passMark ? QStringLiteral("Admis") : avg >= retakeMark ? QStringLiteral("Rattrapage") : QStringLiteral("Ajourné");
        } else {
            m["average"] = QString();
            m["decision"] = QStringLiteral("—");
        }
        out << m;
    }
    return out;
}

QVariantList SchoolApp::cycles() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name FROM cycles ORDER BY sort_order,id")) return out;
    while (q.next()) { QVariantMap m; m["id"] = q.value(0).toInt(); m["name"] = q.value(1).toString(); out << m; }
    return out;
}

bool SchoolApp::addCycle(const QString &name)
{
    if (!can("structure.manage")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty()) { emit errorOccurred(QStringLiteral("Nom du cycle requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO cycles(name,sort_order) VALUES(?,(SELECT COALESCE(MAX(sort_order),0)+1 FROM cycles))");
    q.addBindValue(n);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce cycle existe déjà.") : q.lastError().text()); return false; }
    audit("create", "cycle", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteCycle(int id)
{
    if (!can("structure.manage")) return false;
    QSqlQuery c(m_db.db());
    c.prepare("SELECT COUNT(*) FROM levels WHERE cycle_id=?");
    c.addBindValue(id);
    if (c.exec() && c.next() && c.value(0).toInt() > 0) {
        emit errorOccurred(QStringLiteral("Ce cycle contient des niveaux : supprime-les d'abord."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM cycles WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "cycle", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::levels() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT l.id,l.name,l.cycle_id,c.name FROM levels l JOIN cycles c ON c.id=l.cycle_id "
                "ORDER BY c.sort_order,l.sort_order,l.id")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["cycleId"] = q.value(2).toInt();
        m["cycleName"] = q.value(3).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addLevel(const QString &name, int cycleId)
{
    if (!can("structure.manage")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty() || cycleId <= 0) { emit errorOccurred(QStringLiteral("Nom du niveau et cycle requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO levels(name,cycle_id,sort_order) VALUES(?,?,(SELECT COALESCE(MAX(sort_order),0)+1 FROM levels))");
    q.addBindValue(n);
    q.addBindValue(cycleId);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce niveau existe déjà.") : q.lastError().text()); return false; }
    audit("create", "level", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteLevel(int id)
{
    if (!can("structure.manage")) return false;
    QSqlQuery c(m_db.db());
    c.prepare("SELECT COUNT(*) FROM school_classes WHERE level_id=?");
    c.addBindValue(id);
    if (c.exec() && c.next() && c.value(0).toInt() > 0) {
        emit errorOccurred(QStringLiteral("Ce niveau contient des classes : supprime-les ou désactive-les d'abord."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM levels WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "level", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::schoolClasses() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT k.id,k.name,k.level_id,l.name,c.name,k.is_active FROM school_classes k "
                "JOIN levels l ON l.id=k.level_id JOIN cycles c ON c.id=l.cycle_id ORDER BY k.sort_order,k.id")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["levelId"] = q.value(2).toInt();
        m["levelName"] = q.value(3).toString();
        m["cycleName"] = q.value(4).toString();
        m["isActive"] = q.value(5).toInt() == 1;
        out << m;
    }
    return out;
}

bool SchoolApp::addSchoolClass(const QString &name, int levelId)
{
    if (!can("structure.manage")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty() || levelId <= 0) { emit errorOccurred(QStringLiteral("Nom de la classe et niveau requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO school_classes(name,level_id,sort_order) VALUES(?,?,(SELECT COALESCE(MAX(sort_order),0)+1 FROM school_classes))");
    q.addBindValue(n);
    q.addBindValue(levelId);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette classe existe déjà.") : q.lastError().text()); return false; }
    audit("create", "school_class", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

bool SchoolApp::setSchoolClassActive(int id, bool active)
{
    if (!can("structure.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE school_classes SET is_active=? WHERE id=?");
    q.addBindValue(active ? 1 : 0);
    q.addBindValue(id);
    if (!q.exec() || q.numRowsAffected() != 1) return false;
    audit("update", "school_class", id, active ? "réactivée" : "désactivée");
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::rooms() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name,capacity FROM rooms ORDER BY name")) return out;
    while (q.next()) { QVariantMap m; m["id"] = q.value(0).toInt(); m["name"] = q.value(1).toString(); m["capacity"] = q.value(2).toInt(); out << m; }
    return out;
}

bool SchoolApp::addRoom(const QString &name, int capacity)
{
    if (!can("structure.manage")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty() || capacity < 0) { emit errorOccurred(QStringLiteral("Nom de la salle requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO rooms(name,capacity) VALUES(?,?)");
    q.addBindValue(n);
    q.addBindValue(capacity);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette salle existe déjà.") : q.lastError().text()); return false; }
    audit("create", "room", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteRoom(int id)
{
    if (!can("structure.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM rooms WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "room", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::calendarEvents() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,title,start_date,end_date,kind FROM calendar_events ORDER BY start_date,id")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["title"] = q.value(1).toString();
        m["startDate"] = q.value(2).toString();
        m["endDate"] = q.value(3).toString();
        m["kind"] = q.value(4).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addCalendarEvent(const QVariantMap &v)
{
    if (!can("calendar.manage")) return false;
    const QString title = v.value("title").toString().trimmed();
    const QDate start = QDate::fromString(v.value("startDate").toString(), "yyyy-MM-dd");
    const QDate end = QDate::fromString(v.value("endDate").toString(), "yyyy-MM-dd");
    const QString kind = v.value("kind").toString();
    if (title.isEmpty() || !start.isValid() || !end.isValid() || end < start
        || !QStringList({"evenement", "ferie", "vacances"}).contains(kind)) {
        emit errorOccurred(QStringLiteral("Titre, dates valides (AAAA-MM-JJ, fin après début) et type requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO calendar_events(title,start_date,end_date,kind) VALUES(?,?,?,?)");
    q.addBindValue(title);
    q.addBindValue(start.toString("yyyy-MM-dd"));
    q.addBindValue(end.toString("yyyy-MM-dd"));
    q.addBindValue(kind);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "calendar_event", q.lastInsertId().toInt(), title);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteCalendarEvent(int id)
{
    if (!can("calendar.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM calendar_events WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "calendar_event", id);
    emit dataChanged();
    return true;
}

void SchoolApp::logDocument(const QString &type, int refId, const QString &label)
{
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO document_history(doc_type,ref_id,label,user_id) VALUES(?,?,?,?)");
    q.addBindValue(type);
    q.addBindValue(refId);
    q.addBindValue(label);
    q.addBindValue(m_userId > 0 ? QVariant(m_userId) : QVariant());
    q.exec();
}

QVariantList SchoolApp::documentHistory(int limit) const
{
    QVariantList out;
    if (!can("documents.history")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT h.created_at,COALESCE(u.name,'Système'),h.doc_type,h.ref_id,COALESCE(h.label,'') "
              "FROM document_history h LEFT JOIN users u ON u.id=h.user_id ORDER BY h.id DESC LIMIT ?");
    q.addBindValue(limit > 0 ? limit : 200);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["createdAt"] = q.value(0).toString();
        m["user"] = q.value(1).toString();
        m["docType"] = q.value(2).toString();
        m["refId"] = q.value(3).toInt();
        m["label"] = q.value(4).toString();
        out << m;
    }
    return out;
}

QVariantList SchoolApp::overdueByStudent(const QString &asOf) const
{
    QVariantList out;
    if (!can("finance.reports")) return out;
    const QString d = asOf.trimmed().isEmpty() ? QDate::currentDate().toString("yyyy-MM-dd") : asOf.trimmed();
    QSqlQuery q(m_db.db());
    q.prepare("SELECT s.id, s.last_name || ' ' || s.first_name, s.current_class, "
              "COALESCE((SELECT SUM(i.amount) FROM invoices i WHERE i.student_id=s.id AND i.status IN ('pending','late') AND i.due_date < ?),0), "
              "COALESCE((SELECT SUM(o.amount) FROM one_time_fees o WHERE o.student_id=s.id AND o.status='pending' AND o.due_date < ?),0), "
              "COALESCE((SELECT MIN(i.due_date) FROM invoices i WHERE i.student_id=s.id AND i.status IN ('pending','late') AND i.due_date < ?),'') "
              "FROM students s WHERE s.deleted_at IS NULL AND s.graduated_at IS NULL");
    q.addBindValue(d); q.addBindValue(d); q.addBindValue(d);
    if (!q.exec()) return out;
    while (q.next()) {
        const double monthly = q.value(3).toDouble();
        const double oneTime = q.value(4).toDouble();
        if (monthly + oneTime <= 0) continue;
        QVariantMap m;
        m["studentId"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["className"] = q.value(2).toString();
        m["monthlyDue"] = monthly;
        m["oneTimeDue"] = oneTime;
        m["total"] = monthly + oneTime;
        m["oldestDue"] = q.value(5).toString();
        out << m;
    }
    std::sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap()["total"].toDouble() > b.toMap()["total"].toDouble();
    });
    return out;
}

QVariantList SchoolApp::parentBalances() const
{
    QVariantList out;
    if (!can("finance.reports")) return out;
    QSqlQuery parents(m_db.db());
    if (!parents.exec("SELECT id,name,email FROM users WHERE role='parent' AND deleted_at IS NULL ORDER BY name")) return out;
    while (parents.next()) {
        const int pid = parents.value(0).toInt();
        double billed = 0, collected = 0;
        QSqlQuery links(m_db.db());
        links.prepare("SELECT student_id FROM parent_student_links WHERE parent_user_id=?");
        links.addBindValue(pid);
        if (links.exec()) {
            while (links.next()) {
                const int sid = links.value(0).toInt();
                QSqlQuery b(m_db.db());
                b.prepare("SELECT COALESCE((SELECT SUM(amount) FROM invoices WHERE student_id=?),0) + "
                          "COALESCE((SELECT SUM(amount) FROM one_time_fees WHERE student_id=?),0), "
                          "COALESCE((SELECT SUM(amount) FROM payments WHERE student_id=?),0)");
                b.addBindValue(sid); b.addBindValue(sid); b.addBindValue(sid);
                if (b.exec() && b.next()) {
                    billed += b.value(0).toDouble();
                    collected += b.value(1).toDouble();
                }
            }
        }
        QVariantMap m;
        m["parentId"] = pid;
        m["name"] = parents.value(1).toString();
        m["email"] = parents.value(2).toString();
        m["billed"] = billed;
        m["collected"] = collected;
        m["balance"] = billed - collected;
        out << m;
    }
    return out;
}

QVariantList SchoolApp::monthlyCollections(int year) const
{
    QVariantList out;
    if (!can("finance.reports")) return out;
    for (int month = 1; month <= 12; ++month) {
        const QString ym = QStringLiteral("%1-%2").arg(year).arg(month, 2, 10, QLatin1Char('0'));
        QSqlQuery b(m_db.db());
        b.prepare("SELECT COALESCE((SELECT SUM(amount) FROM invoices WHERE strftime('%Y-%m',due_date)=?),0) + "
                  "COALESCE((SELECT SUM(amount) FROM one_time_fees WHERE strftime('%Y-%m',due_date)=?),0), "
                  "COALESCE((SELECT SUM(amount) FROM payments WHERE strftime('%Y-%m',paid_at)=?),0)");
        b.addBindValue(ym); b.addBindValue(ym); b.addBindValue(ym);
        QVariantMap m;
        m["month"] = ym;
        m["label"] = QDate(year, month, 1).toString("MMMM yyyy");
        m["billed"] = b.exec() && b.next() ? b.value(0).toDouble() : 0.0;
        m["collected"] = b.value(1).toDouble();
        out << m;
    }
    return out;
}

bool SchoolApp::periodOpenFor(const QString &dateText) const
{
    const QString d = dateText.trimmed().isEmpty() ? QDate::currentDate().toString("yyyy-MM-dd") : dateText.trimmed().left(10);
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COUNT(*) FROM accounting_periods WHERE closed=1 AND ? BETWEEN start_date AND end_date");
    q.addBindValue(d);
    return !(q.exec() && q.next() && q.value(0).toInt() > 0);
}

QVariantList SchoolApp::paymentMethodList() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT code,label,is_active FROM payment_methods ORDER BY rowid")) return out;
    while (q.next()) {
        QVariantMap m;
        m["code"] = q.value(0).toString();
        m["label"] = q.value(1).toString();
        m["active"] = q.value(2).toInt() == 1;
        out << m;
    }
    return out;
}

bool SchoolApp::addPaymentMethod(const QString &code, const QString &label)
{
    if (!can("paymentmethods.manage")) return false;
    const QString c = code.trimmed().toLower(), l = label.trimmed();
    if (c.isEmpty() || l.isEmpty() || c.contains(' ')) { emit errorOccurred(QStringLiteral("Code (sans espace) et libellé requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO payment_methods(code,label,is_active) VALUES(?,?,1)");
    q.addBindValue(c);
    q.addBindValue(l);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce moyen de paiement existe déjà.") : q.lastError().text()); return false; }
    audit("create", "payment_method", 0, c);
    emit dataChanged();
    return true;
}

bool SchoolApp::setPaymentMethodActive(const QString &code, bool active)
{
    if (!can("paymentmethods.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE payment_methods SET is_active=? WHERE code=?");
    q.addBindValue(active ? 1 : 0);
    q.addBindValue(code);
    if (!q.exec() || q.numRowsAffected() != 1) return false;
    audit("update", "payment_method", 0, code + (active ? " activé" : " désactivé"));
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::accountingPeriods() const
{
    QVariantList out;
    if (!can("closing.manage") && !can("accounting.write")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,label,start_date,end_date,closed FROM accounting_periods ORDER BY start_date DESC")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["label"] = q.value(1).toString();
        m["startDate"] = q.value(2).toString();
        m["endDate"] = q.value(3).toString();
        m["closed"] = q.value(4).toInt() == 1;
        out << m;
    }
    return out;
}

bool SchoolApp::addAccountingPeriod(const QVariantMap &v)
{
    if (!can("closing.manage")) return false;
    const QString label = v.value("label").toString().trimmed();
    const QDate start = QDate::fromString(v.value("startDate").toString(), "yyyy-MM-dd");
    const QDate end = QDate::fromString(v.value("endDate").toString(), "yyyy-MM-dd");
    if (label.isEmpty() || !start.isValid() || !end.isValid() || end < start) {
        emit errorOccurred(QStringLiteral("Libellé et dates valides (AAAA-MM-JJ, fin après début) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO accounting_periods(label,start_date,end_date,closed) VALUES(?,?,?,0)");
    q.addBindValue(label);
    q.addBindValue(start.toString("yyyy-MM-dd"));
    q.addBindValue(end.toString("yyyy-MM-dd"));
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette période existe déjà.") : q.lastError().text()); return false; }
    audit("create", "accounting_period", q.lastInsertId().toInt(), label);
    emit dataChanged();
    return true;
}

bool SchoolApp::setAccountingPeriodClosed(int id, bool closed)
{
    if (!can("closing.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE accounting_periods SET closed=?, closed_at=? WHERE id=?");
    q.addBindValue(closed ? 1 : 0);
    q.addBindValue(closed ? QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss") : QVariant());
    q.addBindValue(id);
    if (!q.exec() || q.numRowsAffected() != 1) return false;
    audit(closed ? "close" : "reopen", "accounting_period", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::cashMovements(const QString &date) const
{
    QVariantList out;
    if (!can("cash.manage")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT id,kind,amount,label FROM cash_movements WHERE movement_date=? ORDER BY id");
    q.addBindValue(date.trimmed());
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["kind"] = q.value(1).toString();
        m["amount"] = q.value(2).toDouble();
        m["label"] = q.value(3).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addCashMovement(const QVariantMap &v)
{
    if (!can("cash.manage")) return false;
    const QDate date = QDate::fromString(v.value("date").toString(), "yyyy-MM-dd");
    const QString kind = v.value("kind").toString();
    const double amount = v.value("amount").toDouble();
    const QString label = v.value("label").toString().trimmed();
    if (!date.isValid() || amount <= 0 || label.isEmpty() || !QStringList({"entree", "sortie"}).contains(kind)) {
        emit errorOccurred(QStringLiteral("Date, type, montant (> 0) et libellé requis."));
        return false;
    }
    if (!periodOpenFor(date.toString("yyyy-MM-dd"))) { emit errorOccurred(QStringLiteral("Période comptable clôturée.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO cash_movements(movement_date,kind,amount,label,recorded_by) VALUES(?,?,?,?,?)");
    q.addBindValue(date.toString("yyyy-MM-dd"));
    q.addBindValue(kind);
    q.addBindValue(amount);
    q.addBindValue(label);
    q.addBindValue(m_userId);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "cash_movement", q.lastInsertId().toInt(), kind + " " + label);
    emit dataChanged();
    return true;
}

QVariantMap SchoolApp::cashExpected(const QString &date) const
{
    QVariantMap out;
    if (!can("cash.manage")) return out;
    const QString d = date.trimmed();
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COALESCE((SELECT SUM(amount) FROM payments WHERE method='especes' AND substr(paid_at,1,10)=?),0) "
              "+ COALESCE((SELECT SUM(amount) FROM cash_movements WHERE movement_date=? AND kind='entree'),0) "
              "- COALESCE((SELECT SUM(amount) FROM cash_movements WHERE movement_date=? AND kind='sortie'),0)");
    q.addBindValue(d); q.addBindValue(d); q.addBindValue(d);
    out["expected"] = q.exec() && q.next() ? q.value(0).toDouble() : 0.0;
    return out;
}

bool SchoolApp::closeCash(const QString &date, double counted)
{
    if (!can("cash.manage")) return false;
    const QDate d = QDate::fromString(date.trimmed(), "yyyy-MM-dd");
    if (!d.isValid() || counted < 0) { emit errorOccurred(QStringLiteral("Date et montant compté valides requis.")); return false; }
    const double expected = cashExpected(d.toString("yyyy-MM-dd")).value("expected").toDouble();
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO cash_closings(closing_date,expected,counted,difference,closed_by) VALUES(?,?,?,?,?) "
              "ON CONFLICT(closing_date) DO UPDATE SET expected=excluded.expected, counted=excluded.counted, "
              "difference=excluded.difference, closed_by=excluded.closed_by");
    q.addBindValue(d.toString("yyyy-MM-dd"));
    q.addBindValue(expected);
    q.addBindValue(counted);
    q.addBindValue(counted - expected);
    q.addBindValue(m_userId);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("close", "cash", 0, d.toString("yyyy-MM-dd") + " écart " + QString::number(counted - expected));
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::cashClosings() const
{
    QVariantList out;
    if (!can("cash.manage")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT closing_date,expected,counted,difference FROM cash_closings ORDER BY closing_date DESC")) return out;
    while (q.next()) {
        QVariantMap m;
        m["date"] = q.value(0).toString();
        m["expected"] = q.value(1).toDouble();
        m["counted"] = q.value(2).toDouble();
        m["difference"] = q.value(3).toDouble();
        out << m;
    }
    return out;
}

QVariantList SchoolApp::bankAccounts() const
{
    QVariantList out;
    if (!can("bank.manage")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT a.id,a.name,COALESCE(a.bank,''),COALESCE(a.last4,''),a.opening_balance, "
                "COALESCE((SELECT SUM(amount) FROM bank_lines WHERE account_id=a.id),0), "
                "(SELECT COUNT(*) FROM bank_lines WHERE account_id=a.id AND payment_id IS NOT NULL), "
                "(SELECT COUNT(*) FROM bank_lines WHERE account_id=a.id) FROM bank_accounts a ORDER BY a.name")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["bank"] = q.value(2).toString();
        m["last4"] = q.value(3).toString();
        m["balance"] = q.value(4).toDouble() + q.value(5).toDouble();
        m["reconciled"] = q.value(6).toInt();
        m["lines"] = q.value(7).toInt();
        out << m;
    }
    return out;
}

bool SchoolApp::addBankAccount(const QVariantMap &v)
{
    if (!can("bank.manage")) return false;
    const QString name = v.value("name").toString().trimmed();
    const QString last4 = v.value("last4").toString().trimmed();
    if (name.isEmpty() || (!last4.isEmpty() && (last4.size() != 4 || !last4.toInt()))) {
        emit errorOccurred(QStringLiteral("Nom requis ; seuls les 4 derniers chiffres du compte sont enregistrés."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO bank_accounts(name,bank,last4,opening_balance) VALUES(?,?,?,?)");
    q.addBindValue(name);
    q.addBindValue(v.value("bank").toString().trimmed());
    q.addBindValue(last4);
    q.addBindValue(v.value("openingBalance").toDouble());
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce compte existe déjà.") : q.lastError().text()); return false; }
    audit("create", "bank_account", q.lastInsertId().toInt(), name);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::bankLines(int accountId) const
{
    QVariantList out;
    if (!can("bank.manage")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT id,line_date,label,amount,COALESCE(payment_id,0) FROM bank_lines WHERE account_id=? ORDER BY line_date DESC, id DESC");
    q.addBindValue(accountId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["lineDate"] = q.value(1).toString();
        m["label"] = q.value(2).toString();
        m["amount"] = q.value(3).toDouble();
        m["paymentId"] = q.value(4).toInt();
        out << m;
    }
    return out;
}

bool SchoolApp::addBankLine(const QVariantMap &v)
{
    if (!can("bank.manage")) return false;
    const QDate d = QDate::fromString(v.value("date").toString(), "yyyy-MM-dd");
    const double amount = v.value("amount").toDouble();
    if (!d.isValid() || amount == 0 || v.value("label").toString().trimmed().isEmpty()) {
        emit errorOccurred(QStringLiteral("Date, libellé et montant (non nul, + ou -) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO bank_lines(account_id,line_date,label,amount) VALUES(?,?,?,?)");
    q.addBindValue(v.value("accountId").toInt());
    q.addBindValue(d.toString("yyyy-MM-dd"));
    q.addBindValue(v.value("label").toString().trimmed());
    q.addBindValue(amount);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "bank_line", q.lastInsertId().toInt(), v.value("label").toString());
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::unreconciledPayments() const
{
    QVariantList out;
    if (!can("bank.manage")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT p.id,p.amount,p.method,substr(p.paid_at,1,10),s.last_name || ' ' || s.first_name FROM payments p "
                "JOIN students s ON s.id=p.student_id WHERE p.method<>'especes' "
                "AND p.id NOT IN (SELECT payment_id FROM bank_lines WHERE payment_id IS NOT NULL) ORDER BY p.paid_at DESC")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["amount"] = q.value(1).toDouble();
        m["method"] = q.value(2).toString();
        m["date"] = q.value(3).toString();
        m["label"] = q.value(3).toString() + " · " + q.value(4).toString() + " · " + QString::number(q.value(1).toDouble(), 'f', 0) + " Ar (" + q.value(2).toString() + ")";
        out << m;
    }
    return out;
}

bool SchoolApp::reconcileBankLine(int lineId, int paymentId)
{
    if (!can("bank.manage")) return false;
    QSqlQuery c(m_db.db());
    c.prepare("SELECT ABS(l.amount) = p.amount FROM bank_lines l, payments p WHERE l.id=? AND p.id=? AND l.payment_id IS NULL "
              "AND p.id NOT IN (SELECT payment_id FROM bank_lines WHERE payment_id IS NOT NULL)");
    c.addBindValue(lineId);
    c.addBindValue(paymentId);
    if (!c.exec() || !c.next()) { emit errorOccurred(QStringLiteral("Rapprochement impossible : ligne ou paiement déjà rapproché.")); return false; }
    if (c.value(0).toInt() != 1) { emit errorOccurred(QStringLiteral("Le montant de la ligne ne correspond pas au paiement.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE bank_lines SET payment_id=? WHERE id=?");
    q.addBindValue(paymentId);
    q.addBindValue(lineId);
    if (!q.exec()) return false;
    audit("update", "bank_reconciliation", lineId, "paiement " + QString::number(paymentId));
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::studentSchedule(int studentId) const
{
    QVariantList out;
    if (!canViewStudent(studentId)) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT id,label,due_date,amount FROM payment_schedules WHERE student_id=? ORDER BY due_date,id");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    QVariantList rows;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["label"] = q.value(1).toString();
        m["dueDate"] = q.value(2).toString();
        m["amount"] = q.value(3).toDouble();
        rows << m;
    }
    QSqlQuery p(m_db.db());
    p.prepare("SELECT COALESCE(SUM(amount),0) FROM payments WHERE student_id=?");
    p.addBindValue(studentId);
    const double paid = p.exec() && p.next() ? p.value(0).toDouble() : 0.0;
    double cumulative = 0;
    for (const QVariant &v : rows) {
        QVariantMap m = v.toMap();
        const double before = cumulative;
        cumulative += m["amount"].toDouble();
        m["status"] = paid >= cumulative ? QStringLiteral("paid") : paid > before ? QStringLiteral("partial") : QStringLiteral("pending");
        out << m;
    }
    return out;
}

bool SchoolApp::addScheduleInstallment(int studentId, const QString &label, const QString &dueDate, double amount)
{
    if (!can("schedule.manage")) return false;
    const QDate d = QDate::fromString(dueDate.trimmed(), "yyyy-MM-dd");
    if (studentId <= 0 || label.trimmed().isEmpty() || !d.isValid() || amount <= 0) {
        emit errorOccurred(QStringLiteral("Élève, libellé, échéance (AAAA-MM-JJ) et montant (> 0) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO payment_schedules(student_id,label,due_date,amount) VALUES(?,?,?,?)");
    q.addBindValue(studentId);
    q.addBindValue(label.trimmed());
    q.addBindValue(d.toString("yyyy-MM-dd"));
    q.addBindValue(amount);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "schedule", q.lastInsertId().toInt(), label);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteScheduleInstallment(int id)
{
    if (!can("schedule.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM payment_schedules WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "schedule", id);
    emit dataChanged();
    return true;
}

double SchoolApp::scholarshipPercent(int studentId) const
{
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COALESCE(SUM(percent),0) FROM scholarships WHERE student_id=?");
    q.addBindValue(studentId);
    const double p = q.exec() && q.next() ? q.value(0).toDouble() : 0.0;
    return p > 100.0 ? 100.0 : p;
}

QVariantList SchoolApp::expenseCategories() const
{
    QVariantList out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name FROM expense_categories ORDER BY name")) return out;
    while (q.next()) { QVariantMap m; m["id"] = q.value(0).toInt(); m["name"] = q.value(1).toString(); out << m; }
    return out;
}

bool SchoolApp::addExpenseCategory(const QString &name)
{
    if (!can("accounting.write")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty()) { emit errorOccurred(QStringLiteral("Nom de la catégorie requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO expense_categories(name) VALUES(?)");
    q.addBindValue(n);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Cette catégorie existe déjà.") : q.lastError().text()); return false; }
    audit("create", "expense_category", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteExpenseCategory(int id)
{
    if (!can("accounting.write")) return false;
    QSqlQuery used(m_db.db());
    used.prepare("SELECT COUNT(*) FROM expenses e JOIN expense_categories c ON c.name=e.category WHERE c.id=?");
    used.addBindValue(id);
    if (used.exec() && used.next() && used.value(0).toInt() > 0) {
        emit errorOccurred(QStringLiteral("Cette catégorie est utilisée par des dépenses : elle ne peut pas être supprimée."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM expense_categories WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "expense_category", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::unallocatedPayments(int studentId) const
{
    QVariantList out;
    if (!can("payments.allocate")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT p.id,p.amount,p.method,substr(p.paid_at,1,10),p.amount - COALESCE((SELECT SUM(a.amount) FROM payment_allocations a WHERE a.payment_id=p.id),0) "
              "FROM payments p WHERE p.student_id=? ORDER BY p.paid_at");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        const double left = q.value(4).toDouble();
        if (left <= 0.005) continue;
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["amount"] = q.value(1).toDouble();
        m["method"] = q.value(2).toString();
        m["paidAt"] = q.value(3).toString();
        m["unallocated"] = left;
        m["label"] = q.value(3).toString() + " · " + q.value(2).toString() + " · reste " + QString::number(left, 'f', 0) + " Ar";
        out << m;
    }
    return out;
}

QVariantList SchoolApp::openInvoices(int studentId) const
{
    QVariantList out;
    if (!can("payments.allocate")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT i.id,i.period_month,i.due_date,i.amount - COALESCE((SELECT SUM(a.amount) FROM payment_allocations a WHERE a.invoice_id=i.id),0) "
              "FROM invoices i WHERE i.student_id=? AND i.status IN ('pending','late') ORDER BY i.due_date");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        const double left = q.value(3).toDouble();
        if (left <= 0.005) continue;
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["month"] = q.value(1).toString();
        m["dueDate"] = q.value(2).toString();
        m["remaining"] = left;
        m["label"] = q.value(1).toString() + " · reste " + QString::number(left, 'f', 0) + " Ar";
        out << m;
    }
    return out;
}

bool SchoolApp::allocatePayment(int paymentId, int invoiceId, double amount)
{
    if (!can("payments.allocate")) return false;
    if (amount <= 0) { emit errorOccurred(QStringLiteral("Montant à affecter (> 0) requis.")); return false; }
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return false;
    QSqlQuery p(db);
    p.prepare("SELECT p.student_id, p.amount - COALESCE((SELECT SUM(a.amount) FROM payment_allocations a WHERE a.payment_id=p.id),0) FROM payments p WHERE p.id=?");
    p.addBindValue(paymentId);
    if (!p.exec() || !p.next()) { db.rollback(); emit errorOccurred(QStringLiteral("Paiement introuvable.")); return false; }
    const int studentId = p.value(0).toInt();
    const double paymentLeft = p.value(1).toDouble();
    QSqlQuery i(db);
    i.prepare("SELECT i.student_id, i.amount - COALESCE((SELECT SUM(a.amount) FROM payment_allocations a WHERE a.invoice_id=i.id),0) FROM invoices i WHERE i.id=? AND i.status IN ('pending','late')");
    i.addBindValue(invoiceId);
    if (!i.exec() || !i.next()) { db.rollback(); emit errorOccurred(QStringLiteral("Facture introuvable ou déjà soldée.")); return false; }
    if (i.value(0).toInt() != studentId) { db.rollback(); emit errorOccurred(QStringLiteral("La facture et le paiement n'appartiennent pas au même élève.")); return false; }
    const double invoiceLeft = i.value(1).toDouble();
    if (amount > paymentLeft + 0.005 || amount > invoiceLeft + 0.005) {
        db.rollback();
        emit errorOccurred(QStringLiteral("Montant supérieur au reste du paiement ou de la facture."));
        return false;
    }
    QSqlQuery ins(db);
    ins.prepare("INSERT INTO payment_allocations(payment_id,invoice_id,amount) VALUES(?,?,?)");
    ins.addBindValue(paymentId);
    ins.addBindValue(invoiceId);
    ins.addBindValue(amount);
    if (!ins.exec()) { db.rollback(); emit errorOccurred(ins.lastError().text()); return false; }
    if (amount >= invoiceLeft - 0.005) {
        QSqlQuery up(db);
        up.prepare("UPDATE invoices SET status='paid', payment_id=COALESCE(payment_id,?) WHERE id=?");
        up.addBindValue(paymentId);
        up.addBindValue(invoiceId);
        if (!up.exec()) { db.rollback(); return false; }
    }
    db.commit();
    audit("update", "allocation", invoiceId, "paiement " + QString::number(paymentId) + " : " + QString::number(amount, 'f', 0) + " Ar");
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::scholarshipsFor(int studentId) const
{
    QVariantList out;
    if (!can("scholarships.manage")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT id,label,percent,COALESCE(school_year,'') FROM scholarships WHERE student_id=? ORDER BY id");
    q.addBindValue(studentId);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["label"] = q.value(1).toString();
        m["percent"] = q.value(2).toDouble();
        m["schoolYear"] = q.value(3).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addScholarship(const QVariantMap &v)
{
    if (!can("scholarships.manage")) return false;
    const int studentId = v.value("studentId").toInt();
    const QString label = v.value("label").toString().trimmed();
    const double percent = v.value("percent").toDouble();
    if (studentId <= 0 || label.isEmpty() || percent <= 0 || percent > 100) {
        emit errorOccurred(QStringLiteral("Élève, libellé et pourcentage entre 0 et 100 requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO scholarships(student_id,label,percent,school_year) VALUES(?,?,?,?)");
    q.addBindValue(studentId);
    q.addBindValue(label);
    q.addBindValue(percent);
    q.addBindValue(v.value("schoolYear").toString().trimmed());
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "scholarship", q.lastInsertId().toInt(), label);
    emit dataChanged();
    return true;
}

bool SchoolApp::deleteScholarship(int id)
{
    if (!can("scholarships.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("DELETE FROM scholarships WHERE id=?");
    q.addBindValue(id);
    if (!q.exec()) return false;
    audit("delete", "scholarship", id);
    emit dataChanged();
    return true;
}

QVariantMap SchoolApp::financialStatements(const QString &fromDate, const QString &toDate) const
{
    QVariantMap out;
    if (!can("finance.reports")) return out;
    const QString from = fromDate.trimmed().isEmpty() ? QStringLiteral("0000-01-01") : fromDate.trimmed();
    const QString to = toDate.trimmed().isEmpty() ? QStringLiteral("9999-12-31") : toDate.trimmed();

    QVariantList byMethod;
    double revenue = 0;
    QSqlQuery r(m_db.db());
    r.prepare("SELECT method, SUM(amount) FROM payments WHERE substr(paid_at,1,10) BETWEEN ? AND ? GROUP BY method ORDER BY method");
    r.addBindValue(from);
    r.addBindValue(to);
    if (r.exec()) {
        while (r.next()) {
            QVariantMap m;
            m["method"] = r.value(0).toString();
            m["amount"] = r.value(1).toDouble();
            revenue += r.value(1).toDouble();
            byMethod << m;
        }
    }

    QVariantList byCategory;
    double expenses = 0;
    QSqlQuery e(m_db.db());
    e.prepare("SELECT category, SUM(amount) FROM expenses WHERE expense_date BETWEEN ? AND ? GROUP BY category ORDER BY SUM(amount) DESC");
    e.addBindValue(from);
    e.addBindValue(to);
    if (e.exec()) {
        while (e.next()) {
            expenses += e.value(1).toDouble();
            QVariantMap m;
            m["category"] = e.value(0).toString();
            m["amount"] = e.value(1).toDouble();
            byCategory << m;
        }
    }
    for (int k = 0; k < byCategory.size(); ++k) {
        QVariantMap m = byCategory[k].toMap();
        m["percent"] = expenses > 0 ? QString::number(m["amount"].toDouble() * 100.0 / expenses, 'f', 1) : QStringLiteral("0.0");
        byCategory[k] = m;
    }

    out["byMethod"] = byMethod;
    out["byCategory"] = byCategory;
    out["revenue"] = revenue;
    out["expenses"] = expenses;
    out["result"] = revenue - expenses;
    return out;
}

QString SchoolApp::studentsCsvTemplate() const
{
    return QStringLiteral("nom;prenom;date_naissance;lieu_naissance;classe;telephone_parent;email_parent;adresse\n");
}

QVariantMap SchoolApp::importStudentsCsv(const QString &csv)
{
    QVariantMap out;
    QVariantList errors;
    int imported = 0;
    out["imported"] = 0;
    out["rejected"] = 0;
    if (!can("students.create")) {
        emit errorOccurred(QStringLiteral("Droit insuffisant pour importer des élèves."));
        out["errors"] = errors;
        return out;
    }
    QStringList lines;
    for (const QString &raw : csv.split('\n')) {
        const QString line = raw.trimmed();
        if (!line.isEmpty()) lines << line;
    }
    if (lines.size() < 2) {
        errors << QStringLiteral("Il faut une ligne d'en-tête et au moins une ligne d'élève.");
        out["errors"] = errors;
        out["rejected"] = errors.size();
        return out;
    }
    const QChar delim = lines.first().contains(';') ? QChar(';') : QChar(',');
    auto clean = [](QString f) { f = f.trimmed(); if (f.startsWith('"') && f.endsWith('"') && f.size() >= 2) f = f.mid(1, f.size() - 2); return f.trimmed(); };
    auto normKey = [](QString k) { k = k.trimmed().toLower(); k.remove('_'); k.remove(' '); k.remove('-'); return k; };

    QVariantMap alias;
    alias["nom"] = "lastName"; alias["lastname"] = "lastName";
    alias["prenom"] = "firstName"; alias["prénom"] = "firstName"; alias["firstname"] = "firstName";
    alias["datenaissance"] = "birthDate"; alias["birthdate"] = "birthDate";
    alias["lieunaissance"] = "birthPlace"; alias["birthplace"] = "birthPlace";
    alias["classe"] = "className"; alias["classname"] = "className";
    alias["telephoneparent"] = "parentPhone"; alias["parentphone"] = "parentPhone";
    alias["emailparent"] = "parentEmail"; alias["parentemail"] = "parentEmail";
    alias["adresse"] = "address"; alias["address"] = "address";

    QStringList header;
    for (const QString &h : lines.first().split(delim)) header << normKey(clean(h));
    QVariantList columns;
    for (const QString &h : header) columns << alias.value(h, QString()).toString();
    const QStringList required = {"lastName", "firstName", "birthDate", "className", "parentPhone", "address"};
    QStringList missing;
    for (const QString &r : required) if (!columns.contains(r)) missing << r;
    if (!missing.isEmpty()) {
        errors << QStringLiteral("Colonnes manquantes dans l'en-tête : ") + missing.join(", ");
        out["errors"] = errors;
        out["rejected"] = errors.size();
        return out;
    }

    const QStringList classList = classes();
    for (int i = 1; i < lines.size(); ++i) {
        const QStringList fields = lines.at(i).split(delim);
        QVariantMap row;
        for (int c = 0; c < columns.size() && c < fields.size(); ++c) {
            const QString key = columns.at(c).toString();
            if (!key.isEmpty()) row[key] = clean(fields.at(c));
        }
        const QString where = QStringLiteral("Ligne %1 : ").arg(i + 1);
        bool ok = true;
        for (const QString &r : required) {
            if (row.value(r).toString().isEmpty()) { errors << where + QStringLiteral("champ « %1 » vide").arg(r); ok = false; break; }
        }
        if (!ok) continue;
        if (!classList.contains(row.value("className").toString())) {
            errors << where + QStringLiteral("classe inconnue « %1 »").arg(row.value("className").toString());
            continue;
        }
        if (!QDate::fromString(row.value("birthDate").toString(), "yyyy-MM-dd").isValid()) {
            errors << where + QStringLiteral("date de naissance invalide (AAAA-MM-JJ attendu)");
            continue;
        }
        QSqlQuery dup(m_db.db());
        dup.prepare("SELECT COUNT(*) FROM students WHERE last_name=? AND first_name=? AND birth_date=? AND deleted_at IS NULL");
        dup.addBindValue(row.value("lastName").toString());
        dup.addBindValue(row.value("firstName").toString());
        dup.addBindValue(row.value("birthDate").toString());
        if (dup.exec() && dup.next() && dup.value(0).toInt() > 0) {
            errors << where + QStringLiteral("élève déjà présent (même nom, prénom et date de naissance)");
            continue;
        }
        if (addStudent(row)) ++imported;
        else errors << where + QStringLiteral("enregistrement refusé");
    }
    audit("import", "students", imported, QStringLiteral("%1 élèves importés").arg(imported));
    if (imported > 0) emit dataChanged();
    out["imported"] = imported;
    out["rejected"] = errors.size();
    out["errors"] = errors;
    return out;
}

namespace {
bool smtpExpect(QSslSocket &s, const QString &command, int expected, QString &error)
{
    if (!command.isEmpty()) {
        const QByteArray bytes = (command + "\r\n").toUtf8();
        if (s.write(bytes) != bytes.size() || !s.waitForBytesWritten(15000)) { error = QStringLiteral("envoi interrompu"); return false; }
    }
    QString text;
    for (;;) {
        if (!s.canReadLine() && !s.waitForReadyRead(15000)) { error = QStringLiteral("pas de réponse du serveur"); return false; }
        while (s.canReadLine()) {
            const QString line = QString::fromUtf8(s.readLine()).trimmed();
            text += line + "\n";
            if (line.size() >= 3 && (line.size() == 3 || line[3] == ' ')) {
                const int code = line.left(3).toInt();
                if (code != expected) { error = QStringLiteral("réponse serveur : ") + line; return false; }
                return true;
            }
        }
    }
}
}

bool SchoolApp::sendMail(const QString &to, const QString &subject, const QString &body, QString *error) const
{
    QString err;
    const QString host = setting("smtp_host").trimmed();
    const int port = setting("smtp_port").isEmpty() ? 587 : setting("smtp_port").toInt();
    const QString user = setting("smtp_user").trimmed();
    const QString from = setting("smtp_from").trimmed();
    const QString security = setting("smtp_security").isEmpty() ? QStringLiteral("starttls") : setting("smtp_security");
    if (host.isEmpty() || from.isEmpty() || to.trimmed().isEmpty()) {
        if (error) *error = QStringLiteral("serveur, adresse expéditrice ou destinataire manquant");
        return false;
    }
    QSslSocket s;
    if (security == QLatin1String("ssl")) {
        s.connectToHostEncrypted(host, port);
        if (!s.waitForEncrypted(15000)) { if (error) *error = QStringLiteral("connexion SSL impossible"); return false; }
    } else {
        s.connectToHost(host, port);
        if (!s.waitForConnected(15000)) { if (error) *error = QStringLiteral("connexion impossible"); return false; }
    }
    bool ok = smtpExpect(s, QString(), 220, err)
        && smtpExpect(s, QStringLiteral("EHLO escato.local"), 250, err);
    if (ok && security == QLatin1String("starttls")) {
        ok = smtpExpect(s, QStringLiteral("STARTTLS"), 220, err);
        if (ok) { s.startClientEncryption(); ok = s.waitForEncrypted(15000); if (!ok) err = QStringLiteral("STARTTLS impossible"); }
        if (ok) ok = smtpExpect(s, QStringLiteral("EHLO escato.local"), 250, err);
    }
    if (ok && !user.isEmpty()) {
        ok = smtpExpect(s, QStringLiteral("AUTH LOGIN"), 334, err)
            && smtpExpect(s, QString::fromLatin1(user.toUtf8().toBase64()), 334, err)
            && smtpExpect(s, QString::fromLatin1(m_smtpPassword.toUtf8().toBase64()), 235, err);
    }
    if (ok) {
        const QString mime = "=?UTF-8?B?" + QString::fromLatin1(subject.toUtf8().toBase64()) + "?=";
        QStringList headers;
        headers << "From: " + from << "To: " + to.trimmed() << "Subject: " + mime
                << "Date: " + QDateTime::currentDateTime().toString(Qt::RFC2822Date)
                << "MIME-Version: 1.0" << "Content-Type: text/plain; charset=UTF-8" << "Content-Transfer-Encoding: 8bit";
        QStringList bodyLines;
        for (const QString &line : body.split('\n')) bodyLines << (line.startsWith('.') ? "." + line : line);
        const QByteArray data = (headers.join("\r\n") + "\r\n\r\n" + bodyLines.join("\r\n") + "\r\n.").toUtf8();
        ok = smtpExpect(s, QStringLiteral("MAIL FROM:<%1>").arg(from), 250, err)
            && smtpExpect(s, QStringLiteral("RCPT TO:<%1>").arg(to.trimmed()), 250, err)
            && smtpExpect(s, QStringLiteral("DATA"), 354, err);
        if (ok) {
            const QByteArray payload = data + "\r\n";
            s.write(payload);
            ok = s.waitForBytesWritten(15000) && smtpExpect(s, QString(), 250, err);
        }
    }
    if (s.state() == QAbstractSocket::ConnectedState) smtpExpect(s, QStringLiteral("QUIT"), 221, err);
    s.disconnectFromHost();
    if (!ok && error) *error = err;
    return ok;
}

void SchoolApp::logEmail(const QString &to, const QString &subject, bool ok, const QString &error)
{
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO email_log(recipient,subject,status,error,user_id) VALUES(?,?,?,?,?)");
    q.addBindValue(to);
    q.addBindValue(subject);
    q.addBindValue(ok ? QStringLiteral("envoyé") : QStringLiteral("échec"));
    q.addBindValue(error);
    q.addBindValue(m_userId > 0 ? QVariant(m_userId) : QVariant());
    q.exec();
}

QVariantMap SchoolApp::smtpSettings() const
{
    QVariantMap out;
    if (!can("email.config")) return out;
    out["host"] = setting("smtp_host");
    out["port"] = setting("smtp_port").isEmpty() ? 587 : setting("smtp_port").toInt();
    out["user"] = setting("smtp_user");
    out["from"] = setting("smtp_from");
    out["security"] = setting("smtp_security").isEmpty() ? QStringLiteral("starttls") : setting("smtp_security");
    out["scheduleEnabled"] = setting("email_schedule_enabled") == QLatin1String("1");
    out["scheduleTime"] = setting("email_schedule_time").isEmpty() ? QStringLiteral("08:00") : setting("email_schedule_time");
    out["passwordSet"] = !m_smtpPassword.isEmpty();
    return out;
}

bool SchoolApp::saveSmtpSettings(const QVariantMap &v)
{
    if (!can("email.config")) return false;
    const QString host = v.value("host").toString().trimmed();
    const QString security = v.value("security").toString();
    if (host.isEmpty() || !QStringList({"starttls", "ssl", "none"}).contains(security)) {
        emit errorOccurred(QStringLiteral("Serveur et mode de chiffrement (starttls, ssl ou none) requis."));
        return false;
    }
    setSetting("smtp_host", host);
    setSetting("smtp_port", QString::number(v.value("port").toInt() > 0 ? v.value("port").toInt() : 587));
    setSetting("smtp_user", v.value("user").toString().trimmed());
    setSetting("smtp_from", v.value("from").toString().trimmed());
    setSetting("smtp_security", security);
    return true;
}

void SchoolApp::setSmtpPassword(const QString &password)
{
    if (!can("email.config")) return;
    m_smtpPassword = password;
    emit dataChanged();
}

bool SchoolApp::saveEmailSchedule(bool enabled, const QString &time)
{
    if (!can("email.config")) return false;
    if (!QTime::fromString(time.trimmed(), "HH:mm").isValid()) {
        emit errorOccurred(QStringLiteral("Heure au format HH:mm requise."));
        return false;
    }
    setSetting("email_schedule_enabled", enabled ? "1" : "0");
    setSetting("email_schedule_time", QTime::fromString(time.trimmed(), "HH:mm").toString("HH:mm"));
    return true;
}

bool SchoolApp::sendTestEmail(const QString &to)
{
    if (!can("email.config")) return false;
    QString err;
    const bool ok = sendMail(to, QStringLiteral("Test ESCATO GS"), QStringLiteral("Ce message confirme que la configuration e-mail fonctionne."), &err);
    logEmail(to, QStringLiteral("Test ESCATO GS"), ok, err);
    if (!ok) emit errorOccurred(QStringLiteral("Envoi impossible : ") + err);
    emit dataChanged();
    return ok;
}

int SchoolApp::sendOverdueReminders()
{
    if (!can("email.send")) return 0;
    const QString school_name = setting("school_name").isEmpty() ? QStringLiteral("l'établissement") : setting("school_name");
    const QString today = QDate::currentDate().toString("dd/MM/yyyy");
    int sent = 0, failed = 0;
    for (const QVariant &v : overdueByStudent(QString())) {
        const QVariantMap m = v.toMap();
        QSqlQuery q(m_db.db());
        q.prepare("SELECT COALESCE(parent_email,'') FROM students WHERE id=?");
        q.addBindValue(m["studentId"].toInt());
        if (!q.exec() || !q.next()) continue;
        const QString to = q.value(0).toString().trimmed();
        if (to.isEmpty()) continue;
        const QString subject = QStringLiteral("Rappel de paiement - %1").arg(m["name"].toString());
        const QString body = QStringLiteral("Bonjour,\n\nNous vous informons que le solde restant dû pour %1 est de %2 à la date du %3.\n\nMerci de bien vouloir régulariser la situation auprès de l'administration.\n\n%4")
                                .arg(m["name"].toString(), QLocale(QLocale::French).toString(m["total"].toDouble(), 'f', 0) + QStringLiteral(" Ar"), today, school_name);
        QString err;
        const bool ok = sendMail(to, subject, body, &err);
        logEmail(to, subject, ok, err);
        ok ? ++sent : ++failed;
    }
    emit dataChanged();
    if (failed > 0) emit errorOccurred(QStringLiteral("%1 relance(s) envoyée(s), %2 échec(s) : voir l'historique.").arg(sent).arg(failed));
    return sent;
}

bool SchoolApp::sendStudentSituation(int studentId)
{
    if (!can("email.send")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COALESCE(parent_email,''), last_name || ' ' || first_name FROM students WHERE id=? AND deleted_at IS NULL");
    q.addBindValue(studentId);
    if (!q.exec() || !q.next()) return false;
    const QString to = q.value(0).toString().trimmed();
    const QString name = q.value(1).toString();
    if (to.isEmpty()) { emit errorOccurred(QStringLiteral("Cet élève n'a pas d'adresse e-mail de parent.")); return false; }
    double billed = 0;
    for (const QVariant &v : studentInvoices(studentId)) billed += v.toMap()["amount"].toDouble();
    double paid = 0;
    for (const QVariant &v : payments(studentId)) paid += v.toMap()["amount"].toDouble();
    const QString subject = QStringLiteral("Situation financière - %1").arg(name);
    const QString body = QStringLiteral("Bonjour,\n\nSituation financière de %1 :\n- montant facturé : %2\n- montant encaissé : %3\n- solde : %4\n\nCordialement.")
                            .arg(name,
                                 QLocale(QLocale::French).toString(billed, 'f', 0) + QStringLiteral(" Ar"),
                                 QLocale(QLocale::French).toString(paid, 'f', 0) + QStringLiteral(" Ar"),
                                 QLocale(QLocale::French).toString(billed - paid, 'f', 0) + QStringLiteral(" Ar"));
    QString err;
    const bool ok = sendMail(to, subject, body, &err);
    logEmail(to, subject, ok, err);
    if (!ok) emit errorOccurred(QStringLiteral("Envoi impossible : ") + err);
    emit dataChanged();
    return ok;
}

QVariantList SchoolApp::emailLog(int limit) const
{
    QVariantList out;
    if (!can("email.send")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT created_at, recipient, subject, status FROM email_log ORDER BY id DESC LIMIT ?");
    q.addBindValue(limit > 0 ? limit : 200);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["createdAt"] = q.value(0).toString();
        m["recipient"] = q.value(1).toString();
        m["subject"] = q.value(2).toString();
        m["status"] = q.value(3).toString();
        out << m;
    }
    return out;
}

void SchoolApp::runScheduledEmails()
{
    if (m_userId <= 0) return;
    if (setting("email_schedule_enabled") != QLatin1String("1")) return;
    const QString nowHm = QTime::currentTime().toString("HH:mm");
    if (nowHm != (setting("email_schedule_time").isEmpty() ? QStringLiteral("08:00") : setting("email_schedule_time"))) return;
    const QString today = QDate::currentDate().toString("yyyy-MM-dd");
    if (setting("email_last_run") == today) return;
    setSetting("email_last_run", today);
    sendOverdueReminders();
}

namespace {
QDate hrPeriodEnd(const QString &period)
{
    const QDate first = QDate::fromString(period + "-01", "yyyy-MM-dd");
    return first.isValid() ? first.addMonths(1).addDays(-1) : QDate();
}
}

QVariantList SchoolApp::hrDepartments() const
{
    QVariantList out;
    if (!can("hr.manage") && !can("hr.payroll")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name FROM hr_departments ORDER BY name")) return out;
    while (q.next()) { QVariantMap m; m["id"] = q.value(0).toInt(); m["name"] = q.value(1).toString(); out << m; }
    return out;
}

bool SchoolApp::addHrDepartment(const QString &name)
{
    if (!can("hr.manage")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty()) { emit errorOccurred(QStringLiteral("Nom du service requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_departments(name) VALUES(?)");
    q.addBindValue(n);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce service existe déjà.") : q.lastError().text()); return false; }
    audit("create", "hr_department", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::hrPositions() const
{
    QVariantList out;
    if (!can("hr.manage") && !can("hr.payroll")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT id,name FROM hr_positions ORDER BY name")) return out;
    while (q.next()) { QVariantMap m; m["id"] = q.value(0).toInt(); m["name"] = q.value(1).toString(); out << m; }
    return out;
}

bool SchoolApp::addHrPosition(const QString &name)
{
    if (!can("hr.manage")) return false;
    const QString n = name.trimmed();
    if (n.isEmpty()) { emit errorOccurred(QStringLiteral("Nom du poste requis.")); return false; }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_positions(name) VALUES(?)");
    q.addBindValue(n);
    if (!q.exec()) { emit errorOccurred(q.lastError().text().contains("UNIQUE") ? QStringLiteral("Ce poste existe déjà.") : q.lastError().text()); return false; }
    audit("create", "hr_position", q.lastInsertId().toInt(), n);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::hrEmployees() const
{
    QVariantList out;
    if (!can("hr.manage") && !can("hr.payroll")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT e.id,e.full_name,COALESCE(e.phone,''),COALESCE(d.name,''),COALESCE(p.name,''),COALESCE(e.contract_type,''),"
                "COALESCE(e.start_date,''),e.base_salary,e.status FROM hr_employees e "
                "LEFT JOIN hr_departments d ON d.id=e.department_id LEFT JOIN hr_positions p ON p.id=e.position_id ORDER BY e.full_name")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["phone"] = q.value(2).toString();
        m["department"] = q.value(3).toString();
        m["position"] = q.value(4).toString();
        m["contract"] = q.value(5).toString();
        m["startDate"] = q.value(6).toString();
        m["baseSalary"] = q.value(7).toDouble();
        m["status"] = q.value(8).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addHrEmployee(const QVariantMap &v)
{
    if (!can("hr.manage")) return false;
    const QString name = v.value("name").toString().trimmed();
    const double base = v.value("baseSalary").toDouble();
    const QString start = v.value("startDate").toString().trimmed();
    if (name.isEmpty() || base < 0 || (!start.isEmpty() && !QDate::fromString(start, "yyyy-MM-dd").isValid())) {
        emit errorOccurred(QStringLiteral("Nom, salaire de base (≥ 0) et date de début (AAAA-MM-JJ) valides requis."));
        return false;
    }
    const int dep = v.value("departmentId").toInt();
    const int pos = v.value("positionId").toInt();
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_employees(full_name,phone,department_id,position_id,contract_type,start_date,base_salary) VALUES(?,?,?,?,?,?,?)");
    q.addBindValue(name);
    q.addBindValue(v.value("phone").toString().trimmed());
    q.addBindValue(dep > 0 ? QVariant(dep) : QVariant());
    q.addBindValue(pos > 0 ? QVariant(pos) : QVariant());
    q.addBindValue(v.value("contractType").toString().trimmed());
    q.addBindValue(start.isEmpty() ? QVariant() : QVariant(start));
    q.addBindValue(base);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "hr_employee", q.lastInsertId().toInt(), name);
    emit dataChanged();
    return true;
}

bool SchoolApp::setHrEmployeeStatus(int id, const QString &status)
{
    if (!can("hr.manage")) return false;
    if (!QStringList({"actif", "sorti"}).contains(status)) return false;
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE hr_employees SET status=? WHERE id=?");
    q.addBindValue(status);
    q.addBindValue(id);
    if (!q.exec() || q.numRowsAffected() != 1) return false;
    audit("update", "hr_employee", id, status);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::hrAttendanceFor(const QString &day) const
{
    QVariantList out;
    if (!can("hr.manage")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT e.id,e.full_name,COALESCE(a.status,'present') FROM hr_employees e "
              "LEFT JOIN hr_attendance a ON a.employee_id=e.id AND a.day=? WHERE e.status='actif' ORDER BY e.full_name");
    q.addBindValue(day.trimmed());
    if (!q.exec()) return out;
    while (q.next()) { QVariantMap m; m["id"] = q.value(0).toInt(); m["name"] = q.value(1).toString(); m["status"] = q.value(2).toString(); out << m; }
    return out;
}

bool SchoolApp::setHrAttendance(int employeeId, const QString &day, const QString &status)
{
    if (!can("hr.manage")) return false;
    if (!QDate::fromString(day, "yyyy-MM-dd").isValid() || !QStringList({"present", "absent", "late", "leave"}).contains(status)) return false;
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_attendance(employee_id,day,status) VALUES(?,?,?) ON CONFLICT(employee_id,day) DO UPDATE SET status=excluded.status");
    q.addBindValue(employeeId);
    q.addBindValue(day);
    q.addBindValue(status);
    if (!q.exec()) return false;
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::hrLeaves() const
{
    QVariantList out;
    if (!can("hr.manage")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT l.id,e.full_name,l.kind,l.start_date,l.end_date,l.status FROM hr_leaves l "
                "JOIN hr_employees e ON e.id=l.employee_id ORDER BY l.id DESC LIMIT 200")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["kind"] = q.value(2).toString();
        m["startDate"] = q.value(3).toString();
        m["endDate"] = q.value(4).toString();
        m["status"] = q.value(5).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::addHrLeave(const QVariantMap &v)
{
    if (!can("hr.manage")) return false;
    const QDate s = QDate::fromString(v.value("startDate").toString(), "yyyy-MM-dd");
    const QDate e = QDate::fromString(v.value("endDate").toString(), "yyyy-MM-dd");
    const QString kind = v.value("kind").toString().trimmed();
    if (v.value("employeeId").toInt() <= 0 || kind.isEmpty() || !s.isValid() || !e.isValid() || e < s) {
        emit errorOccurred(QStringLiteral("Salarié, type et dates valides (AAAA-MM-JJ, fin après début) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_leaves(employee_id,kind,start_date,end_date) VALUES(?,?,?,?)");
    q.addBindValue(v.value("employeeId").toInt());
    q.addBindValue(kind);
    q.addBindValue(s.toString("yyyy-MM-dd"));
    q.addBindValue(e.toString("yyyy-MM-dd"));
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "hr_leave", q.lastInsertId().toInt(), kind);
    emit dataChanged();
    return true;
}

bool SchoolApp::decideHrLeave(int id, bool approve)
{
    if (!can("hr.manage")) return false;
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE hr_leaves SET status=? WHERE id=? AND status='en attente'");
    q.addBindValue(approve ? QStringLiteral("approuvé") : QStringLiteral("refusé"));
    q.addBindValue(id);
    if (!q.exec() || q.numRowsAffected() != 1) return false;
    audit(approve ? "approve" : "refuse", "hr_leave", id);
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::hrAdvances() const
{
    QVariantList out;
    if (!can("hr.payroll")) return out;
    QSqlQuery q(m_db.db());
    if (!q.exec("SELECT a.id,e.full_name,a.advance_date,a.amount,a.deducted FROM hr_advances a "
                "JOIN hr_employees e ON e.id=a.employee_id ORDER BY a.id DESC LIMIT 200")) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["date"] = q.value(2).toString();
        m["amount"] = q.value(3).toDouble();
        m["deducted"] = q.value(4).toInt() == 1;
        out << m;
    }
    return out;
}

bool SchoolApp::addHrAdvance(const QVariantMap &v)
{
    if (!can("hr.payroll")) return false;
    const QDate d = QDate::fromString(v.value("date").toString(), "yyyy-MM-dd");
    const double amount = v.value("amount").toDouble();
    if (v.value("employeeId").toInt() <= 0 || !d.isValid() || amount <= 0) {
        emit errorOccurred(QStringLiteral("Salarié, date et montant (> 0) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_advances(employee_id,advance_date,amount) VALUES(?,?,?)");
    q.addBindValue(v.value("employeeId").toInt());
    q.addBindValue(d.toString("yyyy-MM-dd"));
    q.addBindValue(amount);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "hr_advance", q.lastInsertId().toInt(), QString::number(amount, 'f', 0));
    emit dataChanged();
    return true;
}

QVariantList SchoolApp::hrItems(const QString &period) const
{
    QVariantList out;
    if (!can("hr.payroll")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT i.id,e.full_name,i.kind,i.label,i.amount FROM hr_items i JOIN hr_employees e ON e.id=i.employee_id "
              "WHERE i.period=? ORDER BY e.full_name");
    q.addBindValue(period.trimmed());
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["id"] = q.value(0).toInt();
        m["name"] = q.value(1).toString();
        m["kind"] = q.value(2).toString();
        m["label"] = q.value(3).toString();
        m["amount"] = q.value(4).toDouble();
        out << m;
    }
    return out;
}

bool SchoolApp::addHrItem(const QVariantMap &v)
{
    if (!can("hr.payroll")) return false;
    const QString period = v.value("period").toString().trimmed();
    const QString kind = v.value("kind").toString();
    const QString label = v.value("label").toString().trimmed();
    const double amount = v.value("amount").toDouble();
    if (v.value("employeeId").toInt() <= 0 || !hrPeriodEnd(period).isValid() || !QStringList({"prime", "retenue"}).contains(kind)
        || label.isEmpty() || amount <= 0) {
        emit errorOccurred(QStringLiteral("Salarié, période (AAAA-MM), type, libellé et montant (> 0) requis."));
        return false;
    }
    QSqlQuery q(m_db.db());
    q.prepare("INSERT INTO hr_items(employee_id,period,kind,label,amount) VALUES(?,?,?,?,?)");
    q.addBindValue(v.value("employeeId").toInt());
    q.addBindValue(period);
    q.addBindValue(kind);
    q.addBindValue(label);
    q.addBindValue(amount);
    if (!q.exec()) { emit errorOccurred(q.lastError().text()); return false; }
    audit("create", "hr_item", q.lastInsertId().toInt(), kind + " " + label);
    emit dataChanged();
    return true;
}

QVariantMap SchoolApp::hrSocialSettings() const
{
    QVariantMap out;
    if (!can("hr.payroll")) return out;
    out["employeeRate"] = setting("hr_employee_rate").isEmpty() ? 0.0 : setting("hr_employee_rate").toDouble();
    out["employerRate"] = setting("hr_employer_rate").isEmpty() ? 0.0 : setting("hr_employer_rate").toDouble();
    return out;
}

bool SchoolApp::saveHrSocialSettings(double employeeRate, double employerRate)
{
    if (!can("hr.payroll")) return false;
    if (employeeRate < 0 || employeeRate > 100 || employerRate < 0 || employerRate > 100) {
        emit errorOccurred(QStringLiteral("Taux entre 0 et 100 %."));
        return false;
    }
    setSetting("hr_employee_rate", QString::number(employeeRate));
    setSetting("hr_employer_rate", QString::number(employerRate));
    return true;
}

QVariantList SchoolApp::hrPayrollPreview(const QString &period) const
{
    QVariantList out;
    if (!can("hr.payroll")) return out;
    const QDate end = hrPeriodEnd(period.trimmed());
    if (!end.isValid()) return out;
    const double empRate = setting("hr_employee_rate").isEmpty() ? 0.0 : setting("hr_employee_rate").toDouble();
    const double erRate = setting("hr_employer_rate").isEmpty() ? 0.0 : setting("hr_employer_rate").toDouble();
    const QString p = period.trimmed();
    QSqlQuery emps(m_db.db());
    if (!emps.exec("SELECT id,full_name,base_salary FROM hr_employees WHERE status='actif' ORDER BY full_name")) return out;
    while (emps.next()) {
        const int eid = emps.value(0).toInt();
        const double base = emps.value(2).toDouble();
        QSqlQuery it(m_db.db());
        it.prepare("SELECT COALESCE(SUM(CASE WHEN kind='prime' THEN amount ELSE 0 END),0), COALESCE(SUM(CASE WHEN kind='retenue' THEN amount ELSE 0 END),0) "
                   "FROM hr_items WHERE employee_id=? AND period=?");
        it.addBindValue(eid);
        it.addBindValue(p);
        double primes = 0, retenues = 0;
        if (it.exec() && it.next()) { primes = it.value(0).toDouble(); retenues = it.value(1).toDouble(); }
        QSqlQuery adv(m_db.db());
        adv.prepare("SELECT COALESCE(SUM(amount),0) FROM hr_advances WHERE employee_id=? AND deducted=0 AND advance_date<=?");
        adv.addBindValue(eid);
        adv.addBindValue(end.toString("yyyy-MM-dd"));
        const double advances = adv.exec() && adv.next() ? adv.value(0).toDouble() : 0.0;
        const double gross = base + primes - retenues;
        const double social = gross * empRate / 100.0;
        QVariantMap m;
        m["employeeId"] = eid;
        m["name"] = emps.value(1).toString();
        m["base"] = base;
        m["primes"] = primes;
        m["retenues"] = retenues;
        m["gross"] = gross;
        m["social"] = social;
        m["advances"] = advances;
        m["net"] = gross - social - advances;
        m["employerCost"] = gross * (1.0 + erRate / 100.0);
        out << m;
    }
    return out;
}

bool SchoolApp::validateHrPayroll(const QString &period)
{
    if (!can("hr.payroll")) return false;
    const QString p = period.trimmed();
    const QDate end = hrPeriodEnd(p);
    if (!end.isValid()) { emit errorOccurred(QStringLiteral("Période au format AAAA-MM requise.")); return false; }
    QSqlQuery exists(m_db.db());
    exists.prepare("SELECT COUNT(*) FROM payroll_runs WHERE period=?");
    exists.addBindValue(p);
    if (exists.exec() && exists.next() && exists.value(0).toInt() > 0) {
        emit errorOccurred(QStringLiteral("La paie de cette période est déjà validée."));
        return false;
    }
    const QVariantList rows = hrPayrollPreview(p);
    QSqlDatabase db = m_db.db();
    if (!db.transaction()) return false;
    for (const QVariant &v : rows) {
        const QVariantMap m = v.toMap();
        QSqlQuery ins(db);
        ins.prepare("INSERT INTO payroll_runs(period,employee_id,gross,social,advances,net,employer_cost) VALUES(?,?,?,?,?,?,?)");
        ins.addBindValue(p);
        ins.addBindValue(m["employeeId"].toInt());
        ins.addBindValue(m["gross"].toDouble());
        ins.addBindValue(m["social"].toDouble());
        ins.addBindValue(m["advances"].toDouble());
        ins.addBindValue(m["net"].toDouble());
        ins.addBindValue(m["employerCost"].toDouble());
        if (!ins.exec()) { db.rollback(); emit errorOccurred(ins.lastError().text()); return false; }
        QSqlQuery ded(db);
        ded.prepare("UPDATE hr_advances SET deducted=1 WHERE employee_id=? AND deducted=0 AND advance_date<=?");
        ded.addBindValue(m["employeeId"].toInt());
        ded.addBindValue(end.toString("yyyy-MM-dd"));
        if (!ded.exec()) { db.rollback(); return false; }
    }
    db.commit();
    audit("validate", "hr_payroll", 0, p + " (" + QString::number(rows.size()) + " salariés)");
    emit dataChanged();
    return true;
}

QVariantMap SchoolApp::hrDashboard() const
{
    QVariantMap out;
    if (!can("hr.manage") && !can("hr.payroll")) return out;
    QSqlQuery a(m_db.db());
    a.exec("SELECT COUNT(*) FROM hr_employees WHERE status='actif'");
    out["activeEmployees"] = a.next() ? a.value(0).toInt() : 0;
    QSqlQuery l(m_db.db());
    l.exec("SELECT COUNT(*) FROM hr_leaves WHERE status='en attente'");
    out["pendingLeaves"] = l.next() ? l.value(0).toInt() : 0;
    QSqlQuery pr(m_db.db());
    pr.prepare("SELECT COUNT(*) FROM hr_attendance WHERE day=? AND status IN ('present','late')");
    pr.addBindValue(QDate::currentDate().toString("yyyy-MM-dd"));
    out["presentToday"] = pr.exec() && pr.next() ? pr.value(0).toInt() : 0;
    QSqlQuery vp(m_db.db());
    vp.exec("SELECT COUNT(DISTINCT period) FROM payroll_runs");
    out["validatedPeriods"] = vp.next() ? vp.value(0).toInt() : 0;
    return out;
}

QVariantList SchoolApp::hrHistory(int limit) const
{
    QVariantList out;
    if (!can("hr.manage") && !can("hr.payroll")) return out;
    QSqlQuery q(m_db.db());
    q.prepare("SELECT a.created_at,COALESCE(u.name,'Système'),a.action,a.details FROM audit_logs a "
              "LEFT JOIN users u ON u.id=a.user_id WHERE a.entity LIKE 'hr_%' ORDER BY a.id DESC LIMIT ?");
    q.addBindValue(limit > 0 ? limit : 200);
    if (!q.exec()) return out;
    while (q.next()) {
        QVariantMap m;
        m["createdAt"] = q.value(0).toString();
        m["user"] = q.value(1).toString();
        m["action"] = q.value(2).toString();
        m["details"] = q.value(3).toString();
        out << m;
    }
    return out;
}

bool SchoolApp::financeVisible(int studentId) const
{
    return can("balances.view") || (canViewStudent(studentId) && !can("students.view"));
}

bool SchoolApp::isPaymentVisible(int paymentId) const
{
    QSqlQuery q(m_db.db());
    q.prepare("SELECT student_id FROM payments WHERE id=?");
    q.addBindValue(paymentId);
    return q.exec() && q.next() && financeVisible(q.value(0).toInt());
}

QString SchoolApp::importPhoto(const QString &fileUrl) const
{
    if (m_userId <= 0) return QString();
    const QUrl url(fileUrl);
    const QString local = url.isLocalFile() ? url.toLocalFile() : fileUrl;
    QImage img(local);
    if (img.isNull()) return QString();
    if (img.width() > 400 || img.height() > 400)
        img = img.scaled(400, 400, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    const QString dirPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/photos");
    QDir().mkpath(dirPath);
    const QString target = dirPath + QStringLiteral("/") + QUuid::createUuid().toString(QUuid::WithoutBraces) + QStringLiteral(".jpg");
    if (!img.save(target, "JPG", 85)) return QString();
    return target;
}

QString SchoolApp::photoUrl(const QString &path) const
{
    if (path.trimmed().isEmpty() || !QFile::exists(path)) return QString();
    return QUrl::fromLocalFile(path).toString();
}

QString SchoolApp::myPhoto() const
{
    if (m_userId <= 0) return QString();
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COALESCE(photo,'') FROM users WHERE id=?");
    q.addBindValue(m_userId);
    return q.exec() && q.next() ? q.value(0).toString() : QString();
}

bool SchoolApp::setMyPhoto(const QString &path)
{
    if (m_userId <= 0) return false;
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE users SET photo=? WHERE id=?");
    q.addBindValue(path.trimmed().isEmpty() ? QVariant() : QVariant(path));
    q.addBindValue(m_userId);
    if (!q.exec()) return false;
    audit("update", "user_photo", m_userId, path.trimmed().isEmpty() ? QStringLiteral("retirée") : QStringLiteral("modifiée"));
    emit dataChanged();
    return true;
}

QString SchoolApp::studentPhotoPath(int studentId) const
{
    if (!canViewStudent(studentId)) return QString();
    QSqlQuery q(m_db.db());
    q.prepare("SELECT COALESCE(photo,'') FROM students WHERE id=?");
    q.addBindValue(studentId);
    return q.exec() && q.next() ? q.value(0).toString() : QString();
}

bool SchoolApp::deleteUser(int id)
{
    if (!can("users.manage")) return false;
    if (id == m_userId) {
        emit errorOccurred(QStringLiteral("Vous ne pouvez pas supprimer votre propre compte."));
        return false;
    }
    QSqlQuery role(m_db.db());
    role.prepare("SELECT role FROM users WHERE id=? AND deleted_at IS NULL");
    role.addBindValue(id);
    if (!role.exec() || !role.next()) {
        emit errorOccurred(QStringLiteral("Utilisateur introuvable."));
        return false;
    }
    if (role.value(0).toString() == QLatin1String("administrateur")) {
        QSqlQuery admins(m_db.db());
        admins.prepare("SELECT COUNT(*) FROM users WHERE role='administrateur' AND deleted_at IS NULL AND id<>?");
        admins.addBindValue(id);
        if (!admins.exec() || !admins.next() || admins.value(0).toInt() == 0) {
            emit errorOccurred(QStringLiteral("Impossible : c'est le dernier administrateur."));
            return false;
        }
    }
    QSqlQuery q(m_db.db());
    q.prepare("UPDATE users SET deleted_at=CURRENT_TIMESTAMP, account_status='blocked', blocked_reason='Compte supprimé' WHERE id=? AND deleted_at IS NULL");
    q.addBindValue(id);
    if (!q.exec() || q.numRowsAffected() != 1) {
        emit errorOccurred(q.lastError().text().isEmpty() ? QStringLiteral("Suppression impossible.") : q.lastError().text());
        return false;
    }
    audit("delete", "user", id);
    emit dataChanged();
    return true;
}

QString SchoolApp::teacherQrText(int userId) const
{
    if (!(can("teachers.manage") || can("students.view"))) return QString();
    QSqlQuery q(m_db.db());
    q.prepare("SELECT u.name,u.email,COALESCE(t.subject,''),COALESCE(t.contact,'') FROM users u "
              "LEFT JOIN teacher_profiles t ON t.user_id=u.id WHERE u.id=? AND u.deleted_at IS NULL");
    q.addBindValue(userId);
    if (!q.exec() || !q.next()) return QString();
    return QStringLiteral("ESCATO GS - ENSEIGNANT\nNom : %1\nMatière : %2\nContact : %3\nE-mail : %4")
        .arg(q.value(0).toString(), q.value(2).toString(), q.value(3).toString(), q.value(1).toString());
}

QString SchoolApp::qrCodePngDataUrl(const QString &text) const
{
    const QString t = text.trimmed();
    if (t.isEmpty()) return QString();
    const qrcodegen::QrCode qr = qrcodegen::QrCode::encodeText(t.toUtf8().constData(), qrcodegen::QrCode::Ecc::MEDIUM);
    const int border = 4;
    const int size = qr.getSize();
    QImage img(size + 2 * border, size + 2 * border, QImage::Format_RGB32);
    img.fill(Qt::white);
    for (int y = 0; y < size; ++y)
        for (int x = 0; x < size; ++x)
            if (qr.getModule(x, y)) img.setPixel(x + border, y + border, qRgb(0, 0, 0));
    img = img.scaled(img.width() * 6, img.height() * 6, Qt::KeepAspectRatio, Qt::FastTransformation);
    QByteArray bytes;
    QBuffer buffer(&bytes);
    buffer.open(QIODevice::WriteOnly);
    img.save(&buffer, "PNG");
    return QStringLiteral("data:image/png;base64,") + QString::fromLatin1(bytes.toBase64());
}
