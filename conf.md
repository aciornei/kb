# Keycloak — 02 Configurare: temă și profilul utilizatorului

| Metadate | Valoare |
|---|---|
| Serviciu | Keycloak — Identity & SSO |
| Secțiune | **02 – Configurare** |
| Platformă | Keycloak 26.6.2; Linux nativ / `systemd` |
| Realm | `AD` |
| Revizie | 1.0 — 16.11.2026 |
| Stare | Configurație operațională, validată în mediul curent |
| Clasificare | Intern — administrare IT |

## Conținut

1. [C-KC-01 — Configurarea temei STS pe clienți](./01-Configurare-tema-STS-pe-clienti.md) — instalare și verificare JAR, activare `sts.v1` pe clienți individuali, configurarea `account-console` pentru pagina `UPDATE_PASSWORD`, validare și revenire.
2. [C-KC-02 — Câmpuri Personal Info read-only și schimbarea parolei Active Directory](./02-Configurare-Personal-Info-read-only-si-parola-AD.md) — LDAP `WRITABLE`, permisiuni User Profile, verificarea mapperelor LDAP, schimbare parolă AD, teste și rollback.

## Rezumatul configurației

- Realm `AD` cu Active Directory și Kerberos/SPNEGO.
- Tema `sts.v1` instalată ca JAR în `/opt/keycloak/providers/`; **doar temă de login**.
- Tema activată numai pentru clienții selectați și `account-console`, nu global pentru toate aplicațiile.
- Provider LDAP în `WRITABLE` pentru a permite schimbarea parolei în AD.
- Utilizatorii pot consulta datele Personal Info, dar nu le pot modifica în interfețele standard Keycloak.
- Datele de identitate se modifică în AD, apoi sunt sincronizate în Keycloak.

## Legături către procedurile operaționale existente

După import, creați manual legăturile interne Outline pentru:

- **P-KC-01 — Autentificare în CLI cu kcadm.sh**
- **P-KC-02 — Invalidarea cache-ului utilizatorilor**
- **P-KC-03 — Mapper Kerberos LDAP**
- **P-KC-05 — Sincronizarea imediată a utilizatorilor modificați în AD**

> **Import Outline:** aceste fișiere conțin linkuri relative între documentele de configurare. Dacă Outline nu le transformă automat în linkuri interne, înlocuiți adresele cu linkurile documentelor publicate.
