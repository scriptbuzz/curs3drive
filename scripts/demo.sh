#!/usr/bin/env bash
# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
# Runs a live end-to-end demo of the file share on macOS and records it.
#
# The demo checks the VPN and the share, copies a made-up CUR workbook to the
# share, waits for the gateway to upload it to S3, compares checksums, saves an
# edited version, and shows a file written straight to S3 appearing on the
# share. Every step's caption, command, output and duration is written to
# docs/demo/recording.log, which tools/build_demo.py turns into the demo pages.
#
# Before running it:
#   1. Connect the AWS VPN Client.
#   2. Mount the share in Finder, so it is available at /Volumes/cur.
#   3. Sign in to AWS: aws sso login --profile sandbox01
#
# Usage, from the repository root:
#   scripts/demo.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

export AWS_PROFILE="${AWS_PROFILE:-sandbox01}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_PAGER=""
SHARE="${SHARE:-/Volumes/cur}"
LOG="${DEMO_LOG:-$root/docs/demo/recording.log}"
TIMEFORMAT='The copy took %R seconds.'

GATEWAY_IP="$(cd terraform && terraform output -raw gateway_private_ip)"
GATEWAY_ID="$(cd terraform && terraform output -raw gateway_id)"
BUCKET="$(cd terraform && terraform output -raw bucket_name)"
GATEWAY_ARN="$(aws storagegateway list-gateways --query "Gateways[?GatewayId=='$GATEWAY_ID'].GatewayARN | [0]" --output text)"
SHARE_ARN="$(aws storagegateway list-file-shares --gateway-arn "$GATEWAY_ARN" --query 'FileShareInfoList[0].FileShareARN' --output text)"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
FILE="cur-demo-$RUN_ID.xlsx"
EXPORT="cur-export-$RUN_ID.xlsx"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$(dirname "$LOG")"
: > "$LOG"
failures=0
demo_start=$SECONDS

bold=$'\033[1m'; cyan=$'\033[36m'; green=$'\033[32m'; red=$'\033[31m'; dim=$'\033[2m'; reset=$'\033[0m'

now() { python3 -c 'import time; print(f"{time.time():.2f}")'; }

step() {
  printf '\n%s%s%s %s\n' "$bold$cyan" "Step $1." "$reset" "$bold$2$reset"
  echo "@@STEP $1|$2" >> "$LOG"
}

run() {
  local cmd="$1" t0 t1 output status
  printf '%s$ %s%s\n' "$dim" "$cmd" "$reset"
  echo "@@CMD $cmd" >> "$LOG"
  t0="$(now)"
  output="$(eval "$cmd" 2>&1)"
  status=$?
  t1="$(now)"
  [[ -n "$output" ]] && printf '%s\n' "$output"
  { echo "@@OUT"; printf '%s\n' "$output"; echo "@@END $status $(python3 -c "print(round($t1 - $t0, 1))")"; } >> "$LOG"
  if [[ $status -ne 0 ]]; then
    failures=$((failures + 1))
    printf '%sThis command failed with exit code %s.%s\n' "$red" "$status" "$reset"
  fi
  return 0
}

plural() { [[ "$1" -eq 1 ]] && echo "$1 $2" || echo "$1 ${2}s"; }

count_versions() {
  local n
  n="$(aws s3api list-object-versions --bucket "$BUCKET" --prefix "$1" --query "length(Versions[?Key=='$1'] || \`[]\`)" --output text 2>/dev/null)"
  [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo 0
}

# Waits until S3 holds more versions of a file than it did before the save.
wait_for_new_version() {
  local key="$1" before="$2" start=$SECONDS n
  while true; do
    n="$(count_versions "$key")"
    if (( n > before )); then
      echo "S3 had a new version of the file $(plural $((SECONDS - start)) second) after the save finished."
      echo "S3 now holds $(plural "$n" version) of the file."
      return 0
    fi
    (( SECONDS - start >= 300 )) && { echo "S3 did not show a new version within 300 seconds."; return 1; }
    sleep 2
  done
}

# Waits until a file appears in the mounted share.
wait_for_share_file() {
  local path="$1" start=$SECONDS
  until ls "$path" > /dev/null 2>&1; do
    (( SECONDS - start >= 420 )) && { echo "The file did not appear on the share within 420 seconds."; return 1; }
    sleep 5
  done
  echo "The file appeared on the share $(plural $((SECONDS - start)) second) after the gateway was asked to refresh."
}

compare_checksums() {
  local a b
  a="$(shasum -a 256 "$WORK/$FILE" | cut -d' ' -f1)"
  b="$(shasum -a 256 "$WORK/from-s3.xlsx" | cut -d' ' -f1)"
  echo "Local copy:    $a"
  echo "Copy from S3:  $b"
  if [[ "$a" == "$b" ]]; then echo "The checksums match."; else echo "The checksums differ."; return 1; fi
}

printf '%sLive demo: Excel files in Amazon S3, opened as a network drive%s\n' "$bold" "$reset"
printf 'Gateway %s at %s, bucket %s, share %s, Region %s.\n' "$GATEWAY_ID" "$GATEWAY_IP" "$BUCKET" "$SHARE" "$AWS_REGION"
{
  echo "@@META started=$(date '+%Y-%m-%d %H:%M %Z')"
  echo "@@META gateway=$GATEWAY_ID"
  echo "@@META address=$GATEWAY_IP"
  echo "@@META bucket=$BUCKET"
  echo "@@META share=$SHARE"
  echo "@@META region=$AWS_REGION"
} >> "$LOG"

step 1 "The AWS VPN Client is connected, so the Mac has an address from the VPN range."
run "ifconfig | grep 'inet 10\.50\.'"

step 2 "The gateway answers a real SMB handshake through the VPN tunnel. No password is sent."
run 'python3 tools/smb_probe.py "$GATEWAY_IP"'

step 3 "Finder has mounted the share, and the session is encrypted."
run 'mount | grep " on $SHARE "'
run 'smbutil statshares -m "$SHARE" | grep -E "SMB_VERSION|SMB_CURR_ENCRYPT_ALGORITHM"'

step 4 "The gateway is running, and its cache disk is attached."
run 'aws storagegateway describe-gateway-information --gateway-arn "$GATEWAY_ARN" --query "{State:GatewayState,Software:SoftwareVersion,Type:GatewayType}" --output table'
run 'aws storagegateway describe-cache --gateway-arn "$GATEWAY_ARN" --query "{CacheBytes:CacheAllocatedInBytes,UsedPercent:CacheUsedPercentage,WaitingForUploadPercent:CacheDirtyPercentage}" --output table'

step 5 "Create a workbook with 20,000 made-up CUR rows."
run 'python3 tools/make_sample_workbook.py "$WORK/$FILE" --rows 20000 --edition 1'

step 6 "Copy the workbook to the share, the same way Excel writes a file it saves."
before="$(count_versions "demo/$FILE")"
run 'mkdir -p "$SHARE/demo" && time cp "$WORK/$FILE" "$SHARE/demo/$FILE"'

step 7 "The gateway uploads the file to S3 in the background."
run 'wait_for_new_version "demo/$FILE" "$before"'
run 'aws s3api head-object --bucket "$BUCKET" --key "demo/$FILE" --query "{Bytes:ContentLength,Saved:LastModified,Encryption:ServerSideEncryption}" --output table'

step 8 "Download the file straight from S3 and compare checksums with the original."
run 'aws s3 cp "s3://$BUCKET/demo/$FILE" "$WORK/from-s3.xlsx" --only-show-errors && compare_checksums'

step 9 "Save an edited version through the share. S3 keeps the previous version."
before="$(count_versions "demo/$FILE")"
run 'python3 tools/make_sample_workbook.py "$WORK/$FILE" --rows 20000 --edition 2 && time cp "$WORK/$FILE" "$SHARE/demo/$FILE"'
run 'wait_for_new_version "demo/$FILE" "$before"'
run 'aws s3api list-object-versions --bucket "$BUCKET" --prefix "demo/$FILE" --query "Versions[].{Latest:IsLatest,Bytes:Size,Saved:LastModified}" --output table'

step 10 "A file written straight to S3, as a CUR export is, appears on the share."
run 'python3 tools/make_sample_workbook.py "$WORK/$EXPORT" --rows 1000 && aws s3 cp "$WORK/$EXPORT" "s3://$BUCKET/demo/$EXPORT" --only-show-errors && echo "Uploaded $EXPORT straight to S3."'
run 'aws storagegateway refresh-cache --file-share-arn "$SHARE_ARN" --folder-list /demo --recursive --query NotificationId --output text'
run 'wait_for_share_file "$SHARE/demo/$EXPORT"'
run 'ls -l "$SHARE/demo" | tail -n +2'

total=$((SECONDS - demo_start))
echo "@@DONE failures=$failures seconds=$total" >> "$LOG"
if (( failures == 0 )); then
  printf '\n%sThe demo finished in %s seconds, and every step succeeded.%s\n' "$bold$green" "$total" "$reset"
else
  printf '\n%sThe demo finished in %s seconds, and %s failed.%s\n' "$bold$red" "$total" "$(plural "$failures" command)" "$reset"
fi
echo "The recording is in ${LOG#$root/}."
