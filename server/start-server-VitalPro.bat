@echo off
echo Checking for processes using port 3001...
cd E:\git-hub\vitalpro\server
e:
REM Check if port 3001 is in use
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :3001 ^| findstr LISTENING') do (
    echo Found process %%a using port 3001, terminating...
    taskkill /PID %%a /F >nul 2>&1
)

echo Starting Node.js server on port 3001...
node server.js



pause
