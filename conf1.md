# C-KC-01 — Configurarea temei STS pe clienții Keycloak

| Metadate | Valoare |
|---|---|
| Serviciu | Keycloak — Identity & SSO |
| Încadrare | **02 – Configurare → Keycloak → Teme și interfață** |
| Platformă | Keycloak **26.6.2**, Linux nativ, serviciu `systemd` |
| Realm | `AD` |
| Tema utilizată | `sts.v1` — doar tipul **login** |
| Revizie | 1.0 — 16.11.2026 |
| Stare | Configurație aplicată și validată funcțional în mediul curent |
| Clasificare | Intern — administrare IT |

## 1. Scop

Configurarea temei personalizate **`sts.v1`** doar pentru aplicațiile selectate din realm-ul `AD`, fără schimbarea temei de login implicite pentru toate aplicațiile. Configurarea clientului **`account-console`** asigură utilizarea paginii STS pentru fluxul de schimbare a parolei (`UPDATE_PASSWORD`).

## 2. Arhitectura și limitele temei

- Instalarea activă Keycloak: `/opt/keycloak`.
- Tema este furnizată ca JAR: `/opt/keycloak/providers/keycloak-sts-themes-1.0.0-26.6.2.jar`.
- Descriptorul din JAR este `META-INF/keycloak-themes.json`, cu `name=sts.v1` și `types=["login"]`.
- Tema conține, între altele, `login-update-password.ftl` (schimbare parolă prin required action) și `login-reset-password.ftl` (flux de recuperare parolă).
- **Nu conține o temă de tip `account`**. Paginile generale `Personal Info`, `Account Security` și `Sessions` rămân în tema Account Console configurată la nivel de realm; numai paginile de login/required actions pot folosi designul STS.
- Alegerea temei este **independentă** de `Browser Flow`: clientul poate folosi `browser` sau `browser-no-kerberos`, conform cerințelor SSO.

## 3. Condiții preliminare

1. Administrare Keycloak în realm-ul `AD`.
2. JAR-ul temei este instalat și vizibil în Keycloak la selecția temei `Login theme`.
3. Se cunosc clienții cărora li se aplică tema.
4. Se notează **valoarea anterioară** a câmpului `Login theme` pentru fiecare client înainte de modificare.

## 4. Activarea temei pentru un client selectat

1. În Admin Console, selectați realm-ul **`AD`**.
2. Navigați la **Clients → [clientul dorit] → Settings**.
3. Identificați câmpul **Login theme** (poate fi în secțiunea de setări de login).
4. Selectați **`sts.v1`** și apăsați **Save**.
5. Accesați aplicația într-o sesiune nouă de browser și verificați pagina de autentificare.
6. Repetați numai pentru clienții aprobați. **Nu modificați `Realm Settings → Themes → Login theme`** dacă nu doriți aplicarea la întreg realm-ul.

### Matrice de configurare

| Domeniu de aplicare | Setare | Efect |
|---|---|---|
| Realm `AD` | Login theme: tema implicită existentă | Neschimbată pentru majoritatea aplicațiilor |
| Client selectat | Login theme: `sts.v1` | Formular de autentificare STS |
| Client fără override | Login theme nesetat | Moștenește tema de login a realm-ului |
| Client `account-console` | Login theme: `sts.v1` | Design STS în paginile de login / `UPDATE_PASSWORD` lansate prin acest client |

## 5. Configurarea specială pentru schimbarea parolei

1. Navigați la **Clients → `account-console` → Settings**.
2. La **Login theme**, selectați `sts.v1` și salvați.
3. Ca utilizator AD de test, intrați în **Account Console → Account Security → Signing in → Password → Update**.
4. Verificați că formularul de schimbare a parolei folosește designul STS și că schimbarea efectivă funcționează.

**Explicație:** operația inițiază fluxul `UPDATE_PASSWORD`, care folosește pagina de login/required action din temă. Configurarea `account-console` **nu personalizează toate paginile Account Console**.

## 6. Instalarea temei pe un server nou (doar dacă lipsește)

Acest pas **nu trebuie repetat** dacă JAR-ul este deja instalat și funcțional. Copierea unui JAR de temă nu este upgrade de versiune al serverului Keycloak.

```bash
# Se execută într-o fereastră de mentenanță, cu fișierul JAR verificat
systemctl stop keycloak

install -o keycloak -g keycloak -m 0644 \
  keycloak-sts-themes-1.0.0-26.6.2.jar \
  /opt/keycloak/providers/keycloak-sts-themes-1.0.0-26.6.2.jar

# Comanda build trebuie rulată cu un cont cu permisiuni suficiente
sudo -u keycloak /opt/keycloak/bin/kc.sh build
systemctl start keycloak
journalctl -u keycloak -n 100 --no-pager
```

Pentru un serviciu `systemd` particularizat, verificați mai întâi `systemctl cat keycloak`; operația de `build` poate necesita utilizatorul/proprietarul instalării și permisiuni suplimentare. Înainte de a copia o versiune nouă, faceți backup la JAR-ul existent. Nu instalați simultan două JAR-uri care declară aceeași temă `sts.v1`.

## 7. Validare

- [ ] Tema `sts.v1` apare în lista **Login theme** a clienților.
- [ ] Un client cu `sts.v1` afișează autentificarea STS.
- [ ] Un client fără override folosește în continuare tema sa anterioară.
- [ ] `account-console` afișează pagina STS la **Update password**.
- [ ] Schimbarea parolei AD funcționează și nu alterează setările de profil read-only.
- [ ] SSO Kerberos și `browser-no-kerberos` funcționează conform configurării fiecărui client.

## 8. Revenire și diagnostic

**Revenire simplă:** în **Clients → client → Settings**, restabiliți vechea valoare `Login theme` și salvați. Nu este necesară eliminarea JAR-ului pentru a reveni la aspectul anterior pe un client.

Dacă tema nu este disponibilă:

```bash
ls -l /opt/keycloak/providers/*sts*.jar
unzip -p /opt/keycloak/providers/keycloak-sts-themes-1.0.0-26.6.2.jar META-INF/keycloak-themes.json
journalctl -u keycloak -n 100 --no-pager
```

Verificați permisiunile, descriptorul temei, încărcarea providerului și instalarea `systemd` folosită efectiv. Modificarea **selecției temei pe client** nu necesită rebuild, restart, Full Sync sau `clear-user-cache`.

## 9. Documente conexe

- [C-KC-02 — Câmpuri Personal Info read-only și schimbarea parolei AD](./02-Configurare-Personal-Info-read-only-si-parola-AD.md)
- **P-KC-01 — Autentificare CLI cu `kcadm.sh`** (link Outline de completat manual)
- **P-KC-02 — Invalidarea cache-ului** (link Outline de completat manual)
- [Înapoi la indexul de configurare](./00-Index-configurare-Keycloak.md)

## 10. Referințe

- [Keycloak — Working with themes](https://www.keycloak.org/ui-customization/themes)
- [Keycloak — Server Administration Guide 26.6](https://www.keycloak.org/docs/26.6.4/server_admin/)

> **Notă pentru Outline:** linkurile relative funcționează între fișierele Markdown. Dacă importul nu le convertește în linkuri interne, înlocuiți-le cu linkurile documentelor din Outline.
