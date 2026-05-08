#!/bin/bash
output="$1"
shift
convert "$@" "$output" && echo "Converted images to $output"
