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
