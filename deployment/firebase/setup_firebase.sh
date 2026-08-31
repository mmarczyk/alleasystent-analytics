#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# AllEasystent — Firebase Hosting setup (both frontends, one GCP project)
#
# Companion to `deployment/setup_gcp.sh` in the alleasystent repo. Run once to
# turn the existing GCP project into a Firebase project, create one Hosting
# site per frontend, and grant the CI service account (the one behind the
# GCP_SA_KEY secret) the two roles firebase-tools needs.
#
# Prerequisites:
#   - gcloud CLI authenticated as a project Owner
#   - firebase CLI (`npm i -g firebase-tools`) authenticated: `firebase login`
#
# Usage:
#   PROJECT_ID=my-project \
#   DEPLOYER_SA_EMAIL=github-deployer@my-project.iam.gserviceaccount.com \
#   bash deployment/firebase/setup_firebase.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT_ID="${PROJECT_ID:?PROJECT_ID env var must be set}"
# The service account whose JSON key is stored as the GCP_SA_KEY secret on
# BOTH repos — the same one deploy-backend.yml already uses for Cloud Run.
DEPLOYER_SA_EMAIL="${DEPLOYER_SA_EMAIL:?DEPLOYER_SA_EMAIL env var must be set}"
# Hosting site IDs. These become the public origins:
#   https://<site>.web.app  and  https://<site>.firebaseapp.com
CHAT_SITE="${CHAT_SITE:-alleasystent}"
ANALYTICS_SITE="${ANALYTICS_SITE:-alleasystent-analytics}"

echo "▶ Setting project: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

# ── Enable APIs ───────────────────────────────────────────────────────────────
echo "▶ Enabling Firebase APIs..."
gcloud services enable \
  firebase.googleapis.com \
  firebasehosting.googleapis.com \
  serviceusage.googleapis.com \
  --project="$PROJECT_ID"

# ── Add Firebase to the existing GCP project ──────────────────────────────────
# Idempotent: a project that already has Firebase returns an error we swallow.
echo "▶ Adding Firebase to the GCP project..."
firebase projects:addfirebase "$PROJECT_ID" || echo "  (already a Firebase project)"

# ── Hosting sites: one per frontend, both inside this single project ──────────
# The project's *default* site is named after the project ID and is left
# unused, so each app gets an explicit, stable origin instead of whichever one
# happened to be created first.
echo "▶ Creating Hosting sites..."
for SITE in "$CHAT_SITE" "$ANALYTICS_SITE"; do
  firebase hosting:sites:create "$SITE" --project "$PROJECT_ID" \
    || echo "  $SITE already exists (or the ID is taken globally — pick another)"
done

# ── CI service account permissions ────────────────────────────────────────────
# firebasehosting.admin        — create versions/releases on the Hosting sites
# serviceusage.serviceUsageConsumer — lets firebase-tools call the API with the
#                                     project as the quota/billing project
echo "▶ Granting Hosting deploy roles to $DEPLOYER_SA_EMAIL..."
for ROLE in \
  roles/firebasehosting.admin \
  roles/serviceusage.serviceUsageConsumer; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$DEPLOYER_SA_EMAIL" \
    --role="$ROLE" --quiet
done

echo ""
echo "✅ Firebase Hosting setup complete!"
echo ""
echo "Sites:"
echo "  chat      https://${CHAT_SITE}.web.app"
echo "  analytics https://${ANALYTICS_SITE}.web.app"
echo ""
echo "Next steps:"
echo "  1. GitHub repo variables (Settings → Secrets and variables → Actions → Variables):"
echo "       alleasystent            FIREBASE_SITE = ${CHAT_SITE}"
echo "       alleasystent-analytics  FIREBASE_SITE = ${ANALYTICS_SITE}"
echo "     GCP_PROJECT_ID and the GCP_SA_KEY secret must exist on BOTH repos"
echo "     (only alleasystent has them today — copy them to the analytics repo)."
echo "  2. Add the new origins to the OAuth 2.0 Client ID (GCP Console → APIs &"
echo "     Services → Credentials → Authorized JavaScript origins):"
echo "       https://${ANALYTICS_SITE}.web.app"
echo "       https://${ANALYTICS_SITE}.firebaseapp.com"
echo "  3. Point the backend at the new origins (repo variables on alleasystent,"
echo "     then re-run deploy-backend.yml so Cloud Run picks them up):"
echo "       FRONTEND_URL           = https://${CHAT_SITE}.web.app"
echo "       ANALYTICS_FRONTEND_URL = https://${ANALYTICS_SITE}.web.app"
echo "  4. Push to main (or run the Firebase workflows manually) to publish."
