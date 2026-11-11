[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   NieR:Automata — Ultimate Auto-Patcher & Mod Installer (2026) " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PayloadDir = Join-Path $ScriptDir "Payload"

if (-not (Test-Path $PayloadDir)) {
    Write-Host "[ОШИБКА] Папка Payload не найдена рядом со скриптом: $PayloadDir" -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода"
    exit 1
}

# 1. Auto-detect NieR:Automata installation folder
$CandidatePaths = @()

# Check if script was placed directly inside NieRAutomata folder
if (Test-Path (Join-Path $ScriptDir "NieRAutomata.exe")) {
    $CandidatePaths += $ScriptDir
}

# Check Steam registry and libraryfolders.vdf
try {
    $SteamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue).SteamPath
    if ($SteamPath) {
        $SteamPath = $SteamPath.Replace("/", "\")
        $VdfPath = Join-Path $SteamPath "steamapps\libraryfolders.vdf"
        if (Test-Path $VdfPath) {
            $VdfContent = Get-Content $VdfPath -Raw
            $Matches = [regex]::Matches($VdfContent, '"path"\s+"([^"]+)"')
            foreach ($m in $Matches) {
                $LibPath = $m.Groups[1].Value.Replace("\\", "\")
                $NierDir = Join-Path $LibPath "steamapps\common\NieRAutomata"
                if (Test-Path $NierDir) {
                    $CandidatePaths += $NierDir
                }
            }
        }
    }
} catch {}

# Fallback drive scan
foreach ($drv in @("C:", "D:", "E:", "F:", "G:")) {
    if (-not (Test-Path "$drv\")) { continue }
    foreach ($sub in @("SteamLibrary\steamapps\common\NieRAutomata", "Steam\steamapps\common\NieRAutomata", "Program Files (x86)\Steam\steamapps\common\NieRAutomata", "Games\NieRAutomata")) {
        $p = "$drv\$sub"
        if ((Test-Path $p) -and ($CandidatePaths -notcontains $p)) {
            $CandidatePaths += $p
        }
    }
}

$TargetDir = $null
# Prefer directory that already has NieRAutomata.exe
foreach ($p in $CandidatePaths) {
    if (Test-Path (Join-Path $p "NieRAutomata.exe")) {
        $TargetDir = $p
        break
    }
}
if (-not $TargetDir -and $CandidatePaths.Count -gt 0) {
    $TargetDir = $CandidatePaths[0]
}

if (-not $TargetDir) {
    Write-Host "Не удалось автоматически найти папку NieRAutomata." -ForegroundColor Yellow
    $TargetDir = Read-Host "Введите полный путь к папке NieRAutomata (где лежит NieRAutomata.exe)"
}

Write-Host "[1/4] Найдена папка игры: " -NoNewline
Write-Host $TargetDir -ForegroundColor Green

$ExePath = Join-Path $TargetDir "NieRAutomata.exe"
if (-not (Test-Path $ExePath)) {
    Write-Host ""
    Write-Host "[ВНИМАНИЕ] Файл NieRAutomata.exe в папке пока не найден (возможно, Steam ещё качает игру)." -ForegroundColor Yellow
    $ans = Read-Host "Всё равно установить моды в эту папку сейчас? (Y/N)"
    if ($ans -notmatch "^[YyДд]") {
        Write-Host "Установка отложена до окончания загрузки игры в Steam." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "      Файл NieRAutomata.exe найден (игра скачана)." -ForegroundColor Gray
    $BakExe702 = Join-Path $ScriptDir "Payload\_Vanilla_Backup\Exe_7020666\NieRAutomata.exe"
    if ((Test-Path $BakExe702) -and ((Get-Item $ExePath).Length -ne 17837952)) {
        Write-Host "      [ЗАЩИТА МОДОВ] Обнаружен обновлённый патчем EXE. Восстанавливаю совместимый с модами NieRAutomata.exe (build 7020666)..." -ForegroundColor Yellow
        Copy-Item -Path $BakExe702 -Destination $ExePath -Force
    }
}

# 2. Detect primary screen resolution
Add-Type -AssemblyName System.Windows.Forms
$Screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$ResW = $Screen.Width
$ResH = $Screen.Height
Write-Host "[2/4] Определено разрешение монитора: " -NoNewline
Write-Host "${ResW}x${ResH}" -ForegroundColor Green

# 4. Copy Payload files into TargetDir
Write-Host "[3/4] Установка пака модов (FAR + WAX + 2B Stellar Blade + 4K AI Textures #794 + Катсцены 2K 60FPS #688 + DLAA + LodMod + HighFPS + Русификатор)..." -ForegroundColor Cyan

# Backup vanilla story movies before installing 1440p 60FPS movies
$TargetMovieDir = Join-Path $TargetDir "data\movie"
$TargetVanMoviesBak = Join-Path $TargetDir "_Vanilla_Backup\Movies_1440p_60FPS"
$PayloadMovieDir = Join-Path $PayloadDir "data\movie"
if ((Test-Path $TargetMovieDir) -and (Test-Path $PayloadMovieDir)) {
    New-Item -ItemType Directory -Path $TargetVanMoviesBak -Force | Out-Null
    Get-ChildItem -Path $PayloadMovieDir -Filter "ev*.usm" | ForEach-Object {
        $origUsm = Join-Path $TargetMovieDir $_.Name
        $bakUsm = Join-Path $TargetVanMoviesBak $_.Name
        if ((Test-Path $origUsm) -and ((Get-Item $origUsm).Length -ne $_.Length)) {
            Move-Item -Path $origUsm -Destination $bakUsm -Force
        }
    }
}

$Ai4kPayload = Join-Path $PayloadDir "SK_Res\inject\textures\NieRAutomata.exe\0_AI4K_RePacked"
$TargetDriveLetter = ($TargetDir -replace ':.*$', '')
$TargetFs = (Get-Volume -DriveLetter $TargetDriveLetter -ErrorAction SilentlyContinue).FileSystemType
$UseHardLinks = (((Split-Path -Qualifier $PayloadDir).ToUpper() -eq (Split-Path -Qualifier $TargetDir).ToUpper()) -and ($TargetFs -eq "NTFS"))
$LinkedMovies = $false
$LinkedAi4k = $false

if ($UseHardLinks) {
    $ExcludeDirs = @()
    if (Test-Path $Ai4kPayload) { $ExcludeDirs += $Ai4kPayload; $LinkedAi4k = $true }
    if (Test-Path $PayloadMovieDir) { $ExcludeDirs += $PayloadMovieDir; $LinkedMovies = $true }
    $RoboArgs = @($PayloadDir, $TargetDir, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP", "/R:3", "/W:1")
    if ($ExcludeDirs.Count -gt 0) {
        $RoboArgs += "/XD"
        $RoboArgs += $ExcludeDirs
    }
    & robocopy @RoboArgs | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "Ошибка копирования базовых файлов сборки (код robocopy: $LASTEXITCODE)"
    }
} else {
    & robocopy $PayloadDir $TargetDir /E /NFL /NDL /NJH /NJS /NP /R:3 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "Ошибка копирования файлов сборки (код robocopy: $LASTEXITCODE)"
    }
}
if ($LinkedMovies) {
    if (-not (Test-Path $TargetMovieDir)) {
        New-Item -ItemType Directory -Path $TargetMovieDir -Force | Out-Null
    }
    Write-Host "      Мгновенная NTFS-линковка 155 видеороликов катсцен 2K (1440p) 60 FPS H.264 (23.1 ГБ, 0 ГБ доп. места)..." -ForegroundColor Gray
    Get-ChildItem -Path $PayloadMovieDir | ForEach-Object {
        $dstLink = Join-Path $TargetMovieDir $_.Name
        if (-not (Test-Path $dstLink)) {
            New-Item -ItemType HardLink -Path $dstLink -Value $_.FullName | Out-Null
        }
    }
}
if ($LinkedAi4k) {
    $Ai4kTarget = Join-Path $TargetDir "SK_Res\inject\textures\NieRAutomata.exe\0_AI4K_RePacked"
    if (-not (Test-Path $Ai4kTarget)) {
        New-Item -ItemType Directory -Path $Ai4kTarget -Force | Out-Null
    }
    $ExistingLinks = (Get-ChildItem -Path $Ai4kTarget -Filter "*.dds" -ErrorAction SilentlyContinue).Count
    if ($ExistingLinks -lt 2301) {
        Write-Host "      Мгновенная NTFS-линковка 2301 текстуры 4K AI Textures RePacked (30.8 ГБ, 0 ГБ доп. места)..." -ForegroundColor Gray
        Get-ChildItem -Path $Ai4kPayload -Filter "*.dds" | ForEach-Object {
            $dstLink = Join-Path $Ai4kTarget $_.Name
            if (-not (Test-Path $dstLink)) {
                New-Item -ItemType HardLink -Path $dstLink -Value $_.FullName | Out-Null
            }
        }
    }
}

# 5. Verify installation integrity
Write-Host "[4/4] Проверка целостности установленных компонентов..." -ForegroundColor Cyan

$Checks = @(
    @{ Name = "FAR / Special K (dxgi.dll)"; Path = (Join-Path $TargetDir "dxgi.dll"); MinSize = 10000000 },
    @{ Name = "WAX Limit Break v0.3.0 (wax.dll — Early OEP Hook)"; Path = (Join-Path $TargetDir "wax.dll"); MinSize = 1400000 },
    @{ Name = "WAX Config (wax\config.json — Heap Overflow + F9 Freeze)"; Path = (Join-Path $TargetDir "wax\config.json"); MinSize = 200 },
    @{ Name = "AutomataHighFPS v0.2.0 (AutomataHighFPS.dll — 120+ FPS + 60Hz физика ткани + быстрые загрузки)"; Path = (Join-Path $TargetDir "AutomataHighFPS.dll"); MinSize = 300000 },
    @{ Name = "Automata LodMod v0.77.4 + Fix v0.3 #675 (xinput1_4.dll + расширенный LodMod.ini)"; Path = (Join-Path $TargetDir "LodMod.ini"); MinSize = 50000 },
    @{ Name = "WAX Гардероб 2B 8-в-1 (wax\mods\2b_wardrobe\outfits\wardrobe.json)"; Path = (Join-Path $TargetDir "wax\mods\2b_wardrobe\outfits\wardrobe.json"); MinSize = 3500 },
    @{ Name = "WAX Гардероб A2 6-в-1 + 9S 5-в-1 + Аксессуары Switch DLC (wax\mods\a2_9s_wardrobe\outfits\wardrobe.json)"; Path = (Join-Path $TargetDir "wax\mods\a2_9s_wardrobe\outfits\wardrobe.json"); MinSize = 4000 },
    @{ Name = "NAIOM Mouse/KB Fix (dinput8.dll)"; Path = (Join-Path $TargetDir "dinput8.dll"); MinSize = 1000000 },
    @{ Name = "Гардероб 2B 8-в-1: 2BS 4K #30 + Классика 2017 + Stellar Blade #776 + Парадный #749 + Реинкарнация #168 + 2BBE + Кимоно + 2P (data\pl\pl000d.dtt)"; Path = (Join-Path $TargetDir "data\pl\pl000d.dtt"); MinSize = 400000000 },
    @{ Name = "Гардероб A2 6-в-1: A2 Vanilla 4K #30 + Парадный #749 + Реинкарнация #162 + Кимоно + P2 (data\pl\pl010d.dtt)"; Path = (Join-Path $TargetDir "data\pl\pl010d.dtt"); MinSize = 150000000 },
    @{ Name = "Гардероб 9S 5-в-1: Реинкарнация #209 + 4K Remaster #30 + Кимоно #812 + Белый 9P (data\pl\pl020d.dtt)"; Path = (Join-Path $TargetDir "data\pl\pl020d.dtt"); MinSize = 180000000 },
    @{ Name = "NVIDIA DLAA 1.1 / DLSS 4 Transformer #826 (d3d11.dll + nvngx_dlss.dll, хоткей F10)"; Path = (Join-Path $TargetDir "nvngx_dlss.dll"); MinSize = 30000000 },
    @{ Name = "Androids Remastered 4K #30 — 2B / A2 / 9S (SK_Res\inject\textures\NieRAutomata.exe\Androids Remastered)"; Path = (Join-Path $TargetDir "SK_Res\inject\textures\NieRAutomata.exe\Androids Remastered\07C200C2.dds"); MinSize = 20000000 },
    @{ Name = "Pods 4K Remastered #30 (SK_Res\inject\textures\NieRAutomata.exe\Pods 4K Remastered)"; Path = (Join-Path $TargetDir "SK_Res\inject\textures\NieRAutomata.exe\Pods 4K Remastered\31C92494.dds"); MinSize = 10000000 },
    @{ Name = "Free Roam Collision Rework #322 — Мир без невидимых стен (data\wd1\g10218.dat)"; Path = (Join-Path $TargetDir "data\wd1\g10218.dat"); MinSize = 100000 },
    @{ Name = "Красные иконки сундуков на карте + 4K UI (data\ui\ui_core_us.dtt)"; Path = (Join-Path $TargetDir "data\ui\ui_core_us.dtt"); MinSize = 30000000 },
    @{ Name = "Классический Ч/Б Бункер по умолчанию (опция Bunker in Color 2.0 в Toggle_Mods [3])"; Path = (Join-Path $TargetDir "_Disabled_Mods\Bunker_in_Color\0D8A1184.dds"); MinSize = 16000 },
    @{ Name = "Grid Overlay & Vignette Removal (013F2718.dds)"; Path = (Join-Path $TargetDir "SK_Res\inject\textures\NieRAutomata.exe\Grid Overlay Removal\013F2718.dds"); MinSize = 1000000 },
    @{ Name = "Main Menu HD Fix (412E6B29.dds)"; Path = (Join-Path $TargetDir "SK_Res\inject\textures\NieRAutomata.exe\Main Menu HD\412E6B29.dds"); MinSize = 5000000 },
    @{ Name = "Denser Grass Mod + Lunar Tear Fix #558 (data\bg\bgd000.dtt + data\et\ete000.dtt)"; Path = (Join-Path $TargetDir "data\et\ete000.dtt"); MinSize = 140000 },
    @{ Name = "Sand Steps Remade HD (data\effect\model\0315.dtt)"; Path = (Join-Path $TargetDir "data\effect\model\0315.dtt"); MinSize = 80000 },
    @{ Name = "Hidden Amusement Park 3D Map Fix (data\um\um8000.dtt)"; Path = (Join-Path $TargetDir "data\um\um8000.dtt"); MinSize = 9000000 },
    @{ Name = "2B Animation Swap #582 + Живое моргание глаз 2B/A2 #771 (data\pl\pl000f.dat)"; Path = (Join-Path $TargetDir "data\pl\pl000f.dat"); MinSize = 15000000 },
    @{ Name = "No Pod Program Cooldown #651 (data\core\core.dat)"; Path = (Join-Path $TargetDir "data\core\core.dat"); MinSize = 4000000 },
    @{ Name = "Апскейл сюжетных катсцен 2K (1440p) 60 FPS H.264 #688 (data\movie\LodMod.ini + 150 роликов)"; Path = (Join-Path $TargetDir "data\movie\LodMod.ini"); MinSize = 50 }
)

$AllOk = $true
foreach ($c in $Checks) {
    if ((Test-Path $c.Path) -and ((Get-Item $c.Path).Length -ge $c.MinSize)) {
        Write-Host "      [OK] $($c.Name)" -ForegroundColor Green
    } else {
        Write-Host "      [ОШИБКА] $($c.Name) отсутствует или повреждён!" -ForegroundColor Red
        $AllOk = $false
    }
}

$DdsCount = (Get-ChildItem -Path (Join-Path $TargetDir "SK_Res\inject\textures") -Filter "*.dds" -Recurse -ErrorAction SilentlyContinue).Count
if ($DdsCount -ge 2600) {
    Write-Host "      [OK] 4K AI Textures RePacked #794 + GPUnity HD + Pods 4K + 9S 4K ($DdsCount 4K/HD-текстур .dds)" -ForegroundColor Green
} else {
    Write-Host "      [ОШИБКА] Найдено только $DdsCount текстур из 2620!" -ForegroundColor Red
    $AllOk = $false
}

$SubCount = (Get-ChildItem -Path (Join-Path $TargetDir "data\subtitle") -Filter "*.dat" -Recurse -ErrorAction SilentlyContinue).Count
if ($SubCount -ge 200) {
    Write-Host "      [OK] Русификатор текста и интерфейса ($SubCount файлов субтитров + UI)" -ForegroundColor Green
} else {
    Write-Host "      [ОШИБКА] Русификатор неполный ($SubCount файлов)!" -ForegroundColor Red
    $AllOk = $false
}

$WaxCfgContent = Get-Content (Join-Path $TargetDir "wax\config.json") -Raw
if ($WaxCfgContent -match '"heap_overflow_allocator"\s*:\s*true' -and $WaxCfgContent -match '"patch_overrides"\s*:\s*true') {
    Write-Host "      [OK] WAX 2026: Безлимитный пул памяти + Гардероб 2B/A2/9S активны" -ForegroundColor Green
} else {
    Write-Host "      [ВНИМАНИЕ] Проверьте настройки wax\config.json!" -ForegroundColor Yellow
}

Write-Host ""
if ($AllOk) {
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host " УСПЕШНО! Все моды установлены и настроены!" -ForegroundColor Green
    Write-Host " Запускать игру нужно просто через кнопку 'ИГРАТЬ' в Steam." -ForegroundColor Green
    Write-Host " (Меню FAR: Ctrl+Shift+Backspace | Меню ReShade: клавиша Home)" -ForegroundColor Gray
    Write-Host "================================================================" -ForegroundColor Green
} else {
    Write-Host "Установка завершилась с предупреждениями. Проверьте лог выше." -ForegroundColor Yellow
}

Write-Host ""
Read-Host "Нажмите Enter для закрытия окна"
