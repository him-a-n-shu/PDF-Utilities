#!/bin/bash
input="$1"
output="$2"
pages_to_keep="$3"
pdftk "$input" cat $pages_to_keep output "$output" && echo "Created new PDF with selected pages"
