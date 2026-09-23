#!/bin/bash
#
# secrets-check.sh — the single source of truth for "no credential is in this repo".
#
# Run by BOTH .githooks/pre-push (before anything leaves the machine) and
# .github/workflows/secrets-guard.yml (backstop for pushes that skip the hook).
# Sharing one script is deliberate: two copies of these rules would drift, and a
# guard that has quietly drifted is worse than no guard.
#
# Design rules learned from an adversarial review that defeated the previous version:
#   - Exclude by VALUE, never by path. Path exclusions create a permitted hiding
#     place: the previous guard skipped the two files whose purpose was to hold a
#     `JEV_BEARER_TOKEN =` line, so inlining the real key there passed every check.
#   - No `git grep -I`. It skips anything git considers binary, and a token in a
#     file with a NUL byte sailed straight through.
#   - Check the class of thing, not one filename. A second secret in Secrets.json
#     was uncovered end to end.
#   - Match a credential-SHAPED value (12+ token characters), not any non-space
#     character. Otherwise this script's own documentation trips it, and the
#     tempting fix for that is the path exclusion this design exists to avoid.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

FAIL=0
ok()  { printf '  \033[32mok\033[0m    %s\n' "$1"; }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=1; }

# 1. The TypeSafe/Jev key belongs in the Cloudflare Worker's environment and nowhere
#    else. Nothing in this repo should assign it a value.
hits=$(git grep -nE \
  -e '(JEV|TYPESAFE)[A-Z_]*(TOKEN|KEY|SECRET)[[:space:]]*[=:][[:space:]]*['"'"'"]?[A-Za-z0-9_.-]{12,}' \
  -e 'Authorization[[:space:]]*:[[:space:]]*.?[Bb]earer[[:space:]]+[A-Za-z0-9_.-]{16,}' \
  HEAD 2>/dev/null || true)
if [ -n "$hits" ]; then bad "credential assignment in tracked content:"; echo "$hits" | sed 's/^/        /'; \
else ok "no Jev/TypeSafe credential assignment in tracked content"; fi

# 2. No credential-shaped file may be tracked, whatever it is called internally.
paths=$(git ls-files | grep -iE '(^|/)(\.env($|\.)|\.dev\.vars|secrets?\.|.*\.(xcconfig|pem|p8|p12|key|keystore|mobileprovision)$)' || true)
if [ -n "$paths" ]; then bad "credential-shaped file is tracked:"; echo "$paths" | sed 's/^/        /'; \
else ok "no credential-shaped file is tracked"; fi

# 3. A .gitignore below the root can NEGATE the root rules (`!Secrets.xcconfig`
#    re-includes, because Config/ itself is not excluded). Proven attack.
nested=$(git ls-files '*/.gitignore' || true)
if [ -n "$nested" ]; then bad "nested .gitignore can negate the root rules:"; echo "$nested" | sed 's/^/        /'; \
else ok "no nested .gitignore"; fi

# 4. The credential block must still be in .gitignore. Without this, a future edit
#    silently re-arms the leak for the next `git add -A`.
for pat in '*.xcconfig' '.dev.vars' 'Secrets.*' '*.p8'; do
  if git show HEAD:.gitignore 2>/dev/null | grep -qxF "$pat"; then :; else bad ".gitignore lost its '$pat' rule"; fi
done
[ "$FAIL" -eq 0 ] && ok ".gitignore credential block intact"

# 5. Positive control: the rules must actually match. If this fails the checks above
#    are meaningless, which is exactly how the previous version passed over nothing.
for probe in .dev.vars Config/Secrets.xcconfig Quant/Secrets.plist .env jev.p8; do
  r=$(git check-ignore --no-index -v "$probe" 2>/dev/null || true)
  case "$r" in
    ""|*:!*) bad "positive control: $probe is NOT ignored" ;;
  esac
done
[ "$FAIL" -eq 0 ] && ok "positive control: credential paths are ignored"

if [ "$FAIL" -ne 0 ]; then
  printf '\n\033[31mSecrets check FAILED.\033[0m The Jev key lives in the Cloudflare Worker env, not here.\n'
  exit 1
fi
printf '\n\033[32mSecrets check passed.\033[0m\n'
