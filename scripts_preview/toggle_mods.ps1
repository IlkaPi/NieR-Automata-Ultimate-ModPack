[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Auto-detect NieR:Automata directory
$TargetDir = $null
if (Test-Path (Join-Path $ScriptDir "NieRAutomata.exe")) {
    $TargetDir = $ScriptDir
} else {
    foreach ($drv in @("E:", "C:", "D:", "F:", "G:")) {
        if (-not (Test-Path "$drv\")) { continue }
        foreach ($sub in @("SteamLibrary\steamapps\common\NieRAutomata", "Steam\steamapps\common\NieRAutomata", "Program Files (x86)\Steam\steamapps\common\NieRAutomata", "Games\NieRAutomata")) {
            $p = "$drv\$sub"
            if (Test-Path (Join-Path $p "NieRAutomata.exe")) {
                $TargetDir = $p
                break
            }
        }
        if ($TargetDir) { break }
    }
}

if (-not $TargetDir) {
    Write-Host "[ОШИБКА] Папка игры NieRAutomata не найдена!" -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода"
    exit 1
}

$ModeLabel = "Живое управление установленными модами в папке игры"
if (-not (Test-Path (Join-Path $TargetDir "dxgi.dll"))) {
    $PayloadCandidate = Join-Path $ScriptDir "Payload"
    if (Test-Path $PayloadCandidate) {
        $TargetDir = $PayloadCandidate
        $ModeLabel = "Преднастройка пака в папке Payload (до запуска Установить_Моды.bat)"
    }
}

$DisRoot = Join-Path $TargetDir "_Disabled_Mods"
$VanRoot = Join-Path $TargetDir "_Vanilla_Backup"
if (-not (Test-Path $DisRoot)) {
    New-Item -ItemType Directory -Path $DisRoot -Force | Out-Null
}

function Get-ModState {
    param (
        [string]$ModKey,
        [string]$ActiveDir,
        [string]$FirstFile
    )
    $FirstDis = Join-Path (Join-Path $DisRoot $ModKey) $FirstFile
    if (Test-Path $FirstDis) {
        return $false
    }
    return (Test-Path (Join-Path $ActiveDir $FirstFile))
}

function Update-A2And9SBaseJson {
    param ([bool]$EnableRemasterMeshes)
    $BaseJsonPaths = @(
        (Join-Path $TargetDir "wax\mods\!base\outfits\base.json"),
        (Join-Path $TargetDir "_Vanilla_Backup\2B_Wardrobe_5in1\wax\mods\!base\outfits\base.json"),
        (Join-Path $TargetDir "_Disabled_Mods\2B_Wardrobe_5in1\wax\mods\!base\outfits\base.json")
    )
    foreach ($bp in $BaseJsonPaths) {
        if (Test-Path $bp) {
            $txt = [System.IO.File]::ReadAllText($bp, [System.Text.Encoding]::UTF8)
            $obj = $txt | ConvertFrom-Json
            if ($obj.pl_9s_outfits -and $obj.pl_9s_outfits.Count -gt 0) {
                $o9 = $obj.pl_9s_outfits[0]
                if ($EnableRemasterMeshes) {
                    $o9.meshes = @("9SRem_Pants","9SRem_Body","9SRem_Leg","9SRem_Mesh_pl0200","Hair")
                    $o9.prologue_meshes = @("9SRem_Body","9SRem_Mesh_es0200","Hair")
                    $o9.holy_meshes = @("9SRem_Pants","9SRem_Body","9SRem_Leg","9SRem_Mesh_es0201","9SRem_Mesh_pl0200","Hair")
                    $o9.no_right_meshes = @("9SRem_Pants","9SRem_Body","9SRem_Leg","9SRem_Mesh_es0206","Hair")
                    $o9.tower_meshes = @("9SRem_Pants","9SRem_Body","9SRem_Leg","9SRem_Mesh_es0202","Hair")
                    $o9.self_destruct_hide_meshes = @("9SRem_Pants")
                    $o9.eyemask_meshes = @("9SRem_Eyemask")
                    $o9.non_eyemask_meshes = @("9SRem_Eyelash")
                    $o9.combat_meshes = @("9SRem_Serious")
                    $o9.non_combat_meshes = @("9SRem_Normal")
                    $o9.hairspray_meshes = @("9SRem_Body")
                } else {
                    $o9.meshes = @("Pants","Body","Leg","mesh_pl0200","Hair")
                    $o9.prologue_meshes = @("Body","mesh_es0200","Hair")
                    $o9.holy_meshes = @("Pants","Body","Leg","mesh_es0201","mesh_pl0200","Hair")
                    $o9.no_right_meshes = @("Pants","Body","Leg","mesh_es0206","Hair")
                    $o9.tower_meshes = @("Pants","Body","Leg","mesh_es0202","Hair")
                    $o9.self_destruct_hide_meshes = @("Pants")
                    $o9.eyemask_meshes = @("Eyemask")
                    $o9.non_eyemask_meshes = @("Eyelash")
                    $o9.combat_meshes = @("facial_serious","Eyelash_serious")
                    $o9.non_combat_meshes = @("facial_normal")
                    $o9.hairspray_meshes = @("Body")
                }
            }
            if ($obj.pl_a2_outfits -and $obj.pl_a2_outfits.Count -gt 0) {
                $oa = $obj.pl_a2_outfits[0]
                if ($EnableRemasterMeshes) {
                    $oa.meshes = @("A2Rem_Body","A2Rem_Cloth","A2Rem_Hair")
                    $oa.self_destruct_hide_meshes = @("A2Rem_Cloth")
                    $oa.combat_meshes = @("A2Rem_facial_serious")
                    $oa.non_combat_meshes = @("A2Rem_facial_normal")
                    $oa.wig_meshes = @("A2Rem_Hair")
                    $oa.hairspray_meshes = @("A2Rem_Hair")
                    if ($obj.pl_a2_outfits.Count -gt 1) {
                        $oa1 = $obj.pl_a2_outfits[1]
                        $oa1.meshes = @("DLC_Body","DLC_Cloth","A2Rem_Hair")
                        $oa1.combat_meshes = @("A2Rem_facial_serious")
                        $oa1.non_combat_meshes = @("A2Rem_facial_normal")
                        $oa1.wig_meshes = @("A2Rem_Hair")
                        $oa1.hairspray_meshes = @("A2Rem_Hair")
                    }
                } else {
                    $oa.meshes = @("Body","Cloth","Hair")
                    $oa.self_destruct_hide_meshes = @("Cloth")
                    $oa.combat_meshes = @("facial_serious")
                    $oa.non_combat_meshes = @("facial_normal")
                    $oa.wig_meshes = @("Hair")
                    $oa.hairspray_meshes = @("Hair")
                    if ($obj.pl_a2_outfits.Count -gt 1) {
                        $oa1 = $obj.pl_a2_outfits[1]
                        $oa1.meshes = @("DLC_Body","DLC_Cloth","Hair")
                        $oa1.combat_meshes = @("facial_serious")
                        $oa1.non_combat_meshes = @("facial_normal")
                        $oa1.wig_meshes = @("Hair")
                        $oa1.hairspray_meshes = @("Hair")
                    }
                }
            }
            $newJson = $obj | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($bp, $newJson, (New-Object System.Text.UTF8Encoding($false)))
        }
    }
}

function Toggle-ModFiles {
    param (
        [string]$ModKey,
        [string]$ActiveDir,
        [string[]]$Files
    )
    $ModDisDir = Join-Path $DisRoot $ModKey
    $ModVanDir = Join-Path $VanRoot $ModKey
    if (-not (Test-Path $ModDisDir)) {
        New-Item -ItemType Directory -Path $ModDisDir -Force | Out-Null
    }
    if (-not (Test-Path $ActiveDir)) {
        New-Item -ItemType Directory -Path $ActiveDir -Force | Out-Null
    }

    $isCurrentlyOn = Get-ModState -ModKey $ModKey -ActiveDir $ActiveDir -FirstFile $Files[0]
    $FirstDis = Join-Path $ModDisDir $Files[0]

    if ($isCurrentlyOn) {
        # Currently ON -> Turn OFF (move mod files to _Disabled_Mods, and restore _Vanilla_Backup if present)
        foreach ($f in $Files) {
            $src = Join-Path $ActiveDir $f
            $dst = Join-Path $ModDisDir $f
            $dstParent = Split-Path -Parent $dst
            if (-not (Test-Path $dstParent)) { New-Item -ItemType Directory -Path $dstParent -Force | Out-Null }
            if (Test-Path $src) {
                Move-Item -Path $src -Destination $dst -Force
            }
            if (Test-Path $ModVanDir) {
                $vanFile = Join-Path $ModVanDir $f
                if (Test-Path $vanFile) {
                    if ($ModKey -eq "Movies_1440p_60FPS") {
                        Move-Item -Path $vanFile -Destination $src -Force
                    } else {
                        Copy-Item -Path $vanFile -Destination $src -Force
                    }
                }
            }
        }
        if ($ModKey -eq "A2_Wardrobe_4in1") {
            Update-A2And9SBaseJson -EnableRemasterMeshes $false
        }
        return $false
    } elseif (Test-Path $FirstDis) {
        # Currently OFF -> Turn ON (backup vanilla if not yet backed up, then move from _Disabled_Mods to ActiveDir)
        foreach ($f in $Files) {
            $src = Join-Path $ModDisDir $f
            $dst = Join-Path $ActiveDir $f
            $dstParent = Split-Path -Parent $dst
            if (-not (Test-Path $dstParent)) { New-Item -ItemType Directory -Path $dstParent -Force | Out-Null }
            if ((Test-Path $dst) -and (-not (Get-Item $dst).PSIsContainer)) {
                $vanFile = Join-Path $ModVanDir $f
                $vanParent = Split-Path -Parent $vanFile
                if (-not (Test-Path $vanFile)) {
                    if (-not (Test-Path $vanParent)) { New-Item -ItemType Directory -Path $vanParent -Force | Out-Null }
                    if ($ModKey -eq "Movies_1440p_60FPS") {
                        Move-Item -Path $dst -Destination $vanFile -Force
                    } else {
                        Copy-Item -Path $dst -Destination $vanFile -Force
                    }
                }
            }
            if (Test-Path $src) {
                Move-Item -Path $src -Destination $dst -Force
            }
        }
        if ($ModKey -eq "A2_Wardrobe_4in1") {
            Update-A2And9SBaseJson -EnableRemasterMeshes $true
        }
        return $true
    } else {
        Write-Host "  [!] Файлы мода '$ModKey' ещё не установлены. Сначала запустите Установить_Моды.bat!" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return $null
    }
}

function Invoke-CleanVanillaReset {
    if (-not (Test-Path (Join-Path $TargetDir "NieRAutomata.exe"))) {
        Write-Host "  [!] Игра уже чиста (вы находитесь в режиме преднастройки Payload)." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return
    }
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $BackupBase = Join-Path $TargetDir "_Clean_Reset_Backups\reset_$stamp"
    New-Item -ItemType Directory -Path $BackupBase, (Join-Path $BackupBase "data"), (Join-Path $BackupBase "data\movie") -Force | Out-Null

    # 1. Move mod folders in data\
    $DataModDirs = @("ba","bg","core","effect","em","et","misctex","mods","novel","ph1","ph2","ph3","ph4","phf","pl","quest","st1","st2","st5","subtitle","txtmess","ui","um","wd1","wd3","wd5","wp")
    foreach ($d in $DataModDirs) {
        $p = Join-Path $TargetDir "data\$d"
        if (Test-Path $p) {
            Move-Item -Path $p -Destination (Join-Path $BackupBase "data\$d") -Force
        }
    }

    # 2. Move extra logo videos and restore vanilla story movies in data\movie\
    $VanMoviesDir = Join-Path $TargetDir "_Vanilla_Backup\Movies_1440p_60FPS"
    if (Test-Path (Join-Path $TargetDir "data\movie\LodMod.ini")) {
        Move-Item -Path (Join-Path $TargetDir "data\movie\LodMod.ini") -Destination (Join-Path $BackupBase "data\movie\LodMod.ini") -Force
        if (Test-Path $VanMoviesDir) {
            Get-ChildItem -Path $VanMoviesDir -Filter "*.usm" | ForEach-Object {
                $actMovie = Join-Path $TargetDir "data\movie\$($_.Name)"
                if (Test-Path $actMovie) {
                    Move-Item -Path $actMovie -Destination (Join-Path $BackupBase "data\movie\$($_.Name)") -Force
                }
                Move-Item -Path $_.FullName -Destination $actMovie -Force
            }
        }
    }
    foreach ($lf in @("logo_01.usm","logo_02.usm","logo_4k_00.usm","logo_4k_01.usm","logo_4k_02.usm")) {
        $lp = Join-Path $TargetDir "data\movie\$lf"
        if (Test-Path $lp) {
            Move-Item -Path $lp -Destination (Join-Path $BackupBase "data\movie\$lf") -Force
        }
    }

    # 3. Move root mod folders and files (keeping Toggle_Mods.bat and toggle_mods.ps1 in place)
    $RootModDirs = @("logs","mods","ReShade","SK_Res","wax","_Disabled_Mods","_Vanilla_Backup")
    foreach ($rd in $RootModDirs) {
        $rp = Join-Path $TargetDir $rd
        if (Test-Path $rp) {
            Move-Item -Path $rp -Destination (Join-Path $BackupBase $rd) -Force
        }
    }

    $RootModFiles = @(
        "AutomataHighFPS.dll","AutomataHighFPS.ini","AutomataHighFPS.log","xinput1_4.dll","LodMod.ini","LodMod.log","d3d11.dll","nvngx_dlss.dll","NIER_DLAA.ini","NIER_DLAA.log",
        "dinput8.dll","dxgi.dll","dxgi.ini","FAR.ini","modloader.dll","NAIOM-GUI.exe","NAIOM.ini",
        "NASA.dll","StellarParry.ini","StellarParry.wav","wax.log",
        "NieR Fantasy ReShade.ini","ReShade.ini","ReShade.log","ReShade64.dll","wax.dll"
    )
    foreach ($rf in $RootModFiles) {
        $rfp = Join-Path $TargetDir $rf
        if (Test-Path $rfp) {
            Move-Item -Path $rfp -Destination (Join-Path $BackupBase $rf) -Force
        }
    }

    Write-Host ""
    Write-Host "  [OK] Игра на 100% возвращена к чистой Steam-ванили!" -ForegroundColor Green
    Write-Host "       Все файлы модов аккуратно перенесены в архив: $BackupBase" -ForegroundColor Gray
    Write-Host "       Чтобы установить весь модпак заново с нуля, запустите Установить_Моды.bat!" -ForegroundColor Cyan
    Read-Host "  Нажмите Enter для выхода"
    exit 0
}

while ($true) {
    Clear-Host
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "   NieR:Automata — Менеджер Включения / Отката Модов (Toggle Mods)    " -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host " Рабочая папка: $TargetDir" -ForegroundColor Gray
    Write-Host " Режим работы : $ModeLabel" -ForegroundColor DarkCyan
    Write-Host " (Откат любого мода мгновенно возвращает оригинальные файлы из .cpk)" -ForegroundColor DarkGray
    Write-Host ""

    $FreeRoamFiles = @("ba\ba0300.dat", "bg\bg0103.dat", "bg\bg0200.dat", "bg\bg0700.dat", "bg\bg1700.dat", "bg\bg2002.dat", "bg\bg2012.dat", "bg\bg2013.dat", "bg\bg2014.dat", "bg\bg5354.dat", "bg\bg5354.dtt", "bg\bgff0f.dat", "wd1\g10218.dat", "wd1\g10318.dat", "wd1\g10319.dat", "wd1\g10415.dat", "wd1\g10416.dat", "wd1\g10419.dat", "wd1\g10514.dat", "wd1\g10515.dat", "wd1\g10517.dat", "wd1\g10519.dat", "wd1\g10520.dat", "wd1\g10614.dat", "wd1\g10615.dat", "wd1\g10617.dat", "wd1\g10619.dat", "wd1\g10713.dat", "wd1\g10714.dat", "wd1\g10717.dat", "wd1\g10718.dat", "wd1\g10719.dat", "wd1\g10812.dat", "wd1\g10813.dat", "wd1\g10814.dat", "wd1\g10815.dat", "wd1\g10817.dat", "wd1\g10818.dat", "wd1\g10820.dat", "wd1\g10821.dat", "wd1\g10822.dat", "wd1\g10912.dat", "wd1\g10914.dat", "wd1\g10915.dat", "wd1\g10916.dat", "wd1\g10917.dat", "wd1\g10918.dat", "wd1\g10919.dat", "wd1\g10920.dat", "wd1\g10921.dat", "wd1\g10922.dat", "wd1\g10923.dat", "wd1\g10924.dat", "wd1\g11013.dat", "wd1\g11014.dat", "wd1\g11015.dat", "wd1\g11016.dat", "wd1\g11017.dat", "wd1\g11018.dat", "wd1\g11021.dat", "wd1\g11113.dat", "wd1\g11114.dat", "wd1\g11115.dat", "wd1\g11117.dat", "wd1\g11118.dat", "wd1\g11119.dat", "wd1\g11120.dat", "wd1\g11121.dat", "wd1\g11212.dat", "wd1\g11213.dat", "wd1\g11214.dat", "wd1\g11215.dat", "wd1\g11218.dat", "wd1\g11219.dat", "wd1\g11220.dat", "wd1\g11221.dat", "wd1\g11312.dat", "wd1\g11313.dat", "wd1\g11314.dat", "wd1\g11315.dat", "wd1\g11316.dat", "wd1\g11317.dat", "wd1\g11318.dat", "wd1\g11319.dat", "wd1\g11320.dat", "wd1\g11413.dat", "wd1\g11414.dat", "wd1\g11415.dat", "wd1\g11416.dat", "wd1\g11417.dat", "wd1\g11418.dat", "wd1\g11419.dat", "wd1\g11420.dat", "wd1\g11421.dat", "wd1\g11512.dat", "wd1\g11513.dat", "wd1\g11514.dat", "wd1\g11515.dat", "wd1\g11516.dat", "wd1\g11517.dat", "wd1\g11519.dat", "wd1\g11520.dat", "wd1\g11521.dat", "wd1\g11612.dat", "wd1\g11613.dat", "wd1\g11614.dat", "wd1\g11615.dat", "wd1\g11617.dat", "wd1\g11619.dat", "wd1\g11620.dat", "wd1\g11711.dat", "wd1\g11712.dat", "wd1\g11713.dat", "wd1\g11714.dat", "wd1\g11716.dat", "wd1\g11717.dat", "wd1\g11812.dat", "wd1\g11813.dat", "wd1\g11816.dat", "wd1\g11911.dat", "wd1\g12010.dat", "wd3\g31118.dat", "wd3\g31119.dat", "wd3\g31120.dat", "wd3\g31121.dat", "wd3\g31218.dat", "wd3\g31219.dat", "wd3\g31220.dat", "wd3\g31221.dat", "wd3\g31317.dat", "wd3\g31318.dat", "wd3\g31319.dat", "wd3\g31320.dat", "wd3\g31416.dat", "wd3\g31417.dat", "wd3\g31418.dat", "wd3\g31419.dat", "wd3\g31518.dat", "wd5\g50100.dat")
    $Pods4KFiles = @("31C92494.dds", "5A3B35D8.dds", "653B619D.dds", "6AB595C1.dds", "6B47A79F.dds", "9DC875A9.dds", "ABCB9FA9.dds", "BF03E162.dds", "C1C1BBCA.dds", "CBF43CC4.dds", "CFD4392F.dds")

    $Mods = @(
        @{ Id = "1";  Key = "2B_Wardrobe_5in1";  Name = "Гардероб 2B 8-в-1 (2BS 4K #30 по умолчанию + Классика 2017 + Коллаб SB #776 + Парадный SB #749 + Реинкарнация #168 + 4K 2BBE + Кимоно #812 + 2P)"; Dir = $TargetDir; Files = @("data\pl\pl0000.dat", "data\pl\pl0000.dtt", "data\pl\pl000d.dat", "data\pl\pl000d.dtt", "wax\mods\!base\outfits\base.json", "wax\mods\2b_wardrobe\item_info\wardrobe.json", "wax\mods\2b_wardrobe\outfits\wardrobe.json", "wax\mods\2b_wardrobe\inventory\wardrobe.json", "wax\mods\2b_wardrobe\mcd\wardrobe.json") },
        @{ Id = "2";  Key = "A2_Wardrobe_4in1";  Name = "Гардероб A2 6-в-1 + 9S 5-в-1 + Аксессуары Switch DLC (A2/9S 4K #30 + Парадный SB #749 + Реинкарнация + Кимоно #812 + P2/9P)"; Dir = $TargetDir; Files = @("data\pl\pl0100.dat", "data\pl\pl0100.dtt", "data\pl\pl010d.dat", "data\pl\pl010d.dtt", "data\pl\pl010e.dat", "data\pl\pl010e.dtt", "data\pl\pl0200.dat", "data\pl\pl0200.dtt", "data\pl\pl020d.dat", "data\pl\pl020d.dtt", "data\et\ete00d.dat", "data\et\ete00d.dtt", "data\et\ete00e.dat", "data\et\ete00e.dtt", "data\et\ete0fa.dat", "data\et\ete0fa.dtt", "wax\mods\a2_9s_wardrobe\item_info\wardrobe.json", "wax\mods\a2_9s_wardrobe\outfits\wardrobe.json", "wax\mods\a2_9s_wardrobe\inventory\wardrobe.json", "wax\mods\a2_9s_wardrobe\mcd\wardrobe.json", "wax\mods\a2_9s_wardrobe\accessories\wardrobe.json", "wax\mods\a2_9s_wardrobe\behaviors\wardrobe.json") },
        @{ Id = "3";  Key = "Bunker_in_Color";   Name = "Цветной Бункер YoRHa (Bunker in Color 2.0)";                                                      Dir = (Join-Path $TargetDir "SK_Res\inject\textures\NieRAutomata.exe\Bunker in Color"); Files = @("0D8A1184.dds") },
        @{ Id = "4";  Key = "Grid_Removal";      Name = "Очистка экрана от сетки и мутной виньетки";                                                       Dir = (Join-Path $TargetDir "SK_Res\inject\textures\NieRAutomata.exe\Grid Overlay Removal"); Files = @("013F2718.dds", "713B879E.dds") },
        @{ Id = "5";  Key = "Denser_Grass";      Name = "Густая и пышная трава (Denser Grass Mod) + 3D Лунная Слеза (#558)";                               Dir = (Join-Path $TargetDir "data"); Files = @("bg\bgd000.dat", "bg\bgd000.dtt", "et\ete000.dat", "et\ete000.dtt") },
        @{ Id = "6";  Key = "Sand_Steps_HD";     Name = "Чёткие HD-следы на песке в Пустыне";                                                              Dir = (Join-Path $TargetDir "data\effect\model"); Files = @("0315.dat", "0315.dtt") },
        @{ Id = "7";  Key = "Amusement_Map";     Name = "Полная 3D-карта скрытых зон Парка Развлечений";                                                   Dir = (Join-Path $TargetDir "data\um"); Files = @("um8000.dat", "um8000.dtt") },
        @{ Id = "8";  Key = "ReShade_Engine";    Name = "Цветокоррекция ReShade (пресет NieR Fantasy, клавиша Home)";                                      Dir = $TargetDir; Files = @("ReShade64.dll") },
        @{ Id = "9";  Key = "Anim_Swap_582";     Name = "Отмена анимаций ударов + мгновенный Под (#582) + Живое моргание глаз (#771)";                     Dir = (Join-Path $TargetDir "data"); Files = @("pl\pl000f.dat", "wp\wpf000.dat", "wp\wpf200.dat", "wp\wpf400.dat", "wp\wpf600.dat") },
        @{ Id = "10"; Key = "No_Pod_CD_651";     Name = "Скиллы Пода без перезарядки (No Pod Cooldown #651)";                                              Dir = (Join-Path $TargetDir "data\core"); Files = @("core.dat") },
        @{ Id = "11"; Key = "Automata_HighFPS";  Name = "Разблокировка 120+ FPS с 60Гц физикой ткани (AutomataHighFPS v0.2.0, хоткей F11)";                Dir = $TargetDir; Files = @("AutomataHighFPS.dll", "AutomataHighFPS.ini") },
        @{ Id = "12"; Key = "Automata_LodMod";   Name = "Дальность прорисовки без LOD + 4K тени + HD AO (LodMod v0.77.4 + Fix v0.3 #675)";                 Dir = $TargetDir; Files = @("xinput1_4.dll", "LodMod.ini") },
        @{ Id = "13"; Key = "DLAA_826";          Name = "Сглаживание NVIDIA DLAA 1.1 / DLSS 4 Transformer (#826, хоткей F10)";                             Dir = $TargetDir; Files = @("d3d11.dll", "nvngx_dlss.dll", "NIER_DLAA.ini") },
        @{ Id = "14"; Key = "Pods_4K_30";        Name = "4K Ремастер Подов 042 и 153 (Pods 4K Remastered #30)";                                            Dir = (Join-Path $TargetDir "SK_Res\inject\textures\NieRAutomata.exe\Pods 4K Remastered"); Files = $Pods4KFiles },
        @{ Id = "15"; Key = "Free_Roam_322";     Name = "Свободное исследование мира без невидимых стен (Free Roam Collision Rework #322)";                Dir = (Join-Path $TargetDir "data"); Files = $FreeRoamFiles },
        @{ Id = "16"; Key = "Red_Chest_Markers"; Name = "Красные иконки несобранных сундуков на мини-карте и 3D-карте (с сохранением 4K RU UI)";           Dir = (Join-Path $TargetDir "data\ui"); Files = @("ui_core_us.dtt") },
        @{ Id = "17"; Key = "AI_4K_Textures_794";Name = "Глобальный пак 4K AI-текстур мира (4K AI Textures RePacked #794 — 2301 текстура, 30.8 ГБ)";       Dir = (Join-Path $TargetDir "SK_Res\inject\textures\NieRAutomata.exe"); Files = @("0_AI4K_RePacked") },
        @{ Id = "18"; Key = "Movies_1440p_60FPS";Name = "Апскейл сюжетных катсцен 2K (1440p) 60 FPS H.264 (#688 — 150 видеороликов, 23.1 ГБ)";             Dir = (Join-Path $TargetDir "data\movie"); Files = @("LodMod.ini", "ev0010.usm", "ev0030.usm", "ev0040.usm", "ev0050.usm", "ev0055.usm", "ev0060.usm", "ev0070.usm", "ev0080.usm", "ev0090.usm", "ev0092.usm", "ev0110.usm", "ev0120.usm", "ev0140.usm", "ev0160.usm", "ev0170.usm", "ev0190.usm", "ev0200.usm", "ev0210.usm", "ev0220.usm", "ev0225.usm", "ev0230.usm", "ev0240.usm", "ev0250.usm", "ev0260.usm", "ev0262.usm", "ev0280.usm", "ev0290.usm", "ev0300.usm", "ev0310.usm", "ev0320.usm", "ev0322.usm", "ev0323.usm", "ev0325.usm", "ev0330.usm", "ev0340.usm", "ev0350.usm", "ev0352.usm", "ev0360.usm", "ev0370.usm", "ev0380.usm", "ev0390.usm", "ev0400.usm", "ev0410.usm", "ev0420.usm", "ev0430.usm", "ev0440.usm", "ev0450.usm", "ev0460.usm", "ev0470.usm", "ev0475.usm", "ev0482.usm", "ev0483.usm", "ev0490.usm", "ev0500.usm", "ev0502.usm", "ev0510.usm", "ev0520.usm", "ev0525.usm", "ev0530.usm", "ev0540.usm", "ev0550.usm", "ev0552.usm", "ev0560.usm", "ev0570.usm", "ev0580.usm", "ev0590.usm", "ev0600.usm", "ev0610.usm", "ev0612.usm", "ev0620.usm", "ev0630.usm", "ev0642.usm", "ev0650.usm", "ev0655.usm", "ev0660.usm", "ev0670.usm", "ev0680.usm", "ev0682.usm", "ev0693.usm", "ev0694.usm", "ev0720.usm", "ev0722.usm", "ev0730.usm", "ev0740.usm", "ev0750.usm", "ev0760.usm", "ev0770.usm", "ev0780.usm", "ev0790.usm", "ev0792.usm", "ev0810.usm", "ev0820.usm", "ev0830.usm", "ev0835.usm", "ev0840.usm", "ev0850.usm", "ev0855.usm", "ev0860.usm", "ev0870.usm", "ev0875.usm", "ev0880.usm", "ev0900.usm", "ev0910.usm", "ev0920.usm", "ev0930.usm", "ev0935.usm", "ev0940.usm", "ev0950.usm", "ev0960.usm", "ev0970.usm", "ev0980.usm", "ev0990.usm", "ev1000.usm", "ev1010.usm", "ev1020.usm", "ev1030.usm", "ev1040.usm", "ev1050.usm", "ev1060.usm", "ev1070.usm", "ev1090.usm", "ev1100.usm", "ev1120.usm", "ev1125.usm", "ev1140.usm", "ev1150.usm", "ev1160.usm", "ev1180.usm", "ev1185.usm", "ev1190.usm", "ev1200.usm", "ev1210.usm", "ev1220.usm", "ev1230.usm", "ev1232.usm", "ev1233.usm", "ev1234.usm", "ev1235.usm", "ev1237.usm", "ev1240.usm", "ev1250.usm", "ev1270.usm", "ev1280.usm", "ev1290.usm", "ev1300.usm", "ev1310.usm", "ev1320.usm", "ev1400.usm", "ev1402.usm", "evb200.usm") }
    )

    foreach ($m in $Mods) {
        $isOn = Get-ModState -ModKey $m.Key -ActiveDir $m.Dir -FirstFile $m.Files[0]
        Write-Host (" [{0,2}] " -f $m.Id) -NoNewline -ForegroundColor Yellow
        if ($isOn) {
            Write-Host "[ ВКЛ  ] " -NoNewline -ForegroundColor Green
        } else {
            Write-Host "[ ВЫКЛ ] " -NoNewline -ForegroundColor DarkGray
        }
        Write-Host $m.Name
    }

    Write-Host ""
    Write-Host " [ R] Полный сброс игры до 100% чистой ванили (архивация всех модов для чистой переустановки)" -ForegroundColor Magenta
    Write-Host " [ 0] Выход" -ForegroundColor Gray
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
    $choice = Read-Host "Введите номер мода (1-18), R для полного сброса до чистой игры, или 0 для выхода"

    if ($choice -eq "0" -or $choice -eq "") {
        break
    }
    if ($choice -match "^[RrКк]$") {
        Invoke-CleanVanillaReset
        break
    }

    $sel = $Mods | Where-Object { $_.Id -eq $choice }
    if ($sel) {
        Toggle-ModFiles -ModKey $sel.Key -ActiveDir $sel.Dir -Files $sel.Files | Out-Null
    }
}
