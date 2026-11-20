# Jira – Încărcare intermitentă a paginilor din cauza conectivității către propriul FQDN

**Categorie:** 05 – Incidente/Probleme  
**Data incidentului:** 20.11.2026  
**Sistem:** Atlassian Jira  
**Status:** Funcționare normală observată după intervenție; monitorizare recomandată

---

## 1. Descrierea incidentului

Anumiți utilizatori au raportat încărcarea foarte lentă sau blocarea intermitentă a paginilor Jira, în special a paginii Dashboard.

**Simptome observate:**

- Browserul afișa o pagină complet albă pentru 10–30 de secunde sau chiar mai mult.
- Uneori încărcarea se bloca pentru câteva minute.
- După o încărcare reușită, accesările următoare funcționau normal.
- Problema apărea intermitent, uneori după câteva ore de funcționare normală.
- Nu toți utilizatorii erau afectați.
- Problema a fost observată atât în Google Chrome, cât și în Mozilla Firefox.
- Ștergerea cache-ului sau resetarea conexiunilor browserului nu constituiau o rezolvare permanentă.

Comportamentul inițial sugera o problemă locală de browser, însă analiza ulterioară a identificat timeouturi în infrastructura Jira.

## 2. Arhitectura relevantă

Fluxul normal de acces:

```text
Utilizator
    |
    | HTTPS :443
    v
jira.stsnet.ro
    |
    v
VIP Nginx / Keepalived
10.190.80.250
    |
    | HTTP :8080
    v
Server Jira
172.20.9.12
```

În plus față de accesul utilizatorilor, anumite componente Jira efectuează cereri HTTP/HTTPS către **propriul Base URL**.

Fluxul respectiv:

```text
Server Jira (172.20.9.12)
    |
    | HTTPS :443
    v
jira.stsnet.ro
    |
    v
VIP Nginx (10.190.80.250)
    |
    | HTTP :8080
    v
Server Jira (172.20.9.12)
```

Acest acces intern la propriul FQDN trebuie să fie funcțional pentru componentele care utilizează cereri HTTP către Base URL.

## 3. Cele două scenarii de funcționare

### Scenariul A – Încărcare normală

```text
Browser
   |
   v
Nginx
   |
   v
Jira
   |
   | Generează pagina
   | Fără apel intern problematic
   v
Nginx
   |
   v
Browser – Pagina se încarcă imediat
```

În acest scenariu, Jira poate genera și transmite răspunsul folosind resurse deja disponibile sau fără efectuarea unui apel HTTP intern care să se blocheze.

**Rezultat:** pagina este afișată rapid.

### Scenariul B – Încărcare blocată

```text
Browser
   |
   v
Nginx
   |
   v
Jira
   |
   | Începe generarea Dashboard-ului
   | O componentă solicită resurse interne
   v
jira.stsnet.ro:443
   |
   v
IP vechi / inaccesibil
10.190.13.250
   |
   X Connection timed out
   |
   v
Întârziere / eroare în componenta Jira
   |
   v
Răspuns incomplet către browser
```

În acest scenariu, o componentă Jira efectuează un apel HTTP către propriul FQDN, dar conexiunea nu poate fi stabilită.

Un astfel de timeout poate întârzia procesarea cererii și poate contribui la încărcarea incompletă a paginii.

**Rezultat:** utilizatorul poate observa o pagină albă sau un timp mare de încărcare.

*Notă tehnică:* Cele două scenarii descriu mecanismul posibil al incidentului. Logurile au confirmat atât blocarea răspunsurilor HTML, cât și eșecul apelurilor interne Jira, însă nu au demonstrat că fiecare răspuns HTML blocat a fost provocat exclusiv de `gadget.activity.stream`.

## 4. Rolul componentei `gadget.activity.stream`

În timpul investigației au fost identificate erori asociate mecanismului de încărcare a resurselor pentru gadgeturile Jira, inclusiv **Activity Stream**.

Acest gadget afișează activitățile recente din Jira și utilizează resurse și servicii interne ale aplicației.

În logul Jira a apărut o cerere către:

```text
/jira/rest/gadgets/1.0/g/messagebundle/und/
gadget.common%2Cgadget.activity.stream
```

Componenta implicată în efectuarea cererii HTTP:

```text
c.a.g.r.internal.http.HttpClientFetcher
```

Eroarea identificată:

```text
org.apache.http.conn.ConnectTimeoutException:

Connect to jira.stsnet.ro:443
[jira.stsnet.ro/10.190.13.250]
failed: Connection timed out
```

Această eroare confirmă că Jira încerca să acceseze propriul FQDN folosind o adresă IP care nu mai era accesibilă.

**De ce nu erau afectați toți utilizatorii?**

Explicații posibile:

- Utilizatorii pot avea Dashboard-uri cu gadgeturi diferite.
- Unele resurse pot fi deja disponibile în cache.
- Nu fiecare accesare declanșează aceleași apeluri interne.
- Cererile pot fi efectuate la momente diferite, în funcție de starea componentelor și a sesiunilor.

Prin urmare, problema poate afecta selectiv anumite pagini sau utilizatori, chiar dacă infrastructura Jira este comună.

## 5. Investigație și diagnostic

### 5.1. Chrome – Developer Tools

În Chrome:

1. Se deschide `F12 → Network`.
2. Se activează **Preserve log**.
3. Se reproduce problema.
4. Se selectează cererea `Dashboard.jspa`.
5. Se verifică fila **Timing**.

În incidentul analizat:

- `Queueing` și `Stalled` aveau durate foarte mici.
- `Waiting for server response` era foarte scurt.
- Întârzierea apărea la `Content download`.
- Browserul primise începutul răspunsului HTTP, dar transferul nu se finaliza.

Au fost utilizate și capturi `chrome://net-export/` pentru corelarea evenimentelor.

### 5.2. Nginx – Access log

În logurile Nginx s-au identificat cereri către `/jira/` și `/jira/secure/Dashboard.jspa` cu durate anormal de mari.

Exemplu:

```text
GET /jira/secure/Dashboard.jspa HTTP/1.1
Status:                 200
request_time:           300.009
upstream_response_time: 300.010
body_bytes_sent:        7902
upstream:               172.20.9.12:8080
```

Deși statusul HTTP era `200`, răspunsul nu se finalizase corect.

**Un status HTTP 200 nu garantează că întregul conținut a fost transmis.** Antetele pot fi deja trimise înainte de apariția unui timeout.

### 5.3. Nginx – Error log

Fișierul analizat:

```bash
/var/log/nginx/jira.stsnet.ro_error.log
```

Comandă:

```bash
tail -f /var/log/nginx/jira.stsnet.ro_error.log
```

Eroarea identificată:

```text
upstream timed out (110: Connection timed out)
while reading upstream

upstream:
http://172.20.9.12:8080/jira/secure/Dashboard.jspa
```

Această eroare confirmă că Nginx aștepta date suplimentare de la upstream-ul Jira și a depășit intervalul permis.

### 5.4. Jira – Application log

Fișier uzual:

```bash
/var/atlassian/application-data/jira/log/atlassian-jira.log
```

Căutare:

```bash
grep -iE \
'ConnectTimeoutException|HttpClientFetcher|gadget.activity.stream' \
/var/atlassian/application-data/jira/log/atlassian-jira.log
```

În timpul incidentului au fost identificate erori `ConnectTimeoutException` la accesarea `jira.stsnet.ro:443`.

Acestea au orientat investigația către rezolvarea DNS locală și conectivitatea serverului Jira.

## 6. Cauza identificată

Pe serverul Jira, în fișierul `/etc/hosts`, exista o înregistrare veche:

```text
10.190.13.250 jira.stsnet.ro
```

Adresa reprezenta fostul Nginx utilizat pentru publicarea aplicației.

După migrarea infrastructurii reverse proxy, noua adresă devenise:

```text
10.190.80.250 jira.stsnet.ro
```

S-au identificat două probleme de configurare:

**1. Înregistrare locală învechită**

Serverul Jira rezolva propriul FQDN către vechiul IP.

**2. Conectivitate HTTPS indisponibilă**

Din serverul Jira nu se putea stabili o conexiune TCP/443 nici către vechiul IP, nici către noul VIP.

Prin urmare, simpla schimbare a înregistrării DNS/hosts nu era suficientă. Era necesară și asigurarea conectivității către noua adresă.

## 7. Procedura de remediere

### Pasul 1 – Verificarea rezolvării numelui

Pe serverul Jira:

```bash
getent ahostsv4 jira.stsnet.ro
```

Se verifică și fișierul:

```bash
grep -n 'jira.stsnet.ro' /etc/hosts
```

Rezultatul așteptat este adresa corectă a serviciului.

### Pasul 2 – Verificarea conectivității HTTPS

```bash
nc -vz -w 5 10.190.80.250 443
```

Se testează și ruta:

```bash
ip route get 10.190.80.250
```

Dacă TCP/443 nu este accesibil, se verifică politicile firewall, rutarea și accesibilitatea VIP-ului Nginx din rețeaua serverului Jira.

Flux necesar:

```text
Sursă:       172.20.9.12
Destinație:  10.190.80.250
Protocol:    TCP
Port:        443
```

### Pasul 3 – Testarea serviciului HTTPS

Fără modificarea `/etc/hosts`:

```bash
curl -vk --noproxy '*' \
  --resolve jira.stsnet.ro:443:10.190.80.250 \
  --connect-timeout 5 \
  --max-time 15 \
  https://jira.stsnet.ro/jira/
```

Se verifică stabilirea conexiunii TLS și primirea unui răspuns HTTP valid. O redirecționare către autentificare poate fi normală.

### Pasul 4 – Actualizarea `/etc/hosts`

După confirmarea conectivității:

```bash
sudo cp -a /etc/hosts /etc/hosts.bak
sudo vi /etc/hosts
```

Se înlocuiește înregistrarea veche cu:

```text
10.190.80.250 jira.stsnet.ro
```

Nu trebuie să rămână o altă înregistrare contradictorie pentru același FQDN.

Se verifică din nou rezolvarea numelui.

### Pasul 5 – Verificarea cache-ului DNS Java

JVM poate păstra în cache rezolvările DNS.

După actualizarea fișierului `/etc/hosts`, trebuie verificat dacă procesul Jira începe să utilizeze noua adresă.

Dacă JVM continuă să folosească vechiul IP, se planifică repornirea Jira într-o fereastră de mentenanță, după evaluarea configurației de DNS caching.

## 8. Validarea remedierii

După corectarea configurației, se verifică:

- Accesarea Dashboard-ului în Chrome și Firefox.
- Accesarea Jira după o perioadă mai lungă de inactivitate.
- Funcționarea gadgeturilor, inclusiv Activity Stream.
- Absența erorilor noi `ConnectTimeoutException` către vechiul IP.
- Absența timeouturilor `while reading upstream` pentru cererile Dashboard.
- Timpii `request_time` și `upstream_response_time` din Nginx.

Validarea trebuie efectuată de pe mai multe stații și, preferabil, cu utilizatori care au Dashboard-uri diferite.

**Rezultat observat:** după intervenție, Jira a funcționat normal la testele efectuate. Monitorizarea este necesară pentru confirmarea stabilității în timp.

## 9. Măsuri preventive

Pentru evitarea reapariției incidentului:

1. După migrarea unui reverse proxy sau VIP, se verifică toate înregistrările locale din `/etc/hosts`.
2. Se verifică accesul serverului aplicației la propriul Base URL.
3. Se verifică separat conectivitatea TCP și răspunsul HTTPS.
4. Se testează Dashboard-urile cu gadgeturi care fac cereri HTTP interne.
5. Se monitorizează în Jira apariția erorilor `ConnectTimeoutException`.
6. Se monitorizează în Nginx timeouturile către upstream.
7. Nu se măresc timeouturile Nginx ca soluție implicită fără identificarea operației care blochează transferul.

## 10. Concluzie

Incidentul a evidențiat o configurație învechită de rezolvare locală a numelui și lipsa conectivității HTTPS dinspre serverul Jira către propriul FQDN.

Erorile `HttpClientFetcher` și `gadget.activity.stream` au oferit indiciul decisiv pentru identificarea apelurilor interne eșuate.

**Lecția principală:** funcționarea accesului Browser → Nginx → Jira nu garantează și funcționarea accesului Jira → propriul Base URL.

Ambele trasee trebuie verificate la orice migrare a infrastructurii de publicare a aplicației.
