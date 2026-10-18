@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

rem 用法：双击运行，或在命令行执行 build_apk.bat [--no-pause]

set "APP_NAME=Qingluan-attendance"
set "OUT_DIR=dist"
set "APK_DIR=build\app\outputs\flutter-apk"

echo ============================================
echo   青鸾考勤 ABI 分包打包
echo ============================================
echo.

where flutter >nul 2>nul
if errorlevel 1 (
  echo [错误] 未找到 flutter 命令，请先把 Flutter SDK 加入 PATH。
  goto :fail
)

rem 从 pubspec.yaml 读取版本号，例如 1.0.0+1 提取为 1.0.0
set "APP_VERSION="
for /f "tokens=2 delims=:+" %%V in ('findstr /b /c:"version:" pubspec.yaml') do (
  if not defined APP_VERSION set "APP_VERSION=%%V"
)
if defined APP_VERSION set "APP_VERSION=%APP_VERSION: =%"
if defined APP_VERSION set APP_VERSION=%APP_VERSION:"=%
if not defined APP_VERSION (
  echo [错误] 无法从 pubspec.yaml 读取 version。
  goto :fail
)

echo 版本号：V%APP_VERSION%
echo 输出目录：%OUT_DIR%\
echo 注意：release 签名由 android/app/build.gradle.kts 配置决定（当前为 debug 签名）。
echo.

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

rem 先删除旧目标文件，避免构建失败时留下过期包
for %%A in (armeabi-v7a arm64-v8a x86_64) do (
  if exist "%OUT_DIR%\%APP_NAME%V%APP_VERSION%-%%A.apk" del /f /q "%OUT_DIR%\%APP_NAME%V%APP_VERSION%-%%A.apk"
)

echo [1/2] 正在构建 release 分包...
call flutter build apk --release --split-per-abi
if errorlevel 1 (
  echo.
  echo [错误] Flutter 构建失败，请查看上方日志。
  goto :fail
)

echo.
echo [2/2] 正在整理 APK...
set "FOUND=0"
for %%A in (armeabi-v7a arm64-v8a x86_64) do (
  set "SRC=%APK_DIR%\app-%%A-release.apk"
  set "DST=%OUT_DIR%\%APP_NAME%V%APP_VERSION%-%%A.apk"
  if exist "!SRC!" (
    copy /y "!SRC!" "!DST!" >nul
    if errorlevel 1 (
      echo [错误] 复制失败：%%A
      goto :fail
    )
    set "FOUND=1"
    for %%F in ("!DST!") do echo   [OK] %%~nxF  %%~zF bytes
  ) else (
    echo   [警告] 未找到 %%A 产物：!SRC!
  )
)

if "!FOUND!"=="0" (
  echo [错误] 没有生成任何 APK。
  goto :fail
)

echo.
echo 打包完成，输出目录：
echo   %CD%\%OUT_DIR%
echo.
if /i "%~1"=="--no-pause" exit /b 0
pause
exit /b 0

:fail
echo.
if /i not "%~1"=="--no-pause" pause
exit /b 1
