@echo off
set "DIAG_SELF=%~f0"
set "DIAG_DIR=%~dp0"
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$c=[IO.File]::ReadAllText($env:DIAG_SELF,[Text.Encoding]::UTF8); $p=$c.IndexOf('# === PS_'+'START ==='); & ([ScriptBlock]::Create($c.Substring($p)))"
if errorlevel 1 if not defined DIAG_NONINTERACTIVE pause
exit /b
# === PS_START ===
try { $Host.UI.RawUI.WindowTitle = "NieR:Automata Ultimate ModPack (2026) — Глубокая диагностика и автофикс" } catch {}
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

$ScriptDir = ($env:DIAG_DIR).TrimEnd('\')
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$ReportPath = Join-Path $ScriptDir "Crash_Diagnosis_Report.txt"
$ReportLines = New-Object System.Collections.Generic.List[string]

$CriticalIssues = New-Object System.Collections.Generic.List[PSObject]
$Warnings       = New-Object System.Collections.Generic.List[PSObject]

function Mask-UserPath {
    param([string]$Text)
    if (-not $Text) { return "" }
    $u = $env:USERNAME
    if ($u) {
        return ($Text -ireplace [regex]::Escape("Users\$u"), "Users\<USER>")
    }
    return $Text
}

function Write-Both {
    param(
        [string]$Text = "",
        [ConsoleColor]$Color = [ConsoleColor]::Gray,
        [switch]$NoNewline
    )
    if ($NoNewline) {
        Write-Host $Text -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Text -ForegroundColor $Color
    }
    $ReportLines.Add((Mask-UserPath $Text))
}

function Add-Finding {
    param(
        [ValidateSet("CRITICAL","WARN")] [string]$Severity,
        [string]$Stage,
        [string]$Title,
        [string]$Detail,
        [string]$Fix
    )
    $obj = [PSCustomObject]@{
        Severity = $Severity
        Stage    = $Stage
        Title    = $Title
        Detail   = $Detail
        Fix      = $Fix
    }
    if ($Severity -eq "CRITICAL") { $CriticalIssues.Add($obj) }
    else { $Warnings.Add($obj) }
}

function Get-QuickSha256 {
    param([string]$FilePath)
    try {
        return (Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    } catch {
        return $null
    }
}

function Decode-Utf16Hex {
    param([string]$Hex)
    try {
        if (-not $Hex -or $Hex.Length -lt 4) { return "" }
        $bytes = New-Object byte[] ([Math]::Floor($Hex.Length / 2))
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
        }
        $str = [System.Text.Encoding]::Unicode.GetString($bytes)
        $nullIdx = $str.IndexOf([char]0)
        if ($nullIdx -ge 0) { $str = $str.Substring(0, $nullIdx) }
        return $str.Trim()
    } catch { return "" }
}

function Toggle-PackModOff {
    param(
        [string]$GameRoot,
        [string]$ModKey,
        [string[]]$RelFiles
    )
    $DisDir = Join-Path $GameRoot "_Disabled_Mods\$ModKey"
    $VanDir = Join-Path $GameRoot "_Vanilla_Backup\$ModKey"
    if (-not (Test-Path $DisDir)) { New-Item -ItemType Directory -Path $DisDir -Force | Out-Null }
    $movedAny = $false
    foreach ($rf in $RelFiles) {
        $src = Join-Path $GameRoot $rf
        $dst = Join-Path $DisDir $rf
        $dstParent = Split-Path -Parent $dst
        if (-not (Test-Path $dstParent)) { New-Item -ItemType Directory -Path $dstParent -Force | Out-Null }
        if (Test-Path $src) {
            Move-Item -Path $src -Destination $dst -Force
            $movedAny = $true
        }
        $vanFile = Join-Path $VanDir $rf
        if (Test-Path $vanFile) {
            Copy-Item -Path $vanFile -Destination $src -Force
        }
    }
    return $movedAny
}

function Run-FullForensicScan {
    $ReportLines.Clear()
    $CriticalIssues.Clear()
    $Warnings.Clear()

    Clear-Host
    Write-Both "============================================================================" Cyan
    Write-Both "  NieR:Automata Ultimate ModPack (2026) — ГЛУБОКАЯ ДИАГНОСТИКА (7 УРОВНЕЙ)  " Cyan
    Write-Both "============================================================================" Cyan
    Write-Both ("  Время проверки: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) DarkGray
    Write-Both ""

    # -------------------------------------------------------------------------
    # СЛОЙ 1: ПОИСК ИГРЫ И ПРОВЕРКА ГЕОМЕТРИИ УСТАНОВКИ ("ТУДА ЛИ ВСТАЛО?")
    # -------------------------------------------------------------------------
    Write-Both "[1/7] Поиск папки игры и аудит корректности распаковки..." Yellow

    if ($ScriptDir -match '\\AppData\\Local\\Temp\\(Rar\$|7z|Temp\d*_)') {
        Add-Finding "CRITICAL" "Этап 0 (Архив)" `
            "Скрипт запущен прямо из временной папки архиватора без распаковки!" `
            "WinRAR/7-Zip распаковывает только один кликнутый .bat во временную папку Temp, без остальных файлов." `
            "Полностью распакуйте архив сборки на NTFS-диск через 7-Zip или WinRAR и запустите Установить_Моды.bat."
    }

    $CandidatePaths = @()
    if (Test-Path (Join-Path $ScriptDir "NieRAutomata.exe")) { $CandidatePaths += $ScriptDir }
    try {
        $SteamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).SteamPath
        if ($SteamPath) {
            $SteamPath = $SteamPath.Replace("/", "\")
            $VdfPath = Join-Path $SteamPath "steamapps\libraryfolders.vdf"
            if (Test-Path $VdfPath) {
                $VdfContent = Get-Content $VdfPath -Raw -ErrorAction SilentlyContinue
                foreach ($m in [regex]::Matches($VdfContent, '"path"\s+"([^"]+)"')) {
                    $LibPath = $m.Groups[1].Value.Replace("\\", "\")
                    $NierDir = Join-Path $LibPath "steamapps\common\NieRAutomata"
                    if ((Test-Path $NierDir) -and ($CandidatePaths -notcontains $NierDir)) {
                        $CandidatePaths += $NierDir
                    }
                }
            }
        }
    } catch {}

    $Drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object { $_.Root.TrimEnd('\') }
    foreach ($drv in $Drives) {
        foreach ($sub in @(
            "SteamLibrary\steamapps\common\NieRAutomata",
            "Steam\steamapps\common\NieRAutomata",
            "Program Files (x86)\Steam\steamapps\common\NieRAutomata",
            "Games\NieRAutomata",
            "Games\NieR Automata",
            "NieRAutomata",
            "NieR - Automata"
        )) {
            $p = "$drv\$sub"
            if ((Test-Path $p) -and ($CandidatePaths -notcontains $p)) {
                $CandidatePaths += $p
            }
        }
    }

    $GameDir = $null
    foreach ($p in $CandidatePaths) {
        if (Test-Path (Join-Path $p "NieRAutomata.exe")) { $GameDir = $p; break }
    }
    if (-not $GameDir -and $CandidatePaths.Count -gt 0) { $GameDir = $CandidatePaths[0] }

    if (-not $GameDir -and -not $env:DIAG_NONINTERACTIVE) {
        Write-Host "  [!] Папка NieRAutomata не найдена автоматически." -ForegroundColor Yellow
        $inputDir = Read-Host "  Введите полный путь к папке игры (где лежит NieRAutomata.exe)"
        if ($inputDir -and (Test-Path $inputDir.Trim('"'))) {
            $GameDir = $inputDir.Trim('"')
        }
    }

    if (-not $GameDir -or -not (Test-Path $GameDir)) {
        Write-Both "  [КРИТИЧНО] Папка игры NieRAutomata не найдена на дисках!" Red
        return $null
    }

    Write-Both ("  Папка игры : " + (Mask-UserPath $GameDir)) Green

    if ($GameDir -match '[^\x00-\x7F]') {
        Add-Finding "CRITICAL" "Этап 0 (Путь к игре)" `
            "В пути к папке игры есть кириллица (русские буквы) или спецсимволы!" `
            ("Путь '" + (Mask-UserPath $GameDir) + "' содержит не-ASCII символы. DirectX-перехватчики (Special K / ReShade / LodMod) и сам движок PlatinumGames ломаются при загрузке шейдеров/текстур по кириллическому пути.") `
            "Перенесите библиотеку Steam / папку игры в путь строго на латинице (например, D:\Games\Steam\steamapps\common\NieRAutomata)."
    }

    $DriveLetter = ($GameDir -replace ':.*$', '')
    $VolInfo = Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue
    if ($VolInfo) {
        $FreeGB = [Math]::Round($VolInfo.SizeRemaining / 1GB, 2)
        Write-Both ("  Файловая система: $($VolInfo.FileSystemType) | Свободно на диске ${DriveLetter}: $FreeGB ГБ") Gray
        if ($VolInfo.FileSystemType -ne "NTFS") {
            Add-Finding "WARN" "Этап 0 (Диск)" `
                "Диск с игрой отформатирован в $($VolInfo.FileSystemType) вместо NTFS" `
                "На exFAT/FAT32 не работают жёсткие ссылки NTFS и права доступа Windows, возможны сбои потоковой подгрузки 4K-текстур." `
                "Рекомендуется устанавливать игру и сборку на стандартный диск NTFS."
        }
        if ($FreeGB -lt 1.5) {
            Add-Finding "CRITICAL" "Этап 0 (Диск)" `
                "На диске ${DriveLetter}: критически мало места ($FreeGB ГБ)!" `
                "Игре, кэшу шейдеров DirectX/NVIDIA и логам Special K некуда записывать данные при старте." `
                "Освободите хотя бы 5–10 ГБ на диске ${DriveLetter}: и системном диске C:."
        }
    }

    # Проверка ошибки "Матрёшка" (кинули папку Payload прямо в игру без запуска Установить_Моды.bat)
    if ((Test-Path (Join-Path $GameDir "Payload\dxgi.dll")) -and -not (Test-Path (Join-Path $GameDir "dxgi.dll"))) {
        Add-Finding "CRITICAL" "Этап 0 (Установка)" `
            "Моды НЕ установлены: папка Payload просто скопирована внутрь папки игры!" `
            "Внутри NieRAutomata лежит подпапка Payload, но сами файлы в корень игры не развёрнуты." `
            "Запустите файл Установить_Моды.bat двойным кликом и дождитесь надписи 'УСПЕШНО!'."
    } elseif (-not (Test-Path (Join-Path $GameDir "dxgi.dll")) -and -not (Test-Path (Join-Path $GameDir "_Disabled_Mods")) -and -not (Test-Path (Join-Path $GameDir "wax"))) {
        Add-Finding "CRITICAL" "Этап 0 (Установка)" `
            "В найденной папке игры вообще нет файлов модпака!" `
            "Либо Установить_Моды.bat ещё не запускался, либо моды были поставлены в другую копию игры на другом диске." `
            "Запустите Установить_Моды.bat и проверьте строку '[1/4] Найдена папка игры'."
    }

    # -------------------------------------------------------------------------
    # СЛОЙ 2: ЛИЦЕНЗИЯ STEAM vs ПИРАТКА / СТАРЫЙ РЕПАК 2017 / MS STORE
    # -------------------------------------------------------------------------
    Write-Both "[2/7] Криминалистика базовой игры (EXE, SteamStub DRM, steam_api64, 24 архива .cpk)..." Yellow

    $ExePath = Join-Path $GameDir "NieRAutomata.exe"
    $OfficialExeSha = "5171bed09e6fec7b21bf0ea479dbd2e1b228695c67d1f0b478549a9be2f5726a"
    $OfficialSteamApiSha = "38f6a1dd1e738e142160322638dae7b88dabcc30eea3f15c58eb08c5341f9b29"

    $IsOfficialSteamExe = $false
    $IsCrackedSteamApi  = $false
    $CrackArtifacts     = @()

    foreach ($cf in @("steam_emu.ini","steam_api64.cdx","steam_api64.o","steam_api64.bak","steam_api64.org","SmartSteamEmu.ini","OnlineFix.ini","OnlineFix64.dll","rune.ini","codex.ini","tenoke.ini","goldberg_steam_apis.dll","steamclient64.dll","steam_interfaces.txt")) {
        if (Test-Path (Join-Path $GameDir $cf)) { $CrackArtifacts += $cf }
    }
    if (Test-Path (Join-Path $GameDir "steam_settings")) { $CrackArtifacts += "steam_settings\" }

    $SteamApiPath = Join-Path $GameDir "steam_api64.dll"
    if (-not (Test-Path $SteamApiPath)) {
        if (Test-Path (Join-Path $GameDir "NieRAutomataCompat.exe")) {
            # У Steam тоже есть NieRAutomataCompat.exe, но без steam_api64.dll это MS Store / повреждённая игра
        }
        Add-Finding "CRITICAL" "Этап 0 (База игры)" `
            "Отсутствует файл steam_api64.dll в корне игры!" `
            "Либо это версия Microsoft Store / Xbox Game Pass (несовместимая со Steam-модами), либо антивирус удалил steam_api64.dll." `
            "Если это Steam — сделайте проверку целостности файлов в Steam, затем заново запустите Установить_Моды.bat."
    } else {
        $sapiSize = (Get-Item $SteamApiPath).Length
        $sapiSha  = Get-QuickSha256 $SteamApiPath
        $sig      = Get-AuthenticodeSignature $SteamApiPath -ErrorAction SilentlyContinue
        if ($sapiSha -eq $OfficialSteamApiSha -and $sapiSize -eq 242976) {
            Write-Both "  [OK] steam_api64.dll: подлинная лицензия Steam (Valve, 242 976 байт)" Green
        } else {
            $IsCrackedSteamApi = $true
            Write-Both ("  [!] steam_api64.dll модифицирован! Размер: $sapiSize байт (оригинал: 242 976), подпись: $($sig.Status)") Red
        }
    }

    if (Test-Path $ExePath) {
        $exeSize = (Get-Item $ExePath).Length
        $exeSha  = Get-QuickSha256 $ExePath
        if ($exeSize -eq 17837952 -and $exeSha -eq $OfficialExeSha) {
            $IsOfficialSteamExe = $true
            Write-Both "  [OK] NieRAutomata.exe: эталонный Steam build 7020666 (17 837 952 байт, секция .bind)" Green
        } else {
            Write-Both "  [!] NieRAutomata.exe НЕ совпадает со Steam build 7020666! Размер: $exeSize байт" Red
            Add-Finding "CRITICAL" "Этап 0 (EXE игры)" `
                "Исполняемый файл NieRAutomata.exe ($exeSize байт) не соответствует Steam-патчу 7020666!" `
                "Моды WAX, AutomataHighFPS, LodMod и NAIOM жёстко привязаны к адресам памяти билда 7020666 (17 837 952 байт)." `
                "Запустите Установить_Моды.bat (он восстановит эталонный EXE) или проверьте целостность лицензии в Steam."
        }
    } else {
        Add-Finding "CRITICAL" "Этап 0 (EXE игры)" `
            "Файл NieRAutomata.exe отсутствует в папке игры!" `
            "Игра недокачана или файл заблокирован антивирусом." `
            "Проверьте карантин Защитника Windows и целостность файлов в Steam."
    }

    # ГЛАВНАЯ ЛОВУШКА ПИРАТОК 2021 ГОДА!
    if (($IsCrackedSteamApi -or $CrackArtifacts.Count -gt 0) -and $IsOfficialSteamExe) {
        $artStr = if ($CrackArtifacts.Count -gt 0) { " Найдены файлы эмулятора: " + ($CrackArtifacts -join ", ") + "." } else { "" }
        Add-Finding "CRITICAL" "Этап 0 (Конфликт Пиратки и SteamStub DRM)" `
            "ОБНАРУЖЕНА ПИРАТКА (РЕПАК), КОНФЛИКТУЮЩАЯ С ЗАШИФРОВАННЫМ STEAM-EXE!" `
            ("В вашей игре подменён пиратский steam_api64.dll ($sapiSize байт вместо 242 976).$artStr При установке автопатчер заменил ваш раскрякнутый NieRAutomata.exe на официальный лицензионный Steam-файл (17 837 952 байт). В официальном EXE осталась защита Valve SteamStub (секция .bind): без запущенного клиента Steam с купленной игрой код .text остаётся зашифрованным и игра мгновенно закрывается/вылетает на старте!") `
            "Сборка рассчитана на лицензию Steam. На репаке зашифрованный лицензионный NieRAutomata.exe не запустится без распаковки секции .bind (Steamless) и включения 'allow_unknown_build: true' в wax\config.json."
    } elseif (-not $IsCrackedSteamApi -and $IsOfficialSteamExe) {
        $steamProc = Get-Process -Name "steam" -ErrorAction SilentlyContinue
        if (-not $steamProc) {
            Add-Finding "WARN" "Этап 0 (Клиент Steam)" `
                "Клиент Steam сейчас закрыт (процесс steam.exe не запущен)" `
                "Лицензионный NieRAutomata.exe защищён оболочкой SteamStub (.bind) — для расшифровки при старте должен быть запущен Steam." `
                "Запускайте игру при включённом клиенте Steam через зелёную кнопку 'ИГРАТЬ'."
        }
    }

    # Точная таблица всех 24 официальных архивов .cpk патча 2021 года
    $ExpectedCpks = [ordered]@{
        "data000.cpk" = 163673152;  "data001.cpk" = 20616;      "data002.cpk" = 17693008;   "data003.cpk" = 28279216;
        "data004.cpk" = 931475872;  "data005.cpk" = 546379848;  "data006.cpk" = 421018944;  "data008.cpk" = 155863808;
        "data009.cpk" = 941418056;  "data010.cpk" = 925588224;  "data012.cpk" = 47820688;   "data013.cpk" = 330214184;
        "data014.cpk" = 7503829728; "data015.cpk" = 3975319320; "data016.cpk" = 3039435104; "data018.cpk" = 1626079696;
        "data019.cpk" = 437752;     "data100.cpk" = 994678272;  "data101.cpk" = 2920624;    "data102.cpk" = 659632;
        "data103.cpk" = 727288;     "data105.cpk" = 4163760;    "data107.cpk" = 4688048;    "data108.cpk" = 4688048
    }
    $Missing2021Cpk = (-not (Test-Path (Join-Path $GameDir "data\data018.cpk"))) -or (-not (Test-Path (Join-Path $GameDir "data\data019.cpk")))
    $BadCpks = @()
    foreach ($kv in $ExpectedCpks.GetEnumerator()) {
        $cp = Join-Path $GameDir ("data\" + $kv.Key)
        if (-not (Test-Path $cp)) {
            $BadCpks += "$($kv.Key) (отсутствует)"
        } else {
            $actualSz = (Get-Item $cp).Length
            if ($actualSz -ne $kv.Value) {
                $BadCpks += "$($kv.Key) (размер $actualSz вместо $($kv.Value))"
            }
        }
    }
    if ($Missing2021Cpk) {
        Write-Both "  [КРИТИЧНО] Отсутствуют архивы data018.cpk / data019.cpk патча 2021 года!" Red
        Add-Finding "CRITICAL" "Этап 0 (Старая версия игры 2017 года)" `
            "Установлена старая версия игры 2017–2020 гг. (до глобального патча июля 2021)!" `
            "В папке data отсутствуют архивы data018.cpk (1.62 ГБ) и data019.cpk. Старые репаки (CPY / Baldman / Xatab / старый FitGirl) полностью несовместимы с EXE и модами 2021–2026 года — игра падает мгновенно при монтировании архивов!" `
            "Установите актуальную лицензионную версию игры из Steam (build 7020666)."
    } elseif ($BadCpks.Count -gt 0) {
        Write-Both ("  [!] Повреждены базовые архивы .cpk (" + $BadCpks.Count + " шт.): " + ($BadCpks[0..([Math]::Min(3,$BadCpks.Count-1))] -join ", ")) Red
        Add-Finding "CRITICAL" "Этап 0 (Битые архивы .cpk)" `
            "Повреждены или отличаются базовые архивы игры data\*.cpk!" `
            ("Не совпадают размеры: " + ($BadCpks -join "; ")) `
            "Нажмите в Toggle_Mods.bat кнопку [R] (сброс к ванили), сделайте проверку целостности файлов в Steam, затем снова запустите Установить_Моды.bat."
    } else {
        Write-Both "  [OK] Все 24 базовых архива data\*.cpk побайтово совпадают с эталоном Steam 2021" Green
    }

    # -------------------------------------------------------------------------
    # СЛОЙ 3: SHA-256 ЦЕЛОСТНОСТЬ МОДОВ, КАРАНТИН АНТИВИРУСА И ЧУЖИЕ ХВОСТЫ
    # -------------------------------------------------------------------------
    Write-Both "[3/7] Криптографическая сверка всех .dll модов (SHA-256), проверка карантина и конфликтов..." Yellow

    $ModBinaries = @(
        @{ File="dxgi.dll";            Size=10617344; Sha="8649378041639807d769972776f77c458ec73d80296ae6786007a046d993f73c"; DisKey="";                Required=$true;  Label="Special K / FAR v23.6.9.1 (ядро)" },
        @{ File="wax.dll";             Size=5020672;  Sha="ed4433830091fcebdc3312deec89808494df1f15ad4aa6f5485ae9b6d1973145"; DisKey="";                Required=$true;  Label="WAX Limit Break v0.3.0 (пул памяти и гардероб)" },
        @{ File="dinput8.dll";         Size=1134592;  Sha="86949b8b935865b4882d3cb23b98e8d70f0ab9120802fc9573c386e8f9195726"; DisKey="";                Required=$true;  Label="NAIOM Input Fix (клавиатура/мышь)" },
        @{ File="AutomataHighFPS.dll"; Size=583680;   Sha="5de8163740749192b0f405521e56f5c12873d4cfd99b52aecc7bf111ae75cf95"; DisKey="Automata_HighFPS";Required=$false; Label="AutomataHighFPS v0.2.0 (#11)" },
        @{ File="xinput1_4.dll";       Size=343040;   Sha="93d02d6abdd4cb964ab044c4f4c73460d4ee970e3ca6456e9fe19c7dac1d6d02"; DisKey="Automata_LodMod"; Required=$false; Label="Automata LodMod v0.77.4 (#12)" },
        @{ File="d3d11.dll";           Size=452608;   Sha="80b503283ffd1ed59df70853f16aee7070c88f6a4c793b120b5302c880b7cc6d"; DisKey="DLAA_826";        Required=$false; Label="NIER_DLAA Proxy (#13)" },
        @{ File="nvngx_dlss.dll";      Size=58956912; Sha="3975567b8943c53acce397f2b72380092f84f162d00b0d2c7d08a1025c563983"; DisKey="DLAA_826";        Required=$false; Label="NVIDIA DLSS 4 / DLAA SDK (#13)" },
        @{ File="ReShade64.dll";       Size=3800288;  Sha="3bf46fafce509b4aba82cbe904d8453d468804669482ee72da0f6e0873a06ece"; DisKey="ReShade_Engine";  Required=$false; Label="ReShade 5.8.0 (#8)" }
    )

    $MissingDlls = @()
    $DlaaActive  = $false
    $ReshadeActive = $false

    foreach ($mb in $ModBinaries) {
        $actP = Join-Path $GameDir $mb.File
        $disP = if ($mb.DisKey) { Join-Path $GameDir ("_Disabled_Mods\" + $mb.DisKey + "\" + $mb.File) } else { "" }
        if (Test-Path $actP) {
            $sz  = (Get-Item $actP).Length
            $sha = Get-QuickSha256 $actP
            if ($sz -eq $mb.Size -and $sha -eq $mb.Sha) {
                Write-Both "  [OK] $($mb.File) — активен, контрольная сумма SHA-256 верна" Green
                if ($mb.File -eq "d3d11.dll") { $DlaaActive = $true }
                if ($mb.File -eq "ReShade64.dll") { $ReshadeActive = $true }
            } else {
                Write-Both "  [КРИТИЧНО] $($mb.File) ПОВРЕЖДЁН ИЛИ ЧУЖОЙ! Размер: $sz (нужен $($mb.Size))" Red
                Add-Finding "CRITICAL" "Этап 1 (Подмена/порча .dll)" `
                    "Файл $($mb.File) ($($mb.Label)) повреждён или перезаписан чужим модом!" `
                    "Контрольная сумма SHA-256 не совпадает с эталоном сборки (текущий размер: $sz байт, эталон: $($mb.Size) байт). Чужая .dll с тем же именем ломает цепочку хуков и вызывает мгновенный вылет!" `
                    "Перезапустите Установить_Моды.bat поверх папки игры (убедившись, что архив распаковался без ошибок)."
            }
        } elseif ($disP -and (Test-Path $disP)) {
            Write-Both "  [--] $($mb.File) — штатно выключен через Toggle_Mods.bat ($($mb.Label))" DarkGray
        } else {
            Write-Both "  [КРИТИЧНО] $($mb.File) БЕСЛЕДНО ОТСУТСТВУЕТ ($($mb.Label))!" Red
            $MissingDlls += $mb.File
        }
    }

    if ($MissingDlls.Count -gt 0) {
        # Проверим журнал Защитника Windows на карантин (Event ID 1116 / 1117)
        $DefQuarantine = ""
        try {
            $defEvents = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational'; Id=1116,1117} -MaxEvents 15 -ErrorAction SilentlyContinue
            foreach ($de in $defEvents) {
                if ($de.Message -match 'NieRAutomata|dxgi\.dll|wax\.dll|dinput8\.dll|xinput1_4\.dll|d3d11\.dll') {
                    $DefQuarantine = " [ПОДТВЕРЖДЕНО ЖУРНАЛОМ ЗАЩИТНИКА WINDOWS: антивирус заблокировал файл игры!]"
                    break
                }
            }
        } catch {}
        Add-Finding "CRITICAL" "Этап 1 (Потерянные .dll / Антивирус)" `
            ("Из папки игры исчезли ключевые библиотеки: " + ($MissingDlls -join ", ")) `
            ("Файлов нет ни в корне игры, ни в _Disabled_Mods. Либо архив распаковался не до конца (не хватило места на диске), либо антивирус молча съел DLL-перехватчики в карантин!" + $DefQuarantine) `
            "Добавьте папку NieRAutomata в исключения антивируса / Защитника Windows и заново запустите Установить_Моды.bat."
    }

    # Поиск ЧУЖИХ старых модов-паразитов в корне игры
    $ForeignConflicts = @()
    foreach ($badFile in @("version.dll","winmm.dll","winhttp.dll","dsound.dll","d3d9.dll","d3d10.dll","d3d12.dll","opengl32.dll","FAR.dll","SpecialK64.dll","dxvk.conf","ReShade32.dll","reshade.dll","input8.dll","msacm32.dll","dbghelp.dll")) {
        if (Test-Path (Join-Path $GameDir $badFile)) { $ForeignConflicts += $badFile }
    }
    if (Test-Path (Join-Path $GameDir "plugins")) { $ForeignConflicts += "папка plugins\" }
    if ($ForeignConflicts.Count -gt 0) {
        Write-Both ("  [КРИТИЧНО] Найдены чужие старые моды-инжекторы в корне игры: " + ($ForeignConflicts -join ", ")) Red
        Add-Finding "CRITICAL" "Этап 1 (Конфликт со старыми модами)" `
            ("В папке игры лежат сторонние старые инжекторы: " + ($ForeignConflicts -join ", ")) `
            "Команда копирования установщика не удаляет чужие файлы от прошлых сборок (старый FAR 2017, Wolf's Limit Break, DXVK, ASI Loader, Resorep). Два перехватчика памяти дерутся за одни и те же адреса и мгновенно роняют игру!" `
            ("Уберите посторонние файлы (" + ($ForeignConflicts -join ", ") + ") из корня игры в отдельную резервную папку.")
    }

    # Проверка тяжёлых игровых архивов сборки, 0-байтовых текстур и JSON-конфигов WAX
    $ZeroByteFiles = @(Get-ChildItem -Path (Join-Path $GameDir "SK_Res\inject\textures") -Filter "*.dds" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Length -eq 0 })
    $DdsTotal = (Get-ChildItem -Path (Join-Path $GameDir "SK_Res\inject\textures") -Filter "*.dds" -Recurse -ErrorAction SilentlyContinue).Count
    if ($ZeroByteFiles.Count -gt 0) {
        Add-Finding "CRITICAL" "Этап 1 (Битая распаковка текстур)" `
            "Найдены пустые (0 байт) повреждённые 4K-текстуры (.dds): $($ZeroByteFiles.Count) шт.!" `
            "При распаковке 59 ГБ архива оборвалась запись (закончилось место во временной папке или сбой архиватора). При подгрузке битой .dds игра вылетает!" `
            "Распакуйте архив сборки заново через 7-Zip (не встроенным Проводником Windows!) и запустите Установить_Моды.bat."
    } elseif ($DdsTotal -gt 0) {
        Write-Both "  [OK] Текстурный банк SK_Res: $DdsTotal .dds файлов (пустых/оборванных 0-байтовых нет)" Green
    }

    # Проверка синтаксиса всех JSON-конфигов WAX
    $BrokenJsons = @()
    $WaxTimeoutMs = $null
    $WaxMaxVramMb = $null
    if (Test-Path (Join-Path $GameDir "wax")) {
        Get-ChildItem -Path (Join-Path $GameDir "wax") -Filter "*.json" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $rawJ = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
                $parsed = $rawJ | ConvertFrom-Json -ErrorAction Stop
                if ($_.Name -eq "config.json") {
                    $WaxTimeoutMs = $parsed.steam_stub_timeout_ms
                    $WaxMaxVramMb = $parsed.max_injected_textures_vram_mb
                }
            } catch {
                $BrokenJsons += $_.FullName.Replace($GameDir + "\", "")
            }
        }
    }
    if ($BrokenJsons.Count -gt 0) {
        Add-Finding "CRITICAL" "Этап 2 (Повреждён JSON в WAX)" `
            ("Сломан синтаксис JSON-конфигов WAX: " + ($BrokenJsons -join ", ")) `
            "Модуль wax.dll аварийно завершается при чтении битого JSON." `
            "Перезапустите Установить_Моды.bat для восстановления чистых конфигов."
    } elseif ($null -ne $WaxTimeoutMs) {
        Write-Both "  [OK] Все JSON-таблицы WAX валидны (steam_stub_timeout_ms = $WaxTimeoutMs мс)" Green
        if ($WaxTimeoutMs -le 500) {
            Add-Finding "WARN" "Этап 2 (Таймаут расшифровки SteamStub в WAX)" `
                "Узкий таймаут ожидания расшифровки SteamStub в wax\config.json ($WaxTimeoutMs мс = 0.2 сек)" `
                "Даже на быстрых NVMe-дисках расшифровка SteamStub занимает ~110–150 мс. Если процессор/диск чуть задумался при старте или антивирус сканирует EXE дольше 200 мс, WAX начинает патчить ещё зашифрованный код и игра мгновенно вылетает с ошибкой 0xc0000005!" `
                "Нажмите [1] в меню авто-фикса ниже — скрипт увеличит ожидание до безопасных 5000 мс (на скорость запуска на быстрых ПК это вообще не влияет!)."
        }
    }

    # -------------------------------------------------------------------------
    # СЛОЙ 4: СИСТЕМНЫЕ БИБЛИОТЕКИ ОС, ЖЕЛЕЗО (GPU/VRAM), ПОДКАЧКА И ДОКУМЕНТЫ
    # -------------------------------------------------------------------------
    Write-Both "[4/7] Проверка библиотек Windows, видеокарты, реального VRAM, файла подкачки и сохранений..." Yellow

    # 4.1 VC++ 2022 (msvcp140_atomic_wait.dll!) и Media Feature Pack (mfplat.dll)
    $Sys32 = Join-Path $env:SystemRoot "System32"
    if (-not (Test-Path (Join-Path $Sys32 "msvcp140_atomic_wait.dll")) -or -not (Test-Path (Join-Path $Sys32 "vcruntime140_1.dll"))) {
        Write-Both "  [КРИТИЧНО] Отсутствует системная библиотека msvcp140_atomic_wait.dll (старый Visual C++)!" Red
        Add-Finding "CRITICAL" "Этап 1 (Загрузчик Windows — нет свежего VC++ 2022)" `
            "Не установлен актуальный пакет Microsoft Visual C++ 2015–2022 (x64)!" `
            "Ядро сборки dxgi.dll (Special K) жёстко импортирует системную библиотеку msvcp140_atomic_wait.dll (она появилась только в свежих выпусках VS 2022 v14.32+, сам Steam со старой игрой её не ставит!). Без неё Windows убивает процесс игры на 0-й секунде (ошибка 0xc0000135) ещё до создания логов!" `
            "Скачайте и установите официальный пакет Microsoft (30 сек): https://aka.ms/vs/17/release/vc_redist.x64.exe (или нажмите [6] в меню ниже для автоустановки через winget)."
    } else {
        $vcVer = (Get-Item (Join-Path $Sys32 "msvcp140_atomic_wait.dll")).VersionInfo.FileVersion
        Write-Both "  [OK] Microsoft Visual C++ 2022 x64 актуален (msvcp140_atomic_wait.dll v$vcVer)" Green
    }

    if (-not (Test-Path (Join-Path $Sys32 "mfplat.dll")) -or -not (Test-Path (Join-Path $Sys32 "mfreadwrite.dll"))) {
        Write-Both "  [КРИТИЧНО] Отсутствует Windows Media Feature Pack (mfplat.dll)!" Red
        Add-Finding "CRITICAL" "Этап 1 (Windows N/KN без Media Feature Pack)" `
            "В вашей редакции Windows отсутствует системный декодер mfplat.dll (Media Feature Pack)!" `
            "Модуль LodMod (xinput1_4.dll) импортирует mfplat.dll для аппаратного декодирования H.264 катсцен 2K 60FPS. Без него игра не может загрузить xinput1_4.dll или падает на первом же ролике!" `
            "Откройте Параметры Windows -> Приложения -> Дополнительные компоненты -> Добавить компонент -> установите 'Пакет Media Feature Pack'."
    }

    # 4.2 Истинное определение видеокарт и 64-битного VRAM
    $Gpus = @()
    Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.DriverDesc) {
            $qw = $_.'HardwareInformation.qwMemorySize'
            $vramGb = if ($qw -is [long] -or $qw -is [uint64] -or $qw -is [int]) { [Math]::Round([double]$qw / 1GB, 2) }
                      elseif ($qw -is [byte[]] -and $qw.Length -ge 8) { [Math]::Round([BitConverter]::ToUInt64($qw, 0) / 1GB, 2) }
                      else { 0 }
            $isIntegrated = ($_.DriverDesc -match 'Intel\(R\)\s*(UHD|HD|Iris)|AMD Radeon\(TM\)\s*Graphics|Microsoft Basic')
            $Gpus += [PSCustomObject]@{
                Name         = $_.DriverDesc
                VramGB       = $vramGb
                DriverVer    = $_.DriverVersion
                IsIntegrated = $isIntegrated
                IsNvidiaRtx  = ($_.DriverDesc -match 'NVIDIA.*RTX')
                IsNvidiaGtx  = ($_.DriverDesc -match 'NVIDIA.*GTX')
                IsAmd        = ($_.DriverDesc -match 'AMD|Radeon') -and -not $isIntegrated
                IsIntelArc   = ($_.DriverDesc -match 'Intel.*Arc')
            }
        }
    }

    $PrimaryGpu = $Gpus | Where-Object { -not $_.IsIntegrated } | Sort-Object VramGB -Descending | Select-Object -First 1
    if (-not $PrimaryGpu -and $Gpus.Count -gt 0) { $PrimaryGpu = $Gpus[0] }

    if ($PrimaryGpu) {
        Write-Both ("  Видеокарта : $($PrimaryGpu.Name) | VRAM: $($PrimaryGpu.VramGB) ГБ | Драйвер: $($PrimaryGpu.DriverVer)") Cyan

        if ($DlaaActive -and -not $PrimaryGpu.IsNvidiaRtx) {
            Add-Finding "CRITICAL" "Этап 3 (Несовместимость NVIDIA DLAA с видеокартой)" `
                "Мод NVIDIA DLAA / DLSS 4 (#13) ВКЛЮЧЁН на видеокарте БЕЗ тензорных ядер RTX ($($PrimaryGpu.Name))!" `
                "Библиотеки d3d11.dll + nvngx_dlss.dll используют проприетарный аппаратный движок NVIDIA NGX (только линейки GeForce RTX 20/30/40/50). На картах AMD Radeon, Intel и NVIDIA GTX инициализация D3D11/NGX обрывается вылетом или чёрным экраном на старте!" `
                "Нажмите [2] в меню авто-фикса ниже (или выключите пункт 13 в Toggle_Mods.bat) — игра сразу перейдёт на чистый системный DirectX 11!"
        }

        if ($PrimaryGpu.VramGB -gt 0 -and $PrimaryGpu.VramGB -le 8.5) {
            $dxgiIniP = Join-Path $GameDir "dxgi.ini"
            $skCacheMb = 0
            if (Test-Path $dxgiIniP) {
                $dxTxt = Get-Content $dxgiIniP -Raw -ErrorAction SilentlyContinue
                if ($dxTxt -match 'MaxSizeInMiB=(\d+)') { $skCacheMb = [int]$Matches[1] }
            }
            if ($skCacheMb -ge 6000) {
                Add-Finding "WARN" "Этап 3 (Квота видеопамяти VRAM)" `
                    "Кэш 4K-текстур в dxgi.ini выставлен на $skCacheMb МБ (8 ГБ), а у вашей карты $($PrimaryGpu.VramGB) ГБ VRAM" `
                    "На видеокартах с 4–8 ГБ видеопамяти такой большой буфер вместе с тенями 4096x4096 может вызывать переполнение памяти драйвера и вылет." `
                    "Нажмите [4] в меню авто-фикса ниже — скрипт аккуратно подстроит квоты кэша под карты 4–8 ГБ VRAM без потери 4K-текстур."
            }
        }
    }

    # 4.3 ОЗУ и Файл подкачки (Commit Limit)
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $ramGB    = [Math]::Round($osInfo.TotalVisibleMemorySize / 1MB, 1)
        $commitGB = [Math]::Round($osInfo.TotalVirtualMemorySize / 1MB, 1)
        $pageGB   = [Math]::Round(($osInfo.TotalVirtualMemorySize - $osInfo.TotalVisibleMemorySize) / 1MB, 1)
        Write-Both "  Память ПК  : ОЗУ $ramGB ГБ | Файл подкачки: $pageGB ГБ (общий лимит: $commitGB ГБ)" Gray
        if ($commitGB -lt 21.0) {
            Add-Finding "CRITICAL" "Этап 4 (Нехватка виртуальной памяти / отключён файл подкачки)" `
                "Суммарный объём виртуальной памяти Windows всего $commitGB ГБ (ОЗУ $ramGB ГБ + подкачка $pageGB ГБ)!" `
                "С пакетом 4K-текстур на 30.8 ГБ игра резервирует 16.5–19 ГБ виртуальной памяти (Commit). Если у вас 16 ГБ ОЗУ и отключён/зажат файл подкачки Windows, процесс NieRAutomata.exe гарантированно падает с Access Violation (0xc0000005) или Out of Memory!" `
                "Включите в Windows 'Размер файла подкачки по выбору системы' на быстром SSD (или задайте минимум 16384 МБ)."
        }
    } catch {}

    # 4.4 Папка сохранений Documents\My Games\NieR_Automata и Контролируемый доступ к папкам Защитника
    $DocsDir = [Environment]::GetFolderPath('MyDocuments')
    $SaveDir = Join-Path $DocsDir "My Games\NieR_Automata"
    $SysData = Join-Path $SaveDir "SystemData.dat"
    $GrafIni = Join-Path $SaveDir "Graphic.ini"

    try {
        $mp = Get-MpPreference -ErrorAction Stop
        if ($mp.EnableControlledFolderAccess -eq 1) {
            $allowed = @($mp.ControlledFolderAccessAllowedApplications)
            $isAllowed = $false
            foreach ($a in $allowed) {
                if ($a -ieq $ExePath) { $isAllowed = $true; break }
            }
            if (-not $isAllowed) {
                Write-Both "  [КРИТИЧНО] Защитник Windows ('Контролируемый доступ к папкам') БЛОКИРУЕТ запись NieRAutomata.exe в Документы!" Red
                Add-Finding "CRITICAL" "Этап 4 (Блокировка папки Документы Защитником Windows)" `
                    "Включён 'Контролируемый доступ к папкам' Windows Defender, а NieRAutomata.exe НЕТ в списке разрешённых!" `
                    "Защитник Windows запрещает игре создавать и обновлять файлы Graphic.ini и SystemData.dat в папке 'Документы\My Games\NieR_Automata', из-за чего игра зависает на белом/чёрном экране или вылетает при инициализации сохранений!" `
                    ("Откройте Безопасность Windows -> Защита от вирусов и угроз -> Защита от программ-шантажистов -> Разрешить работу приложения -> добавьте: " + (Mask-UserPath $ExePath))
            } else {
                Write-Both "  [OK] Контролируемый доступ к папкам активен, но NieRAutomata.exe добавлен в белый список" Green
            }
        }
    } catch {}

    if (-not (Test-Path $SysData)) {
        Write-Both "  [!] Файл SystemData.dat в 'Документы\My Games\NieR_Automata' ещё не создан!" Yellow
        Add-Finding "WARN" "Этап 4 (Первый чистый запуск)" `
            "Отсутствует системное сохранение SystemData.dat в папке Документы\My Games\NieR_Automata" `
            "Либо игру ни разу не запускали до/после установки, либо игра упала раньше появления стартового экрана, либо OneDrive / Защитник Windows не дал создать папку." `
            "Если стоят агрессивные хуки (DLAA/ReShade), примените пункт [5] в меню ниже для первого успешного входа и создания SystemData.dat."
    } else {
        if (Test-Path $GrafIni) {
            $gRaw = Get-Content $GrafIni -Raw -ErrorAction SilentlyContinue
            if ($gRaw -match 'VideoCard=([0-9A-Fa-f]+)') {
                $boundGpu = Decode-Utf16Hex $Matches[1]
                if ($boundGpu) {
                    Write-Both "  [OK] Профиль сохранений активен (игра привязана к видеокарте: '$boundGpu')" Green
                    if (($boundGpu -match 'Intel\(R\)\s*(UHD|HD|Iris)|AMD Radeon\(TM\)\s*Graphics') -and $PrimaryGpu -and (-not $PrimaryGpu.IsIntegrated)) {
                        Add-Finding "CRITICAL" "Этап 3 (Игра запустилась на встроенной графике процессора вместо видеокарты!)" `
                            "Игра привязалась к слабой встроенной графике '$boundGpu' вместо вашей видеокарты '$($PrimaryGpu.Name)'!" `
                            "Либо кабель монитора воткнут в материнскую плату вместо разъёма видеокарты, либо Windows назначила энергосберегающее видеоядро." `
                            "В Параметрах Windows -> Система -> Дисплей -> Графика выберите NieRAutomata.exe и поставьте 'Высокая производительность ($($PrimaryGpu.Name))'."
                    }
                }
            }
        }
    }

    # -------------------------------------------------------------------------
    # СЛОЙ 5: «ЧЁРНЫЙ ЯЩИК» — ПОЭТАПНАЯ РЕКОНСТРУКЦИЯ ПОСЛЕДНЕГО ЗАПУСКА ПО ЛОГАМ
    # -------------------------------------------------------------------------
    Write-Both "[5/7] Реконструкция цепочки последнего запуска по всем логам модов («Чёрный ящик»)..." Yellow

    $DxgiLogP  = Join-Path $GameDir "logs\dxgi.log"
    $DlaaLogP  = Join-Path $GameDir "NIER_DLAA.log"
    $HfpsLogP  = Join-Path $GameDir "AutomataHighFPS.log"
    $LodLogP   = Join-Path $GameDir "LodMod.log"
    $ReshLogP  = Join-Path $GameDir "ReShade.log"
    $WaxLogObj = Get-ChildItem -Path (Join-Path $GameDir "logs") -Filter "wax.log*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    $AllLogs = @()
    foreach ($lp in @($DxgiLogP, $DlaaLogP, $HfpsLogP, $LodLogP, $ReshLogP)) {
        if (Test-Path $lp) { $AllLogs += (Get-Item $lp) }
    }
    if ($WaxLogObj) { $AllLogs += $WaxLogObj }

    $LatestBootTime = $null
    if ($AllLogs.Count -eq 0) {
        Write-Both "  [!] В папке игры нет НИ ОДНОГО лога запуска модов!" Red
        Add-Finding "CRITICAL" "Этап 0–1 (Смерть процесса ДО инициализации модов)" `
            "Ни один мод (даже ядро dxgi.dll) ни разу не успел получить управление!" `
            "Это означает 100% одно из трёх: (1) вы ещё ни разу не нажимали 'Играть' после установки; (2) в Windows нет свежей системной библиотеки msvcp140_atomic_wait.dll (Visual C++ 2022); (3) сработала защита SteamStub на пиратке / закрытом Steam." `
            "Проверьте пункты выше (VC++ 2022, клиент Steam, антивирус)."
    } else {
        $LatestBootTime = ($AllLogs | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
        Write-Both ("  Последняя зафиксированная попытка запуска: " + $LatestBootTime.ToString("yyyy-MM-dd HH:mm:ss")) Cyan

        # Читаем содержимое актуальных логов этой сессии (окно 5 минут от последнего лога)
        $SessionCutoff = $LatestBootTime.AddMinutes(-5)

        $dxgiTxt = if ((Test-Path $DxgiLogP) -and ((Get-Item $DxgiLogP).LastWriteTime -ge $SessionCutoff)) { Get-Content $DxgiLogP -Raw -ErrorAction SilentlyContinue } else { "" }
        $waxTxt  = if ($WaxLogObj -and ($WaxLogObj.LastWriteTime -ge $SessionCutoff)) { Get-Content $WaxLogObj.FullName -TotalCount 150 -ErrorAction SilentlyContinue | Out-String } else { "" }
        $hfpsTxt = if ((Test-Path $HfpsLogP) -and ((Get-Item $HfpsLogP).LastWriteTime -ge $SessionCutoff)) { Get-Content $HfpsLogP -TotalCount 60 -ErrorAction SilentlyContinue | Out-String } else { "" }
        $dlaaTxt = if ((Test-Path $DlaaLogP) -and ((Get-Item $DlaaLogP).LastWriteTime -ge $SessionCutoff)) { Get-Content $DlaaLogP -TotalCount 80 -ErrorAction SilentlyContinue | Out-String } else { "" }
        $lodTxt  = if ((Test-Path $LodLogP)  -and ((Get-Item $LodLogP).LastWriteTime  -ge $SessionCutoff)) { Get-Content $LodLogP  -TotalCount 80 -ErrorAction SilentlyContinue | Out-String } else { "" }
        $reshTxt = if ((Test-Path $ReshLogP) -and ((Get-Item $ReshLogP).LastWriteTime -ge $SessionCutoff)) { Get-Content $ReshLogP -TotalCount 80 -ErrorAction SilentlyContinue | Out-String } else { "" }

        # Этап A: Старт Special K (dxgi.dll)
        if ($dxgiTxt -match 'dxgi\.log created') {
            Write-Both "    [ШАГ 1: ПРОЙДЕН] Ядро Special K (dxgi.dll) загрузилось в процесс" Green
        } else {
            Write-Both "    [ШАГ 1: СБОЙ!]   dxgi.dll НЕ обновил лог при последнем запуске!" Red
        }

        # Этап B: Ранние плагины AutomataHighFPS + WAX + расшифровка SteamStub
        if ($waxTxt -match 'The OEP hardware breakpoint never fired within') {
            Write-Both "    [ШАГ 2: СБОЙ!]   WAX НЕ ДОЖДАЛСЯ РАСШИФРОВКИ STEAMSTUB (таймаут 200 мс истёк)!" Red
            Add-Finding "CRITICAL" "Этап 2 (Подтверждено логом WAX: сбой SteamStub 200 мс!)" `
                "В логе wax.log найдена точная причина вылета: 'The OEP hardware breakpoint never fired within 200 ms'!" `
                "Расшифровка Steam-защиты на вашем ПК заняла чуть больше 0.2 секунды, и WAX начал патчить ещё зашифрованную память игры, вызвав мгновенный краш!" `
                "Нажмите [1] в меню ниже — таймаут увеличится до 5000 мс, и вылет исчезнет мгновенно!"
        } elseif ($waxTxt -match 'Unexpected executable|does not match the build WAX supports') {
            Write-Both "    [ШАГ 2: СБОЙ!]   WAX отклонил чужой/пиратский NieRAutomata.exe!" Red
            Add-Finding "CRITICAL" "Этап 2 (Подтверждено логом WAX: несовместимый EXE)" `
                "В логе wax.log зафиксирован отказ: NieRAutomata.exe не соответствует лицензионному Steam-билду!" `
                "Без аллокатора памяти WAX игра с тяжёлыми 4K-моделями костюмов вылетает." `
                "Используйте лицензионный Steam-билд 7020666."
        } elseif ($waxTxt -match 'Patches applied, starting game') {
            Write-Both "    [ШАГ 2: ПРОЙДЕН] SteamStub расшифрован, патчи памяти WAX и HighFPS успешно применены" Green
        } elseif ($waxTxt) {
            Write-Both "    [ШАГ 2: ОБОРВАН] WAX начал загрузку, но оборвался до запуска игры!" Red
        }

        if ($hfpsTxt -match 'unsupported game version') {
            Add-Finding "CRITICAL" "Этап 2 (Лог AutomataHighFPS)" `
                "AutomataHighFPS сообщил 'unsupported game version'!" `
                "Версия NieRAutomata.exe не совпадает с патчем 2021 года." `
                "Запустите Установить_Моды.bat для восстановления совместимого EXE."
        }

        # Этап C: DirectX 11 + NVIDIA DLAA
        if ($DlaaActive) {
            if ($dlaaTxt -match 'NGX init failed|DLSS not available|creating the DLSS feature.*failed|D3D11 setup failed|FATAL:') {
                Write-Both "    [ШАГ 3: СБОЙ!]   Модуль NVIDIA DLAA (d3d11.dll) выдал фатальную ошибку инициализации NGX/DLSS!" Red
                Add-Finding "CRITICAL" "Этап 3 (Подтверждено логом NIER_DLAA.log: сбой NGX/DLSS!)" `
                    "В NIER_DLAA.log записан отказ инициализации NVIDIA DLAA / NGX!" `
                    "Либо видеокарта не поддерживает RTX DLSS, либо устарел видеодрайвер NVIDIA." `
                    "Нажмите [2] в меню ниже для мгновенного отключения DLAA (или обновите драйвер NVIDIA Game Ready)."
            } elseif ($dlaaTxt -match 'D3D11CreateDeviceAndSwapChain') {
                Write-Both "    [ШАГ 3: ПРОЙДЕН] Прокси DirectX 11 и хуки NVIDIA DLAA инициализированы" Green
            } elseif ($dlaaTxt -match 'NIER_DLAA proxy attached') {
                Write-Both "    [ШАГ 3: ОБОРВАН] NIER_DLAA подключился, но игра УПАЛА ДО создания D3D11-устройства окна!" Red
                Add-Finding "CRITICAL" "Этап 3 (Обрыв на создании DirectX 11 устройства)" `
                    "Лог NIER_DLAA.log оборвался ровно перед созданием окна DirectX 11 (D3D11CreateDeviceAndSwapChain)!" `
                    "Типичный конфликт тройного перехвата DirectX 11 (Special K + DLAA d3d11.dll + ReShade / внешний оверлей)." `
                    "Нажмите [2] или [5] в меню ниже, чтобы отключить DLAA/ReShade и проверить чистый запуск."
            }
        }

        # Этап D: LodMod (XInput + USM катсцены)
        if ($lodTxt -match 'Error:|Failed to create H264 Decoder|Ran out of memory') {
            Write-Both "    [ШАГ 4: СБОЙ!]   В LodMod.log обнаружена критическая ошибка памяти/декодера!" Red
            Add-Finding "CRITICAL" "Этап 4 (Подтверждено логом LodMod.log)" `
                "В LodMod.log зафиксирована ошибка декодера H.264 или нехватки памяти!" `
                "Проверьте наличие Media Feature Pack и размер файла подкачки Windows." `
                "При необходимости нажмите [4] в меню ниже для снижения разрешения теней с 4096 до 2048."
        } elseif ($lodTxt -match 'Shadow resolution patched') {
            Write-Both "    [ШАГ 4: ПРОЙДЕН] Модуль LodMod (дальность прорисовки и 155 роликов 2K 60FPS) загружен" Green
        }

        # Этап E: ReShade 5.8 + SwapChain
        if ($ReshadeActive) {
            if ($reshTxt -match 'CreateSwapChainForHwnd') {
                Write-Both "    [ШАГ 5: ПРОЙДЕН] Шейдерный движок ReShade 5.8 успешно создал графическое окно игры" Green
            } elseif ($reshTxt -match 'Initializing crosire') {
                Write-Both "    [ШАГ 5: ОБОРВАН] ReShade начал ставить хуки, но игра УПАЛА до вывода картинки на экран!" Red
                Add-Finding "CRITICAL" "Этап 5 (Сбой на инициализации хуков ReShade64.dll)" `
                    "ReShade.log оборвался во время перехвата DirectX 11 до появления окна (CreateSwapChainForHwnd)!" `
                    "Конфликт ленивой подгрузки ReShade64.dll с драйвером видеокарты или фоновым оверлеем (MSI Afterburner / RTSS / NVIDIA App)." `
                    "Нажмите [3] в меню ниже для отключения ReShade (#8)."
            }
        }

        # Этап F: Вход в сам движок NieR:Automata (STARTUP BOOT CORE)
        if ($waxTxt -match 'STARTUP BOOT CORE') {
            Write-Both "    [ШАГ 6: ПРОЙДЕН] Движок самой игры смонтировал все .cpk и вошёл в STARTUP BOOT CORE!" Green
        } elseif ($waxTxt) {
            Write-Both "    [ШАГ 6: ОБОРВАН] Игра НЕ дошла до чтения ядра STARTUP BOOT CORE (упала на этапе монтирования окон/архивов)!" Red
        }
    }

    # -------------------------------------------------------------------------
    # СЛОЙ 6: РАЗБОР СТЕКА ПАДЕНИЯ (logs\crash\*\crash.log + WINDOWS EVENT ID 1000)
    # -------------------------------------------------------------------------
    Write-Both "[6/7] Криминалистика дампов падения (Special K Crash Handler + Журнал событий Windows)..." Yellow

    $LatestSkCrash = Get-ChildItem -Path (Join-Path $GameDir "logs\crash") -Filter "crash.log" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 400 } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $LatestSkCrash) {
        $rootCrash = Join-Path $GameDir "logs\crash.log"
        if ((Test-Path $rootCrash) -and ((Get-Item $rootCrash).Length -gt 400)) {
            $LatestSkCrash = Get-Item $rootCrash
        }
    }

    if ($LatestSkCrash) {
        $isFreshSkCrash = (-not $LatestBootTime) -or ($LatestSkCrash.LastWriteTime -ge $LatestBootTime.AddMinutes(-5))
        $cTxt = Get-Content $LatestSkCrash.FullName -TotalCount 55 -ErrorAction SilentlyContinue | Out-String
        $faultMod = if ($cTxt -match "\[ FaultMod \]\s+# File\.*:\s+'([^']+)'") { Split-Path -Leaf $Matches[1] } else { "Неизвестно" }
        $ripAddr  = if ($cTxt -match "\[ FaultMod \]\s+\* RIP Addr\.:\s+([^\r\n]+)") { $Matches[1].Trim() } else { "" }
        $exType   = if ($cTxt -match "\[! Except !\]\s+<<\s*([^>]+?)\s*>>") { $Matches[1].Trim() } else { "Unhandled Exception" }
        $vramLine = if ($cTxt -match "Current VRAM In Use\.*:\s*([^\r\n]+)") { $Matches[1].Trim() } else { "окно ещё не создано (вылет на старте)" }
        $vmLine   = if ($cTxt -match "Current Virtual Memory\.:\s*([^\r\n]+)") { $Matches[1].Trim() } else { "" }

        $stackMods = @()
        foreach ($sm in @("ReShade64.dll","d3d11.dll","nvngx_dlss.dll","wax.dll","AutomataHighFPS.dll","xinput1_4.dll","dinput8.dll","RTSSHooks64.dll","DiscordHook64.dll","EOSOVH-Win64-Shipping.dll","nvspcap64.dll","nvwgf2umx.dll","amdxc64.dll","aticfx64.dll")) {
            if ($cTxt -match [regex]::Escape($sm)) { $stackMods += $sm }
        }

        if ($isFreshSkCrash) {
            Write-Both ("  [СВЕЖИЙ ДАМП ПАДЕНИЯ SPECIAL K] Время: " + $LatestSkCrash.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")) Red
        } else {
            Write-Both ("  [АРХИВНЫЙ ДАМП ПРОШЛОЙ СЕССИИ] Время: " + $LatestSkCrash.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") + " (последний запуск прошёл без этого сбоя)") DarkGray
        }
        Write-Both ("    Исключение      : $exType") Yellow
        Write-Both ("    Сбойный модуль  : $faultMod ($ripAddr)") $(if ($isFreshSkCrash) { [ConsoleColor]::Red } else { [ConsoleColor]::Gray })
        if ($stackMods.Count -gt 0) {
            Write-Both ("    Замешаны в стеке: " + ($stackMods -join " -> ")) Yellow
        }
        Write-Both ("    Память в момент сбоя: Virtual=$vmLine | VRAM=$vramLine") Gray

        if ($isFreshSkCrash) {
            if ($faultMod -ieq "ReShade64.dll" -or ($stackMods -contains "ReShade64.dll")) {
                Add-Finding "CRITICAL" "Этап 5 (Пойман с поличным в crash.log: ReShade64.dll!)" `
                    "Дамп падения прямо указывает на сбой внутри ReShade64.dll ($ripAddr)!" `
                    "Конфликт оверлея ImGui внутри ReShade 5.8 при создании окна DirectX 11." `
                    "Нажмите [3] в меню ниже для отключения ReShade (#8) — вылет прекратится."
            } elseif ($faultMod -ieq "d3d11.dll" -or $faultMod -ieq "nvngx_dlss.dll" -or ($stackMods -contains "d3d11.dll") -or ($stackMods -contains "nvngx_dlss.dll")) {
                Add-Finding "CRITICAL" "Этап 3 (Пойман с поличным в crash.log: NVIDIA DLAA!)" `
                    "Дамп падения прямо указывает на модуль сглаживания NVIDIA DLAA ($faultMod)!" `
                    "Сбой перехвата шейдеров D3D11 или библиотеки nvngx_dlss.dll." `
                    "Нажмите [2] в меню ниже для отключения NVIDIA DLAA (#13)."
            } elseif ($stackMods -contains "RTSSHooks64.dll") {
                Add-Finding "CRITICAL" "Этап 5 (Пойман в стеке падения: RivaTuner / MSI Afterburner!)" `
                    "В стеке падения обнаружена библиотека RTSSHooks64.dll (RivaTuner Statistics Server)!" `
                    "Внешний оверлей MSI Afterburner / RivaTuner столкнулся с хуками Special K и сломал цепочку вывода кадра." `
                    "Закройте RivaTuner / MSI Afterburner (или добавьте NieRAutomata.exe в исключения RTSS с Application detection level = None)."
            }
        }
    } else {
        Write-Both "  [OK] В папке logs\crash свежих дампов Special K не обнаружено" Green
    }

    # Системный Журнал событий Windows (Application Error Event ID 1000) — ловит даже 0-секундные сбои ДО модов!
    $WinNierCrashes = @()
    try {
        $ev1000 = Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error'; Id=1000} -MaxEvents 60 -ErrorAction SilentlyContinue
        foreach ($ev in $ev1000) {
            if ($ev.Properties.Count -ge 8 -and ([string]$ev.Properties[0].Value -ieq "NieRAutomata.exe")) {
                $WinNierCrashes += [PSCustomObject]@{
                    Time       = $ev.TimeCreated
                    FaultMod   = [string]$ev.Properties[3].Value
                    ExCode     = ([string]$ev.Properties[6].Value).ToLowerInvariant()
                    Offset     = [string]$ev.Properties[7].Value
                    ModPath    = Mask-UserPath ([string]$ev.Properties[11].Value)
                }
                if ($WinNierCrashes.Count -ge 3) { break }
            }
        }
    } catch {}

    if ($WinNierCrashes.Count -gt 0) {
        $lastW = $WinNierCrashes[0]
        $isFreshWinCrash = (-not $LatestBootTime) -or ($lastW.Time -ge $LatestBootTime.AddMinutes(-5))
        $codeMeaning = switch -Regex ($lastW.ExCode) {
            'c0000135' { "STATUS_DLL_NOT_FOUND — в системе НЕ ХВАТАЕТ системной библиотеки .dll (свежего Visual C++ 2022 или Media Feature Pack)!" }
            'c000007b' { "STATUS_INVALID_IMAGE_FORMAT — повреждена 64-битная системная библиотека DirectX / Visual C++ в System32!" }
            'c0000005' { "ACCESS_VIOLATION — обращение к недоступной/зашифрованной памяти внутри модуля '$($lastW.FaultMod)'!" }
            'c0000409' { "STACK_BUFFER_OVERRUN — сбой защиты стека в модуле '$($lastW.FaultMod)' (конфликт хуков памяти)!" }
            'c0000374' { "HEAP_CORRUPTION — повреждение кучи памяти (конфликт инжекторов или нехватка памяти)!" }
            '80000003' { "BREAKPOINT — сбой аппаратной точки останова при расшифровке DRM!" }
            default    { "Системное исключение Windows ($($lastW.ExCode)) в модуле '$($lastW.FaultMod)'" }
        }
        Write-Both ("  [ЖУРНАЛ СОБЫТИЙ WINDOWS] Системный сбой NieRAutomata.exe: " + $lastW.Time.ToString("yyyy-MM-dd HH:mm:ss")) $(if ($isFreshWinCrash) { [ConsoleColor]::Red } else { [ConsoleColor]::DarkGray })
        Write-Both ("    Сбойный модуль : $($lastW.FaultMod) (смещение +0x$($lastW.Offset))") $(if ($isFreshWinCrash) { [ConsoleColor]::Red } else { [ConsoleColor]::Gray })
        Write-Both ("    Код ошибки     : 0x$($lastW.ExCode) -> $codeMeaning") Yellow

        if ($isFreshWinCrash) {
            if ($lastW.ExCode -match 'c0000135') {
                Add-Finding "CRITICAL" "Этап 1 (Журнал Windows 0xc0000135)" `
                    "Windows официально зафиксировала код 0xc0000135 (Не найдена системная DLL)!" `
                    "Процесс падает на уровне ядра Windows до запуска игры." `
                    "Установите свежий Microsoft Visual C++ 2015–2022 x64 (https://aka.ms/vs/17/release/vc_redist.x64.exe)."
            } elseif ($lastW.FaultMod -match 'amdxc64|aticfx64|amdxn64' -and $DlaaActive) {
                Add-Finding "CRITICAL" "Этап 3 (Журнал Windows: краш драйвера AMD из-за DLAA)" `
                    "Сбой произошёл прямо в видеодрайвере AMD ($($lastW.FaultMod))!" `
                    "Оставленный включённым мод NVIDIA DLAA (#13) уронил драйвер Radeon." `
                    "Нажмите [2] в меню ниже для отключения NVIDIA DLAA (#13)."
            } elseif ($lastW.FaultMod -ieq "ReShade64.dll") {
                Add-Finding "CRITICAL" "Этап 5 (Журнал Windows: сбой в ReShade64.dll)" `
                    "Журнал событий Windows подтвердил падение внутри модуля ReShade64.dll!" `
                    "Конфликт инициализации оверлея ReShade." `
                    "Нажмите [3] в меню ниже для отключения ReShade (#8)."
            } elseif ($lastW.FaultMod -ieq "d3d11.dll" -or $lastW.FaultMod -ieq "nvngx_dlss.dll") {
                Add-Finding "CRITICAL" "Этап 3 (Журнал Windows: сбой в NVIDIA DLAA)" `
                    "Журнал событий Windows подтвердил падение внутри модуля $($lastW.FaultMod)!" `
                    "Несовместимость или сбой хука NVIDIA DLAA (#13)." `
                    "Нажмите [2] в меню ниже для отключения NVIDIA DLAA (#13)."
            } elseif ($lastW.FaultMod -ieq "wax.dll") {
                Add-Finding "CRITICAL" "Этап 2 (Журнал Windows: сбой в wax.dll)" `
                    "Журнал событий Windows зафиксировал падение в wax.dll!" `
                    "Вероятнее всего — гонка расшифровки SteamStub (200 мс) или чужой билд EXE." `
                    "Нажмите [1] в меню ниже для увеличения таймаута SteamStub до 5000 мс."
            }
        }
    } else {
        Write-Both "  [OK] В системном Журнале событий Windows (Event ID 1000) записей об аварийном падении NieRAutomata.exe нет" Green
    }

    # -------------------------------------------------------------------------
    # СЛОЙ 7: ИТОГОВЫЙ ВЕРДИКТ НА ЧЕЛОВЕЧЕСКОМ ЯЗЫКЕ + ЗАПИСЬ ОТЧЁТА
    # -------------------------------------------------------------------------
    Write-Both ""
    Write-Both "============================================================================" Cyan
    Write-Both "                       ИТОГОВЫЙ ВЕРДИКТ ДИАГНОСТИКИ                         " Cyan
    Write-Both "============================================================================" Cyan

    if ($CriticalIssues.Count -eq 0 -and $Warnings.Count -eq 0) {
        Write-Both "  [ИДЕАЛЬНО] Ни одной ошибки, битого файла, конфликта или следа краша НЕ НАЙДЕНО!" Green
        Write-Both "  Все 24 архива .cpk, все SHA-256 суммы .dll, библиотеки VC++ 2022 и видеокарта в полном порядке." Gray
    } else {
        $idxNum = 1
        foreach ($ci in $CriticalIssues) {
            Write-Both ""
            Write-Both "  [КРИТИЧЕСКАЯ ПРИЧИНА #$idxNum] [$($ci.Stage)] $($ci.Title)" Red
            Write-Both "     Суть   : $($ci.Detail)" Gray
            Write-Both "     Решение: $($ci.Fix)" Green
            $idxNum++
        }
        foreach ($wi in $Warnings) {
            Write-Both ""
            Write-Both "  [ПРЕДУПРЕЖДЕНИЕ #$idxNum] [$($wi.Stage)] $($wi.Title)" Yellow
            Write-Both "     Суть   : $($wi.Detail)" Gray
            Write-Both "     Совет  : $($wi.Fix)" Cyan
            $idxNum++
        }
    }

    Write-Both ""
    Write-Both "----------------------------------------------------------------------------" DarkGray
    try {
        [System.IO.File]::WriteAllLines($ReportPath, $ReportLines, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ("  [i] Полный обезличенный отчёт сохранён в файл: " + $ReportPath) -ForegroundColor DarkCyan
    } catch {}

    return $GameDir
}

while ($true) {
    $FoundGameDir = Run-FullForensicScan
    if (-not $FoundGameDir -or $env:DIAG_NONINTERACTIVE) { break }

    Write-Host ""
    Write-Host "  БЫСТРОЕ АВТО-ЛЕЧЕНИЕ В 1 КЛИК (без удаления файлов, 100% обратимо в Toggle_Mods.bat):" -ForegroundColor Cyan
    Write-Host "   [1] Увеличить ожидание расшифровки SteamStub в WAX (200 мс -> 5000 мс) [рекомендуется всем!]" -ForegroundColor Green
    Write-Host "   [2] Выключить NVIDIA DLAA / DLSS 4 (#13) [обязательно для AMD Radeon / GTX и при сбое D3D11]" -ForegroundColor Yellow
    Write-Host "   [3] Выключить ReShade 5.8 (#8) [убирает вылеты оверлея ReShade при создании окна]" -ForegroundColor Yellow
    Write-Host "   [4] Оптимизировать кэш видеопамяти под карты 4–8 ГБ VRAM (снизить пик VRAM и тени до 2048)" -ForegroundColor Yellow
    Write-Host "   [5] ВКЛЮЧИТЬ «БЕЗОПАСНЫЙ СТАРТ» (применить пункты 1 + 2 + 3 сразу для гарантированного запуска)" -ForegroundColor Magenta
    Write-Host "   [6] Обновить Microsoft Visual C++ 2015–2022 x64 автоматически через системный winget" -ForegroundColor Cyan
    Write-Host "   [R] Перепроверить заново" -ForegroundColor Gray
    Write-Host "   [0] Выход" -ForegroundColor DarkGray
    Write-Host "----------------------------------------------------------------------------" -ForegroundColor DarkGray

    $ans = Read-Host "  Выберите действие (1-6, R или 0 для выхода)"
    if ($ans -eq "0" -or $ans -eq "") { break }
    if ($ans -match '^[RrКк]$') { continue }

    if ($ans -eq "1" -or $ans -eq "5") {
        $waxCfgP = Join-Path $FoundGameDir "wax\config.json"
        if (Test-Path $waxCfgP) {
            $wTxt = [System.IO.File]::ReadAllText($waxCfgP, [System.Text.Encoding]::UTF8)
            $wObj = $wTxt | ConvertFrom-Json
            $wObj.steam_stub_timeout_ms = 5000
            [System.IO.File]::WriteAllText($waxCfgP, ($wObj | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "  [OK] Таймаут расшифровки SteamStub в wax\config.json увеличен до 5000 мс!" -ForegroundColor Green
        }
    }

    if ($ans -eq "2" -or $ans -eq "5") {
        $did = Toggle-PackModOff -GameRoot $FoundGameDir -ModKey "DLAA_826" -RelFiles @("d3d11.dll","nvngx_dlss.dll","NIER_DLAA.ini")
        if ($did) {
            Write-Host "  [OK] Модуль NVIDIA DLAA (#13) аккуратно переведён в ВЫКЛ (_Disabled_Mods\DLAA_826)!" -ForegroundColor Green
        } else {
            Write-Host "  [i] NVIDIA DLAA (#13) уже был выключен." -ForegroundColor Gray
        }
    }

    if ($ans -eq "3" -or $ans -eq "5") {
        $did = Toggle-PackModOff -GameRoot $FoundGameDir -ModKey "ReShade_Engine" -RelFiles @("ReShade64.dll")
        if ($did) {
            Write-Host "  [OK] Модуль ReShade (#8) аккуратно переведён в ВЫКЛ (_Disabled_Mods\ReShade_Engine)!" -ForegroundColor Green
        } else {
            Write-Host "  [i] ReShade (#8) уже был выключен." -ForegroundColor Gray
        }
    }

    if ($ans -eq "4") {
        $dxgiIniP = Join-Path $FoundGameDir "dxgi.ini"
        if (Test-Path $dxgiIniP) {
            $dxTxt = [System.IO.File]::ReadAllText($dxgiIniP, [System.Text.Encoding]::UTF8)
            $dxTxt = $dxTxt -replace 'MaxSizeInMiB=\d+', 'MaxSizeInMiB=3072'
            [System.IO.File]::WriteAllText($dxgiIniP, $dxTxt, (New-Object System.Text.UTF8Encoding($false)))
        }
        $waxCfgP = Join-Path $FoundGameDir "wax\config.json"
        if (Test-Path $waxCfgP) {
            $wObj = ([System.IO.File]::ReadAllText($waxCfgP, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
            $wObj.max_injected_textures_vram_mb = 2048
            [System.IO.File]::WriteAllText($waxCfgP, ($wObj | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
        }
        $lodIniP = Join-Path $FoundGameDir "LodMod.ini"
        if (Test-Path $lodIniP) {
            $lTxt = [System.IO.File]::ReadAllText($lodIniP, [System.Text.Encoding]::UTF8)
            $lTxt = $lTxt -replace 'ShadowResolution\s*=\s*\d+', 'ShadowResolution = 2048'
            [System.IO.File]::WriteAllText($lodIniP, $lTxt, (New-Object System.Text.UTF8Encoding($false)))
        }
        Write-Host "  [OK] Лимиты видеопамяти адаптированы под карты 4–8 ГБ VRAM (кэш SK: 3072 МБ, WAX: 2048 МБ, тени: 2048)!" -ForegroundColor Green
    }

    if ($ans -eq "6") {
        Write-Host "  [*] Запускаю официальное обновление Microsoft Visual C++ 2015-2022 x64 через winget..." -ForegroundColor Cyan
        & winget install --id Microsoft.VCRedist.2015+.x64 -e --accept-package-agreements --accept-source-agreements
    }

    Start-Sleep -Seconds 2
}
