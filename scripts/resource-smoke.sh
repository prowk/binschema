#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

max_rss_kib="${RESOURCE_MAX_RSS_KIB:-786432}"
enforce_rss="${RESOURCE_ENFORCE_RSS:-1}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

moon build --target native benchmarks/resource_probe --release --deny-warn
moon build --target native cmd/main --release --deny-warn

find_executable() {
  local directory="$1"
  local executable
  executable="$(find "$directory" -maxdepth 1 -type f -perm -111 -print -quit)"
  if [[ -z "$executable" ]]; then
    echo "no native executable found under $directory" >&2
    exit 1
  fi
  printf '%s\n' "$executable"
}

probe="$(find_executable _build/native/release/build/benchmarks/resource_probe)"
cli="$(find_executable _build/native/release/build/cmd/main)"

check_rss() {
  local scenario="$1"
  local rss_kib="$2"
  if [[ "$enforce_rss" == "1" ]] && (( rss_kib > max_rss_kib )); then
    echo "$scenario exceeded RSS smoke limit: ${rss_kib} KiB > ${max_rss_kib} KiB" >&2
    exit 1
  fi
}

run_probe() {
  local scenario="$1"
  local output="$work_dir/$scenario.json"
  local timing="$work_dir/$scenario.time"
  /usr/bin/time -q -f $'%e\t%M\t%x' -o "$timing" \
    "$probe" "$scenario" > "$output"
  local elapsed_seconds max_rss exit_code
  IFS=$'\t' read -r elapsed_seconds max_rss exit_code < "$timing"
  [[ "$exit_code" == "0" ]]
  check_rss "$scenario" "$max_rss"
  cat "$output"
  printf '{"scenario":"%s","elapsed_seconds":%s,"max_rss_kib":%s,"exit_code":%s}\n' \
    "$scenario" "$elapsed_seconds" "$max_rss" "$exit_code"
}

for scenario in large-input elf-repeated-names short-frames many-traces; do
  run_probe "$scenario"
done

oversize_file="$work_dir/oversize.bin"
truncate -s $((64 * 1024 * 1024 + 1)) "$oversize_file"
cli_timing="$work_dir/cli-limit.time"
set +e
/usr/bin/time -q -f $'%e\t%M\t%x' -o "$cli_timing" \
  "$cli" inspect "$oversize_file" --format png > "$work_dir/cli-limit.out"
cli_status=$?
set -e
if [[ "$cli_status" != "3" ]]; then
  cat "$work_dir/cli-limit.out" >&2
  echo "CLI oversize input returned $cli_status, expected data-error exit code 3" >&2
  exit 1
fi
IFS=$'\t' read -r cli_elapsed cli_rss cli_recorded_status < "$cli_timing"
[[ "$cli_recorded_status" == "3" ]]
check_rss "cli-input-limit" "$cli_rss"
printf '{"scenario":"cli-input-limit","input_bytes":%s,"limit_bytes":%s,"elapsed_seconds":%s,"max_rss_kib":%s,"exit_code":%s}\n' \
  "$((64 * 1024 * 1024 + 1))" "$((64 * 1024 * 1024))" \
  "$cli_elapsed" "$cli_rss" "$cli_status"
