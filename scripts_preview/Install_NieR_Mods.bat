@echo off
chcp 65001 >nul
title NieR:Automata - Ultimate Auto-Patcher and Mod Installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch_nier.ps1"
