#!/usr/bin/env bash
# scrub-check.sh: refuse to let private details into this public repo.
#
#   scripts/scrub-check.sh --staged   # what's about to be committed (pre-commit hook)
#   scripts/scrub-check.sh --all      # every tracked file + commit authors (CI)
#
# Two layers:
#   1. Generic patterns below: IPs, emails, key/token formats. Public on purpose;
#      they reveal nothing.
#   2. A private denylist of literals specific to this project, never committed:
#      $SCRUB_DENYLIST (the text itself, used by CI from a repo secret), else the
#      file at $SCRUB_DENYLIST_FILE, else the file named by `git config scrub.denylist`
#      (local clone config, so the path never lands in the repo).
# No denylist = failure. A guard that silently skips half its checks reads as
# protection while protecting nothing.
#
# One-time setup per clone:
#   git config core.hooksPath .githooks
#   git config scrub.denylist <path to the private denylist>
set -uo pipefail

mode="${1:---staged}"
root="$(git rev-parse --show-toplevel)"
cd "$root"

# ── Layer 1: generic patterns (extended regex, case-insensitive) ─────────────
generic=(
  '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'                       # any IPv4 address
  '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}'                 # any email address
  'eyJ[A-Z0-9_-]{10,}\.[A-Z0-9_-]{10,}'                   # JWT
  '\b[a-z]{20}\.supabase\.(co|in)\b'                      # Supabase project URL
  '\b(prj|team|dpl)_[A-Z0-9]{20,}'                        # Vercel IDs
  '\b(sk|rk)_(live|test)_[A-Z0-9]{10,}'                   # Stripe keys
  '\bsb_(secret|publishable)_[A-Z0-9_-]{10,}'             # Supabase API keys
  '\b(ghp|gho|ghs|ghr)_[A-Z0-9]{30,}|github_pat_[A-Z0-9_]{30,}'  # GitHub tokens
  '\bre_[A-Z0-9]{8,}_[A-Z0-9]{8,}'                        # Resend keys
  '\bAKIA[0-9A-Z]{16}\b'                                  # AWS access keys
  'BEGIN [A-Z ]*PRIVATE KEY'                              # private key blocks
  '(api[_-]?key|secret|password|token)["'\'' ]*[:=] *["'\''][^"'\'' ]{12,}'  # inline secrets
)
# Addresses that are allowed to appear (placeholders and GitHub noreply).
email_allow='@(example\.(com|org|net)|users\.noreply\.github\.com)\b'

# ── Layer 2: private denylist ─────────────────────────────────────────────────
deny_file="$(mktemp)"; trap 'rm -f "$deny_file"' EXIT
if [[ -n "${SCRUB_DENYLIST:-}" ]]; then
  printf '%s\n' "$SCRUB_DENYLIST" > "$deny_file"
else
  src="${SCRUB_DENYLIST_FILE:-$(git config --get scrub.denylist || true)}"
  src="${src/#\~/$HOME}"
  if [[ -z "$src" || ! -r "$src" ]]; then
    echo "scrub-check: no private denylist (set SCRUB_DENYLIST, SCRUB_DENYLIST_FILE or 'git config scrub.denylist <path>'; got '${src}')." >&2
    echo "scrub-check: refusing to pass with only half the checks." >&2
    exit 2
  fi
  cp "$src" "$deny_file"
fi
sed -i -e 's/#.*$//' -e 's/[[:space:]]*$//' -e '/^$/d' "$deny_file"
if [[ ! -s "$deny_file" ]]; then
  echo "scrub-check: the private denylist is empty; refusing to pass." >&2
  exit 2
fi

# ── Collect content to scan ───────────────────────────────────────────────────
scan_dir="$(mktemp -d)"; trap 'rm -f "$deny_file"; rm -rf "$scan_dir"' EXIT
case "$mode" in
  --staged) mapfile -t files < <(git diff --cached --name-only --diff-filter=ACMR) ;;
  --all)    mapfile -t files < <(git ls-files) ;;
  --message) files=() ;;  # commit-msg hook: scan only the message file in $2
  *) echo "usage: $0 [--staged|--all|--message <file>]" >&2; exit 2 ;;
esac

self="scripts/scrub-check.sh"
for f in "${files[@]}"; do
  out="$scan_dir/$f"; mkdir -p "$(dirname "$out")"
  if [[ "$mode" == --staged ]]; then git show ":$f" > "$out" 2>/dev/null; else cp "$f" "$out"; fi
done
# File names can leak too.
printf '%s\n' "${files[@]}" > "$scan_dir/.scrub-paths"
if [[ "$mode" == --message ]]; then
  # Git's own "# Please enter the commit message" comment lines are dropped first.
  grep -v '^#' "${2:?--message needs a file}" > "$scan_dir/.scrub-commit-message"
fi
# Commit metadata (--all only): author/committer emails and every commit message,
# since the history is public too.
if [[ "$mode" == --all ]]; then
  git log --format='%ae%n%ce' | sort -u > "$scan_dir/.scrub-commit-emails"
  git log --format='%B' > "$scan_dir/.scrub-commit-messages"
fi

fail=0
report() { echo "  ✗ $1"; fail=1; }

# Generic layer (this script is skipped: it necessarily contains the patterns).
for pat in "${generic[@]}"; do
  while IFS= read -r hit; do
    [[ "$hit" == "$scan_dir/$self:"* ]] && continue
    line="${hit#"$scan_dir/"}"
    if [[ "$pat" == *'@[A-Z0-9.-]+'* ]] && grep -qiE "$email_allow" <<<"$line"; then continue; fi
    report "generic: ${line:0:160}"
  done < <(grep -rIniE "$pat" "$scan_dir" 2>/dev/null)
done

# Private layer: reports file:line only, never the matched secret, because CI logs are public.
while IFS= read -r hit; do
  loc="${hit#"$scan_dir/"}"
  report "private denylist match at ${loc%%:*}:$(cut -d: -f2 <<<"$loc")"
done < <(grep -rIniFf "$deny_file" "$scan_dir" 2>/dev/null | cut -d: -f1,2)

if (( fail )); then
  echo "scrub-check: FAILED. Remove the lines above before this goes public." >&2
  exit 1
fi
echo "scrub-check: clean (${#files[@]} files, $(wc -l < "$deny_file") private terms, ${#generic[@]} patterns)."
