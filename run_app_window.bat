@echo off
chcp 65001 > nul
echo [My 약] 모바일 앱 전용 창 모드로 실행 중입니다...

:: Chrome이 설치되어 있는 경우
if exist "C:\Program Files\Google\Chrome\Application\chrome.exe" (
    start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" --app=http://localhost:8080 --window-size=420,915
    exit /b
)

:: Edge가 설치되어 있는 경우
if exist "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" (
    start "" "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --app=http://localhost:8080 --window-size=420,915
    exit /b
)

:: 기본 브라우저로 열기
start http://localhost:8080
