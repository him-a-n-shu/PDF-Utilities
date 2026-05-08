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
