#!/bin/bash
input="$1"
output="$2"
quality="${3:-75}"
convert "$input" -quality "$quality" "$output"
original_size=$(du -k "$input" | cut -f1)
new_size=$(du -k "$output" | cut -f1)
reduction=$(awk "BEGIN {print (($original_size-$new_size)/$original_size)*100}")
echo "Compressed from ${original_size}KB to ${new_size}KB (${reduction}% reduction)"
