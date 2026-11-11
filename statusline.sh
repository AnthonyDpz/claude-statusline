#!/bin/bash
# Claude Code status line : modele | dossier | branche git | contexte | session | semaine
input=$(cat)

if command -v jq >/dev/null 2>&1; then
  model=$(echo "$input" | jq -r '.model.display_name // empty')
  dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
  used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
  session=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
  week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
  session_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
  week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
  duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
else
  # Repli sans jq : extraction approximative par sed (pas de session/semaine)
  model=$(echo "$input" | sed -n 's/.*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  dir=$(echo "$input" | sed -n 's/.*"current_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  [ -z "$dir" ] && dir=$(echo "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  used=$(echo "$input" | sed -n 's/.*"used_percentage"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' | head -n1)
  session=""
  week=""
  session_reset=""
  week_reset=""
  duration_ms=""
fi

# Secondes -> "2j 4h" / "2h10" / "35min"
fmt_duration() {
  local s=$1 d h m
  d=$((s / 86400)); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
  if [ "$d" -gt 0 ]; then printf '%sj %sh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%sh%02d' "$h" "$m"
  else printf '%smin' "$m"; fi
}

# Temps restant avant une date de reinitialisation (epoch en secondes ou ISO 8601)
fmt_reset() {
  local r=$1 target now
  [ -z "$r" ] && return
  if [[ "$r" =~ ^[0-9]+$ ]]; then
    target=$r
    [ "$target" -gt 100000000000 ] && target=$((target / 1000))
  else
    target=$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "${r%%.*}" +%s 2>/dev/null) || return
  fi
  now=$(date +%s)
  [ "$target" -le "$now" ] && return
  printf '↻ %s' "$(fmt_duration $((target - now)))"
}

[ -z "$dir" ] && dir=$(pwd)
base=$(basename "$dir")

# Branche git (sans verrous optionnels) et marqueur "dirty"
branch=""
dirty=""
if git -C "$dir" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$dir" --no-optional-locks symbolic-ref --short -q HEAD 2>/dev/null \
    || git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$(git -C "$dir" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
    dirty="*"
  fi
fi

# Segment "libelle barre pct %" ; vert <50, jaune <80, rouge >=80
segment() {
  local label=$1 value=$2 extra=$3 pct c width=6 filled bar="" i
  pct=$(printf '%.0f' "$value")
  [ "$pct" -gt 100 ] && pct=100
  # vert <50, jaune <70, orange <85, rouge >=85
  # Couleurs 256 fixes : independantes du theme du terminal
  if [ "$pct" -ge 85 ]; then c="38;5;196"
  elif [ "$pct" -ge 70 ]; then c="38;5;208"
  elif [ "$pct" -ge 50 ]; then c="38;5;220"
  else c="38;5;114"; fi
  filled=$(( (pct * width + 50) / 100 ))
  for ((i = 0; i < width; i++)); do
    if [ "$i" -lt "$filled" ]; then bar="${bar}▰"; else bar="${bar}▱"; fi
  done
  printf '\033[%sm%s %s %s %%%s\033[0m' "$c" "$label" "$bar" "$pct" "${extra:+ $extra}"
}

sep=$(printf ' \033[90m|\033[0m ')
out=""
[ -n "$model" ] && out=$(printf '\033[36m%s\033[0m' "$model")
out="$out$sep$(printf '\033[34m%s\033[0m' "$base")"
if [ -n "$branch" ]; then
  out="$out$sep$(printf '\033[32m %s\033[0m' "$branch")"
  [ -n "$dirty" ] && out="$out$(printf '\033[31m%s\033[0m' "$dirty")"
fi
[ -n "$used" ]    && out="$out$sep$(segment contexte "$used")"
[ -n "$session" ] && out="$out$sep$(segment session "$session" "$(fmt_reset "$session_reset")")"
[ -n "$week" ]    && out="$out$sep$(segment semaine "$week" "$(fmt_reset "$week_reset")")"
if [ -n "$duration_ms" ]; then
  out="$out$sep$(printf '\033[90m⏱ %s\033[0m' "$(fmt_duration $((${duration_ms%%.*} / 1000)))")"
fi

# Retire un separateur initial si pas de modele
out=${out#"$sep"}
printf '%s\n' "$out"
