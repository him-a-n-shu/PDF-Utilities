#!/bin/bash
output="$1"
shift
# Convert any image files to temporary PDFs
temp_dir=$(mktemp -d)
pdf_files=()
for file in "$@"; do
  if [[ "$file" == *.jpg || "$file" == *.jpeg || "$file" == *.png ]]; then
    temp_pdf="${temp_dir}/$(basename "$file").pdf"
    convert "$file" "$temp_pdf"
    pdf_files+=("$temp_pdf")
  else
    pdf_files+=("$file")
  fi
done
# Merge all PDFs
pdftk "${pdf_files[@]}" cat output "$output"
rm -rf "$temp_dir"
echo "Merged files into $output"
