SCAN_FAILED=0

while IFS= read -r image; do

  if [ -z "$image" ]; then
    continue
  fi

  echo
  echo "--------------------------------------"
  echo "Scanning:"
  echo "  $image"
  echo "--------------------------------------"

  if ! docker run \
    --rm \
    --volume trivy-cache:/root/.cache/ \
    "$TRIVY_IMAGE" \
    image \
      --no-progress \
      --scanners vuln \
      --severity HIGH,CRITICAL \
      --ignore-unfixed \
      --exit-code 1 \
      "$image"
  then
    echo
    echo "Vulnerabilities found in:"
    echo "  $image"

    SCAN_FAILED=1
  fi

done <<< "$IMAGES"

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