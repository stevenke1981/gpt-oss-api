@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

:: ============================================================
:: GPT-OSS 20B 模型服務腳本 (Windows)
:: 用途: 使用 llama.cpp 啟動 OpenAI 相容 API 服務
:: ============================================================

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%.."
set "MODELS_DIR=%ROOT_DIR%\models"
set "CONFIG_FILE=%ROOT_DIR%\config\settings.ini"

:: 讀取設定檔預設值
set "HOST=127.0.0.1"
set "PORT=8080"
set "N_GPU_LAYERS=0"
set "N_THREADS=8"
set "CTX_SIZE=8192"
set "N_PARALLEL=4"
set "BATCH_SIZE=512"
set "TEMPERATURE=0.8"
set "REPEAT_PENALTY=1.1"
set "TOP_K=40"
set "TOP_P=0.95"
set "MIN_P=0.05"

:: 嘗試從設定檔讀取覆蓋值
if exist "%CONFIG_FILE%" (
    for /f "tokens=1,2 delims== eol=#" %%A in (%CONFIG_FILE%) do (
        if "%%A"=="HOST"          set "HOST=%%B"
        if "%%A"=="PORT"          set "PORT=%%B"
        if "%%A"=="N_GPU_LAYERS"  set "N_GPU_LAYERS=%%B"
        if "%%A"=="N_THREADS"     set "N_THREADS=%%B"
        if "%%A"=="CTX_SIZE"      set "CTX_SIZE=%%B"
        if "%%A"=="N_PARALLEL"    set "N_PARALLEL=%%B"
        if "%%A"=="BATCH_SIZE"    set "BATCH_SIZE=%%B"
        if "%%A"=="TEMPERATURE"   set "TEMPERATURE=%%B"
        if "%%A"=="REPEAT_PENALTY" set "REPEAT_PENALTY=%%B"
        if "%%A"=="TOP_K"         set "TOP_K=%%B"
        if "%%A"=="TOP_P"         set "TOP_P=%%B"
        if "%%A"=="MIN_P"         set "MIN_P=%%B"
    )
)

cls
echo.
echo ============================================================
echo   GPT-OSS 20B 模型服務啟動工具
echo ============================================================
echo.

:: ─── 步驟 1: 尋找 llama-server ───────────────────────────────
set "LLAMA_SERVER="

:: 常見安裝路徑搜尋順序
for %%P in (
    "llama-server.exe"
    "%ROOT_DIR%\llama.cpp\llama-server.exe"
    "%ROOT_DIR%\llama.cpp\build\bin\Release\llama-server.exe"
    "%ROOT_DIR%\llama.cpp\build\bin\llama-server.exe"
    "C:\llama.cpp\llama-server.exe"
    "C:\llama.cpp\build\bin\Release\llama-server.exe"
    "%LOCALAPPDATA%\llama.cpp\llama-server.exe"
) do (
    if exist %%P set "LLAMA_SERVER=%%~P"
)

:: PATH 中搜尋
if not defined LLAMA_SERVER (
    where llama-server.exe >nul 2>&1 && set "LLAMA_SERVER=llama-server.exe"
)

if not defined LLAMA_SERVER (
    echo [錯誤] 找不到 llama-server.exe!
    echo.
    echo 請選擇安裝方式:
    echo.
    echo  [方法 1] 使用預編譯版本 (推薦):
    echo    1. 前往 https://github.com/ggerganov/llama.cpp/releases
    echo    2. 下載 llama-b????-bin-win-*.zip (選擇符合硬體的版本)
    echo    3. 解壓到 %ROOT_DIR%\llama.cpp\
    echo.
    echo  [方法 2] 自行編譯:
    echo    git clone https://github.com/ggerganov/llama.cpp
    echo    cd llama.cpp
    echo    cmake -B build -DGGML_CUDA=ON  (有 NVIDIA GPU)
    echo    cmake --build build --config Release
    echo.
    echo  [方法 3] 手動指定路徑:
    set /p LLAMA_SERVER="請輸入 llama-server.exe 的完整路徑: "
    if not exist "!LLAMA_SERVER!" (
        echo [錯誤] 路徑不存在
        pause
        exit /b 1
    )
)

echo [資訊] llama-server 路徑: %LLAMA_SERVER%

:: ─── 步驟 2: 選擇模型 ────────────────────────────────────────
echo.
echo === 選擇要啟動的模型 ===
echo.

set "MODEL_COUNT=0"
for %%F in ("%MODELS_DIR%\*.gguf") do (
    set /a MODEL_COUNT+=1
    for %%S in ("%%F") do (
        set /a SIZE_MB=%%~zS/1048576
        echo  [!MODEL_COUNT!] %%~nxF  (!SIZE_MB! MB^)
    )
    set "MODEL_PATH_!MODEL_COUNT!=%%F"
)

if "%MODEL_COUNT%"=="0" (
    echo [錯誤] models 目錄中沒有 .gguf 檔案
    echo [提示] 請先執行 download.bat 下載模型
    pause
    exit /b 1
)

echo.
set /p MODEL_NUM="請選擇模型編號: "
set "MODEL_PATH=!MODEL_PATH_%MODEL_NUM%!"
if not defined MODEL_PATH (
    echo [錯誤] 無效的模型編號
    pause
    exit /b 1
)

:: ─── 步驟 3: 設定啟動參數 ────────────────────────────────────
echo.
echo === 啟動參數設定 ===
echo.
echo  目前設定 (按 Enter 使用預設值):
echo.
set /p HOST_IN="  服務位址 [%HOST%]: "
if not "%HOST_IN%"=="" set "HOST=%HOST_IN%"

set /p PORT_IN="  服務埠號 [%PORT%]: "
if not "%PORT_IN%"=="" set "PORT=%PORT_IN%"

set /p CTX_IN="  上下文長度 [%CTX_SIZE%] (8192-131072): "
if not "%CTX_IN%"=="" set "CTX_SIZE=%CTX_IN%"

set /p GPU_IN="  GPU 層數 [%N_GPU_LAYERS%] (0=純CPU, -1=全GPU): "
if not "%GPU_IN%"=="" set "N_GPU_LAYERS=%GPU_IN%"

set /p THREADS_IN="  CPU 執行緒數 [%N_THREADS%]: "
if not "%THREADS_IN%"=="" set "N_THREADS=%THREADS_IN%"

set /p PARALLEL_IN="  平行處理槽數 [%N_PARALLEL%]: "
if not "%PARALLEL_IN%"=="" set "N_PARALLEL=%PARALLEL_IN%"

:: ─── 步驟 4: 啟動服務 ────────────────────────────────────────
echo.
echo ============================================================
echo   啟動設定摘要
echo ============================================================
echo   模型:     %MODEL_PATH%
echo   位址:     http://%HOST%:%PORT%
echo   上下文:   %CTX_SIZE% tokens
echo   GPU 層:   %N_GPU_LAYERS%
echo   執行緒:   %N_THREADS%
echo   平行槽:   %N_PARALLEL%
echo ============================================================
echo.
echo  API 端點:
echo    聊天:   http://%HOST%:%PORT%/v1/chat/completions
echo    補全:   http://%HOST%:%PORT%/v1/completions
echo    健康:   http://%HOST%:%PORT%/health
echo    Web UI: http://%HOST%:%PORT%
echo ============================================================
echo.

set /p START_CONFIRM="確認啟動服務? (Y/n): "
if /i "%START_CONFIRM%"=="n" exit /b 0

echo.
echo [資訊] 正在啟動 llama-server...
echo [資訊] 按 Ctrl+C 停止服務
echo.

"%LLAMA_SERVER%" ^
    --model "%MODEL_PATH%" ^
    --host %HOST% ^
    --port %PORT% ^
    --ctx-size %CTX_SIZE% ^
    --n-gpu-layers %N_GPU_LAYERS% ^
    --threads %N_THREADS% ^
    --parallel %N_PARALLEL% ^
    --batch-size %BATCH_SIZE% ^
    --temp %TEMPERATURE% ^
    --repeat-penalty %REPEAT_PENALTY% ^
    --top-k %TOP_K% ^
    --top-p %TOP_P% ^
    --min-p %MIN_P% ^
    --flash-attn ^
    --metrics ^
    --log-format text

if %errorlevel% neq 0 (
    echo.
    echo [錯誤] llama-server 異常退出，錯誤碼: %errorlevel%
    echo.
    echo 常見問題排查:
    echo  - 模型檔案損壞: 重新執行 download.bat
    echo  - 記憶體不足:   降低 --ctx-size 或 --n-gpu-layers
    echo  - 埠號衝突:     更換 --port 設定
    echo  - GPU 錯誤:     設定 N_GPU_LAYERS=0 改用 CPU
)

pause
endlocal
