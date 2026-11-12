#!/usr/bin/env bash
# Policy asset hygiene (review 7.8 / R9):
#  1. A fragment file stacks/<stack>/fragments/frag-<name>.xml is wired up in
#     that stack (its .tf files mention "<name>").
#  2. Every other policy / spec XML is referenced by file name from a .tf file.
#  3. No XML file name exists in two places (one owner per asset).
#  4. Every *.xml file name referenced from Terraform exists.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
fail=0
existing() { while IFS= read -r p; do [[ -e "$p" ]] && printf '%s\n' "$p"; done; }
mapfile -t xml < <(git ls-files -co --exclude-standard -- '*.xml' | existing)
mapfile -t tf < <(git ls-files -co --exclude-standard -- '*.tf' | existing)

for f in "${xml[@]}"; do
  base=$(basename "$f")
  if [[ "$f" =~ ^stacks/([^/]+)/fragments/frag-(.+)\.xml$ ]]; then
    stack="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"
    if ! grep -qF "\"$name\"" stacks/"$stack"/*.tf; then
      echo "::error file=$f::fragment '$name' isn't wired up in stacks/$stack (add it to fragments.tf or delete the file)"; fail=1
    fi
  elif ! grep -qF "$base" "${tf[@]}"; then
    echo "::error file=$f::not referenced from any .tf file (delete it or wire it up)"; fail=1
  fi
done

dups=$(printf '%s\n' "${xml[@]}" | xargs -n1 basename | sort | uniq -d)
for d in $dups; do
  echo "::error::'$d' exists in more than one folder: $(printf '%s\n' "${xml[@]}" | grep "/$d$" | tr '\n' ' ')"; fail=1
done

while IFS=: read -r file _ name; do
  name="${name#[/\"]}"; name="${name%\"}"
  [[ "$name" == *'$'* ]] && continue
  if ! printf '%s\n' "${xml[@]}" | grep -q "/$name$"; then
    echo "::error file=$file::references missing XML file '$name'"; fail=1
  fi
done < <(grep -nEo '[/"][A-Za-z0-9_-]+\.xml"' "${tf[@]}" | sed -E 's#:[/"]([^"]+)"$#:\1#' || true)

[[ $fail -eq 0 ]] && echo "policy assets OK (${#xml[@]} files)"
exit $fail
