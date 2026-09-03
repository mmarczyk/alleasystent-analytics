# Firebase Hosting — deploy workflows for both frontends

Both AllEasystent frontends are static sites that currently publish to GitHub
Pages. This directory holds the **Firebase Hosting** version of those deploys:
one Hosting site per app, both inside the **same GCP project** that already
runs the Cloud Run backend, authenticated with the **same `GCP_SA_KEY`
service-account key** the Cloud Run workflows use.

| App | Repo | Source | Hosting target | Origin |
|---|---|---|---|---|
| Chat UI (PWA) | `mmarczyk/alleasystent` | `web/` | `chat` | `https://<CHAT_SITE>.web.app` |
| Analytics dashboard | `mmarczyk/alleasystent-analytics` | `index.html` + generated `config.js` | `analytics` | `https://<ANALYTICS_SITE>.web.app` |

## What's here

```
deployment/firebase/
├── README.md                              ← this file
├── setup_firebase.sh                      ← one-time GCP/Firebase provisioning
└── alleasystent/                          ← files to COPY into the alleasystent repo
    ├── deploy-chat-firebase.yml           → .github/workflows/deploy-chat-firebase.yml
    └── firebase.json                      → firebase.json (repo root)
```

The analytics side is already wired up in this repo:

```
.github/workflows/deploy-firebase.yml      ← analytics dashboard → Firebase Hosting
firebase.json                              ← analytics Hosting config
```

The `alleasystent/` files live here because this session can only push to
`alleasystent-analytics`; copy them into the other repo as shown above.

## Where the GCP details come from

Everything reuses what `deploy-backend.yml` (alleasystent) already
established, so there is no second set of credentials to manage:

| Thing | Value / source | Notes |
|---|---|---|
| GCP project | `${{ vars.FIREBASE_PROJECT_ID }}`, falling back to `${{ vars.GCP_PROJECT_ID }}` | Same project as Cloud Run by default; see [Hosting in its own project](#hosting-in-its-own-project) |
| Credentials | `${{ secrets.GCP_SA_KEY }}` via `google-github-actions/auth@v2` | The step exports `GOOGLE_APPLICATION_CREDENTIALS`; `firebase-tools` reads it directly, so no deprecated `FIREBASE_TOKEN` is involved |
| Region | n/a | Hosting is a global CDN — unlike Cloud Run's `europe-central2`, there is nothing to pin |
| Backend URL | `${{ vars.BACKEND_URL }}` | Injected into `config.js` at deploy time, exactly as the Pages workflows do |

## Hosting in its own project

Hosting does not have to live in the Cloud Run project. The frontends are
static files that reach the backend over its public HTTPS URL, so the only
thing coupling them is CORS — nothing breaks by splitting them.

That is worth knowing because a Firebase project **is** a GCP project: opening
the Firebase console and clicking "Create a project" produces a brand-new GCP
project, not a view onto an existing one, and the two cannot be merged
afterwards. If Hosting has already landed somewhere separate, keep it there and
set `FIREBASE_PROJECT_ID` on both repos; leave the variable unset for the
single-project case and `GCP_PROJECT_ID` is used.

Two things then need doing on the Hosting project, both from `setup_firebase.sh`
(`FIREBASE_PROJECT_ID=<id>`) or by hand:

- **Grant the deployer service account its two roles there.** A service account
  created in one project can hold roles in another — Cloud Console → IAM on the
  Hosting project → Grant access → paste the SA's email → Firebase Hosting
  Admin + Service Usage Consumer. Nothing about `GCP_SA_KEY` changes.
- **Link a billing account** if you need more than one Hosting site. A second
  site requires the Blaze plan, and "Blaze" means exactly "this project has a
  Cloud Billing account attached". A fresh Firebase project has none, so it
  starts on Spark with a single default site whose ID equals the project ID.
  Attaching the billing account the Cloud Run project already uses is enough;
  Hosting's free tier covers two static sites with room to spare.

Registering a **Web App** in the Firebase console does *not* create a Hosting
site, and is not needed at all here — an app registration exists to hand you a
`firebaseConfig` object for the Firebase JS SDK, which neither frontend uses.

The project ID is deliberately **not** committed to a `.firebaserc`. The
workflow runs `firebase target:apply hosting <target> <site> --project
"$GCP_PROJECT_ID"` at deploy time, which writes `.firebaserc` in the runner's
workspace — so `firebase.json` stays free of environment-specific IDs, and the
project ID keeps living in the same repo variable the Cloud Run deploys use.

## One-time setup

### 1. Provision Firebase on the existing GCP project

```bash
PROJECT_ID=<your-gcp-project> \
DEPLOYER_SA_EMAIL=<the SA behind GCP_SA_KEY> \
bash deployment/firebase/setup_firebase.sh
```

It enables the Firebase APIs, adds Firebase to the project, creates both
Hosting sites, and grants the CI service account the two roles
`firebase-tools` needs on top of what it already has for Cloud Run:

- `roles/firebasehosting.admin` — create Hosting versions and releases
- `roles/serviceusage.serviceUsageConsumer` — use the project for API quota

Override the site IDs with `CHAT_SITE=` / `ANALYTICS_SITE=` if the defaults
(`alleasystent`, `alleasystent-analytics`) are already taken — Hosting site IDs
are globally unique.

### 2. GitHub repo variables and secrets

On **`alleasystent-analytics`** (Settings → Secrets and variables → Actions):

| Kind | Name | Value |
|---|---|---|
| Secret | `GCP_SA_KEY` | Same SA JSON key as on the `alleasystent` repo |
| Variable | `GCP_PROJECT_ID` | Same project ID as on the `alleasystent` repo |
| Variable | `FIREBASE_SITE` | `alleasystent-analytics` |
| Variable | `FIREBASE_PROJECT_ID` | Only when Hosting is in its own project |
| Variable | `BACKEND_URL` | The Cloud Run URL (already set for the Pages deploy) |
| Variable | `GOOGLE_CLIENT_ID` | The OAuth Client ID (already set) |
| Variable | `CHAT_URL` | `https://<CHAT_SITE>.web.app` — the dashboard's "← Chat" link |

`GCP_SA_KEY` and `GCP_PROJECT_ID` only exist on the `alleasystent` repo today;
they have to be copied here, since this repo never talked to GCP before.

On **`alleasystent`**:

| Kind | Name | Value |
|---|---|---|
| Variable | `FIREBASE_SITE` | `alleasystent` |
| Variable | `FIREBASE_PROJECT_ID` | Only when Hosting is in its own project |

`GCP_SA_KEY`, `GCP_PROJECT_ID` and `BACKEND_URL` are already set there.

### 3. Re-point the origins (the part that actually breaks things)

Moving off GitHub Pages **changes both frontends' origins**, and three places
hardcode them:

1. **OAuth 2.0 Client ID** (GCP Console → APIs & Services → Credentials →
   Authorized JavaScript origins) — add
   `https://<ANALYTICS_SITE>.web.app` and
   `https://<ANALYTICS_SITE>.firebaseapp.com`. Without this, Google Sign-In
   fails with `origin_mismatch` and the dashboard shows nothing.
2. **Backend CORS** — repo variables on `alleasystent`:
   `ANALYTICS_FRONTEND_URL = https://<ANALYTICS_SITE>.web.app` and
   `FRONTEND_URL = https://<CHAT_SITE>.web.app`. These are read by
   `deploy-backend.yml` into Cloud Run env vars, so **re-run that workflow**
   afterwards — changing the variable alone does nothing to the running
   service.
3. **`CHAT_URL`** repo variable on this repo (see above), so the dashboard's
   back-link points at the Firebase-hosted chat instead of GitHub Pages.

Firebase serves each site on both `.web.app` and `.firebaseapp.com`. Only the
`.web.app` one is wired into the variables above; if you want the other to work
too, add it to the OAuth origins and to the backend's CORS allowlist.

## Coexistence with the GitHub Pages workflows

The existing Pages workflows (`deploy.yml` here, `deploy-chat.yml` on
`alleasystent`) are left in place, so during the migration a push to `main`
publishes to **both** targets. That is intentional — the Pages URLs keep
working until you have verified the Firebase ones. Once you have, retire Pages
per repo by either deleting its workflow file or narrowing its trigger to
`workflow_dispatch:` only.

`.nojekyll` is only meaningful for GitHub Pages; the Firebase workflow doesn't
copy it into `dist/`.

## Deliberately not included: PR preview channels

Firebase Hosting preview channels are the usual reason to prefer it over
Pages, but they don't fit these two apps as they stand. A preview URL is
`https://<site>--<channel>-<hash>.web.app` with a hash that can't be known in
advance, so it can be registered neither as an OAuth JavaScript origin (the
dashboard's Google Sign-In would fail) nor in the backend's CORS allowlist
(every API call would fail). Adding previews means making the backend accept a
wildcard origin pattern — a real decision about loosening CORS, not a workflow
tweak, so the workflows deploy to the live channel only.

## Rollback

Firebase Hosting keeps every release, and each one is tagged with the
deploying commit SHA (`--message "$GITHUB_SHA"` in the workflows), so the
release list maps straight back to git history. To roll back, open Firebase
Console → Hosting → the site's release history and use **Rollback** on the
previous release; it is instant and needs no rebuild. Re-running the workflow
on the desired commit (`workflow_dispatch` from a tag or branch) achieves the
same thing from CI.
