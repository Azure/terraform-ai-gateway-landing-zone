#!/usr/bin/env bash
# Policy asset hygiene (review findings: duplicated / diverged / unused XML).
#  1. Every policy XML in the repository is referenced from Terraform (no dead files).
#  2. No policy file name exists in two places (one owner per asset, review §7.8).
#  3. Every "policies/<file>.xml" literal referenced from Terraform exists.
# APIM policy XML embeds C# expressions, so it isn't strictly well-formed XML;
# well-formedness is validated by APIM at apply time, not here.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
fail=0
existing() { while IFS= read -r p; do [[ -e "$p" ]] && printf '%s\n' "$p"; done; }
mapfile -t xml < <(git ls-files -co --exclude-standard -- '*.xml' | existing)
mapfile -t tf  < <(git ls-files -co --exclude-standard -- '*.tf' | existing)

for f in "${xml[@]}"; do
  base=$(basename "$f")
  if ! grep -qF "$base" "${tf[@]}"; then
    echo "::error file=$f::policy file is not referenced from any .tf file (delete it or wire it up)"; fail=1
  fi
done

dups=$(printf '%s\n' "${xml[@]}" | xargs -n1 basename | sort | uniq -d)
for d in $dups; do
  echo "::error::policy file '$d' exists in more than one folder: $(printf '%s\n' "${xml[@]}" | grep "/$d$" | tr '\n' ' ')"; fail=1
done

while IFS=: read -r file _ ref; do
  name=$(sed -E 's#.*policies/([A-Za-z0-9._-]+\.xml).*#\1#' <<<"$ref")
  if ! printf '%s\n' "${xml[@]}" | grep -q "/$name$"; then
    echo "::error file=$file::references missing policy file '$name'"; fail=1
  fi
done < <(grep -nEo 'policies/[A-Za-z0-9._-]+\.xml' "${tf[@]}" || true)

[[ $fail -eq 0 ]] && echo "policy assets OK (${#xml[@]} files)"
exit $fail
