#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd -P)"
SWIFT_PACKAGE_DIR="${OPENOATS_SWIFT_DIR:-$ROOT_DIR/OpenOats}"
SWIFT_PACKAGE_REL="${SWIFT_PACKAGE_DIR#"$ROOT_DIR"/}"

EEDOM_IMAGE="${EEDOM_IMAGE:-eedom:latest}"
EEDOM_PLATFORM="${EEDOM_PLATFORM:-}"
EEDOM_SCANNERS="${EEDOM_SCANNERS:-complexity,cpd,cspell,gitleaks,trivy}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"
REPORT_FORMAT="both"
OUTPUT_PREFIX=""
DRY_RUN=0

BASE_REF="${EEDOM_BASE_REF:-origin/main}"
PR_NUMBER=""
DIFF_PATH=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/eedom_scan.sh [options] full
  scripts/eedom_scan.sh [options] folder <path-under-OpenOats>
  scripts/eedom_scan.sh [options] pr [--base <ref>]
  scripts/eedom_scan.sh [options] pr --pr <number>
  scripts/eedom_scan.sh [options] pr --diff <diff-file>

Runs eedom from a container against the Swift package. Python/npm scanners are
not used by default.

Modes:
  full                 Scan the whole OpenOats Swift package.
  folder <path>        Scan one folder under OpenOats/.
  pr                   Scan Swift files changed in the current branch PR diff.

Options:
  --image <image>      Container image to run. Default: eedom:latest
  --platform <value>   Container platform. Default: linux/arm64 on Apple Silicon,
                       linux/amd64 on x86_64.
  --engine <name>      Container engine: podman or docker. Default: auto-detect.
  --scanners <list>    Comma-separated eedom scanners.
                       Default: complexity,cpd,cspell,gitleaks,trivy
  --format <fmt>       json, markdown, or both. Default: both
  --output-prefix <p>  Write root reports as <p>.json and/or <p>.md.
  --base <ref>         PR mode base ref. Default: origin/main
  --pr <number>        PR mode: use `gh pr diff <number>`.
  --diff <file>        PR mode: use an existing unified diff.
  --dry-run            Print container commands without running them.
  -h, --help           Show this help.

Output defaults:
  full      eedom_report.json, EEDOM_REVIEW_REPORT.md
  folder    eedom_report_folder_<slug>.json, EEDOM_REVIEW_REPORT_folder_<slug>.md
  pr        eedom_report_pr.json, EEDOM_REVIEW_REPORT_pr.md

Environment:
  EEDOM_IMAGE, EEDOM_PLATFORM, EEDOM_SCANNERS, CONTAINER_ENGINE,
  OPENOATS_SWIFT_DIR, EEDOM_BASE_REF
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

detect_platform() {
  case "$(uname -m)" in
    arm64|aarch64) echo "linux/arm64" ;;
    x86_64|amd64) echo "linux/amd64" ;;
    *) die "unsupported host architecture: $(uname -m). Set EEDOM_PLATFORM explicitly." ;;
  esac
}

detect_engine() {
  if [[ -n "$CONTAINER_ENGINE" ]]; then
    command -v "$CONTAINER_ENGINE" >/dev/null 2>&1 || die "$CONTAINER_ENGINE not found"
    echo "$CONTAINER_ENGINE"
  elif command -v podman >/dev/null 2>&1; then
    echo "podman"
  elif command -v docker >/dev/null 2>&1; then
    echo "docker"
  else
    die "podman or docker is required"
  fi
}

image_exists() {
  local engine="$1"
  if [[ "$engine" == "podman" ]]; then
    "$engine" image exists "$EEDOM_IMAGE"
  else
    "$engine" image inspect "$EEDOM_IMAGE" >/dev/null 2>&1
  fi
}

slugify() {
  echo "$1" | sed 's#^OpenOats/##; s#[^A-Za-z0-9._-]#_#g; s#_*$##'
}

abs_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd -P)
  else
    (cd "$(dirname "$path")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$path")")
  fi
}

container_path_for_host() {
  local host_path
  host_path="$(abs_path "$1")"
  case "$host_path" in
    "$ROOT_DIR") echo "/workspace" ;;
    "$ROOT_DIR"/*) echo "/workspace/${host_path#"$ROOT_DIR"/}" ;;
    *) die "path is outside repo root: $host_path" ;;
  esac
}

resolve_folder() {
  local requested="$1"
  local candidate=""

  if [[ "$requested" = /* ]]; then
    candidate="$requested"
  elif [[ -d "$ROOT_DIR/$requested" ]]; then
    candidate="$ROOT_DIR/$requested"
  elif [[ -d "$SWIFT_PACKAGE_DIR/$requested" ]]; then
    candidate="$SWIFT_PACKAGE_DIR/$requested"
  else
    die "folder not found: $requested"
  fi

  candidate="$(abs_path "$candidate")"
  case "$candidate" in
    "$SWIFT_PACKAGE_DIR"|"$SWIFT_PACKAGE_DIR"/*) echo "$candidate" ;;
    *) die "folder scans must target OpenOats Swift package paths, got: $candidate" ;;
  esac
}

parse_common_option() {
  case "${1:-}" in
    --image) EEDOM_IMAGE="${2:-}"; [[ -n "$EEDOM_IMAGE" ]] || die "--image requires a value"; return 2 ;;
    --platform) EEDOM_PLATFORM="${2:-}"; [[ -n "$EEDOM_PLATFORM" ]] || die "--platform requires a value"; return 2 ;;
    --engine) CONTAINER_ENGINE="${2:-}"; [[ -n "$CONTAINER_ENGINE" ]] || die "--engine requires a value"; return 2 ;;
    --scanners) EEDOM_SCANNERS="${2:-}"; [[ -n "$EEDOM_SCANNERS" ]] || die "--scanners requires a value"; return 2 ;;
    --format)
      REPORT_FORMAT="${2:-}"
      [[ "$REPORT_FORMAT" == "json" || "$REPORT_FORMAT" == "markdown" || "$REPORT_FORMAT" == "both" ]] || die "--format must be json, markdown, or both"
      return 2
      ;;
    --output-prefix) OUTPUT_PREFIX="${2:-}"; [[ -n "$OUTPUT_PREFIX" ]] || die "--output-prefix requires a value"; return 2 ;;
    --base) BASE_REF="${2:-}"; [[ -n "$BASE_REF" ]] || die "--base requires a value"; return 2 ;;
    --pr) PR_NUMBER="${2:-}"; [[ -n "$PR_NUMBER" ]] || die "--pr requires a value"; return 2 ;;
    --diff) DIFF_PATH="${2:-}"; [[ -n "$DIFF_PATH" ]] || die "--diff requires a value"; return 2 ;;
    --dry-run) DRY_RUN=1; return 1 ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unknown option: $1" ;;
    *) return 0 ;;
  esac
}

run_container() {
  local engine="$1"
  shift

  local cmd=(
    "$engine" run --rm
    --platform "$EEDOM_PLATFORM"
    --user 0:0
    -v "$ROOT_DIR:/workspace:rw"
    "$EEDOM_IMAGE"
    "$@"
  )

  printf '+'
  printf ' %q' "${cmd[@]}"
  printf '\n'

  if [[ "$DRY_RUN" == "0" ]]; then
    "${cmd[@]}"
  fi
}

run_review() {
  local engine="$1"
  local json_name="$2"
  local markdown_name="$3"
  shift 3

  if [[ "$REPORT_FORMAT" == "json" || "$REPORT_FORMAT" == "both" ]]; then
    run_container "$engine" review "$@" --format json --output "/workspace/$json_name"
  fi

  if [[ "$REPORT_FORMAT" == "markdown" || "$REPORT_FORMAT" == "both" ]]; then
    run_container "$engine" review "$@" --format markdown --output "/workspace/$markdown_name"
  fi
}

normalize_swift_diff() {
  awk '
    function is_swift(path) {
      return path ~ /\.swift$/ || path == "Package.swift" || path == "Package.resolved"
    }
    /^diff --git / {
      line = $0
      path = line
      sub(/^diff --git a\//, "", path)
      sub(/ b\/.*/, "", path)
      norm = path
      sub(/^OpenOats\//, "", norm)
      keep = is_swift(norm) && (path == norm || path == "OpenOats/" norm)
      if (keep) {
        gsub(/ a\/OpenOats\//, " a/", line)
        gsub(/ b\/OpenOats\//, " b/", line)
        print line
      }
      next
    }
    keep {
      line = $0
      sub(/^--- a\/OpenOats\//, "--- a/", line)
      sub(/^\+\+\+ b\/OpenOats\//, "+++ b/", line)
      print line
    }
  ' "$1"
}

make_pr_diff() {
  mkdir -p "$ROOT_DIR/.temp"
  local raw_diff="$ROOT_DIR/.temp/eedom-pr.raw.diff"
  local filtered_diff="$ROOT_DIR/.temp/eedom-pr.diff"

  if [[ -n "$DIFF_PATH" ]]; then
    [[ -f "$DIFF_PATH" ]] || die "diff file not found: $DIFF_PATH"
    normalize_swift_diff "$DIFF_PATH" > "$filtered_diff"
  elif [[ -n "$PR_NUMBER" ]]; then
    command -v gh >/dev/null 2>&1 || die "gh is required for --pr"
    gh pr diff "$PR_NUMBER" > "$raw_diff"
    normalize_swift_diff "$raw_diff" > "$filtered_diff"
  else
    git -C "$SWIFT_PACKAGE_DIR" diff --relative --no-ext-diff "$BASE_REF...HEAD" \
      -- '*.swift' 'Package.swift' 'Package.resolved' > "$filtered_diff"
  fi

  [[ -s "$filtered_diff" ]] || die "PR diff contains no Swift package changes"
  echo "$filtered_diff"
}

[[ -d "$SWIFT_PACKAGE_DIR" ]] || die "Swift package directory not found: $SWIFT_PACKAGE_DIR"

MODE=""
while [[ $# -gt 0 ]]; do
  if parse_common_option "$@"; then
    MODE="$1"
    shift
    break
  else
    consumed="$?"
    shift "$consumed"
  fi
done

[[ -n "$MODE" ]] || { usage; exit 1; }
[[ "$MODE" == "full" || "$MODE" == "folder" || "$MODE" == "pr" ]] || die "unknown mode: $MODE"

FOLDER_PATH=""
if [[ "$MODE" == "folder" ]]; then
  [[ $# -gt 0 ]] || die "folder mode requires a folder path"
  FOLDER_PATH="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  if parse_common_option "$@"; then
    die "unexpected argument: $1"
  else
    consumed="$?"
    shift "$consumed"
  fi
done

EEDOM_PLATFORM="${EEDOM_PLATFORM:-$(detect_platform)}"
ENGINE="$(detect_engine)"
image_exists "$ENGINE" || die "container image not found: $EEDOM_IMAGE. Build it first, for example from eedom: bash scripts/build.sh --fast"

CONTAINER_REPO="/workspace/$SWIFT_PACKAGE_REL"
BASE_REVIEW_ARGS=(--repo-path "$CONTAINER_REPO" --scanners "$EEDOM_SCANNERS")

case "$MODE" in
  full)
    json_name="${OUTPUT_PREFIX:+$OUTPUT_PREFIX.json}"
    markdown_name="${OUTPUT_PREFIX:+$OUTPUT_PREFIX.md}"
    json_name="${json_name:-eedom_report.json}"
    markdown_name="${markdown_name:-EEDOM_REVIEW_REPORT.md}"
    run_review "$ENGINE" "$json_name" "$markdown_name" "${BASE_REVIEW_ARGS[@]}"
    ;;
  folder)
    folder_host="$(resolve_folder "$FOLDER_PATH")"
    folder_container="$(container_path_for_host "$folder_host")"
    folder_rel="${folder_host#"$SWIFT_PACKAGE_DIR"/}"
    slug="$(slugify "$folder_rel")"
    json_name="${OUTPUT_PREFIX:+$OUTPUT_PREFIX.json}"
    markdown_name="${OUTPUT_PREFIX:+$OUTPUT_PREFIX.md}"
    json_name="${json_name:-eedom_report_folder_$slug.json}"
    markdown_name="${markdown_name:-EEDOM_REVIEW_REPORT_folder_$slug.md}"
    run_review "$ENGINE" "$json_name" "$markdown_name" \
      "${BASE_REVIEW_ARGS[@]}" --scope folder --package "$folder_container"
    ;;
  pr)
    diff_host="$(make_pr_diff)"
    diff_container="$(container_path_for_host "$diff_host")"
    json_name="${OUTPUT_PREFIX:+$OUTPUT_PREFIX.json}"
    markdown_name="${OUTPUT_PREFIX:+$OUTPUT_PREFIX.md}"
    json_name="${json_name:-eedom_report_pr.json}"
    markdown_name="${markdown_name:-EEDOM_REVIEW_REPORT_pr.md}"
    run_review "$ENGINE" "$json_name" "$markdown_name" \
      "${BASE_REVIEW_ARGS[@]}" --scope diff --diff "$diff_container"
    ;;
esac
