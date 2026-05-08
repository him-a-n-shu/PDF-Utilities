#!/bin/bash
output="$1"
shift
pdftk "$@" cat output "$output" && echo "Merged PDFs to $output"
