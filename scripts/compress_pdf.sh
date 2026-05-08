#!/bin/bash
input="$1"
output="$2"
quality="${3:-ebook}"
if [ -z "$input" ] || [ -z "$output" ]; then
    echo "Error: Input and output files must be specified."
    exit 1
fi
if [ ! -f "$input" ]; then
    echo "Error: Input file '$input' does not exist."
    exit 1
fi
input_size=$(du -k "$input" | cut -f1)
if [ "$input_size" -lt 1024 ]; then
    echo "Warning: Input file is less than 1 MB (${input_size}KB). Compression may not be effective."
fi
# Ensure quality defaults to 'ebook' if invalid, and validate options to avoid size increase
valid_qualities=("screen" "ebook" "printer" "prepress")
if [[ ! " ${valid_qualities[*]} " =~ " $quality " ]]; then
    quality="ebook"  # Default to ebook if quality is invalid or unset
fi
gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/$quality -dNOPAUSE -dQUIET -dBATCH -sOutputFile="$output" "$input"
if [ $? -eq 0 ]; then
    new_size=$(du -k "$output" | cut -f1)
    reduction=$(awk "BEGIN {print (($input_size-$new_size)/$input_size)*100}")
    echo "Compressed from ${input_size}KB to ${new_size}KB (${reduction}% reduction)"
else
    echo "Error: Failed to compress the PDF."
    exit 1
fi
