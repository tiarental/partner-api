# TIARENTAL — paketimi Git/DNS v2

Ky është revizioni **v2 i paketimit për Git**, jo një API e re `/v2`. Aplikacioni
mbetet **v13.16.0**, kurse Partner API dhe plugin-i mbeten **v1**. Ndryshimet
këtu janë udhëzime publikimi; krijimi i domain-it nuk kërkon ndryshim të kodit.

## Dy repo të ndara

| ZIP | GitHub | Vercel |
| --- | --- | --- |
| `TIARENTAL-GIT-V2.zip` | `tiarental/tiarental.com` — private | I njëjti projekt ku është `tiarental.com`; këtu ekzekutohet `/v1/*` |
| `PARTNER-API-GIT-V2.zip` | `tiarental/partner-api` — public | Nuk publikohet si aplikacion më vete |

Të dy ZIP-et kanë skedarët në rrënjë, pa folder prindër dhe pa `.git` ose
sekrete. Nxirri në dy dosje të veçanta. Mos e ngarko ZIP-in si një skedar të
vetëm në GitHub: kopjo përmbajtjen e tij në repo-n përkatëse.

## 1. Projekti kryesor — VS Code / PowerShell

Përdor një klonim të ri që të mos trashëgosh rebase/merge conflict të dosjes
së vjetër. Në terminalin PowerShell të VS Code:

```powershell
cd "$env:USERPROFILE\Downloads"
git clone https://github.com/tiarental/tiarental.com.git tiarental-git-v2
cd tiarental-git-v2
git switch -c release/tiarental-git-v2
git status --short
git rm -r -- .
```

Nëse `git status --short` tregon ndryshime para `git rm`, ruaji dhe kontrollo
se je vërtet në klonimin e ri.

Tani nxirr `TIARENTAL-GIT-V2.zip` dhe kopjo **përmbajtjen** brenda
`tiarental-git-v2`. Përfshi skedarët që fillojnë me pikë (`.github`,
`.gitignore`); ruaj folderin `.git` të klonimit. `git rm` përdoret vetëm në
këtë klonim të ri dhe fshin skedarët e gjurmuar të snapshot-it të vjetër, jo
historikun Git. Kontrollo listën e ndryshimeve para commit-it:

```powershell
git add -A
git diff --cached --check
git diff --cached --stat
git status --short
git commit -m "TIARENTAL v13.16.0 Git and API domain guide v2"
git push -u origin release/tiarental-git-v2
```

Në GitHub hap Pull Request nga `release/tiarental-git-v2` drejt `main`.
Kontrollo në Vercel që projekti i lidhur me `tiarental.com` lexon po këtë repo,
branch-i i prodhimit është `main` dhe build-i është **Ready**. Push te branch-i
`release/*` jep Preview; prodhimi përditësohet pas bashkimit në `main`.

## 2. Repo publike Partner API — VS Code / PowerShell

```powershell
cd ..
git clone https://github.com/tiarental/partner-api.git partner-api-git-v2
cd partner-api-git-v2
git switch -c release/partner-api-git-v2
```

Nxirr `PARTNER-API-GIT-V2.zip`, kopjo **përmbajtjen** në
`partner-api-git-v2`, pastaj:

```powershell
git add -A
git diff --cached --check
git diff --cached --stat
git status --short
git commit -m "Document Partner API domain and Git release v2"
git push -u origin release/partner-api-git-v2
```

Hap Pull Request për `partner-api/main`. Nëse dikush ka shtuar ndryshime në
repo ndërkohë, rishiko diff-in para commit-it; mos përdor `force push`.

## 3. Domain-i `api.tiarental.com`

Në **Vercel → projekti kryesor TIARENTAL → Settings → Domains → Add Domain**,
shto `api.tiarental.com`, lidhe me **Production** dhe mos vendos redirect te
`tiarental.com`. Në DNS, nëse domain-i përdor një ofrues tjetër, shto:

| Type | Host/Name | Target/Value |
| --- | --- | --- |
| CNAME | `api` | Vlera e saktë unike që të shfaq Vercel për këtë projekt |

Nëse DNS menaxhohet në Vercel, ndiq udhëzimin e panelit dhe kontrollo nëse
rekordi krijohet automatikisht. Mos ndrysho rekordet `@`, `www` ose MX. Prit
statusin **Valid Configuration** dhe certifikatën HTTPS.

DNS nuk e publikon kodin. Nëse aplikacioni v13.16.0 nuk është ende në një
deployment Production **Ready**, endpoint-et `/v1/*` do të mungojnë edhe pasi
CNAME të jetë korrekt.

## 4. Kushtet para aktivizimit të rezervimeve për partnerët

1. Konfirmo projektin Supabase që përdor Vercel dhe backup-in e tij.
2. Rishiko dhe apliko vetëm migration-in
   `supabase/migrations/20260918165924_v13_16_0_partner_api_booking_transfer.sql`
   sipas `docs/INSTALL-v13.16.0.md`; nuk është aplikuar nga paketimi v2.
3. Vendos në Vercel, vetëm si variabla serveri,
   `PARTNER_API_KEY_PEPPER` dhe `PARTNER_WEBHOOK_ENCRYPTION_KEY`, bashkë me
   konfigurimin ekzistues të Supabase. Mos vendos vlera reale në GitHub.
4. Pas kontrollit të migration-it dhe konfigurimit, bashko Pull Request-in e
   aplikacionit kryesor në `main`; prit statusin **Ready** te Deployments.

## 5. Prova e API

Në PowerShell:

```powershell
curl.exe -i https://api.tiarental.com/v1/me
```

Pa key, **HTTP 401** me `UNAUTHORIZED` dhe `X-Request-Id` tregon që endpoint-i
është publikuar dhe u arrit. **404** zakonisht tregon kod të vjetër/projekt të
gabuar në Vercel; problem DNS/TLS tregon konfigurim të papërfunduar të
domain-it. Provo key real vetëm pasi krijohet te **Vendor → Integrations**;
ruaje në server, jo në frontend ose Git. Për testet e rezervimeve, blocks,
webhooks dhe WordPress ndiq `docs/INSTALL-v13.16.0.md`.
