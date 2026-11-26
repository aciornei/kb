# CHG – Securizarea autentificării OpenLDAP către Active Directory (LDAP → LDAPS)

## 1. Identificarea schimbării

| Câmp | Valoare |
|---|---|
| Serviciu | OpenLDAP |
| Componentă | Cyrus SASL – saslauthd |
| Tip schimbare | Normală – securitate / configurare |
| Mediu | De completat |
| Server OpenLDAP | De completat |
| Data implementării | De completat |
| Responsabil | De completat |
| Status | De completat |
| Risc estimat | Mediu – impact potențial asupra autentificării |

## 2. Scopul schimbării

Migrarea comunicației dintre serviciul `saslauthd` și serverele Active Directory de la LDAP (TCP/389) la LDAPS (TCP/636), cu verificarea certificatului TLS al serverelor de autentificare.

Obiective:

- Criptarea traficului de autentificare dintre `saslauthd` și Active Directory.
- Validarea identității Domain Controllerelor prin certificatul CA de încredere.
- Eliminarea conexiunilor LDAP pe TCP/389 inițiate de `saslauthd` către cele două Domain Controllere.
- Menținerea funcționalității autentificării prin OpenLDAP.

## 3. Situația existentă și configurația țintă

| Parametru | Înainte | După |
|---|---|---|
| Protocol către AD | LDAP | LDAPS |
| DC1 | `ldap://dc1.sts.nest:389` | `ldaps://dc1.sts.nest:636` |
| DC2 | `ldap://dc2.sts.nest:389` | `ldaps://dc2.sts.nest:636` |
| Versiune LDAP | De verificat | 3 |
| StartTLS | `no` | `no` (TLS implicit prin LDAPS) |
| Validare certificat | Nu se aplică pentru LDAP necriptat | Activată |
| Certificat CA | — | `/etc/ssl/certs/ad-rootca.cer` |

Fluxul de autentificare după schimbare:

```text
Aplicații / utilizatori
        |
        v
OpenLDAP (slapd)
        |
        | Unix socket SASL
        v
saslauthd
        |
        | LDAPS / TCP 636
        +----> dc1.sts.nest
        +----> dc2.sts.nest
```

Schimbarea vizează exclusiv conexiunea `saslauthd` → Active Directory. Protocolul folosit de aplicații pentru conectarea la OpenLDAP, schema LDAP, baza de căutare și contul de serviciu nu se modifică. Criptarea conexiunilor aplicațiilor către OpenLDAP nu este asigurată de această schimbare.

## 4. Impact și riscuri

- Restartul `saslauthd` poate produce o întrerupere scurtă a autentificărilor care depind de acesta.
- Nu este necesar, în mod normal, restartul serviciului `slapd`.
- Dacă portul 636 este inaccesibil, certificatul nu este valid sau lanțul CA este incomplet, autentificarea poate eșua.
- Disponibilitatea ambelor Domain Controllere trebuie verificată individual.
- Blocarea portului 389 în firewall nu face parte din această schimbare; se poate trata separat după verificarea altor dependențe.

## 5. Verificări preliminare

Toate comenzile se execută pe serverul OpenLDAP, cu drepturi adecvate. Înainte de schimbare se confirmă funcționarea autentificării printr-o aplicație reprezentativă.

### 5.1. Verificarea serviciului și a configurației active

```bash
systemctl status saslauthd
systemctl cat saslauthd
ps -eo pid,user,args | grep '[s]aslauthd'
```

Se verifică mecanismul LDAP, calea configurației active (inclusiv eventualul argument `-O`), calea socketului și existența opțiunii de cache (`-c`). Procedura presupune că fișierul activ este `/etc/saslauthd.conf` și că serviciul este administrat prin systemd.

### 5.2. Verificarea conectivității și a rezolvării DNS

```bash
for dc in dc1.sts.nest dc2.sts.nest; do
    echo "=== $dc ==="
    getent ahosts "$dc"
    nc -vz -w 5 "$dc" 636
done
```

Rezultat așteptat: rezolvare DNS corectă și portul TCP/636 accesibil pentru ambele servere.

### 5.3. Instalarea și verificarea certificatului Root CA

Certificatul trebuie preluat dintr-o sursă PKI de încredere. Se verifică amprenta SHA-256 față de valoarea furnizată de administratorul CA.

```bash
openssl x509 -inform PEM -in rootca.cer \
  -noout -subject -issuer -dates -fingerprint -sha256
```

Dacă fișierul este deja instalat, se verifică fișierul existent, fără a-l suprascrie inutil. Pentru instalare:

```bash
install -o root -g root -m 0644 rootca.cer \
  /etc/ssl/certs/ad-rootca.cer

ls -l /etc/ssl/certs/ad-rootca.cer
```

Certificatul trebuie să fie în format PEM (`-----BEGIN CERTIFICATE-----`). Extensia `.cer` nu influențează formatul. Dacă certificatul este DER, se convertește mai întâi:

```bash
openssl x509 -inform DER -in rootca.cer \
  -outform PEM -out rootca.pem
```

În acest caz se instalează `rootca.pem` la calea stabilită. Permisiunile `644` sunt suficiente pentru certificatul public CA. Nu este necesară instalarea CA la nivelul întregului sistem, întrucât acesta este specificat explicit în configurația `saslauthd`.

### 5.4. Verificarea TLS pentru ambele Domain Controllere

```bash
for dc in dc1.sts.nest dc2.sts.nest; do
    echo "=== $dc ==="
    openssl s_client \
      -connect "$dc:636" \
      -servername "$dc" \
      -verify_hostname "$dc" \
      -verify_return_error \
      -CAfile /etc/ssl/certs/ad-rootca.cer \
      -showcerts </dev/null
done
```

Rezultat așteptat pentru fiecare server:

```text
Verify return code: 0 (ok)
```

Se verifică inclusiv valabilitatea certificatului, corespondența numelui DNS și lanțul de încredere. Root CA este suficient dacă lanțul poate fi validat; în caz contrar se obține certificatul intermediar necesar din sursa PKI autorizată. Nu se dezactivează verificarea TLS pentru a ocoli erorile.

### 5.5. Testarea autentificării LDAP prin 636

Se testează contul de serviciu și căutarea unui utilizator de test pe fiecare Domain Controller, folosind DN-ul real configurat în `ldap_bind_dn`:

```bash
for dc in dc1.sts.nest dc2.sts.nest; do
    echo "=== $dc ==="
    LDAPTLS_CACERT=/etc/ssl/certs/ad-rootca.cer \
    LDAPTLS_REQCERT=demand \
    ldapsearch -x -LLL \
      -H "ldaps://$dc:636" \
      -D 'CN=CONT_SERVICIU,CN=Users,DC=sts,DC=nest' \
      -W -b 'DC=sts,DC=nest' \
      '(sAMAccountName=UTILIZATOR_TEST)' dn
done
```

Rezultat așteptat: comanda se încheie cu succes și returnează DN-ul utilizatorului de test pentru fiecare server. Parola se introduce interactiv și nu se include în documentație.

**Condiție de implementare:** toate verificările preliminare trebuie să fie finalizate cu succes.

## 6. Plan de implementare

### 6.1. Backup configurație

Se păstrează permisiunile și proprietarul fișierului original. Backupul poate conține credențiale și trebuie păstrat într-un director accesibil numai administratorului.

```bash
umask 077
backup="/root/saslauthd.conf.pre-ldaps.$(date +%Y%m%d-%H%M%S)"
cp -a /etc/saslauthd.conf "$backup"
chmod 600 "$backup"
printf 'Backup: %s\n' "$backup"
```

Se consemnează calea exactă a backupului pentru rollback.

### 6.2. Modificare configurație

```bash
vi /etc/saslauthd.conf
```

Configurația țintă (fragment relevant):

```ini
ldap_servers: ldaps://dc1.sts.nest:636 ldaps://dc2.sts.nest:636
ldap_version: 3
ldap_start_tls: no
ldap_tls_check_peer: yes
ldap_tls_cacert_file: /etc/ssl/certs/ad-rootca.cer
ldap_search_base: DC=sts,DC=nest
ldap_filter: (sAMAccountName=%u)
```

Se păstrează neschimbate `ldap_bind_dn`, `ldap_password` și ceilalți parametri specifici instalării. Nu se introduc credențiale în documentație. Fiecare parametru trebuie să fie pe o linie separată.

Se verifică permisiunile fișierului, fără a le modifica dacă sunt deja adecvate utilizatorului serviciului.

### 6.3. Aplicarea schimbării

```bash
systemctl restart saslauthd
systemctl status saslauthd --no-pager
```

## 7. Plan de validare post-implementare

### 7.1. Verificarea logurilor

```bash
journalctl -u saslauthd --since '10 minutes ago' --no-pager
```

Se verifică și logurile `slapd` sau syslog, dacă sunt relevante pentru instalare. Nu trebuie să apară erori noi de conectare, TLS, bind sau autentificare.

### 7.2. Verificarea traficului de rețea

Înainte de testarea autentificării se pornește captura într-un terminal separat:

```bash
tcpdump -ni any \
  '(host dc1.sts.nest or host dc2.sts.nest) and (tcp port 389 or tcp port 636)'
```

Se efectuează autentificări noi, care să nu fie servite exclusiv din cache. Se confirmă apariția traficului către TCP/636 și absența traficului către TCP/389 în intervalul observat. Nu este obligatoriu să apară trafic către ambele DC-uri în timpul funcționării normale; fiecare a fost testat individual în etapa preliminară.

Monitorizare exclusivă a traficului către portul vechi:

```bash
tcpdump -ni any \
  '(host dc1.sts.nest or host dc2.sts.nest) and tcp dst port 389'
```

Monitorizarea se menține într-un interval reprezentativ de utilizare. Dacă serverele au mai multe adrese IP sau DNS-ul se modifică, se verifică acoperirea tuturor adreselor relevante de către filtru.

Verificare suplimentară a conexiunilor stabilite:

```bash
ss -ntp state established '( dport = :389 or dport = :636 )'
```

Conexiunile scurte pot să nu fie surprinse de `ss`; captura `tcpdump` este metoda principală. Dacă se observă trafic pe 389, se identifică procesul sursă înainte de a concluziona că aparține `saslauthd`.

### 7.3. Verificarea autentificării end-to-end

- Se testează autentificarea prin `saslauthd`, dacă este disponibil utilitarul `testsaslauthd` (cu un cont dedicat; parola transmisă în argument poate fi vizibilă în lista de procese).
- Se testează autentificarea prin OpenLDAP, utilizând o aplicație reprezentativă și un cont valid.
- Se confirmă respingerea unei parole incorecte cu un cont de test, respectând politica de blocare a conturilor.
- Dacă este prevăzută validarea failover-ului efectiv, aceasta se realizează controlat, fără a afecta alte servicii, într-o fereastră aprobată.

## 8. Criterii de succes

- [ ] Serviciul `saslauthd` este activ după restart.
- [ ] Certificatul TLS pentru DC1 este validat cu succes.
- [ ] Certificatul TLS pentru DC2 este validat cu succes.
- [ ] Căutarea LDAP cu contul de serviciu funcționează pe ambele DC-uri prin LDAPS.
- [ ] Autentificarea prin OpenLDAP funcționează.
- [ ] Traficul către TCP/636 este confirmat în timpul unei autentificări noi.
- [ ] Nu există trafic TCP/389 către cele două DC-uri în intervalul monitorizat sau eventualul trafic este investigat și atribuit altor servicii.
- [ ] Nu există erori noi relevante în loguri.

## 9. Plan de rollback

Rollback-ul se inițiază dacă autentificarea nu funcționează, serviciul nu pornește sau apar erori TLS care nu pot fi remediate în fereastra de schimbare.

```bash
# Se înlocuiește calea cu backupul consemnat la punctul 6.1
cp -a /root/saslauthd.conf.pre-ldaps.DATA-ORA /etc/saslauthd.conf
systemctl restart saslauthd
systemctl status saslauthd --no-pager
```

Se restabilesc proprietarul și permisiunile originale ale fișierului, dacă diferă de backupul protejat. Se verifică autentificarea prin OpenLDAP și revenirea la configurația anterioară. Rollback-ul presupune că accesul TCP/389 este încă disponibil.

Se consemnează cauza rollback-ului. Certificatul CA instalat poate rămâne pe server; eliminarea lui se face numai dacă nu este utilizat de alte componente.

## 10. Rezultatul implementării

| Verificare | Rezultat |
|---|---|
| TLS DC1 | De completat |
| TLS DC2 | De completat |
| LDAP search prin LDAPS | De completat |
| Autentificare OpenLDAP | De completat |
| Trafic TCP/636 | De completat |
| Trafic TCP/389 | De completat |
| Interval monitorizare | De completat |
| Erori în loguri | De completat |
| Rezultat final | De completat – succes / rollback |
| Data și ora finalizării | De completat |
| Validat de | De completat |

Se atașează rezultatele verificărilor relevante, fără parole, token-uri sau alte informații sensibile.
