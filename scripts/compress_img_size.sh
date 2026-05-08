#!/bin/bash
input="$1"
output="$2"
target_size="$3"  # in KB
quality=90
while [ "$quality" -gt 10 ]; do
  convert "$input" -quality "$quality" "$output"
  size=$(du -k "$output" | cut -f1)
  if [ "$size" -le "$target_size" ]; then
    echo "Compressed to ${size}KB with quality $quality"
    break
  fi
  quality=$((quality - 5))
done
if [ "$quality" -le 10 ]; then
  echo "Warning: Reached minimum quality. Could not compress below target size."
fi
