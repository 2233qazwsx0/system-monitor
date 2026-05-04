@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion
title System Monitor — 自动安装器
echo ═══════════════════════════════════════════════
echo   System Monitor — Windows 自动安装
echo ═══════════════════════════════════════════════
echo.

REM ── 1. 配置项 ──────────────────────────────────
set "INSTALL_DIR=C:\SystemMonitor"
set "REPO_URL=https://github.com/2233qazwsx0/system-monitor.git"
echo [1/6] 安装目录: %INSTALL_DIR%

REM ── 2. 检查 Git ───────────────────────────────
echo [2/6] 检查 Git ...
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Git 未安装，正在下载安装 ...
    set "GIT_INSTALLER=%TEMP%\GitSetup.exe"
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/download/v2.48.1.windows.1/Git-2.48.1-64-bit.exe' -OutFile '%GIT_INSTALLER%'" 2>&1
    if %errorlevel% neq 0 (
        echo [FAIL] Git 下载失败，请手动安装: https://git-scm.com/download/win
        pause
        exit /b 1
    )
    echo [*] 正在静默安装 Git ...
    start /wait "%GIT_INSTALLER%" /VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh
    timeout /t 5 /nobreak >nul
    REM 刷新 PATH
    set "PATH=%ProgramFiles%\\Git\\cmd;%ProgramFiles(x86)%\\Git\\cmd;%LOCALAPPDATA%\\Microsoft\\WindowsApps;%PATH%"
    where git >nul 2>&1
    if %errorlevel% neq 0 (
        REM 再尝试默认安装路径
        for /d %%G in ("%ProgramFiles%\\Git\\cmd" "%ProgramFiles(x86)%\\Git\\cmd" "C:\\Program Files\\Git\\cmd") do (
            if exist "%%G\\git.exe" set "PATH=%%G;%PATH%"
        )
    )
)
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo [FAIL] Git 仍不可用，请手动安装后重新运行此脚本。
    pause
    exit /b 1
)
echo [OK] Git 已就绪
git --version
echo.

REM ── 3. 检查 Python ─────────────────────────────
echo [3/6] 检查 Python ...
where python >nul 2>&1
if %errorlevel% neq 0 (
    where python3 >nul 2>&1
    if %errorlevel% neq 0 (
        echo [FAIL] 未检测到 Python！请先安装: https://www.python.org/downloads/
        echo      勾选 "Add Python to PATH" 后重装。
        pause
        exit /b 1
    )
    set "PYTHON=python3"
) else (
    set "PYTHON=python"
)
for /f "tokens=2 delims= " %%V in ('%PYTHON% --version 2^>^&1') do set "PY_VER=%%V"
echo [OK] Python %PY_VER%
echo.

REM ── 4. 拉取源码 ────────────────────────────────
echo [4/6] 拉取最新代码 ...
if exist "%INSTALL_DIR%" (
    echo [*] 目录已存在，更新中 ...
    pushd "%INSTALL_DIR%" && git pull --rebase 2>&1 && popd
) else (
    git clone "%REPO_URL%" "%INSTALL_DIR%" >nul 2>&1
)
if %errorlevel% neq 0 (
    echo [FAIL] 代码拉取失败，请检查网络连接。
    pause
    exit /b 1
)
echo [OK] 代码已就绪
echo.

REM ── 5. 安装依赖 ────────────────────────────────
echo [5/6] 安装依赖包 ...
%PYTHON% -m pip install -q --upgrade pip
%PYTHON% -m pip install -q -r "%INSTALL_DIR%\requirements.txt"
if %errorlevel% neq 0 (
    echo [FAIL] 依赖安装失败，请检查 Python 和 pip 配置。
    pause
    exit /b 1
)
echo [OK] 依赖安装完成
echo.

REM ── 6. 生成启动脚本 ────────────────────────────
echo [6/6] 生成启动脚本 ...

set "RUNNER=%INSTALL_DIR%\start-system-monitor.bat"
> "%RUNNER%" echo @echo off
>>"%RUNNER%" echo cd /d "%INSTALL_DIR%"
>>"%RUNNER%" echo title System Monitor
>>"%RUNNER%" echo echo 正在启动 System Monitor ...
>>"%RUNNER%" echo echo 访问地址: http://localhost:8000
>>"%RUNNER%" echo echo 按 Ctrl+C 停止服务
>>"%RUNNER%" echo echo.
>>"%RUNNER%" echo %PYTHON% "%INSTALL_DIR%\server.py"

echo [OK] 启动脚本已生成:
echo     %RUNNER%
echo.

REM ── 完成 ──────────────────────────────────────
echo ═══════════════════════════════════════════════
echo   安装完成！
echo ═══════════════════════════════════════════════
echo  源码目录 : %INSTALL_DIR%
echo  推荐启动 : double-click "%INSTALL_DIR%\start-system-monitor.bat"
echo  浏览器访问: http://localhost:8000
echo ═══════════════════════════════════════════════
pause
endlocal