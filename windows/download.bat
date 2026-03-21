@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

:: ============================================================
:: GPT-OSS 20B 模型下載腳本 (Windows)
:: 用途: 從 HuggingFace 下載指定的 GGUF 模型檔案
:: ============================================================

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%.."
set "MODELS_DIR=%ROOT_DIR%\models"
set "HF_REPO=DavidAU/OpenAi-GPT-oss-20b-abliterated-uncensored-NEO-Imatrix-gguf"

:: 建立 models 目錄
if not exist "%MODELS_DIR%" mkdir "%MODELS_DIR%"

echo.
echo ============================================================
echo   GPT-OSS 20B 模型下載工具
echo   Repository: %HF_REPO%
echo ============================================================
echo.

:: 偵測下載工具
set "DOWNLOADER="
where huggingface-cli >nul 2>&1 && set "DOWNLOADER=hf-cli"
if not defined DOWNLOADER (
    where python >nul 2>&1 && set "DOWNLOADER=python"
)
if not defined DOWNLOADER (
    where curl >nul 2>&1 && set "DOWNLOADER=curl"
)
if not defined DOWNLOADER (
    echo [錯誤] 找不到下載工具。請安裝以下其中之一:
    echo   1. pip install huggingface_hub[cli]
    echo   2. curl (Windows 10+ 內建)
    exit /b 1
)
echo [資訊] 使用下載工具: %DOWNLOADER%
echo.

:: 選擇量化類型
echo 請選擇量化類型:
echo.
echo  [1] IQ4_NL  - 約 12GB  ^ 創意/娛樂用途 (Imatrix 最強效果)
echo  [2] Q5_1    - 約 16GB  ^ 均衡/一般用途 (穩定性佳)
echo  [3] Q8_0    - 約 22GB  ^ 最高品質      (檔案最大)
echo  [4] 手動輸入檔名
echo  [0] 結束
echo.
set /p QUANT_CHOICE="請輸入選項 (0-4): "

if "%QUANT_CHOICE%"=="0" exit /b 0
if "%QUANT_CHOICE%"=="1" goto :menu_iq4
if "%QUANT_CHOICE%"=="2" goto :menu_q51
if "%QUANT_CHOICE%"=="3" goto :menu_q80
if "%QUANT_CHOICE%"=="4" goto :manual_input
echo [錯誤] 無效選項
exit /b 1

:menu_iq4
echo.
echo === IQ4_NL 模型清單 (約 12GB) ===
echo  [1] OpenAI-20B-NEO-Uncensored2-IQ4_NL.gguf           (標準)
echo  [2] OpenAI-20B-NEOPlus-Uncensored-IQ4_NL.gguf         (增強版)
echo  [3] OpenAI-20B-NEO-CODEPlus16-Uncensored-IQ4_NL.gguf  (程式碼加強)
echo  [4] OpenAI-20B-NEO-HRRPlus-Uncensored-IQ4_NL.gguf     (DI-Matrix)
echo  [5] OpenAI-20B-NEO-CODEPlus-Uncensored-IQ4_NL.gguf    (DI-Matrix 程式碼)
echo  [6] OpenAI-20B-NEO-CODE2-Plus-Uncensored-IQ4_NL.gguf  (程式碼 v2)
echo  [7] OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-IQ4_NL.gguf (TRI-Matrix)
echo  [0] 返回
echo.
set /p MODEL_IDX="請選擇模型 (0-7): "
if "%MODEL_IDX%"=="0" goto :start
if "%MODEL_IDX%"=="1" set "MODEL_FILE=OpenAI-20B-NEO-Uncensored2-IQ4_NL.gguf"
if "%MODEL_IDX%"=="2" set "MODEL_FILE=OpenAI-20B-NEOPlus-Uncensored-IQ4_NL.gguf"
if "%MODEL_IDX%"=="3" set "MODEL_FILE=OpenAI-20B-NEO-CODEPlus16-Uncensored-IQ4_NL.gguf"
if "%MODEL_IDX%"=="4" set "MODEL_FILE=OpenAI-20B-NEO-HRRPlus-Uncensored-IQ4_NL.gguf"
if "%MODEL_IDX%"=="5" set "MODEL_FILE=OpenAI-20B-NEO-CODEPlus-Uncensored-IQ4_NL.gguf"
if "%MODEL_IDX%"=="6" set "MODEL_FILE=OpenAI-20B-NEO-CODE2-Plus-Uncensored-IQ4_NL.gguf"
if "%MODEL_IDX%"=="7" set "MODEL_FILE=OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-IQ4_NL.gguf"
if not defined MODEL_FILE (echo [錯誤] 無效選項 & exit /b 1)
goto :do_download

:menu_q51
echo.
echo === Q5_1 模型清單 (約 16GB) ===
echo  [1] OpenAI-20B-NEO-Uncensored2-Q5_1.gguf              (標準)
echo  [2] OpenAI-20B-NEOPlus-Uncensored-Q5_1.gguf            (增強版)
echo  [3] OpenAI-20B-NEO-CODEPlus-Uncensored-Q5_1.gguf       (程式碼)
echo  [4] OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-Q5_1.gguf   (TRI-Matrix)
echo  [5] OpenAI-20B-NEO-HRR-DI-Uncensored-Q5_1.gguf         (DI-Matrix)
echo  [6] OpenAI-20B-NEO-CODE-DI-Uncensored-Q5_1.gguf        (DI-Matrix 程式碼)
echo  [0] 返回
echo.
set /p MODEL_IDX="請選擇模型 (0-6): "
if "%MODEL_IDX%"=="0" goto :start
if "%MODEL_IDX%"=="1" set "MODEL_FILE=OpenAI-20B-NEO-Uncensored2-Q5_1.gguf"
if "%MODEL_IDX%"=="2" set "MODEL_FILE=OpenAI-20B-NEOPlus-Uncensored-Q5_1.gguf"
if "%MODEL_IDX%"=="3" set "MODEL_FILE=OpenAI-20B-NEO-CODEPlus-Uncensored-Q5_1.gguf"
if "%MODEL_IDX%"=="4" set "MODEL_FILE=OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-Q5_1.gguf"
if "%MODEL_IDX%"=="5" set "MODEL_FILE=OpenAI-20B-NEO-HRR-DI-Uncensored-Q5_1.gguf"
if "%MODEL_IDX%"=="6" set "MODEL_FILE=OpenAI-20B-NEO-CODE-DI-Uncensored-Q5_1.gguf"
if not defined MODEL_FILE (echo [錯誤] 無效選項 & exit /b 1)
goto :do_download

:menu_q80
echo.
echo === Q8_0 模型清單 (約 22GB) ===
echo  [1] OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf             (增強版)
echo  [2] OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-Q8_0.gguf    (TRI-Matrix)
echo  [3] OpenAI-20B-NEO-HRR-CODE-5-TRI-Uncensored-Q8_0.gguf  (TRI-Matrix v5)
echo  [4] OpenAI-20B-NEO-HRR-DI-Uncensored-Q8_0.gguf          (DI-Matrix)
echo  [5] OpenAI-20B-NEO-CODE-DI-Uncensored-Q8_0.gguf         (DI-Matrix 程式碼)
echo  [0] 返回
echo.
set /p MODEL_IDX="請選擇模型 (0-5): "
if "%MODEL_IDX%"=="0" goto :start
if "%MODEL_IDX%"=="1" set "MODEL_FILE=OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf"
if "%MODEL_IDX%"=="2" set "MODEL_FILE=OpenAI-20B-NEO-HRR-CODE-TRI-Uncensored-Q8_0.gguf"
if "%MODEL_IDX%"=="3" set "MODEL_FILE=OpenAI-20B-NEO-HRR-CODE-5-TRI-Uncensored-Q8_0.gguf"
if "%MODEL_IDX%"=="4" set "MODEL_FILE=OpenAI-20B-NEO-HRR-DI-Uncensored-Q8_0.gguf"
if "%MODEL_IDX%"=="5" set "MODEL_FILE=OpenAI-20B-NEO-CODE-DI-Uncensored-Q8_0.gguf"
if not defined MODEL_FILE (echo [錯誤] 無效選項 & exit /b 1)
goto :do_download

:manual_input
echo.
set /p MODEL_FILE="請輸入完整檔名 (例: OpenAI-20B-NEOPlus-Uncensored-Q8_0.gguf): "
if "%MODEL_FILE%"=="" (echo [錯誤] 檔名不能為空 & exit /b 1)

:do_download
set "DEST_PATH=%MODELS_DIR%\%MODEL_FILE%"
set "HF_URL=https://huggingface.co/%HF_REPO%/resolve/main/%MODEL_FILE%"

echo.
echo ============================================================
echo  準備下載:
echo    檔案: %MODEL_FILE%
echo    目標: %DEST_PATH%
echo    來源: %HF_URL%
echo ============================================================
echo.

:: 檢查是否已存在
if exist "%DEST_PATH%" (
    echo [警告] 檔案已存在: %DEST_PATH%
    set /p OVERWRITE="是否重新下載? (y/N): "
    if /i not "!OVERWRITE!"=="y" (
        echo [資訊] 取消下載
        exit /b 0
    )
)

:: 執行下載
if "%DOWNLOADER%"=="hf-cli" (
    echo [資訊] 使用 huggingface-cli 下載...
    huggingface-cli download "%HF_REPO%" "%MODEL_FILE%" --local-dir "%MODELS_DIR%" --local-dir-use-symlinks False
) else if "%DOWNLOADER%"=="python" (
    echo [資訊] 使用 Python huggingface_hub 下載...
    python -c "from huggingface_hub import hf_hub_download; hf_hub_download(repo_id='%HF_REPO%', filename='%MODEL_FILE%', local_dir='%MODELS_DIR%', local_dir_use_symlinks=False)"
) else if "%DOWNLOADER%"=="curl" (
    echo [資訊] 使用 curl 下載...
    echo [提示] 若速度太慢，建議改用 huggingface-cli: pip install huggingface_hub[cli]
    curl -L --progress-bar -C - "%HF_URL%" -o "%DEST_PATH%"
)

if %errorlevel% neq 0 (
    echo.
    echo [錯誤] 下載失敗! 錯誤碼: %errorlevel%
    echo [提示] 請確認網路連線，或設定 HF_TOKEN 環境變數後重試
    exit /b 1
)

echo.
echo [成功] 模型下載完成: %DEST_PATH%
echo.

:: 驗證檔案大小
for %%F in ("%DEST_PATH%") do (
    set /a SIZE_MB=%%~zF/1048576
    echo [資訊] 檔案大小: !SIZE_MB! MB
)

echo.
echo [提示] 可執行 serve.bat 啟動模型服務
pause
endlocal
