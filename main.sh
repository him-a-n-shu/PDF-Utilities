#!/bin/bash

# Create necessary directories
mkdir -p scripts web temp

# Check for required dependencies
dependencies=("convert" "pdftk" "gs" "python3")
missing=()

for cmd in "${dependencies[@]}"; do
  if ! command -v $cmd &> /dev/null; then
    missing+=($cmd)
  fi
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing required dependencies: ${missing[*]}"
  echo "Installing missing dependencies..."
  sudo apt-get update
  sudo apt-get install -y imagemagick pdftk ghostscript python3 python3-pip
  pip3 install flask
fi

# Create script files
cat > scripts/img2pdf.sh << 'EOF'
#!/bin/bash
output="$1"
shift
convert "$@" "$output" && echo "Converted images to $output"
EOF

cat > scripts/merge_pdfs.sh << 'EOF'
#!/bin/bash
output="$1"
shift
pdftk "$@" cat output "$output" && echo "Merged PDFs to $output"
EOF

cat > scripts/compress_pdf.sh << 'EOF'
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
EOF

cat > scripts/compress_pdf_size.sh << 'EOF'
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
EOF

cat > scripts/remove_pages.sh << 'EOF'
#!/bin/bash
input="$1"
output="$2"
pages_to_keep="$3"
pdftk "$input" cat $pages_to_keep output "$output" && echo "Created new PDF with selected pages"
EOF

cat > scripts/merge_img_pdf.sh << 'EOF'
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
EOF

cat > scripts/compress_img.sh << 'EOF'
#!/bin/bash
input="$1"
output="$2"
quality="${3:-75}"
convert "$input" -quality "$quality" "$output"
original_size=$(du -k "$input" | cut -f1)
new_size=$(du -k "$output" | cut -f1)
reduction=$(awk "BEGIN {print (($original_size-$new_size)/$original_size)*100}")
echo "Compressed from ${original_size}KB to ${new_size}KB (${reduction}% reduction)"
EOF

cat > scripts/compress_img_size.sh << 'EOF'
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
EOF

cat > scripts/reorder_pages.sh << 'EOF'
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
EOF

# Make all scripts executable
chmod +x scripts/*.sh

# Create the web interface
cat > web/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PDF Utilities</title>
    <link rel="stylesheet" href="style.css">
    <link rel="icon" type="image/x-icon" href="/favicon.ico">
</head>
<body>
    <nav>
        <div class="logo">PDF Utilities</div>
        <ul class="nav-links">
            <li data-section="img2pdf">Image to PDF</li>
            <li data-section="merge-pdfs">Merge PDFs</li>
            <li data-section="compress-pdf">Compress PDF</li>
            <li data-section="compress-pdf-size">Compress PDF to Size</li>
            <li data-section="remove-pages">Remove Pages</li>
            <li data-section="merge-img-pdf">Merge Images & PDFs</li>
            <li data-section="compress-img">Compress Image</li>
            <li data-section="compress-img-size">Compress Image to Size</li>
            <li data-section="reorder-pages">Reorder Pages</li>
        </ul>
    </nav>

    <main>
        <section id="img2pdf" class="tool-section">
            <h2>Convert Images to PDF</h2>
            <form action="/process" method="post" enctype="multipart/form-data">
                <input type="hidden" name="tool" value="img2pdf">
                <div class="form-group">
                    <label for="img2pdf-files">Select Images:</label>
                    <input type="file" id="img2pdf-files" name="files" multiple accept="image/*">
                </div>
                <button type="submit">Convert</button>
            </form>
        </section>

        <section id="merge-pdfs" class="tool-section hidden">
            <h2>Merge PDFs</h2>
            <form action="/process" method="post" enctype="multipart/form-data">
                <input type="hidden" name="tool" value="merge-pdfs">
                <div class="form-group">
                    <label for="merge-files">Select PDFs:</label>
                    <input type="file" id="merge-files" name="files" multiple accept=".pdf">
                </div>
                <button type="submit">Merge</button>
            </form>
        </section>

        <section id="compress-pdf" class="tool-section hidden">
            <h2>Compress PDF</h2>
            <form action="/process" method="post" enctype="multipart/form-data">
                <input type="hidden" name="tool" value="compress-pdf">
                <div class="form-group">
                    <label for="compress-file">Select PDF:</label>
                    <input type="file" id="compress-file" name="file" accept=".pdf">
                </div>
                <div class="form-group">
                    <label for="quality">Compression Level:</label>
                    <select id="quality" name="quality">
                        <option value="screen">Low Quality (Maximum Compression)</option>
                        <option value="ebook" selected>Medium Quality</option>
                        <option value="printer">Good Quality</option>
                        <option value="prepress">High Quality (Minimum Compression)</option>
                        <option value="default">Default</option>
                    </select>
                </div>
                <button type="submit">Compress</button>
            </form>
        </section>

        <section id="compress-pdf-size" class="tool-section hidden">
            <h2>Compress PDF to Size</h2>
            <form action="/process" method="post" enctype="multipart/form-data">
                <input type="hidden" name="tool" value="compress-pdf-size">
                <div class="form-group">
                    <label for="compress-size-file">Select PDF:</label>
                    <input type="file" id="compress-size-file" name="file" accept=".pdf">
                </div>
                <div class="form-group">
                    <label for="target-size">Target Size:</label>
                    <select id="target-size" name="target-size">
                        <option value="100">Less than 100KB</option>
                        <option value="300">Less than 300KB</option>
                        <option value="500">Less than 500KB</option>
                        <option value="1024">Less than 1MB</option>
                    </select>
                </div>
                <button type="submit">Compress</button>
            </form>
        </section>

        <section id="remove-pages" class="tool-section hidden">
            <h2>Remove Pages from PDF</h2>
            <form action="/process" method="post" enctype="multipart/form-data">
                <input type="hidden" name="tool" value="remove-pages">
                <div class="form-group">
                    <label for="remove-file">Select PDF:</label>
                    <input type="file" id="remove-file" name="file" accept=".pdf">
                </div>
                <div class="form-group">
                    <label for="pages">Pages to Keep (e.g., "1-5 7 9-end"):</label>
                    <input type="text" id="pages" name="pages" placeholder="1-5 7 9-end">
                </div>
                <button type="submit">Create New PDF</button>
            </form>
        </section>

        <section id="merge-img-pdf" class="tool-section hidden">
            <h2>Merge Images and PDFs</h2>
            <form action="/process" method="post" enctype="multipart/form-data">
                <input type="hidden" name="tool" value="merge-img-pdf">
                <div class="form-group">
                    <label for="merge-mixed-files">Select Files:</label>
                    <input type="file" id="merge-mixed-files" name="files" multiple accept=".pdf,image/*">
                </div>
                <button type="submit">Merge</button>
            </form>
        </section>

        <section id="compress-img" class="tool-section hidden">
            <h2>Compress Image</h2>
            <form action="/process" method="post" enctype="multipart/form-data">
                <input type="hidden" name="tool" value="compress-img">
                <div class="form-group">
                    <label for="img-compress-file">Select Image:</label>
                    <input type="file" id="img-compress-file" name="file" accept="image/*">
                </div>
                <div class="form-group">
                    <label for="img-quality">Quality (1-100):</label>
                    <input type="range" id="img-quality" name="quality" min="1" max="100" value="75">
                    <span id="quality-value">75</span>
                </div>
                <button type="submit">Compress</button>
            </form>
        </section>

        <section id="compress-img-size" class="tool-section hidden">
            <h2>Compress Image to Size</h2>
            <form action="/process" method="post" enctype="multipart/form-data">
                <input type="hidden" name="tool" value="compress-img-size">
                <div class="form-group">
                    <label for="img-compress-size-file">Select Image:</label>
                    <input type="file" id="img-compress-size-file" name="file" accept="image/*">
                </div>
                <div class="form-group">
                    <label for="img-target-size">Target Size:</label>
                    <select id="img-target-size" name="target-size">
                        <option value="100">Less than 100KB</option>
                        <option value="300">Less than 300KB</option>
                        <option value="500">Less than 500KB</option>
                        <option value="1024">Less than 1MB</option>
                    </select>
                </div>
                <button type="submit">Compress</button>
            </form>
        </section>

        <section id="reorder-pages" class="tool-section hidden">
            <h2>Reorder and Remove Pages</h2>
            <form id="reorder-pages-form" action="/process" method="post" enctype="multipart/form-data">
                <input type="hidden" name="tool" value="reorder-pages">
                <input type="hidden" name="action" value="process-reorder">
                <div class="form-group">
                    <label for="reorder-files">Select PDF:</label>
                    <input type="file" id="reorder-files" name="files" accept=".pdf">
                </div>
                <div class="form-group">
                    <label for="order">New Page Order (e.g., "3 1 2"):</label>
                    <input type="text" id="order" name="order" placeholder="Enter page numbers (leave blank for default)">
                </div>
                <div class="form-group">
                    <label for="remove-pages">Pages to Remove (e.g., "4 5"):</label>
                    <input type="text" id="remove-pages" name="remove_pages" placeholder="Enter pages to remove (optional)">
                </div>
                <button type="submit">Process PDF</button>
            </form>
        </section>
    </main>

    <script src="script.js"></script>
</body>
</html>
EOF

cat > web/style.css << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
    font-family: Arial, sans-serif;
}

body {
    background-color: #f5f5f5;
}

nav {
    background-color: #2a56c6;
    color: white;
    padding: 1rem;
    box-shadow: 0 2px 5px rgba(0, 0, 0, 0.1);
}

.logo {
    font-size: 1.5rem;
    font-weight: bold;
    margin-bottom: 1rem;
}

.nav-links {
    list-style: none;
    display: flex;
    flex-wrap: wrap;
    gap: 1rem;
}

.nav-links li {
    cursor: pointer;
    padding: 0.5rem 1rem;
    border-radius: 4px;
    transition: background-color 0.3s;
}

.nav-links li:hover {
    background-color: rgba(255, 255, 255, 0.2);
}

.nav-links li.active {
    background-color: rgba(255, 255, 255, 0.3);
    font-weight: bold;
}

main {
    max-width: 800px;
    margin: 2rem auto;
    padding: 1rem;
}

.tool-section {
    background-color: white;
    padding: 2rem;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
}

.hidden {
    display: none;
}

h2 {
    margin-bottom: 1.5rem;
    color: #2a56c6;
}

.form-group {
    margin-bottom: 1.5rem;
}

label {
    display: block;
    margin-bottom: 0.5rem;
    font-weight: bold;
}

input[type="file"],
input[type="text"],
input[type="range"],
select {
    width: 100%;
    padding: 0.5rem;
    border: 1px solid #ddd;
    border-radius: 4px;
}

button {
    background-color: #2a56c6;
    color: white;
    border: none;
    padding: 0.75rem 1.5rem;
    border-radius: 4px;
    cursor: pointer;
    font-weight: bold;
    transition: background-color 0.3s;
}

button:hover {
    background-color: #1c3e9c;
}

.preview-container {
    display: flex;
    flex-wrap: wrap;
    gap: 1rem;
    margin-top: 2rem;
}

.page-preview {
    position: relative;
    width: 150px;
    text-align: center;
}

.page-preview img {
    width: 100%;
    border: 1px solid #ddd;
    border-radius: 4px;
}

.page-preview .page-number {
    margin-top: 0.5rem;
    font-size: 0.9rem;
}

.page-preview .remove-btn {
    position: absolute;
    top: 5px;
    right: 5px;
    background-color: red;
    color: white;
    border: none;
    border-radius: 50%;
    width: 24px;
    height: 24px;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
}

.page-preview.dragging {
    opacity: 0.5;
}

#reset-previews {
    background-color: #ff4444;
    margin-left: 1rem;
}

#reset-previews:hover {
    background-color: #cc0000;
}
EOF

cat > web/script.js << 'EOF'
document.addEventListener('DOMContentLoaded', function() {
    // Navigation functionality
    const navLinks = document.querySelectorAll('.nav-links li');
    const sections = document.querySelectorAll('.tool-section');

    navLinks.forEach(link => {
        link.addEventListener('click', function() {
            const sectionId = this.getAttribute('data-section');
            navLinks.forEach(l => l.classList.remove('active'));
            this.classList.add('active');
            sections.forEach(section => {
                section.classList.add('hidden');
                if (section.id === sectionId) {
                    section.classList.remove('hidden');
                }
            });
        });
    });

    // Set first section as active by default
    navLinks[0].classList.add('active');

    // Form submission handler for other tools
    const forms = document.querySelectorAll('form');
    forms.forEach(form => {
        form.addEventListener('submit', async function(e) {
            e.preventDefault();
            const formData = new FormData(this);
            try {
                const response = await fetch('/process', {
                    method: 'POST',
                    body: formData
                });
                if (!response.ok) throw new Error('Processing failed');
                const blob = await response.blob();
                const url = window.URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = response.headers.get('Content-Disposition')?.split('filename=')[1] || 'output.pdf';
                a.click();
                window.URL.revokeObjectURL(url);
            } catch (error) {
                alert('Error: ' + error.message);
            }
        });
    });

    // Quality range input
    const qualityRange = document.getElementById('img-quality');
    const qualityValue = document.getElementById('quality-value');
    if (qualityRange && qualityValue) {
        qualityRange.addEventListener('input', function() {
            qualityValue.textContent = this.value;
        });
    }
});
EOF

cat > web/server.py << 'EOF'
#!/usr/bin/env python3
from flask import Flask, request, send_file, jsonify, send_from_directory
import os
import subprocess
import uuid
import shutil
import glob
from pathlib import Path

app = Flask(__name__, static_folder='.', static_url_path='')

PORT = 8000
TEMP_DIR = '../temp'
SCRIPTS_DIR = '../scripts'

@app.route('/')
def serve_index():
    return send_from_directory('.', 'index.html')

@app.route('/<path:path>')
def serve_static(path):
    return send_from_directory('.', path)

import traceback

@app.route('/process', methods=['POST'])
def process():
    # Create session directory
    session_id = str(uuid.uuid4())
    session_dir = os.path.join(TEMP_DIR, session_id)
    os.makedirs(session_dir, exist_ok=True)

    try:
        tool = request.form.get('tool')
        action = request.form.get('action', '')

        if tool == 'reorder-pages' and action == 'load-previews':
            return process_load_previews(session_dir, session_id)
        elif tool == 'reorder-pages' and action == 'process-reorder':
            return process_reorder_pages(session_dir)
        else:
            result_file = process_tool(tool, session_dir)
            if not os.path.exists(result_file):
                raise FileNotFoundError(f"Output file {result_file} was not created.")
            return send_file(
                result_file,
                as_attachment=True,
                download_name=os.path.basename(result_file)
            )
    except Exception as e:
        error_msg = f"Error: {str(e)}\n{traceback.format_exc()}"
        print(error_msg)  # Log to console for debugging
        return error_msg, 500
    finally:
        # Clean up session directory and previews
        shutil.rmtree(session_dir, ignore_errors=True)
        preview_dir = os.path.join('previews', session_id)
        shutil.rmtree(preview_dir, ignore_errors=True)

def save_uploaded_files(files, session_dir):
    if not files:
        raise ValueError("No files provided")
    file_paths = []
    for file in files:
        if file and file.filename:
            filename = file.filename
            file_path = os.path.join(session_dir, filename)
            file.save(file_path)
            file_paths.append(file_path)
    return file_paths

def process_tool(tool, session_dir):
    if tool == 'img2pdf':
        files = request.files.getlist('files')
        file_paths = save_uploaded_files(files, session_dir)
        output_path = os.path.join(session_dir, "output.pdf")
        cmd = [os.path.join(SCRIPTS_DIR, "img2pdf.sh"), output_path] + file_paths
        subprocess.run(cmd, check=True)
        return output_path

    elif tool == 'merge-pdfs':
        files = request.files.getlist('files')
        file_paths = save_uploaded_files(files, session_dir)
        output_path = os.path.join(session_dir, "merged.pdf")
        cmd = [os.path.join(SCRIPTS_DIR, "merge_pdfs.sh"), output_path] + file_paths
        subprocess.run(cmd, check=True)
        return output_path

    elif tool == 'compress-pdf':
        if 'file' not in request.files:
            raise ValueError("No file provided for compression")
        file = request.files['file']
        quality = request.form.get('quality', 'ebook')
        input_path = save_uploaded_files([file], session_dir)[0]
        output_path = os.path.join(session_dir, "compressed.pdf")
        cmd = [os.path.join(SCRIPTS_DIR, "compress_pdf.sh"), input_path, output_path, quality]
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(result.stdout)
        if result.returncode != 0:
            raise RuntimeError(f"Compression failed: {result.stderr}")
        return output_path

    elif tool == 'compress-pdf-size':
        if 'file' not in request.files:
            raise ValueError("No file provided for compression")
        file = request.files['file']
        target_size = request.form.get('target-size', '500')
        input_path = save_uploaded_files([file], session_dir)[0]
        output_path = os.path.join(session_dir, "compressed.pdf")
        cmd = [os.path.join(SCRIPTS_DIR, "compress_pdf_size.sh"), input_path, output_path, target_size]
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(result.stdout)
        if result.returncode != 0:
            raise RuntimeError(f"Compression failed: {result.stderr}")
        return output_path

    elif tool == 'remove-pages':
        file = request.files['file']
        pages = request.form.get('pages', '')
        input_path = save_uploaded_files([file], session_dir)[0]
        output_path = os.path.join(session_dir, "pages_removed.pdf")
        cmd = [os.path.join(SCRIPTS_DIR, "remove_pages.sh"), input_path, output_path, pages]
        subprocess.run(cmd, check=True)
        return output_path

    elif tool == 'merge-img-pdf':
        files = request.files.getlist('files')
        file_paths = save_uploaded_files(files, session_dir)
        output_path = os.path.join(session_dir, "merged.pdf")
        cmd = [os.path.join(SCRIPTS_DIR, "merge_img_pdf.sh"), output_path] + file_paths
        subprocess.run(cmd, check=True)
        return output_path

    elif tool == 'compress-img':
        file = request.files['file']
        quality = request.form.get('quality', '75')
        input_path = save_uploaded_files([file], session_dir)[0]
        file_ext = os.path.splitext(input_path)[1]
        output_path = os.path.join(session_dir, f"compressed{file_ext}")
        cmd = [os.path.join(SCRIPTS_DIR, "compress_img.sh"), input_path, output_path, quality]
        subprocess.run(cmd, check=True)
        return output_path

    elif tool == 'compress-img-size':
        file = request.files['file']
        target_size = request.form.get('target-size', '500')
        input_path = save_uploaded_files([file], session_dir)[0]
        file_ext = os.path.splitext(input_path)[1]
        output_path = os.path.join(session_dir, f"compressed{file_ext}")
        cmd = [os.path.join(SCRIPTS_DIR, "compress_img_size.sh"), input_path, output_path, target_size]
        subprocess.run(cmd, check=True)
        return output_path

    else:
        raise ValueError(f"Unknown tool: {tool}")

def process_load_previews(session_dir, session_id):
    files = request.files.getlist('files')
    file_paths = save_uploaded_files(files, session_dir)
    if not file_paths:
        raise ValueError("No valid files uploaded")

    preview_dir = os.path.join(session_dir, "previews")
    cmd = [os.path.join(SCRIPTS_DIR, "reorder_pages.sh"), "dummy_input.pdf", "dummy_output.pdf", "dummy_order", preview_dir] + file_paths
    subprocess.run(cmd, check=True)

    # Collect preview images
    pages = []
    for i, preview in enumerate(sorted(glob.glob(os.path.join(preview_dir, "page_*.png"))), 1):
        # Move preview to a static location so it can be served
        static_preview_path = os.path.join("previews", f"{session_id}_page_{i}.png")
        os.makedirs(os.path.dirname(static_preview_path), exist_ok=True)
        shutil.copy(preview, static_preview_path)
        pages.append({
            "number": i,
            "preview": f"/{static_preview_path}"
        })

    return jsonify({"pages": pages})

def process_reorder_pages(session_dir):
    files = request.files.getlist('files')
    file_paths = save_uploaded_files(files, session_dir)
    if not file_paths:
        raise ValueError("No valid files uploaded")

    order = request.form.get('order', '')  # New page order (e.g., "3 1 2")
    remove_pages = request.form.get('remove_pages', '')  # Pages to remove (e.g., "4 5")

    output_path = os.path.join(session_dir, "reordered.pdf")
    cmd = [os.path.join(SCRIPTS_DIR, "reorder_pages.sh"), file_paths[0], output_path, order, remove_pages]
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    print(result.stdout)  # Log output for debugging
    if result.returncode != 0:
        raise RuntimeError(f"Processing failed: {result.stderr}")
    return send_file(
        output_path,
        as_attachment=True,
        download_name="reordered.pdf"
    )

if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    app.run(host="0.0.0.0", port=PORT, debug=False)
EOF

# Make server.py executable
chmod +x web/server.py

echo "#!/bin/bash

# Start the web server in the background
cd $(pwd)
python3 web/server.py &
SERVER_PID=\$!

# Open the browser
if command -v xdg-open &> /dev/null; then
    xdg-open http://localhost:8000
elif command -v open &> /dev/null; then
    open http://localhost:8000
elif command -v python3 &> /dev/null; then
    python3 -m webbrowser http://localhost:8000
else
    echo 'Please open http://localhost:8000 in your browser'
fi

# Keep the script running until Ctrl+C
echo 'Press Ctrl+C to stop the server'
trap 'kill \$SERVER_PID; exit 0' INT
wait \$SERVER_PID
" > start.sh

chmod +x start.sh

echo "PDF Utilities setup complete! Run ./start.sh to start the application."
