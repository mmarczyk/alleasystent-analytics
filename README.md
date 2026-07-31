# AllEasystent — Analytics Dashboard

Static "who's asking what" dashboard for the [AllEasystent](https://github.com/mmarczyk/alleasystent)
AI assistant: intent distribution, recent queries, LLM-detected tool gaps,
and on-demand LLM clustering of recent queries. Hosted on GitHub Pages.

This repo is **frontend only**. The data (Redis-backed query log, LLM
clustering) is served by the `alleasystent` backend's `/admin/analytics` and
`/admin/analytics/analyze` endpoints — GitHub Pages can't run that Python
service, so it stays put and this dashboard calls it cross-origin.

Access used to be gated by a secret URL token baked into the `alleasystent`
build. It's now gated by **Google Sign-In**: only Google accounts on an
email allowlist configured on the backend can see any data.

## How it works

- `index.html` shows a Google Sign-In button. On success, the browser holds
  a short-lived Google ID token (in `sessionStorage`, cleared on tab close).
- Every call to the backend sends that token as `Authorization: Bearer
  <token>`.
- The backend (`alleasystent`, see `main.py:_check_analytics_auth`) verifies
  the token's signature and audience against Google, then checks the
  token's email against `ANALYTICS_ALLOWED_EMAILS`. A `401`/`403` response
  here signs the dashboard out and shows the sign-in screen again.
- `config.js` is generated at deploy time by `.github/workflows/deploy.yml`
  from two repo variables — it is **not** committed with real values.

## One-time setup

1. **Create a Google OAuth 2.0 Client ID** (GCP Console → APIs & Services →
   Credentials → Create Credentials → OAuth client ID → Web application).
   - Authorized JavaScript origin: `https://<your-username>.github.io`
   - No redirect URI needed (Sign In With Google uses the implicit/GIS flow).

2. **On this repo** (Settings → Secrets and variables → Actions → Variables):
   | Variable | Value |
   |---|---|
   | `BACKEND_URL` | The `alleasystent` Cloud Run URL, e.g. `https://alleasystent-xxxx-ew.a.run.app` |
   | `GOOGLE_CLIENT_ID` | The OAuth Client ID from step 1 |

3. **On the `alleasystent` repo/backend**, configure the matching side:
   - Repo variables: `ANALYTICS_GOOGLE_CLIENT_ID` (same Client ID),
     `ANALYTICS_FRONTEND_URL` (this site's origin, e.g.
     `https://<your-username>.github.io`, used for CORS).
   - Secret Manager secret `analytics-allowed-emails`: comma-separated list
     of Google account emails allowed to view the dashboard (mapped to the
     `ANALYTICS_ALLOWED_EMAILS` env var in `deploy-backend.yml`).
   - See `deployment/setup_gcp.sh` in that repo for the exact commands.

4. **Enable GitHub Pages** on this repo: Settings → Pages → Source →
   "GitHub Actions".

5. Push to `main` (or run the "Deploy Analytics Dashboard to GitHub Pages"
   workflow manually) to publish.

## Local development

Serve the folder with any static file server and point `config.js` at a
local or deployed backend:

```bash
python3 -m http.server 8081
```

Then edit `config.js` locally (don't commit real values) to point
`__BACKEND_URL__` at your backend and `__GOOGLE_CLIENT_ID__` at a Client ID
whose authorized origins include `http://localhost:8081`.
