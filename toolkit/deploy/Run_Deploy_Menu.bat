@echo off
chcp 65001 >nul
title NOCI Deploy Menu
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run_Deploy_Menu.ps1"
