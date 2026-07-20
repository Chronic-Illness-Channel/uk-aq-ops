#!/usr/bin/env bash
set -euo pipefail

REPO="Chronic-Illness-Channel/uk-aq-ops"
CONFIG="config/uk_aq_github_env_targets.csv"
WORKFLOWS_FILE="$(mktemp)"
trap 'rm -f "$WORKFLOWS_FILE"' EXIT

echo "Forcing all ops Scheduler variables to false..."

awk -F, '
  $1 ~ /_SCHEDULER_ENABLED$/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
    print $1
  }
' "$CONFIG" |
sort -u |
while IFS= read -r key; do
  [ -z "$key" ] && continue
  echo "  $key=false"
  gh variable set "$key" \
    --body "false" \
    --repo "$REPO"
done

echo
echo "Finding active ops Cloud Run deployment workflows..."

gh api --paginate \
  "repos/${REPO}/actions/workflows?per_page=100" \
  --jq '
    .workflows[]
    | select(.state == "active")
    | select(
        (.path | contains("cloud_run"))
        and
        (.path | contains("deploy"))
      )
    | [.name, .path]
    | @tsv
  ' |
while IFS=$'\t' read -r name path; do
  case "$path" in
    *aqilevels_retention*)
      echo "Skipping retired AQI-level retention workflow: $name" >&2
      continue
      ;;
  esac

  printf '%s\t%s\n' "$name" "$path"
done > "$WORKFLOWS_FILE"

if [ ! -s "$WORKFLOWS_FILE" ]; then
  echo "No active ops Cloud Run deployment workflows found."
  exit 0
fi

echo
echo "The following ops workflows will be deployed:"
while IFS=$'\t' read -r name path; do
  printf '  %-48s %s\n' "$name" "$path"
done < "$WORKFLOWS_FILE"

echo
read -r -p "Deploy these ops workflows sequentially? [y/N] " answer

case "$answer" in
  y|Y|yes|YES) ;;
  *)
    echo "Cancelled."
    exit 0
    ;;
esac

while IFS=$'\t' read -r name path; do
  workflow_file="${path##*/}"

  echo
  echo "============================================================"
  echo "Deploying: $name"
  echo "Workflow:  $workflow_file"
  echo "============================================================"

  previous_run="$(
    gh run list \
      --repo "$REPO" \
      --workflow "$workflow_file" \
      --event workflow_dispatch \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId // 0'
  )"

  gh workflow run "$workflow_file" \
    --repo "$REPO" \
    --ref main

  run_id=""

  for attempt in {1..30}; do
    latest_run="$(
      gh run list \
        --repo "$REPO" \
        --workflow "$workflow_file" \
        --event workflow_dispatch \
        --limit 1 \
        --json databaseId \
        --jq '.[0].databaseId // 0'
    )"

    if [ "$latest_run" != "0" ] && [ "$latest_run" != "$previous_run" ]; then
      run_id="$latest_run"
      break
    fi

    sleep 2
  done

  if [ -z "$run_id" ]; then
    echo "ERROR: Could not find the newly dispatched run for $workflow_file"
    exit 1
  fi

  echo "Watching run: $run_id"

  gh run watch "$run_id" \
    --repo "$REPO" \
    --exit-status

  echo "Completed successfully: $name"
done < "$WORKFLOWS_FILE"

echo
echo "All active ops Cloud Run deployments completed successfully."