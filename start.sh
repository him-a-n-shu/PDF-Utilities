#!/bin/bash

# Start the web server in the background
cd /home/himchu/pdf_project
python3 web/server.py &
SERVER_PID=$!

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
trap 'kill $SERVER_PID; exit 0' INT
wait $SERVER_PID

