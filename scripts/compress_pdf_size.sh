#!/bin/bash
input="$1"
output="$2"
target_size="$3"  # in KB
if [ -z "$input" ] || [ -z "$output" ] || [ -z "$target_size" ]; then
    echo "Error: Input file, output file, and target size must be specified."
    exit 1
fi
if [ ! -f "$input" ]; then
    echo "Error: Input file '$input' does not exist."
    exit 1
fi
temp_file="temp_compressed.pdf"
gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/screen -dNOPAUSE -dQUIET -dBATCH -sOutputFile="$temp_file" "$input"
size=$(du -k "$temp_file" | cut -f1)
qualities=("screen" "ebook" "printer" "prepress" "default")
quality_index=0
while [ "$size" -gt "$target_size" ] && [ "$quality_index" -lt "${#qualities[@]}" ]; do
    quality="${qualities[$quality_index]}"
    gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/$quality -dNOPAUSE -dQUIET -dBATCH -sOutputFile="$output" "$temp_file"
    mv "$output" "$temp_file"
    size=$(du -k "$temp_file" | cut -f1)
    quality_index=$((quality_index + 1))
done
mv "$temp_file" "$output"
final_size=$(du -k "$output" | cut -f1)
if [ "$final_size" -le "$target_size" ]; then
    echo "Compressed to ${final_size}KB (target: ${target_size}KB)"
else
    echo "Could not compress below ${target_size}KB (current: ${final_size}KB)"
fi
