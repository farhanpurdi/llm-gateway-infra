#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")" &&
  pwd
)"

REPO_ROOT="$(
  cd "$SCRIPT_DIR/../.." &&
  pwd
)"

cd "$REPO_ROOT"

TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.74.0}"
REPORT_ONLY="${REPORT_ONLY:-0}"

BASELINE_FILE="$SCRIPT_DIR/container-high-baseline.json"

TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TEMP_DIR"
}

trap cleanup EXIT


echo
echo "======================================"
echo "Container Vulnerability Scan"
echo "======================================"

echo
echo "Scanner:"
echo "  $TRIVY_IMAGE"

echo
echo "Policy:"
echo "  CRITICAL fixable: 0"
echo "  HIGH fixable: per-image baseline"

if [ "$REPORT_ONLY" = "1" ]; then
  echo
  echo "Mode:"
  echo "  REPORT ONLY"
fi


#
# --------------------------------------------------
# Preflight
# --------------------------------------------------
#

echo
echo "[1/4] Preflight"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is required."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required."
  exit 1
fi

if [ "$REPORT_ONLY" != "1" ] && \
   [ ! -f "$BASELINE_FILE" ]; then
  echo "ERROR: baseline file not found:"
  echo "  $BASELINE_FILE"
  exit 1
fi

echo "Preflight: PASS"


#
# --------------------------------------------------
# Scanner availability
# --------------------------------------------------
#

echo
echo "[2/4] Scanner availability"

docker run \
  --rm \
  "$TRIVY_IMAGE" \
  version

echo "Scanner availability: PASS"


#
# --------------------------------------------------
# Resolve images
# --------------------------------------------------
#

echo
echo "[3/4] Resolve runtime images"

IMAGES="$(
  docker compose \
    config \
    --images \
    | sort \
    -u
)"

if [ -z "$IMAGES" ]; then
  echo "ERROR: no container images found."
  exit 1
fi

echo
echo "Runtime images:"

while IFS= read -r image; do
  if [ -n "$image" ]; then
    echo "  - $image"
  fi
done <<< "$IMAGES"


#
# --------------------------------------------------
# Scan
# --------------------------------------------------
#

echo
echo "[4/4] Vulnerability policy evaluation"

SCAN_FAILED=0


while IFS= read -r image; do

  if [ -z "$image" ]; then
    continue
  fi

  SAFE_NAME="$(
    printf '%s' "$image" \
      | tr '/:' '__'
  )"

  REPORT_FILE="$TEMP_DIR/$SAFE_NAME.json"

  echo
  echo "======================================"
  echo "Scanning:"
  echo "  $image"
  echo "======================================"

  #
  # Trivy itself does NOT make the policy
  # decision here.
  #
  # We only request fixable HIGH/CRITICAL
  # findings and evaluate them below.
  #

  if ! docker run \
    --rm \
    --volume trivy-cache:/root/.cache/ \
    "$TRIVY_IMAGE" \
    image \
      --no-progress \
      --skip-version-check \
      --scanners vuln \
      --severity HIGH,CRITICAL \
      --ignore-unfixed \
      --format json \
      "$image" \
      > "$REPORT_FILE"
  then
    echo
    echo "ERROR: Trivy failed to scan:"
    echo "  $image"

    SCAN_FAILED=1
    continue
  fi


  #
  # Count unique findings.
  #
  # A finding is uniquely identified using:
  #
  # target
  # vulnerability ID
  # package
  # installed version
  #

  CRITICAL_COUNT="$(
    jq '
      [
        .Results[]? as $result
        |
        $result.Vulnerabilities[]?
        |
        select(.Severity == "CRITICAL")
        |
        (
          ($result.Target // "")
          + "|"
          + (.VulnerabilityID // "")
          + "|"
          + (.PkgName // "")
          + "|"
          + (.InstalledVersion // "")
        )
      ]
      | unique
      | length
    ' "$REPORT_FILE"
  )"


  HIGH_COUNT="$(
    jq '
      [
        .Results[]? as $result
        |
        $result.Vulnerabilities[]?
        |
        select(.Severity == "HIGH")
        |
        (
          ($result.Target // "")
          + "|"
          + (.VulnerabilityID // "")
          + "|"
          + (.PkgName // "")
          + "|"
          + (.InstalledVersion // "")
        )
      ]
      | unique
      | length
    ' "$REPORT_FILE"
  )"


  echo
  echo "Results:"
  echo "  CRITICAL: $CRITICAL_COUNT"
  echo "  HIGH:     $HIGH_COUNT"


  #
  # Report-only mode is used to establish
  # the initial approved baseline.
  #

  if [ "$REPORT_ONLY" = "1" ]; then
    echo
    echo "Suggested baseline entry:"
    printf '  "%s": %s\n' \
      "$image" \
      "$HIGH_COUNT"

    if [ "$CRITICAL_COUNT" -gt 0 ]; then
      echo
      echo "WARNING:"
      echo "  $CRITICAL_COUNT fixable CRITICAL finding(s)"
      echo "  were detected."
      echo
      echo "  CRITICAL findings must NOT be added"
      echo "  to the approved baseline."
    fi

    continue
  fi


  #
  # Every image must have an explicitly
  # approved HIGH baseline.
  #

  if ! jq \
    --exit-status \
    --arg image "$image" \
    'has($image)' \
    "$BASELINE_FILE" \
    >/dev/null
  then
    echo
    echo "ERROR: image has no approved baseline:"
    echo "  $image"
    echo
    echo "Run:"
    echo
    echo "Suggested baseline entry:"
    echo "\"$image\": {"
    echo "  \"critical\": $CRITICAL_COUNT,"
    echo "  \"high\": $HIGH_COUNT"
    echo "}"

    SCAN_FAILED=1
    continue
  fi


  MAX_CRITICAL="$(
    jq \
      --raw-output \
      --arg image "$image" \
      '.[$image].critical' \
      "$BASELINE_FILE"
  )"

  MAX_HIGH="$(
    jq \
      --raw-output \
      --arg image "$image" \
      '.[$image].high' \
      "$BASELINE_FILE"
  )"


  if ! [[ "$MAX_CRITICAL" =~ ^[0-9]+$ ]]; then
    echo
    echo "ERROR: invalid CRITICAL baseline for:"
    echo "  $image"
    echo "Value:"
    echo "  $MAX_CRITICAL"

    SCAN_FAILED=1
    continue
  fi

  if ! [[ "$MAX_HIGH" =~ ^[0-9]+$ ]]; then
    echo
    echo "ERROR: invalid HIGH baseline for:"
    echo "  $image"
    echo "Value:"
    echo "  $MAX_HIGH"

    SCAN_FAILED=1
    continue
  fi


  echo
  echo "Approved policy:"
  echo "  CRITICAL <= $MAX_CRITICAL"
  echo "  HIGH     <= $MAX_HIGH"


  IMAGE_FAILED=0


  #
  # CRITICAL is never baselined.
  #

  if [ "$CRITICAL_COUNT" -gt "$MAX_CRITICAL" ]; then
    echo
    echo "ERROR:"
    echo "  CRITICAL vulnerability baseline exceeded."
    echo
    echo "Approved:"
    echo "  $MAX_CRITICAL"
    echo
    echo "Current:"
    echo "  $CRITICAL_COUNT"

    IMAGE_FAILED=1
  fi


  #
  # HIGH may not exceed the approved
  # per-image baseline.
  #

  if [ "$HIGH_COUNT" -gt "$MAX_HIGH" ]; then
    echo
    echo "ERROR:"
    echo "  HIGH vulnerability baseline exceeded."
    echo
    echo "Approved:"
    echo "  $MAX_HIGH"
    echo
    echo "Current:"
    echo "  $HIGH_COUNT"

    IMAGE_FAILED=1
  fi


  #
  # If security posture improved, CI still
  # passes, but we ask the maintainer to
  # lower the baseline.
  #

  if [ "$CRITICAL_COUNT" -lt "$MAX_CRITICAL" ]; then
    echo
    echo "NOTICE:"
    echo "  CRITICAL vulnerability count improved."
    echo
    echo "Current:"
    echo "  $CRITICAL_COUNT"
    echo
    echo "Approved baseline:"
    echo "  $MAX_CRITICAL"
    echo
    echo "Consider lowering the CRITICAL baseline."
  fi

  if [ "$HIGH_COUNT" -lt "$MAX_HIGH" ]; then
    echo
    echo "NOTICE:"
    echo "  HIGH vulnerability count improved."
    echo
    echo "Current:"
    echo "  $HIGH_COUNT"
    echo
    echo "Approved baseline:"
    echo "  $MAX_HIGH"
    echo
    echo "Consider lowering the HIGH baseline."
  fi


  if [ "$IMAGE_FAILED" -ne 0 ]; then

    echo
    echo "Relevant findings:"
    echo

    jq \
      --raw-output \
      '
        .Results[]? as $result
        |
        $result.Vulnerabilities[]?
        |
        select(
          .Severity == "HIGH"
          or
          .Severity == "CRITICAL"
        )
        |
        [
          .Severity,
          .VulnerabilityID,
          .PkgName,
          .InstalledVersion,
          (.FixedVersion // ""),
          ($result.Target // "")
        ]
        |
        @tsv
      ' \
      "$REPORT_FILE"

    SCAN_FAILED=1

  else

    echo
    echo "Policy evaluation:"
    echo "  PASS"

  fi

done <<< "$IMAGES"


#
# --------------------------------------------------
# Final status
# --------------------------------------------------
#

if [ "$REPORT_ONLY" = "1" ]; then
  echo
  echo "======================================"
  echo "REPORT-ONLY SCAN COMPLETE"
  echo "======================================"
  exit 0
fi


if [ "$SCAN_FAILED" -ne 0 ]; then
  echo
  echo "======================================"
  echo "CONTAINER VULNERABILITY SCAN: FAILED"
  echo "======================================"
  exit 1
fi


echo
echo "======================================"
echo "CONTAINER VULNERABILITY SCAN: PASSED"
echo "======================================"