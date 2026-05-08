#!/bin/bash

input="$1"         # Input PDF file
output="$2"        # Output PDF file
order="$3"         # New page order (e.g., "3 1 2")
remove_pages="$4"  # Pages to remove (e.g., "4 5")

# Validate input and output
if [ -z "$input" ] || [ -z "$output" ]; then
    echo "Error: Input and output files must be specified."
    exit 1
fi

if [ ! -f "$input" ]; then
    echo "Error: Input file '$input' does not exist."
    exit 1
fi

# Get total number of pages in the input PDF
total_pages=$(pdftk "$input" dump_data | grep "NumberOfPages" | awk '{print $2}')
if [ -z "$total_pages" ]; then
    echo "Error: Could not determine the number of pages in '$input'."
    exit 1
fi

# Create a list of all pages
all_pages=$(seq 1 "$total_pages" | tr '\n' ' ' | sed 's/ $//')

# Handle page removal
if [ -n "$remove_pages" ]; then
    # Convert remove_pages to an array
    IFS=' ' read -r -a remove_array <<< "$remove_pages"
    # Build a list of pages to keep
    pages_to_keep=""
    for page in $(seq 1 "$total_pages"); do
        keep=1
        for remove in "${remove_array[@]}"; do
            if [ "$page" -eq "$remove" ]; then
                keep=0
                break
            fi
        done
        if [ "$keep" -eq 1 ]; then
            pages_to_keep="$pages_to_keep $page"
        fi
    done
    pages_to_keep=$(echo "$pages_to_keep" | sed 's/^ //')  # Remove leading space
else
    pages_to_keep="$all_pages"
fi

# If no pages are left to keep, error out
if [ -z "$pages_to_keep" ]; then
    echo "Error: No pages left after removal."
    exit 1
fi

# Convert pages_to_keep to an array for reordering
IFS=' ' read -r -a keep_array <<< "$pages_to_keep"

# If no order is provided, use the default order of remaining pages
if [ -z "$order" ]; then
    order="$pages_to_keep"
else
    # Map the user-provided order to the remaining pages
    IFS=' ' read -r -a order_array <<< "$order"
    final_order=""
    for pos in "${order_array[@]}"; do
        if [ "$pos" -le "${#keep_array[@]}" ] && [ "$pos" -ge 1 ]; then
            final_order="$final_order ${keep_array[$((pos-1))]}"
        fi
    done
    order=$(echo "$final_order" | sed 's/^ //')  # Remove leading space
fi

# If the final order is empty, error out
if [ -z "$order" ]; then
    echo "Error: No valid pages in the new order after removal."
    exit 1
fi

# Process the PDF with the final order
pdftk "$input" cat $order output "$output"
if [ $? -eq 0 ]; then
    echo "Processed PDF with removals and new order. Output: $output"
else
    echo "Error: Failed to process PDF."
    exit 1
fi
