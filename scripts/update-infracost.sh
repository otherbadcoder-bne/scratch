#!/usr/bin/env bash
set -euo pipefail

# Finds directories containing .tf files with a README that has infracost markers,
# runs infracost breakdown, and injects the output between the markers.

for dir in $(find . -name "*.tf" -exec dirname {} \; | sort -u); do
  README="$dir/README.md"

  if [[ ! -f "$README" ]] || ! grep -q "BEGIN_INFRACOST" "$README"; then
    continue
  fi

  COST=$(infracost breakdown --path "$dir" --format table --no-color --log-level error 2>/dev/null) || true

  python3 -c "
import sys

marker_start = '<!-- BEGIN_INFRACOST -->'
marker_end = '<!-- END_INFRACOST -->'

with open('$README') as f:
    readme = f.read()

start = readme.index(marker_start) + len(marker_start)
end = readme.index(marker_end)

cost = sys.stdin.read()
# Strip trailing whitespace from each line to avoid fighting with trailing-whitespace hook
cost = '\n'.join(line.rstrip() for line in cost.splitlines()) + '\n'
new_content = readme[:start] + '\n\`\`\`\n' + cost + '\`\`\`\n' + readme[end:]

with open('$README', 'w') as f:
    f.write(new_content)
" <<< "$COST"

  git add "$README"
done
