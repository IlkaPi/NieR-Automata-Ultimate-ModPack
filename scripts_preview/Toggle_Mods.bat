@echo off
chcp 65001 >nul
title NieR:Automata — Включение и откат модов (Toggle Mods)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0toggle_mods.ps1"
