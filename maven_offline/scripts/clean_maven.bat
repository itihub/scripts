@echo off
setlocal enabledelayedexpansion

:: ==============================================================================
:: 脚本名称: clean-maven.bat
:: 脚本描述: 深度清理 Maven 本地仓库中的损坏文件。
:: 
:: 使用方式:
::   clean-maven.bat                     (清理默认路径)
::   clean-maven.bat D:\custom_repo      (清理指定路径)
:: ==============================================================================

:: 1. 动态获取路径：优先使用第一个参数 %1，否则使用默认路径
set "RAW_PATH=%~1"
if "%RAW_PATH%"=="" (
    set "RAW_PATH=%USERPROFILE%\.m2\repository"
)
for %%I in ("%RAW_PATH%") do set "TARGET_DIR=%%~fI"

:: 2. 路径检查 (防御性编程)
if not exist "%TARGET_DIR%" (
    echo [错误] 找不到目录: "%TARGET_DIR%"
    echo 请检查路径是否正确。
    exit /b 1
)

echo ">>> 开始清理 Maven 仓库: "%TARGET_DIR%""

:: 3. 执行清理操作
:: /S: 循环目录  /Q: 静默模式  /F: 强制删除只读文件
echo 正在移除下载失败标记 (.lastUpdated)...
del /s /q /f "%TARGET_DIR%\*.lastUpdated" >nul 2>&1

echo 正在移除远程记录文件 (_remote.repositories)...
del /s /q /f "%TARGET_DIR%\_remote.repositories" >nul 2>&1

:: 4. 结束语
echo.
echo ">>> 清理完成！"
echo.

:: 只有在双击运行时才暂停，方便查看结果；如果在命令行运行则直接结束
echo %cmdcmdline% | find /i "%~0" >nul
if not errorlevel 1 pause

endlocal