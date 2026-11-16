# C-KC-02 — Câmpuri Personal Info read-only și schimbarea parolei Active Directory

| Metadate | Valoare |
|---|---|
| Serviciu | Keycloak — Identity & SSO |
| Încadrare | **02 – Configurare → Keycloak → LDAP / User Profile** |
| Platformă | Keycloak **26.6.2**, realm `AD` |
| Sursă identități | Active Directory prin LDAP User Federation |
| Configurație actuală | `Edit Mode = WRITABLE`; utilizatorilor li s-a restricționat modificarea atributelor personale |
| Revizie | 1.0 — 16.11.2026 |
| Stare | Configurație aplicată și testată funcțional în mediul curent |
| Clasificare | Intern — administrare IT |

## 1. Scop

Permiterea **schimbării parolei Active Directory din Keycloak**, cu păstrarea datelor personale (`username`, `firstName`, `lastName`, `email`) ca informații vizibile, dar **nemodificabile de utilizator** din Account Console și din fluxurile standard Keycloak.

### Comportamentul urmărit

| Operație | Utilizator final |
|---|---|
| Consultare nume, prenume, email | Permisă |
| Modificare nume, prenume, email | Interzisă |
| Modificare username | Interzisă |
| Schimbare parolă AD | Permisă, conform politicii AD |
| Autentificare SSO Kerberos | Neschimbată |
| Actualizare date de identitate din AD | Permisă prin mecanismele de sincronizare configurate |

**Distincție importantă:** `LDAP Edit Mode = WRITABLE` permite în principiu operații de scriere în AD. Interzicerea editării profilului de către utilizator trebuie configurată separat în **User Profile** și, după necesități, în mapperele LDAP și drepturile efective din AD.

## 2. Condiții preliminare și măsuri de siguranță

1. Identificați providerul LDAP corect în **User Federation**.
2. Folosiți **LDAPS sau LDAP cu StartTLS**, cu validarea certificatului serverului AD.
3. Contul AD pentru integrare nu trebuie să aibă privilegii generale de modificare a identităților; delegați strict drepturile necesare fluxului de schimbare/resetare parolă și verificați operațiile efective în AD.
4. Salvați configurația LDAP, mapperelor și schema **Realm Settings → User Profile** (din JSON Editor, ca evidență/versionare), fără a publica secrete.
5. Testați pe un utilizator AD dedicat, înainte de aplicare generală. La modificări cu impact, verificați backupul bazei **externe** Keycloak; snapshotul VM-ului SSO nu include acea bază.

## 3. Configurarea LDAP pentru schimbarea parolei

1. În Keycloak Admin Console, selectați realm-ul **`AD`**.
2. Deschideți **User Federation → [providerul LDAP] → Settings**.
3. Setați **Edit Mode = `WRITABLE`** și salvați.
4. Păstrați configurațiile funcționale pentru import, Kerberos, sincronizare și mappere.
5. Testați schimbarea parolei unui cont AD de test din Account Console.

**Nu folosiți `UNSYNCED` dacă obiectivul este schimbarea efectivă a parolei în Active Directory**: în acest mod actualizările pot rămâne în stocarea locală Keycloak. În modul `READ_ONLY`, actualizarea parolei LDAP nu este disponibilă.

**Atenție:** dacă providerul a fost creat în `READ_ONLY` și modificat ulterior în `WRITABLE`, configurațiile mapperelor LDAP **nu se rescriu automat**. Verificați-le punctual (pasul 5).

## 4. Blocarea modificărilor în User Profile

1. Navigați la **Realm Settings → User Profile → Attributes**.
2. Deschideți fiecare atribut relevant: `username`, `firstName`, `lastName`, `email` (denumirile din listă pot avea etichete afișate diferite).
3. În **Permissions**, configurați:

| Setare | Valoare |
|---|---|
| **Who can view** | `User` și `Admin` |
| **Who can edit** | Numai `Admin` |

4. Salvați fiecare atribut.
5. În **Realm Settings → Login**, verificați că **Edit username** este dezactivat, dacă opțiunea este prezentă în configurația realm-ului.
6. Revizuiți și eventualele atribute personalizate AD expuse în Personal Info: restricțiile trebuie aplicate și acestor câmpuri, dacă nu trebuie modificate de utilizatori.

Această configurație permite utilizatorului să își vadă datele, dar împiedică actualizarea lor prin fluxurile standard care respectă schema User Profile. Nu modificați aici configurarea pentru schimbarea parolei: parola este gestionată separat, ca o credențială, nu ca atribut obișnuit de profil.

### Exemplu orientativ din JSON Editor

```json
{
  "name": "email",
  "permissions": {
    "view": ["user", "admin"],
    "edit": ["admin"]
  }
}
```

**Atenție:** fragmentul reprezintă **un singur atribut**, nu întreaga configurație JSON a User Profile. Nu înlocuiți configurația completă cu acest fragment.

## 5. Verificarea mapperelor LDAP

În **User Federation → LDAP → Mappers**, examinați mapper-ele folosite pentru `username`, `first name`, `last name`, `email` și pentru eventualele câmpuri suplimentare. În mediul actual a fost identificat și un mapper `username-cn` către `username`; acesta trebuie inventariat și verificat înainte de orice modificare, deoarece pot exista mai multe surse LDAP pentru același câmp Keycloak.

Pentru mapper-ele de tip **User Attribute LDAP Mapper**, examinați **Read Only**:

- `Read Only = ON` blochează operațiile de scriere a acelui atribut prin mapperul respectiv către LDAP, acolo unde opțiunea este disponibilă.
- Verificați separat că **citirea și sincronizarea din AD** continuă să funcționeze.
- Nu modificați în bloc toate mapper-ele; unele au roluri speciale (Kerberos, grupuri, starea contului etc.).
- Opțiunea de mapper **nu înlocuiește** permisiunile User Profile; cele două măsuri se completează.

**Recomandare de guvernanță:** pentru datele administrative de identitate, AD rămâne sursa autorizată. Schimbările de nume/email se fac în AD, apoi se preiau în Keycloak prin LDAP Sync.

## 6. Verificarea funcțională

Cu un utilizator AD de test:

1. Deschideți **Account Console → Personal Info** și verificați că datele personale sunt vizibile, fără opțiunea de modificare sau cu câmpurile marcate read-only.
2. Încercați în condiții controlate modificarea unui atribut personal și verificați că operația este respinsă și că AD rămâne neschimbat.
3. Deschideți **Account Security → Signing in → Password → Update**.
4. Verificați pagina de schimbare a parolei cu design `sts.v1` (consultați [C-KC-01 — Configurarea temei](./01-Configurare-tema-STS-pe-clienti.md)).
5. Schimbați parola contului de test; validați conectarea cu parola nouă și respectarea politicii AD.
6. Verificați că SSO Kerberos, grupurile/rolurile și atributele sincronizate continuă să funcționeze.
7. Confirmați că nu s-au modificat numele/emailul/username-ul în AD după test.

### Checklist de acceptanță

- [ ] Contul AD poate modifica parola prin Keycloak.
- [ ] Schimbarea parolei se reflectă efectiv în Active Directory.
- [ ] `username`, `firstName`, `lastName`, `email` nu sunt editabile de utilizator.
- [ ] Nici un atribut personal suplimentar expus în profil nu este editabil neautorizat.
- [ ] Administratorii cunosc faptul că editarea din Admin Console poate fi guvernată diferit.
- [ ] Autentificarea SSO și fluxurile OTP nu sunt afectate.
- [ ] Pagina de `UPDATE_PASSWORD` afișează tema `sts.v1` pe clientul `account-console`.

## 7. Cache, sesiuni și sincronizare

Modificările de **User Profile**, **Edit Mode** și ale mapperelor ar trebui să fie aplicate după salvare. Pentru simpla schimbare a acestor setări **nu se execută automat** `clear-user-cache`, `clear-realm-cache`, LDAP Full Sync sau restartul Keycloak.

- Folosiți sesiune nouă de browser pentru a evita confuzia cu interfața deja încărcată.
- Dacă a fost schimbat un atribut **în AD**, iar Keycloak încă arată valoarea veche, utilizați procedura **P-KC-05 — Sincronizare imediată AD și invalidarea cache-ului** (link Outline de completat manual).
- Comanda `clear-user-cache` invalidează cache-ul utilizatorilor; nu este o comandă de logout și nu înlocuiește LDAP Sync.

## 8. Revenire / rollback

Dacă apar probleme cu actualizarea parolei sau cu profilul:

1. Restaurați configurația User Profile/LDAP Mapper din exportul salvat, **numai pentru câmpurile afectate**.
2. Reveniți temporar la `READ_ONLY` doar dacă este necesară blocarea scrierilor în AD și acceptați pierderea funcției de schimbare a parolei prin Keycloak.
3. Revizuiți drepturile AD și logurile Keycloak; **nu relaxați drepturile în AD pentru a ocoli erorile de autorizare**.
4. Repetați testele pentru profil și parolă după remediere.

## 9. Documente conexe

- [C-KC-01 — Configurarea temei STS pe clienți](./01-Configurare-tema-STS-pe-clienti.md)
- **P-KC-02 — Invalidarea cache-ului** (link Outline de completat manual)
- **P-KC-03 — Mapper Kerberos LDAP** (link Outline de completat manual)
- **P-KC-05 — Sincronizare imediată AD și cache** (link Outline de completat manual)
- [Înapoi la indexul de configurare](./00-Index-configurare-Keycloak.md)

## 10. Referințe oficiale

- [Keycloak — Server Administration Guide 26.6: LDAP Edit Mode, LDAP Mappers, User Profile](https://www.keycloak.org/docs/26.6.4/server_admin/)
- [Keycloak — Working with themes](https://www.keycloak.org/ui-customization/themes)

> **Notă pentru Outline:** după import, înlocuiți legăturile către procedurile `P-KC-xx` cu adresele lor interne în Outline.
