@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

:: ============================================================
:: GPT-OSS 20B 模型管理腳本 (Windows)
:: 用途: 列出、查看資訊、刪除已下載的 GGUF 模型
:: ============================================================

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%.."
set "MODELS_DIR=%ROOT_DIR%\models"

if not exist "%MODELS_DIR%" mkdir "%MODELS_DIR%"

:main_menu
cls
echo.
echo ============================================================
echo   GPT-OSS 20B 模型管理工具
echo   模型目錄: %MODELS_DIR%
echo ============================================================
echo.
echo  [1] 列出所有已下載模型
echo  [2] 查看模型詳細資訊
echo  [3] 刪除模型
echo  [4] 磁碟空間資訊
echo  [5] 清理不完整的下載檔案
echo  [6] 開啟模型目錄
echo  [0] 結束
echo.
set /p CHOICE="請選擇操作 (0-6): "

if "%CHOICE%"=="0" exit /b 0
if "%CHOICE%"=="1" goto :list_models
if "%CHOICE%"=="2" goto :model_info
if "%CHOICE%"=="3" goto :delete_model
if "%CHOICE%"=="4" goto :disk_info
if "%CHOICE%"=="5" goto :clean_partial
if "%CHOICE%"=="6" goto :open_dir
echo [錯誤] 無效選項
timeout /t 2 >nul
goto :main_menu

:: ============================================================
:list_models
cls
echo.
echo ============================================================
echo   已下載的模型清單
echo ============================================================
echo.

set "COUNT=0"
set "TOTAL_MB=0"

for %%F in ("%MODELS_DIR%\*.gguf") do (
    set /a COUNT+=1
    for %%S in ("%%F") do (
        set /a SIZE_MB=%%~zS/1048576
        set /a TOTAL_MB+=!SIZE_MB!
        echo  [!COUNT!] %%~nxF
        echo       大小: !SIZE_MB! MB
        echo       路徑: %%F
        echo       修改: %%~tF
        echo.
    )
)

if "%COUNT%"=="0" (
    echo  [提示] 尚未下載任何模型
    echo  [提示] 請執行 download.bat 下載模型
) else (
    echo ============================================================
    echo   共 %COUNT% 個模型，總計 %TOTAL_MB% MB
    echo ============================================================
)

echo.
pause
goto :main_menu

:: ============================================================
:model_info
cls
echo.
echo === 查看模型資訊 ===
echo.
call :show_model_list
if "%MODEL_COUNT%"=="0" goto :main_menu

echo.
set /p INFO_NUM="請輸入模型編號: "
call :get_model_by_num %INFO_NUM%
if not defined SELECTED_MODEL goto :main_menu

echo.
echo ============================================================
echo   模型詳細資訊: %SELECTED_MODEL%
echo ============================================================
echo.

for %%F in ("%MODELS_DIR%\%SELECTED_MODEL%") do (
    set /a SIZE_MB=%%~zF/1048576
    set /a SIZE_GB_INT=%%~zF/1073741824
    echo  檔名:     %%~nxF
    echo  大小:     !SIZE_MB! MB (~!SIZE_GB_INT! GB)
    echo  完整路徑: %%F
    echo  建立時間: %%~tF
    echo.
)

:: 解析量化類型
echo  量化資訊:
echo  !SELECTED_MODEL! | findstr /i "IQ4_NL" >nul && echo    類型: IQ4_NL (4-bit Imatrix) - 創意/娛樂用途
echo  !SELECTED_MODEL! | findstr /i "Q5_1"   >nul && echo    類型: Q5_1 (5-bit) - 均衡一般用途
echo  !SELECTED_MODEL! | findstr /i "Q8_0"   >nul && echo    類型: Q8_0 (8-bit) - 最高品質

echo  !SELECTED_MODEL! | findstr /i "TRI"    >nul && echo    Matrix: TRI-Matrix (3個資料集平均)
echo  !SELECTED_MODEL! | findstr /i "-DI-"   >nul && echo    Matrix: DI-Matrix (2個資料集平均)

echo.
echo  建議啟動參數:
echo    --ctx-size 8192
echo    --temp 0.8
echo    --repeat-penalty 1.1
echo    --top-k 40
echo    --top-p 0.95
echo    --min-p 0.05
echo.
pause
goto :main_menu

:: ============================================================
:delete_model
cls
echo.
echo === 刪除模型 ===
echo.
call :show_model_list
if "%MODEL_COUNT%"=="0" goto :main_menu

echo.
set /p DEL_NUM="請輸入要刪除的模型編號 (0=取消): "
if "%DEL_NUM%"=="0" goto :main_menu
call :get_model_by_num %DEL_NUM%
if not defined SELECTED_MODEL goto :main_menu

echo.
echo [警告] 即將刪除: %SELECTED_MODEL%
for %%F in ("%MODELS_DIR%\%SELECTED_MODEL%") do (
    set /a SIZE_MB=%%~zF/1048576
    echo [警告] 檔案大小: !SIZE_MB! MB (此操作無法復原)
)
echo.
set /p CONFIRM="確認刪除? 請輸入 YES 確認: "
if not "%CONFIRM%"=="YES" (
    echo [資訊] 已取消刪除
    timeout /t 2 >nul
    goto :main_menu
)

del "%MODELS_DIR%\%SELECTED_MODEL%"
if %errorlevel% equ 0 (
    echo [成功] 已刪除: %SELECTED_MODEL%
) else (
    echo [錯誤] 刪除失敗!
)
timeout /t 2 >nul
goto :main_menu

:: ============================================================
:disk_info
cls
echo.
echo === 磁碟空間資訊 ===
echo.

:: 取得模型目錄所在磁碟
for %%D in ("%MODELS_DIR%") do set "DISK_DRIVE=%%~dD"

echo  模型目錄磁碟: %DISK_DRIVE%
echo.
fsutil volume diskfree %DISK_DRIVE% 2>nul || (
    wmic logicaldisk where "DeviceID='%DISK_DRIVE%'" get Size,FreeSpace /format:list 2>nul
)

echo.
echo  各量化類型所需空間:
echo    IQ4_NL  : 約 12 GB
echo    Q5_1    : 約 16 GB
echo    Q8_0    : 約 22 GB
echo.
echo  模型目錄已用空間:
set "TOTAL_MB=0"
for %%F in ("%MODELS_DIR%\*.gguf") do (
    for %%S in ("%%F") do set /a TOTAL_MB+=%%~zS/1048576
)
echo    %TOTAL_MB% MB

echo.
pause
goto :main_menu

:: ============================================================
:clean_partial
cls
echo.
echo === 清理不完整的下載檔案 ===
echo.
echo  正在掃描臨時/部分下載檔案...
echo.

set "FOUND=0"
for %%F in ("%MODELS_DIR%\*.tmp" "%MODELS_DIR%\*.part" "%MODELS_DIR%\*.download") do (
    if exist "%%F" (
        echo  找到: %%~nxF
        set "FOUND=1"
    )
)

if "%FOUND%"=="0" (
    echo  [資訊] 未找到需要清理的臨時檔案
) else (
    set /p CLEAN="是否刪除以上臨時檔案? (y/N): "
    if /i "!CLEAN!"=="y" (
        del /q "%MODELS_DIR%\*.tmp" 2>nul
        del /q "%MODELS_DIR%\*.part" 2>nul
        del /q "%MODELS_DIR%\*.download" 2>nul
        echo  [成功] 臨時檔案已清理
    )
)

echo.
pause
goto :main_menu

:: ============================================================
:open_dir
explorer "%MODELS_DIR%"
goto :main_menu

:: ============================================================
:: 輔助函數: 列出模型並設定 MODEL_COUNT
:show_model_list
set "MODEL_COUNT=0"
for %%F in ("%MODELS_DIR%\*.gguf") do (
    set /a MODEL_COUNT+=1
    for %%S in ("%%F") do (
        set /a SIZE_MB=%%~zS/1048576
        echo  [!MODEL_COUNT!] %%~nxF  (!SIZE_MB! MB^)
    )
    set "MODEL_!MODEL_COUNT!=%%~nxF"
)
if "%MODEL_COUNT%"=="0" (
    echo  [提示] 尚未下載任何模型，請先執行 download.bat
)
goto :eof

:: 輔助函數: 依編號取得模型名稱
:get_model_by_num
set "SELECTED_MODEL="
set "IDX=0"
for %%F in ("%MODELS_DIR%\*.gguf") do (
    set /a IDX+=1
    if "!IDX!"=="%1" set "SELECTED_MODEL=%%~nxF"
)
goto :eof

endlocal
