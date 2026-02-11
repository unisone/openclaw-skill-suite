#!/usr/bin/env bash
# browse-inspo.sh — Open design inspiration sites by category
# Usage: browse-inspo.sh [category]
# Categories: web, landing, saas, navbar, cta, animation, mobile, brand, icons, 3d-icons, components, hero, all

set -euo pipefail

get_url() {
  case "$1" in
    web)        echo "https://curated.design" ;;
    landing)    echo "https://landing.love" ;;
    saas)       echo "https://saaspo.com" ;;
    navbar)     echo "https://navbar.gallery" ;;
    cta)        echo "https://cta.gallery" ;;
    animation)  echo "https://appmotion.design" ;;
    mobile)     echo "https://mobbin.com" ;;
    brand)      echo "https://rebrand.gallery" ;;
    icons)      echo "https://hugeicons.com" ;;
    3d-icons)   echo "https://icoon.co" ;;
    components) echo "https://component.gallery" ;;
    hero)       echo "https://herocapture.com" ;;
    *)          return 1 ;;
  esac
}

ALL_CATS="web landing saas navbar cta animation mobile brand icons 3d-icons components hero"

category="${1:-}"

if [[ -z "$category" ]]; then
  echo "Design Inspiration Sites:"
  echo ""
  for key in $ALL_CATS; do
    printf "  %-12s → %s\n" "$key" "$(get_url "$key")"
  done
  echo ""
  echo "Usage: browse-inspo.sh <category>"
  echo "       browse-inspo.sh all  (opens all)"
  exit 0
fi

open_url() {
  local url="$1"
  if command -v open &>/dev/null; then
    open "$url"
  elif command -v xdg-open &>/dev/null; then
    xdg-open "$url"
  else
    echo "Open: $url"
  fi
}

if [[ "$category" == "all" ]]; then
  for key in $ALL_CATS; do
    open_url "$(get_url "$key")"
  done
  echo "Opened all 12 design inspiration sites"
  exit 0
fi

url="$(get_url "$category" 2>/dev/null)" || {
  echo "Unknown category: $category"
  echo "Available: $ALL_CATS"
  exit 1
}

open_url "$url"
echo "Opened $category → $url"
