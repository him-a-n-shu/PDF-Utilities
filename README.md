# PDF Utilities

A web-based application for manipulating PDF files and images with various tools including conversion, compression, merging, and page management.

## Features

* Image to PDF: Convert images to PDF
* PDF Merging: Combine multiple PDFs
* PDF Compression: Reduce PDF file size
* Target Size Compression: Compress PDFs to specific sizes
* Page Management: Remove specific pages
* Mixed Content Merging: Combine images and PDFs
* Image Compression: Reduce image file sizes
* Page Reordering: Reorder pages in PDFs

## Directory Structure

```text id="jvh9om"
pdf-utilities/
├── main.sh                  # Main setup script
├── start.sh                 # Script to start the application
├── scripts/                 # Utility scripts for processing
│   ├── img2pdf.sh
│   ├── merge_pdfs.sh
│   ├── compress_pdf.sh
│   ├── compress_pdf_size.sh
│   ├── remove_pages.sh
│   ├── merge_img_pdf.sh
│   ├── compress_img.sh
│   ├── compress_img_size.sh
│   └── reorder_pages.sh
├── web/                     # Web application files
│   ├── index.html           # Main interface
│   ├── style.css            # Styling
│   ├── script.js            # Client-side code
│   └── server.py            # Flask server
└── temp/                    # Temporary storage (created at runtime)
```

## Installation

### 1. Make sure you have Python 3 installed

### 2. Run the setup script

```bash id="ifmjlwm"
./main.sh
```

This will:

* Create necessary folders
* Install required dependencies
* Set up all scripts
* Create the web interface

### 3. If you get permission errors, make the scripts executable

```bash id="zy6lhu"
chmod +x main.sh
chmod +x start.sh
chmod +x scripts/*.sh
chmod +x web/server.py
```

## How to Use

### 1. Start the application

```bash id="l1jk0y"
./start.sh
```

### 2. Open in browser

```text id="ubf6sp"
http://localhost:8000
```

### 3. Use the application

1. Choose a tool from the navigation menu
2. Upload your files and select options
3. Click the action button (Convert, Merge, Compress, etc.)
4. The processed file will download automatically

### 4. Stop the application

Press `Ctrl + C` in the terminal.

## Requirements

### Operating System

* Linux or macOS

### Software Requirements

* Python 3.6+
* ImageMagick
* PDFtk
* Ghostscript
* Flask (Python package)

The setup script will check for and install these requirements if they are missing.
