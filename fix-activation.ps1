<#
  Windows 10 / 11 激活修复工具（图形界面）
  ------------------------------------------------------------------
  适用系统：Windows 10（含 LTSC）、Windows 11（含 LTSC）、Windows Server
  适用版本：家庭版 / 家庭中文版 / 家庭单语言版 / 专业版 / 专业教育版 /
            专业工作站版 / 教育版 / 企业版 / 企业版 LTSC / 企业多会话版 /
            IoT 企业版，以及各版本的 N 变体

  解决的问题：
    · 第三方 KMS 激活工具替换了 sppsvc.exe，导致数字签名失效
    · Software Protection (sppsvc) 服务无法启动
    · slmgr 卡死、查不到激活状态（"查看激活就卡住"）
    · 报 0xC004F069「在运行非核心版本的计算机上运行 slui.exe」
    · 安装的密钥与系统版本不匹配

  用法：双击同目录下的 run-fix.bat（会自动请求管理员权限）
#>

# ==================== 自动提权 ====================
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Add-Type -AssemblyName System.Windows.Forms
  try {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"')
    ) | Out-Null
  } catch {
    [System.Windows.Forms.MessageBox]::Show(
      "无法获取管理员权限，请右键 run-fix.bat 选择「以管理员身份运行」。`n`n" + $_.Exception.Message,
      '需要管理员权限') | Out-Null
  }
  exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:SppsvcPath = 'C:\Windows\System32\sppsvc.exe'
$script:LogBuffer  = New-Object System.Collections.ArrayList
$script:LogFile    = Join-Path ([Environment]::GetFolderPath('Desktop')) ('激活修复日志-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$script:BackupDir  = 'C:\Windows\Temp\ActivationFixBackup'

# ==================== 知识库：版本与 GVLK ====================
# Windows 10/11 客户端各版本对应的 KMS 客户端密钥（GVLK）
# 仅用于「诊断比对」——判断当前装的密钥是否属于这个版本
$script:EditionTable = @{
  'Core'                     = @{ Name = '家庭版';           GV = 'TX9XD-98N7V-6WMQ6-BX7FG-H8Q99' }
  'CoreN'                    = @{ Name = '家庭版 N';         GV = '3KHY7-WNT83-DGQKR-F7HPR-844BM' }
  'CoreCountrySpecific'      = @{ Name = '家庭中文版';       GV = 'PVMJN-6DFY6-9CCP6-7BKTT-D3WVR' }
  'CoreSingleLanguage'       = @{ Name = '家庭单语言版';     GV = '7HNRX-D7KGG-3K4RQ-4WPJ4-YTDFH' }
  'Professional'             = @{ Name = '专业版';           GV = 'W269N-WFGWX-YVC9B-4J6C9-T83GX' }
  'ProfessionalN'            = @{ Name = '专业版 N';         GV = 'MH37W-N47XK-V7XM9-C7227-GCQG9' }
  'ProfessionalEducation'    = @{ Name = '专业教育版';       GV = '6TP4R-GNPTD-KYYHQ-7B7DP-J447Y' }
  'ProfessionalEducationN'   = @{ Name = '专业教育版 N';     GV = 'YVWGF-BXNMC-HTQYQ-CPQ99-66QFC' }
  'ProfessionalWorkstation'  = @{ Name = '专业工作站版';     GV = 'NRG8B-VKK3Q-CXVCJ-9G2XF-6Q84J' }
  'ProfessionalWorkstationN' = @{ Name = '专业工作站版 N';   GV = '9FNHH-K3HBT-3W4TD-6383H-6XYWF' }
  'Education'                = @{ Name = '教育版';           GV = 'NW6C2-QMPVW-D7KKK-3GKT6-VCFB2' }
  'EducationN'               = @{ Name = '教育版 N';         GV = '2WH4N-8QGBV-H22JP-CT43Q-MDWWJ' }
  'Enterprise'               = @{ Name = '企业版';           GV = 'NPPR9-FWDCX-D2C8J-H872K-2YT43' }
  'EnterpriseN'              = @{ Name = '企业版 N';         GV = 'DPH2V-TTNVB-4X9Q3-TJR4H-KHJW4' }
  'EnterpriseS'              = @{ Name = '企业版 LTSC';      GV = 'M7XTQ-FN8P6-TTKYV-9D4CC-J462D' }
  'EnterpriseSN'             = @{ Name = '企业版 LTSC N';    GV = '92NFX-8DJQP-P6BBQ-THF9C-7CG2H' }
  'ServerRdsh'               = @{ Name = '企业多会话版';     GV = 'NJCF7-PW8QT-3324D-688JX-2YV66' }
  'IoTEnterprise'            = @{ Name = 'IoT 企业版';       GV = 'XQQYW-NFFMW-XJPBH-K8732-CKFFD' }
}

# ==================== 窗体 ====================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows 10 / 11 激活修复工具'
$form.ClientSize = New-Object System.Drawing.Size(780, 610)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(720, 540)
$form.BackColor = [System.Drawing.Color]::FromArgb(255, 255, 255)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Location = New-Object System.Drawing.Point(0, 0)
$panelTop.Size = New-Object System.Drawing.Size(780, 74)
$panelTop.Anchor = 'Top,Left,Right'
$panelTop.BackColor = [System.Drawing.Color]::FromArgb(30, 58, 104)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'Windows 10 / 11 激活修复工具'
$lblTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.AutoSize = $true
$lblTitle.BackColor = [System.Drawing.Color]::Transparent
$lblTitle.Location = New-Object System.Drawing.Point(20, 10)
$panelTop.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = '修复被 KMS 工具篡改的 sppsvc.exe · 适配全部版本 · 恢复软件保护服务 · 重新激活'
$lblSub.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(185, 205, 235)
$lblSub.AutoSize = $true
$lblSub.BackColor = [System.Drawing.Color]::Transparent
$lblSub.Location = New-Object System.Drawing.Point(22, 45)
$panelTop.Controls.Add($lblSub)
$form.Controls.Add($panelTop)

$panelBottom = New-Object System.Windows.Forms.Panel
$panelBottom.Location = New-Object System.Drawing.Point(0, 480)
$panelBottom.Size = New-Object System.Drawing.Size(780, 130)
$panelBottom.Anchor = 'Bottom,Left,Right'
$panelBottom.BackColor = [System.Drawing.Color]::FromArgb(247, 248, 250)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = '就绪'
$lblStatus.AutoSize = $false
$lblStatus.Location = New-Object System.Drawing.Point(22, 6)
$lblStatus.Size = New-Object System.Drawing.Size(736, 20)
$lblStatus.Anchor = 'Top,Left,Right'
$lblStatus.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(90, 96, 108)
$panelBottom.Controls.Add($lblStatus)

function New-Btn([string]$text, [int]$x, [int]$y, [int]$w, [bool]$primary) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $text
  $b.Location = New-Object System.Drawing.Point($x, $y)
  $b.Size = New-Object System.Drawing.Size($w, 38)
  $b.FlatStyle = 'Flat'
  $b.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
  if ($primary) {
    $b.BackColor = [System.Drawing.Color]::FromArgb(30, 110, 200)
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatAppearance.BorderSize = 0
  } else {
    $b.BackColor = [System.Drawing.Color]::FromArgb(236, 239, 244)
    $b.ForeColor = [System.Drawing.Color]::FromArgb(45, 50, 60)
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(205, 210, 220)
  }
  return $b
}

$tip = New-Object System.Windows.Forms.ToolTip
$tip.AutoPopDelay = 12000
$tip.InitialDelay = 400
$tip.ReshowDelay = 100

$btnDiag    = New-Btn '① 诊断'       20  32 86  $false
$btnRepair  = New-Btn '② 一键修复'   114 32 104 $true
$btnDeep    = New-Btn '③ 深度修复'   226 32 104 $false
$btnNet     = New-Btn '④ 联网修复'   338 32 104 $false
$btnReinst  = New-Btn '⑤ 保资料重装'  20  78 130 $false
$btnSave    = New-Btn '保存日志'     158 78 96  $false
$btnOpen    = New-Btn '备份目录'     262 78 96  $false

$tip.SetToolTip($btnDiag,   '只读检查：系统版本、服务状态、文件签名、组件库、激活详情')
$tip.SetToolTip($btnRepair, '用本地组件库的原版 sppsvc.exe 替换被篡改文件，然后重新激活')
$tip.SetToolTip($btnDeep,   '文件已修好但仍未激活时使用：重置授权状态并重新激活')
$tip.SetToolTip($btnNet,    '组件库里没有可用原版时使用：从 Windows Update 按需下载组件修复（需联网，较慢）')
$tip.SetToolTip($btnReinst, '用微软官方 ISO 做就地升级修复：保留个人文件、设置和已装应用，不需 U 盘')
$tip.SetToolTip($btnSave,   '把本次输出保存为桌面上的 txt')
$tip.SetToolTip($btnOpen,   '打开备份目录，查看被替换前的原文件')

$panelBottom.Controls.AddRange(@($btnDiag, $btnRepair, $btnDeep, $btnNet, $btnReinst, $btnSave, $btnOpen))
$form.Controls.Add($panelBottom)

$rtb = New-Object System.Windows.Forms.RichTextBox
$rtb.Location = New-Object System.Drawing.Point(18, 86)
$rtb.Size = New-Object System.Drawing.Size(744, 382)
$rtb.Anchor = 'Top,Bottom,Left,Right'
$rtb.ReadOnly = $true
$rtb.BackColor = [System.Drawing.Color]::FromArgb(252, 253, 255)
$rtb.BorderStyle = 'FixedSingle'
$rtb.Font = New-Object System.Drawing.Font('Consolas', 9.5)
$rtb.WordWrap = $true
$rtb.HideSelection = $false
$rtb.DetectUrls = $false
$form.Controls.Add($rtb)

# ==================== 输出 ====================
function Log([string]$msg, [string]$color = 'Default') {
  $c = switch ($color) {
    'Red'    { [System.Drawing.Color]::FromArgb(205, 45, 45) }
    'Green'  { [System.Drawing.Color]::FromArgb(20, 145, 75) }
    'Orange' { [System.Drawing.Color]::FromArgb(200, 120, 20) }
    'Blue'   { [System.Drawing.Color]::FromArgb(30, 100, 190) }
    'Gray'   { [System.Drawing.Color]::FromArgb(115, 120, 130) }
    default  { [System.Drawing.Color]::FromArgb(28, 30, 36) }
  }
  [void]$script:LogBuffer.Add($msg)
  $rtb.SelectionStart = $rtb.TextLength
  $rtb.SelectionLength = 0
  $rtb.SelectionColor = $c
  $rtb.AppendText($msg + "`r`n")
  $rtb.ScrollToCaret()
  [void][System.Windows.Forms.Application]::DoEvents()
}

function LogHead([string]$t) {
  Log ''
  Log ('── ' + $t + ' ' + ('─' * [Math]::Max(4, 56 - $t.Length))) 'Blue'
}

function SetStatus([string]$s) {
  $lblStatus.Text = $s
  [void][System.Windows.Forms.Application]::DoEvents()
}

function Pump([int]$ms) {
  $end = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $end) {
    Start-Sleep -Milliseconds 100
    [void][System.Windows.Forms.Application]::DoEvents()
  }
}

# ==================== 基础工具 ====================
function Get-SigStatus([string]$path) {
  try { return (Get-AuthenticodeSignature $path).Status.ToString() } catch { return 'Error' }
}

function Get-SigSigner([string]$path) {
  try {
    $s = Get-AuthenticodeSignature $path
    if ($s.SignerCertificate) { return $s.SignerCertificate.Subject }
    return '(无)'
  } catch { return '(读取失败)' }
}

function Get-SysInfo {
  $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
  $build = 0
  [void][int]::TryParse([string]$cv.CurrentBuild, [ref]$build)
  $installType = [string]$cv.InstallationType

  $osName = 'Windows'
  if ($installType -eq 'Server') {
    $osName = 'Windows Server'
  } elseif ($build -ge 22000) {
    $osName = 'Windows 11'
  } elseif ($build -ge 10240) {
    $osName = 'Windows 10'
  }

  $ed = [string]$cv.EditionID
  $edName = $ed
  $gvlk = $null
  if ($script:EditionTable.ContainsKey($ed)) {
    $edName = $script:EditionTable[$ed].Name
    $gvlk   = $script:EditionTable[$ed].GV
  }

  $ubrNum = 0
  [void][int]::TryParse([string]$cv.UBR, [ref]$ubrNum)

  return [pscustomobject]@{
    ProductName = [string]$cv.ProductName
    OSName      = $osName
    Build       = $build
    UBR         = [string]$cv.UBR
    UbrNum      = $ubrNum
    DisplayVer  = [string]$cv.DisplayVersion
    EditionID   = $ed
    CompEdition = [string]$cv.CompositionEditionID
    EditionName = $edName
    GVLK        = $gvlk
    InstallType = $installType
    Registered  = [string]$cv.RegisteredOwner
  }
}

function Find-GoodSppsvc([int]$osBuild, [int]$osUbr) {
  $all = New-Object System.Collections.ArrayList

  # 收录一个候选，无论签名是否有效都记录下来（便于诊断）
  function _add {
    param([string]$path)
    try {
      $fi = Get-Item $path -ErrorAction Stop
      $status = 'Unknown'
      $signer = ''
      $sig = Get-AuthenticodeSignature $path -ErrorAction SilentlyContinue
      if ($sig) {
        $status = $sig.Status.ToString()
        if ($sig.SignerCertificate) { $signer = $sig.SignerCertificate.Subject }
      }
      [void]$all.Add([pscustomobject]@{
        Path    = $path
        Version = ($fi.VersionInfo.FileVersion -split ' ')[0]
        Size    = $fi.Length
        Sig     = $status
        Signer  = $signer
      })
    } catch { }
  }

  # 快速路径：组件文件夹名含 security-spp
  $dirs = Get-ChildItem 'C:\Windows\WinSxS' -Directory -Filter '*security-spp*' -ErrorAction SilentlyContinue
  foreach ($d in $dirs) {
    $f = Join-Path $d.FullName 'sppsvc.exe'
    if (Test-Path $f) { _add $f }
  }

  if ($all.Count -eq 0) {
    Log '  快速查找未命中，正在深度扫描组件库（较慢，请稍候）...' 'Gray'
    Get-ChildItem 'C:\Windows\WinSxS' -Filter 'sppsvc.exe' -Recurse -Depth 2 -ErrorAction SilentlyContinue |
      ForEach-Object { _add $_.FullName }
  }

  $script:AllCandidates = $all

  # 只有签名 Valid 才能用于替换
  $valid = @($all | Where-Object { $_.Sig -eq 'Valid' })
  if ($valid.Count -eq 0) { return $null }

  # 版本匹配优先级：
  #   0 = 修订号与本机 UBR 完全一致（最理想，本来就是同一份）
  #   1 = 同一 build 家族
  #   2 = 更低 build
  #   3 = 更高 build（不推荐，可能不兼容）
  foreach ($c in $valid) {
    $v = $null
    try { $v = [version]$c.Version } catch { $v = [version]'0.0.0.0' }
    $c | Add-Member -NotePropertyName V -NotePropertyValue $v -Force
    if ($osUbr -gt 0 -and $v.Revision -eq $osUbr) { $rank = 0 }
    elseif ($v.Build -eq $osBuild)               { $rank = 1 }
    elseif ($v.Build -lt $osBuild)               { $rank = 2 }
    else                                         { $rank = 3 }
    $c | Add-Member -NotePropertyName Rank -NotePropertyValue $rank -Force
  }

  return ($valid | Sort-Object -Property @{Expression='Rank';Ascending=$true}, @{Expression={$_.V};Descending=$true} | Select-Object -First 1)
}

function Run-Slmgr([string]$arg, [int]$timeoutMs) {
  $tmp = [IO.Path]::GetTempFileName()
  try {
    $p = Start-Process -FilePath "$env:windir\system32\cscript.exe" `
          -ArgumentList '//nologo', "$env:windir\system32\slmgr.vbs", $arg `
          -RedirectStandardOutput $tmp -NoNewWindow -PassThru
    $end = (Get-Date).AddMilliseconds($timeoutMs)
    while (-not $p.HasExited -and (Get-Date) -lt $end) {
      Start-Sleep -Milliseconds 150
      [void][System.Windows.Forms.Application]::DoEvents()
    }
    if (-not $p.HasExited) { try { $p.Kill() } catch { } ; return '__TIMEOUT__' }
    return (Get-Content $tmp -Raw -ErrorAction SilentlyContinue)
  } catch {
    return ('__ERROR__ ' + $_.Exception.Message)
  } finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Parse-Dlv([string]$text) {
  $r = @{ Name = $null; Desc = $null; Channel = $null; Partial = $null; Status = $null; Kms = $null }
  if (-not $text) { return $r }
  foreach ($ln in ($text -split "`r?`n")) {
    if ($ln -match '^名称:\s*(.+)$')        { $r.Name    = $Matches[1].Trim() }
    if ($ln -match '^描述:\s*(.+)$')        { $r.Desc    = $Matches[1].Trim() }
    if ($ln -match '产品密钥通道:\s*(.+)$') { $r.Channel = $Matches[1].Trim() }
    if ($ln -match '部分产品密钥:\s*(\S+)') { $r.Partial = $Matches[1].Trim() }
    if ($ln -match '许可证状态:\s*(.+)$')   { $r.Status  = $Matches[1].Trim() }
    if ($ln -match '密钥管理服务:\s*(.+)$') { $r.Kms     = $Matches[1].Trim() }
  }
  return $r
}

function Ensure-BackupDir {
  if (-not (Test-Path $script:BackupDir)) { New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null }
}

# ==================== 诊断 ====================
function Do-Diagnose {
  LogHead '系统与环境'
  $s = Get-SysInfo
  Log ('  系统       : ' + $s.ProductName + '   [' + $s.OSName + ']')
  Log ('  版本       : ' + $s.DisplayVer + '   Build ' + $s.Build + '.' + $s.UBR + '   ' + $s.InstallType)
  Log ('  EditionID  : ' + $s.EditionID + '   (' + $s.EditionName + ')')
  if ($s.CompEdition -and $s.CompEdition -ne $s.EditionID) {
    Log ('  组成版本ID : ' + $s.CompEdition + '   [与 EditionID 不一致，版本可能被改过]') 'Orange'
  } else {
    Log ('  组成版本ID : ' + $s.CompEdition + '   [一致]') 'Green'
  }
  if ($s.GVLK) {
    Log ('  该版本GVLK : ' + $s.GVLK + '   (末五位 ' + $s.GVLK.Substring($s.GVLK.Length - 5) + ')') 'Gray'
  } else {
    Log '  该 EditionID 不在对照表中（可能是 Server / 非标准版本）' 'Orange'
  }
  Log ('  计算机名   : ' + $env:COMPUTERNAME + '    用户: ' + $env:USERNAME)

  LogHead '软件保护服务 (sppsvc)'
  $svc = Get-Service sppsvc -ErrorAction SilentlyContinue
  if ($svc) {
    $c1 = if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' }
    Log ('  状态       : ' + $svc.Status) $c1
    Log ('  启动类型   : ' + $svc.StartType)
    Log ('  依赖服务   : ' + (($svc.ServicesDependedOn | ForEach-Object { $_.Name }) -join ', '))
    if ($svc.Status -ne 'Running') {
      Log '  尝试启动服务以确认是否真的损坏...' 'Gray'
      Start-Service sppsvc -ErrorAction SilentlyContinue
      Pump 3500
      $svc = Get-Service sppsvc
      if ($svc.Status -eq 'Running') {
        Log '  启动成功 —— 服务本身正常（Stopped 只是按需休眠，不是故障）' 'Green'
      } else {
        Log '  启动失败 —— 这就是真正的故障点' 'Red'
      }
    }
  } else {
    Log '  服务不存在！' 'Red'
  }

  LogHead '核心文件完整性'
  if (Test-Path $script:SppsvcPath) {
    $fi  = Get-Item $script:SppsvcPath
    $sig = Get-SigStatus $script:SppsvcPath
    Log ('  文件       : ' + $script:SppsvcPath)
    Log ('  大小       : ' + $fi.Length + ' 字节')
    Log ('  版本       : ' + $fi.VersionInfo.FileVersion)
    if ($sig -eq 'Valid') { Log '  数字签名   : Valid   [正常]' 'Green' }
    else { Log ('  数字签名   : ' + $sig + '   [已被篡改]') 'Red' }
    Log ('  签发者     : ' + (Get-SigSigner $script:SppsvcPath)) 'Gray'

    $fv = ($fi.VersionInfo.FileVersion -split ' ')[0]
    try {
      $vv = [version]$fv
      # Windows 组件按「修订号 UBR」推进，build 号在分支内是固定的，
      # 因此用修订号比对才有意义（例如 26100.9711 对应系统 UBR 9711）
      if ($s.UbrNum -gt 0 -and $vv.Revision -eq $s.UbrNum) {
        Log ('  版本匹配   : 修订号 ' + $vv.Revision + ' 与系统 UBR ' + $s.UbrNum + ' 一致') 'Green'
      } elseif ($s.UbrNum -gt 0) {
        Log ('  版本匹配   : 文件修订 ' + $vv.Revision + '，系统 UBR ' + $s.UbrNum + '（可能落后于系统更新）') 'Gray'
      }
    } catch { }
  } else {
    Log '  sppsvc.exe 不存在！' 'Red'
  }

  LogHead '组件库中的原版备份 (WinSxS)'
  $good = Find-GoodSppsvc $s.Build $s.UbrNum
  $total = 0
  if ($script:AllCandidates) { $total = @($script:AllCandidates).Count }

  if ($total -eq 0) {
    Log '  组件库中没有找到任何 sppsvc.exe' 'Red'
    Log '  说明组件库被严重破坏，需要用「④ 联网修复」从 Windows Update 取回。' 'Orange'
  } else {
    Log ('  共扫描到   : ' + $total + ' 份 sppsvc.exe') 'Gray'
    foreach ($c in @($script:AllCandidates | Sort-Object { $_.Version } -Descending | Select-Object -First 8)) {
      $mark = if ($c.Sig -eq 'Valid') { '✓' } else { '✗' }
      $col  = if ($c.Sig -eq 'Valid') { 'Green' } else { 'Orange' }
      Log ('    ' + $mark + ' ' + $c.Sig.PadRight(13) + $c.Version.PadRight(24) + $c.Size.ToString().PadLeft(9) + ' 字节') $col
    }
    if ($good) {
      Log ('  推荐使用   : ' + $good.Version) 'Green'
      Log ('               ' + $good.Path) 'Gray'
      Log '  （选择规则：签名必须 Valid；修订号与系统 UBR 一致者优先）' 'Gray'
    } else {
      Log ''
      Log '  [!] 以上副本签名全部无效 —— 说明组件库本身也被替换过。' 'Red'
      Log '      本地已没有可信来源，请点击「④ 联网修复」，' 'Orange'
      Log '      让 DISM 从 Windows Update 取回正版组件后再修复。' 'Orange'
    }
  }

  LogHead '软件保护服务的启动失败记录'
  $evts = @()
  try {
    $evts = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; Id=7000} -MaxEvents 40 -ErrorAction Stop |
              Where-Object { $_.Message -match 'Software Protection|sppsvc|软件保护' } |
              Select-Object -First 3
  } catch { }
  if ($evts.Count -gt 0) {
    foreach ($ev in $evts) {
      $first = ($ev.Message -split "`n")[0].Trim()
      $second = ''
      if (($ev.Message -split "`n").Count -gt 1) { $second = ($ev.Message -split "`n")[1].Trim() }
      Log ('  ' + $ev.TimeCreated.ToString('MM-dd HH:mm:ss') + '  ' + $first) 'Orange'
      if ($second) { Log ('      ' + $second) 'Orange' }
    }
  } else {
    Log '  未发现软件保护服务的启动失败记录' 'Green'
  }

  if (-not $svc -or $svc.Status -ne 'Running') {
    Log ''
    Log '  服务未运行，无法查询激活状态 —— 这就是「查看激活就卡死」的直接原因。' 'Orange'
    Log '  请点击「② 一键修复」。' 'Orange'
    return
  }

  LogHead '激活详情 (slmgr /dlv)'
  $dlvText = Run-Slmgr '/dlv' 35000
  if ($dlvText -eq '__TIMEOUT__') {
    Log '  查询超时 —— 服务在运行但响应异常，建议直接执行修复' 'Red'
    return
  }
  foreach ($ln in ($dlvText -split "`r?`n")) { if ($ln.Trim() -ne '') { Log ('  ' + $ln.TrimEnd()) } }

  LogHead '密钥与版本匹配分析'
  $d = Parse-Dlv $dlvText
  Log ('  许可证名称 : ' + $d.Name)
  Log ('  密钥通道   : ' + $d.Channel)
  Log ('  部分密钥   : ' + $d.Partial)
  Log ('  许可证状态 : ' + $d.Status)
  if (-not [string]::IsNullOrWhiteSpace($d.Kms)) { Log ('  KMS 服务器 : ' + $d.Kms) }

  $isVolume = ($d.Channel -match 'GVLK|Volume|KMS|MAK')
  if ($isVolume -and $s.GVLK) {
    $want = $s.GVLK.Substring($s.GVLK.Length - 5)
    if ($d.Partial -and $d.Partial -ne $want) {
      Log ''
      Log ('  [不匹配] 当前密钥末五位 [' + $d.Partial + '] 与「' + $s.EditionName + '」应有的 [' + $want + '] 不一致。') 'Red'
      Log '  这正是 0xC004F069「在运行非核心版本的计算机上运行 slui.exe」的根因：' 'Red'
      Log '  安装的 KMS 密钥属于另一个 Windows 版本，与当前系统版本不匹配。' 'Red'
      Log '  修复办法：装回本版本对应的密钥，或还原原厂密钥后联网自动激活。' 'Orange'
    } elseif ($d.Partial) {
      Log ''
      Log ('  [匹配] 密钥与版本一致（' + $d.Partial + '），问题不在密钥。') 'Green'
    }
  } elseif (-not $isVolume -and $d.Channel) {
    Log ''
    Log ('  密钥通道为「' + $d.Channel + '」，属零售/OEM 密钥，不做 GVLK 比对（这是正常的）。') 'Green'
  }

  if ($d.Kms -and $d.Kms -notmatch 'kms\.core\.windows\.net' -and -not [string]::IsNullOrWhiteSpace($d.Kms)) {
    Log ''
    Log ('  [注意] KMS 指向非微软官方地址「' + $d.Kms + '」——第三方 KMS 私服，') 'Orange'
    Log '  该服务器下线后激活即失效，且随时可能被吊销。' 'Orange'
  }
}

# ==================== 一键修复 ====================
function Do-Repair {
  $ok = $true
  $s = Get-SysInfo
  Ensure-BackupDir

  LogHead '第 1 步：检查当前 sppsvc.exe'
  if (-not (Test-Path $script:SppsvcPath)) {
    Log '  文件不存在，将从组件库还原' 'Orange'
    $curSig = 'Missing'
  } else {
    $curSig = Get-SigStatus $script:SppsvcPath
    Log ('  当前签名 : ' + $curSig)
  }

  if ($curSig -eq 'Valid') {
    Log '  签名有效，文件未被篡改 —— 跳过替换，直接尝试修复服务与激活。' 'Green'
  } else {
    Log '  签名无效，需要从组件库还原。' 'Orange'

    LogHead '第 2 步：选择匹配的原版'
    $good = Find-GoodSppsvc $s.Build $s.UbrNum
    if (-not $good) {
      Log '  组件库中没有签名有效的 sppsvc.exe，无法安全替换。' 'Red'
      Log '' 
      Log '  处理办法：点击「④ 联网修复」，工具会自动执行' 'Orange'
      Log '    DISM /Online /Cleanup-Image /RestoreHealth   （从 Windows Update 取回正版组件）' 'Orange'
      Log '    sfc /scannow                                 （用修好的组件库还原系统文件）' 'Orange'
      Log '  完成后会自动重新尝试替换与激活。' 'Orange'
      return $false
    }
    Log ('  选用副本 : ' + $good.Version + '   ' + $good.Size + ' 字节') 'Green'
    Log ('  路径     : ' + $good.Path) 'Gray'

    LogHead '第 3 步：备份当前文件'
    $bak = Join-Path $script:BackupDir ('sppsvc.exe.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try {
      if (Test-Path $script:SppsvcPath) {
        Copy-Item $script:SppsvcPath $bak -Force -ErrorAction Stop
        Log ('  已备份   : ' + $bak) 'Green'
      } else {
        Log '  原文件不存在，无需备份' 'Gray'
      }
    } catch {
      Log ('  备份失败（不影响继续）: ' + $_.Exception.Message) 'Orange'
    }

    LogHead '第 4 步：取得所有权并替换'
    if (Test-Path $script:SppsvcPath) {
      (& takeown.exe /f $script:SppsvcPath /a 2>&1) | ForEach-Object { if ($_) { Log ('  ' + $_) 'Gray' } }
      (& icacls.exe $script:SppsvcPath /grant '*S-1-5-32-544:F' 2>&1) | ForEach-Object { if ($_) { Log ('  ' + $_) 'Gray' } }
    }
    try {
      Copy-Item $good.Path $script:SppsvcPath -Force -ErrorAction Stop
      Log '  替换成功' 'Green'
    } catch {
      Log ('  替换失败: ' + $_.Exception.Message) 'Red'
      $ok = $false
    }
    if (Test-Path $script:SppsvcPath) {
      (& icacls.exe $script:SppsvcPath /setowner 'NT SERVICE\TrustedInstaller' 2>&1) | ForEach-Object { if ($_) { Log ('  ' + $_) 'Gray' } }
    }
  }

  LogHead '第 5 步：校验替换结果'
  $newSig = Get-SigStatus $script:SppsvcPath
  $nfi = Get-Item $script:SppsvcPath
  Log ('  大小     : ' + $nfi.Length + ' 字节')
  Log ('  版本     : ' + $nfi.VersionInfo.FileVersion)
  if ($newSig -eq 'Valid') { Log '  数字签名 : Valid   [正常]' 'Green' }
  else { Log ('  数字签名 : ' + $newSig + '   [仍异常]') 'Red'; $ok = $false }

  LogHead '第 6 步：启动软件保护服务'
  Start-Service sppsvc -ErrorAction SilentlyContinue
  for ($i = 0; $i -lt 12; $i++) {
    Pump 700
    if ((Get-Service sppsvc).Status -eq 'Running') { break }
  }
  $svc = Get-Service sppsvc
  $c2 = if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' }
  Log ('  服务状态 : ' + $svc.Status) $c2

  if ($svc.Status -ne 'Running') {
    (& sc.exe start sppsvc 2>&1) | ForEach-Object { if ($_) { Log ('  ' + $_) 'Gray' } }
    Pump 3000
    $svc = Get-Service sppsvc
    Log ('  重试结果 : ' + $svc.Status) $(if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' })
    if ($svc.Status -ne 'Running') {
      Log '  服务仍无法启动。建议改用「③ 深度修复」，或先重启电脑再试。' 'Orange'
      return $false
    }
  }

  LogHead '第 7 步：查询授权详情 (slmgr /dlv)'
  $dlv = Run-Slmgr '/dlv' 40000
  if ($dlv -eq '__TIMEOUT__') {
    Log '  查询超时' 'Red'; $ok = $false
  } else {
    foreach ($ln in ($dlv -split "`r?`n")) { if ($ln.Trim() -ne '') { Log ('  ' + $ln.TrimEnd()) } }
  }

  LogHead '第 8 步：重新激活 (slmgr /ato)'
  Log '  正在连接微软激活服务器，请稍候...' 'Gray'
  $ato = Run-Slmgr '/ato' 90000
  if ($ato -eq '__TIMEOUT__') {
    Log '  激活请求超时（可能无法联网，请确认网络后重试）' 'Red'
    $ok = $false
  } else {
    foreach ($ln in ($ato -split "`r?`n")) { if ($ln.Trim() -ne '') { Log ('  ' + $ln.TrimEnd()) } }
  }

  LogHead '第 9 步：确认激活状态 (slmgr /xpr)'
  $xpr = Run-Slmgr '/xpr' 40000
  if ($xpr -eq '__TIMEOUT__') {
    Log '  查询超时' 'Red'
  } else {
    foreach ($ln in ($xpr -split "`r?`n")) { if ($ln.Trim() -ne '') { Log ('  ' + $ln.TrimEnd()) } }
    if ($xpr -match '永久|Permanent') { Log '  [成功] 已永久激活' 'Green' }
    elseif ($xpr -match '通知|Notification') { Log '  [注意] 仍处于通知状态，建议执行「③ 深度修复」' 'Orange'; $ok = $false }
  }

  return $ok
}

# ==================== 深度修复 ====================
function Do-DeepRepair {
  $ok = $true
  LogHead '深度修复：重置授权状态'
  Log '  适用场景：文件已还原但服务仍异常、授权数据库损坏、密钥状态错乱。' 'Gray'

  $svc = Get-Service sppsvc -ErrorAction SilentlyContinue
  if (-not $svc -or $svc.Status -ne 'Running') {
    Log '  服务未运行，先尝试启动...' 'Orange'
    Start-Service sppsvc -ErrorAction SilentlyContinue
    Pump 4000
    if ((Get-Service sppsvc).Status -ne 'Running') {
      Log '  服务无法启动，深度修复无法继续 —— 请先执行「② 一键修复」。' 'Red'
      return $false
    }
  }

  LogHead '步骤 1：slmgr /rearm（重置授权状态）'
  $rearm = Run-Slmgr '/rearm' 60000
  if ($rearm -eq '__TIMEOUT__') {
    Log '  rearm 超时' 'Red'; $ok = $false
  } else {
    foreach ($ln in ($rearm -split "`r?`n")) { if ($ln.Trim() -ne '') { Log ('  ' + $ln.TrimEnd()) } }
  }

  LogHead '步骤 2：重启软件保护服务'
  Stop-Service sppsvc -Force -ErrorAction SilentlyContinue
  Pump 3000
  Start-Service sppsvc -ErrorAction SilentlyContinue
  for ($i = 0; $i -lt 12; $i++) {
    Pump 700
    if ((Get-Service sppsvc).Status -eq 'Running') { break }
  }
  $st = (Get-Service sppsvc).Status
  Log ('  服务状态 : ' + $st) $(if ($st -eq 'Running') { 'Green' } else { 'Red' })
  if ($st -ne 'Running') { return $false }

  LogHead '步骤 3：重新激活 (slmgr /ato)'
  Log '  正在连接微软激活服务器...' 'Gray'
  $ato = Run-Slmgr '/ato' 120000
  if ($ato -eq '__TIMEOUT__') {
    Log '  激活超时' 'Red'; $ok = $false
  } else {
    foreach ($ln in ($ato -split "`r?`n")) { if ($ln.Trim() -ne '') { Log ('  ' + $ln.TrimEnd()) } }
  }

  LogHead '步骤 4：确认状态 (slmgr /xpr)'
  $xpr = Run-Slmgr '/xpr' 40000
  if ($xpr -ne '__TIMEOUT__') {
    foreach ($ln in ($xpr -split "`r?`n")) { if ($ln.Trim() -ne '') { Log ('  ' + $ln.TrimEnd()) } }
    if ($xpr -match '永久|Permanent') { Log '  [成功] 已永久激活' 'Green' }
    elseif ($xpr -match '通知|Notification') { Log '  [注意] 仍为通知状态' 'Orange'; $ok = $false }
  }

  if (-not $ok) {
    Log ''
    Log '  如果以上步骤都无效，可尝试手工重置授权存储（谨慎）：' 'Orange'
    Log '    1) 备份 C:\Windows\System32\spp\store\2.0\tokens.dat' 'Orange'
    Log '    2) 停止 sppsvc 服务后删除该文件' 'Orange'
    Log '    3) 启动服务，再运行 slmgr /ato' 'Orange'
    Log '  注意：这会同时影响 Office 等使用 KMS 的组件。' 'Orange'
  }
  return $ok
}

# ==================== 联网修复（按需下载组件） ====================
# 运行外部程序并把最后一行输出实时显示到状态栏
function Run-WithTail([string]$exe, [string]$arguments, [int]$timeoutMin, [string]$label) {
  $outFile = [IO.Path]::GetTempFileName()
  $p = Start-Process -FilePath $exe -ArgumentList $arguments `
        -RedirectStandardOutput $outFile -RedirectStandardError "$outFile.err" -NoNewWindow -PassThru
  $end = (Get-Date).AddMinutes($timeoutMin)
  $lastShown = ''
  while (-not $p.HasExited -and (Get-Date) -lt $end) {
    Start-Sleep -Milliseconds 900
    [void][System.Windows.Forms.Application]::DoEvents()
    try {
      $txt = Get-Content $outFile -Raw -ErrorAction SilentlyContinue
      if ($txt) {
        $clean = ($txt -replace "`r", "`n")
        $lines = @($clean -split "`n" | Where-Object { $_.Trim() -ne '' })
        if ($lines.Count -gt 0) {
          $cur = $lines[-1].Trim()
          if ($cur.Length -gt 90) { $cur = $cur.Substring($cur.Length - 90) }
          if ($cur -ne $lastShown) { $lastShown = $cur; SetStatus ($label + '：' + $cur) }
        }
      }
    } catch { }
  }
  $killed = $false
  if (-not $p.HasExited) { try { $p.Kill(); $killed = $true } catch { } }
  $final = ''
  try { $final = (Get-Content $outFile -Raw -ErrorAction SilentlyContinue) } catch { }
  try { $final += "`r`n" + (Get-Content "$outFile.err" -Raw -ErrorAction SilentlyContinue) } catch { }
  Remove-Item $outFile -Force -ErrorAction SilentlyContinue
  Remove-Item "$outFile.err" -Force -ErrorAction SilentlyContinue
  return [pscustomobject]@{ Output = $final; ExitCode = $(if ($killed) { -1 } else { $p.ExitCode }); TimedOut = $killed }
}

function Do-NetRepair {
  $s = Get-SysInfo
  LogHead '联网修复：从 Windows Update 按需获取组件'
  Log '  DISM 会向 Windows Update 请求本系统所需的组件文件，重建本地组件库；' 'Gray'
  Log '  随后 SFC 用修复后的组件库还原 System32 中的系统文件。' 'Gray'
  Log ('  目标系统：' + $s.OSName + ' Build ' + $s.Build + '.' + $s.UBR) 'Gray'
  Log ''
  Log '  提示：这个过程通常需要 10~40 分钟，取决于网速和磁盘速度，' 'Orange'
  Log '        期间请勿关闭窗口、不要重启。' 'Orange'

  # ---------- 1. DISM ----------
  LogHead '步骤 1/3：DISM /Online /Cleanup-Image /RestoreHealth'
  SetStatus 'DISM 正在连接 Windows Update...'
  $dism = Run-WithTail 'dism.exe' '/Online /Cleanup-Image /RestoreHealth /LogPath:C:\Windows\Temp\dism-actfix.log' 60 'DISM'
  foreach ($ln in ($dism.Output -split "`r?`n")) {
    $t = $ln.Trim()
    if ($t -ne '' -and $t -notmatch '^\[=+\s*\d+') { Log ('  ' + $t) 'Gray' }
  }
  Log ('  DISM 退出码: ' + $dism.ExitCode) $(if ($dism.ExitCode -eq 0) { 'Green' } else { 'Orange' })

  $dismOk = ($dism.ExitCode -eq 0)
  if (-not $dismOk) {
    Log '  DISM 未成功。常见原因：无法访问 Windows Update、被组策略/防火墙拦截、' 'Orange'
    Log '  或系统组件库损坏过重。可稍后重试，或改用本地安装介质作为源：' 'Orange'
    Log '    dism /Online /Cleanup-Image /RestoreHealth /Source:D:\sources\install.wim:1 /LimitAccess' 'Orange'
  }

  # ---------- 2. SFC ----------
  LogHead '步骤 2/3：sfc /scannow'
  SetStatus 'SFC 正在扫描系统文件...'
  $sfc = Run-WithTail "$env:windir\system32\sfc.exe" '/scannow' 60 'SFC'
  $sfcText = [string]$sfc.Output
  foreach ($ln in ($sfcText -split "`r?`n")) {
    $t = ($ln -replace "`b", '').Trim()
    if ($t -ne '' -and $t.Length -lt 160) { Log ('  ' + $t) 'Gray' }
  }
  Log ('  SFC 退出码: ' + $sfc.ExitCode) $(if ($sfc.ExitCode -eq 0) { 'Green' } else { 'Orange' })

  # ---------- 3. 复查组件库并自动完成修复 ----------
  LogHead '步骤 3/3：复查组件库'
  $good = Find-GoodSppsvc $s.Build $s.UbrNum
  $total = 0
  if ($script:AllCandidates) { $total = @($script:AllCandidates).Count }

  if ($good) {
    Log ('  组件库已恢复：找到 ' + $total + ' 份副本，其中签名有效，推荐 ' + $good.Version) 'Green'
    Log '  继续执行一键修复流程（替换文件 → 重启服务 → 重新激活）...' 'Green'
    $r = Do-Repair
    return $r
  }

  Log ('  仍未找到签名有效的 sppsvc.exe（共扫描到 ' + $total + ' 份）') 'Red'
  if ($total -gt 0) {
    Log '  扫描到的副本及其签名状态：' 'Gray'
    foreach ($c in @($script:AllCandidates | Select-Object -First 8)) {
      Log ('    ' + $c.Sig.PadRight(14) + $c.Version.PadRight(24) + $c.Size.ToString().PadLeft(9) + ' 字节') 'Gray'
    }
    Log '  若这些副本签名都无效，说明组件库本身也被替换过，' 'Orange'
    Log '  需要 DISM 成功执行后才有干净来源；DISM 失败时只能使用系统安装介质修复安装。' 'Orange'
  } else {
    Log '  组件库中完全没有 sppsvc.exe —— 需要 DISM 或安装介质。' 'Orange'
  }
  return $false
}

# ==================== 保资料重装（官方 ISO 就地升级修复） ====================
function Get-FreeSpaceGB {
  try {
    $d = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop
    return [math]::Round($d.Free / 1GB, 1)
  } catch { return -1 }
}

function Get-IsoCandidates {
  $list = New-Object System.Collections.ArrayList
  foreach ($d in @((Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop'), 'D:\', 'E:\', 'F:\')) {
    if (Test-Path $d) {
      Get-ChildItem $d -Filter '*.iso' -File -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$list.Add($_) }
    }
  }
  return $list
}

function Check-ReinstallPreflight {
  $issues = New-Object System.Collections.ArrayList
  $warns  = New-Object System.Collections.ArrayList

  $free = Get-FreeSpaceGB
  if ($free -ge 0) {
    if ($free -lt 15)      { [void]$issues.Add('系统盘可用空间仅 ' + $free + ' GB，就地升级至少需要 15~20 GB。') }
    elseif ($free -lt 25)  { [void]$warns.Add('系统盘可用空间 ' + $free + ' GB，建议清理到 25 GB 以上更稳妥。') }
    else                   { [void]$warns.Add('系统盘可用空间 ' + $free + ' GB，充足。') }
  }

  try {
    $bat = Get-CimInstance Win32_Battery -ErrorAction Stop
    if ($bat) {
      $online = $null
      try { $online = (Get-CimInstance -ClassName BatteryStatus -Namespace root\wmi -ErrorAction Stop).PowerOnline } catch { }
      if ($online -eq $false) { [void]$issues.Add('当前使用电池供电。升级中途断电会造成系统损坏，请先接上电源。') }
      elseif ($online -eq $true) { [void]$warns.Add('电源：已接通交流电。') }
      else { [void]$warns.Add('电源：检测到电池，请确认已插电。') }
    } else {
      [void]$warns.Add('电源：台式设备，无电池。')
    }
  } catch { }

  try {
    $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    if ($bl.ProtectionStatus -eq 'On') {
      [void]$warns.Add('BitLocker 已开启：安装程序会自动处理，但强烈建议先备份恢复密钥。')
    }
  } catch { }

  $pending = $false
  if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pending = $true }
  if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pending = $true }
  if ($pending) { [void]$issues.Add('系统有挂起的重启任务，请先重启电脑再执行。') }

  return [pscustomobject]@{ Issues = $issues; Warns = $warns }
}

function Mount-Iso([string]$isoPath) {
  if (-not (Test-Path $isoPath)) { throw '找不到 ISO 文件：' + $isoPath }
  $img = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
  Start-Sleep -Seconds 2
  $vol = Get-DiskImage -ImagePath $isoPath | Get-Volume
  if (-not $vol -or -not $vol.DriveLetter) {
    try { Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue } catch { }
    throw 'ISO 已挂载但未获得盘符（可能是映像格式不受支持）'
  }
  return ($vol.DriveLetter + ':')
}

function Do-Reinstall([string]$isoPath) {
  $s = Get-SysInfo
  LogHead '保资料重装（就地升级修复）'
  Log ('  ISO 文件   : ' + $isoPath) 'Gray'
  Log '  方式       : 挂载 ISO → 运行 setup.exe → 保留个人文件和应用' 'Gray'
  Log '  说明       : 这不是格式化重装，不会删除任何个人文件。' 'Green'

  # ---- 挂载 ----
  LogHead '步骤 1：挂载 ISO'
  $drive = $null
  try {
    $drive = Mount-Iso $isoPath
    Log ('  已挂载到   : ' + $drive) 'Green'
  } catch {
    Log ('  挂载失败: ' + $_.Exception.Message) 'Red'
    return $false
  }

  try {
    # ---- 校验内容 ----
    LogHead '步骤 2：校验安装源'
    $setup = Join-Path $drive 'setup.exe'
    if (-not (Test-Path $setup)) {
      Log '  ISO 根目录没有 setup.exe，不像 Windows 安装映像。' 'Red'
      return $false
    }
    $wimPaths = @(
      (Join-Path $drive 'sources\install.wim'),
      (Join-Path $drive 'sources\install.esd')
    )
    $wim = $wimPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $wim) {
      Log '  未找到 sources\install.wim 或 install.esd，映像可能不完整。' 'Red'
      return $false
    }
    Log ('  install 文件: ' + (Split-Path $wim -Leaf) + '  ' + ([math]::Round((Get-Item $wim).Length / 1GB, 2)) + ' GB') 'Green'

    # ---- 版本比对 ----
    LogHead '步骤 3：版本兼容性'
    $isoVer = ($(Get-Item $setup).VersionInfo.FileVersion -split ' ')[0]
    $isoBuild = 0
    try { $isoBuild = ([version]$isoVer).Build } catch { }
    Log ('  ISO 版本   : ' + $isoVer + '  (Build ' + $isoBuild + ')')
    Log ('  当前系统   : Build ' + $s.Build + '.' + $s.UBR)

    if ($isoBuild -gt 0 -and $s.Build -gt 0) {
      if ($isoBuild -lt $s.Build) {
        Log '' 
        Log '  [不兼容] ISO 版本低于当前系统。安装程序会拒绝升级（提示"此版本比当前系统旧"）。' 'Red'
        Log '  请下载与当前系统相同或更高版本的 ISO。' 'Orange'
        return $false
      } elseif ($isoBuild -eq $s.Build) {
        Log '  [最佳] 与当前系统同一版本，属标准"就地修复安装"。' 'Green'
      } else {
        Log '  [可升级] ISO 版本高于当前系统，会顺带升级到新版本，同样保留数据。' 'Green'
      }
    }

    # ---- 启动 ----
    LogHead '步骤 4：启动安装程序'
    Log '  即将打开 Windows 安装程序，请在向导中：' 'Orange'
    Log '    1) 点「下一步」开始' 'Orange'
    Log '    2) 在"选择要保留的内容"处确认选的是「保留个人文件和应用」' 'Orange'
    Log '    3) 之后电脑会自动重启数次，全程 30~60 分钟，勿断电' 'Orange'
    Log ''
    Start-Process -FilePath $setup -ErrorAction Stop
    Log '  安装程序已启动。' 'Green'
    Log ('  ISO 保持挂载在 ' + $drive + '，安装完成后可手动弹出，或重启后自动释放。') 'Gray'
    return $true
  } catch {
    Log ('  执行出错: ' + $_.Exception.Message) 'Red'
    return $false
  }
}

# ==================== 事件 ====================
$btnDiag.Add_Click({
  $btnDiag.Enabled = $false
  SetStatus '正在诊断...'
  try {
    LogHead ('诊断开始    ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Do-Diagnose
    Log ''
    Log '诊断完成。' 'Green'
    SetStatus '诊断完成'
  } catch {
    Log ('诊断过程出错: ' + $_.Exception.Message) 'Red'
    Log ($_.ScriptStackTrace) 'Gray'
    SetStatus '诊断出错'
  } finally { $btnDiag.Enabled = $true }
})

$btnRepair.Add_Click({
  $ans = [System.Windows.Forms.MessageBox]::Show(
    "即将执行：`n`n" +
    "1. 检查 sppsvc.exe 的数字签名`n" +
    "2. 若被篡改，从组件库还原微软原版`n" +
    "3. 重启「软件保护」服务`n" +
    "4. 联网重新激活 Windows`n`n" +
    "原文件会备份到 " + $script:BackupDir + "`n`n是否继续？",
    '确认修复', 'YesNo', 'Question')
  if ($ans -ne 'Yes') { return }

  $btnRepair.Enabled = $false; $btnDiag.Enabled = $false; $btnDeep.Enabled = $false; $btnNet.Enabled = $false; $btnReinst.Enabled = $false
  SetStatus '正在修复，请勿关闭窗口...'
  try {
    LogHead ('一键修复开始    ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    $result = Do-Repair
    Log ''
    if ($result) {
      Log '════════ 修复流程已完成 ════════' 'Green'
      SetStatus '修复完成'
      [System.Windows.Forms.MessageBox]::Show(
        "修复流程已执行完毕。`n`n请看窗口最下方的激活状态。`n若仍显示未激活，请尝试「③ 深度修复」或重启后再试。",
        '完成', 'OK', 'Information') | Out-Null
    } else {
      Log '════════ 修复未能完全成功 ════════' 'Orange'
      Log '建议：先试「③ 深度修复」，仍不行则重启电脑后重试。' 'Orange'
      SetStatus '修复未完成'
    }
  } catch {
    Log ('修复过程出错: ' + $_.Exception.Message) 'Red'
    Log ($_.ScriptStackTrace) 'Gray'
    SetStatus '修复出错'
  } finally { $btnRepair.Enabled = $true; $btnDiag.Enabled = $true; $btnDeep.Enabled = $true; $btnNet.Enabled = $true; $btnReinst.Enabled = $true }
})

$btnDeep.Add_Click({
  $ans = [System.Windows.Forms.MessageBox]::Show(
    "深度修复会重置 Windows 授权状态：`n`n" +
    "1. slmgr /rearm  重置授权`n" +
    "2. 重启软件保护服务`n" +
    "3. 重新联网激活`n`n" +
    "适用于「文件已修好但仍未激活」的情况。`n" +
    "注意：会影响 Office 等同样依赖 KMS 的组件，需要时它们会重新激活。`n`n是否继续？",
    '确认深度修复', 'YesNo', 'Warning')
  if ($ans -ne 'Yes') { return }

  $btnRepair.Enabled = $false; $btnDiag.Enabled = $false; $btnDeep.Enabled = $false; $btnNet.Enabled = $false; $btnReinst.Enabled = $false
  SetStatus '正在深度修复...'
  try {
    LogHead ('深度修复开始    ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    $r = Do-DeepRepair
    Log ''
    if ($r) { Log '════════ 深度修复完成 ════════' 'Green'; SetStatus '深度修复完成' }
    else { Log '════════ 深度修复未完成 ════════' 'Orange'; SetStatus '深度修复未完成' }
  } catch {
    Log ('深度修复出错: ' + $_.Exception.Message) 'Red'
    Log ($_.ScriptStackTrace) 'Gray'
    SetStatus '深度修复出错'
  } finally { $btnRepair.Enabled = $true; $btnDiag.Enabled = $true; $btnDeep.Enabled = $true; $btnNet.Enabled = $true; $btnReinst.Enabled = $true }
})

$btnNet.Add_Click({
  $ans = [System.Windows.Forms.MessageBox]::Show(
    "联网修复会执行：`n`n" +
    "1. DISM 从 Windows Update 下载并修复系统组件`n" +
    "2. SFC 扫描并还原系统文件`n" +
    "3. 若组件库恢复，自动替换 sppsvc.exe 并重新激活`n`n" +
    "预计 10~40 分钟，需要能正常上网，期间请勿关闭窗口。`n`n是否继续？",
    '确认联网修复', 'YesNo', 'Warning')
  if ($ans -ne 'Yes') { return }

  $btnRepair.Enabled = $false; $btnDiag.Enabled = $false; $btnDeep.Enabled = $false; $btnNet.Enabled = $false; $btnReinst.Enabled = $false; $btnNet.Enabled = $false
  SetStatus '联网修复进行中...'
  try {
    LogHead ('联网修复开始    ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = Do-NetRepair
    Log ''
    Log ('  总耗时: ' + [math]::Round($sw.Elapsed.TotalMinutes, 1) + ' 分钟') 'Gray'
    if ($r) {
      Log '════════ 联网修复完成 ════════' 'Green'
      SetStatus '联网修复完成'
    } else {
      Log '════════ 联网修复未完成 ════════' 'Orange'
      SetStatus '联网修复未完成'
    }
  } catch {
    Log ('联网修复出错: ' + $_.Exception.Message) 'Red'
    Log ($_.ScriptStackTrace) 'Gray'
    SetStatus '联网修复出错'
  } finally {
    $btnRepair.Enabled = $true; $btnDiag.Enabled = $true; $btnDeep.Enabled = $true; $btnNet.Enabled = $true
  }
})

$btnReinst.Add_Click({
  $s = Get-SysInfo
  $msg = "「保资料重装」会用微软官方安装映像做一次就地升级修复。`n`n" +
         "会保留：个人文件、已装软件、大部分设置、激活状态`n" +
         "不会做：格式化、清除数据、删除分区`n`n" +
         "需要：一个与当前系统同版本或更新的 Windows ISO`n" +
         "耗时：30~60 分钟，电脑会重启数次，期间请勿断电`n`n" +
         "当前系统：" + $s.OSName + " " + $s.DisplayVer + "  Build " + $s.Build + "  " + $s.EditionName + "`n`n" +
         "确认继续吗？"
  $ans = [System.Windows.Forms.MessageBox]::Show($msg, '确认保资料重装', 'YesNo', 'Warning')
  if ($ans -ne 'Yes') { return }

  LogHead ('保资料重装    ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
  Log '  正在做安装前检查...' 'Gray'
  $pf = Check-ReinstallPreflight
  foreach ($w in $pf.Warns) { Log ('  · ' + $w) 'Gray' }

  if ($pf.Issues.Count -gt 0) {
    Log ''
    foreach ($i in $pf.Issues) { Log ('  [阻止] ' + $i) 'Red' }
    [System.Windows.Forms.MessageBox]::Show(($pf.Issues -join "`r`n`r`n"), '存在必须先解决的问题', 'OK', 'Error') | Out-Null
    Log '  已中止，未做任何修改。' 'Orange'
    SetStatus '已中止'
    return
  }

  # ---------- 选择 ISO ----------
  $iso = $null
  $cands = Get-IsoCandidates
  if ($cands.Count -gt 0) {
    $newest = $cands | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $pick = [System.Windows.Forms.MessageBox]::Show(
      ("检测到 ISO：`r`n" + $newest.FullName + "`r`n（" + [math]::Round($newest.Length / 1GB, 2) + " GB）`r`n`r`n直接使用它吗？选「否」可手动指定其它 ISO。"),
      '选择安装映像', 'YesNoCancel', 'Question')
    if ($pick -eq 'Cancel') { Log '  已取消。' 'Gray'; SetStatus '已取消'; return }
    if ($pick -eq 'Yes') { $iso = $newest.FullName }
  }

  if (-not $iso) {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = '选择 Windows 安装 ISO'
    $dlg.Filter = '光盘映像 (*.iso)|*.iso|所有文件 (*.*)|*.*'
    if (Test-Path (Join-Path $env:USERPROFILE 'Downloads')) { $dlg.InitialDirectory = (Join-Path $env:USERPROFILE 'Downloads') }
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
      $go = [System.Windows.Forms.MessageBox]::Show(
        "还没有 ISO 文件。`r`n`r`n是否现在打开微软官方下载页面？`r`n下载完成后回到本工具，再点一次「⑤ 保资料重装」。",
        '需要 Windows ISO', 'YesNo', 'Information')
      if ($go -eq 'Yes') {
        $url = if ($s.OSName -eq 'Windows 11') { 'https://www.microsoft.com/zh-cn/software-download/windows11' } else { 'https://www.microsoft.com/zh-cn/software-download/windows10' }
        try { Start-Process $url } catch { }
        Log ('  已打开微软官方下载页：' + $url) 'Green'
        Log '  下载时请选择与当前系统一致的版本和语言，' 'Orange'
        Log '  ISO 保存到「下载」或「桌面」后，本工具会自动识别。' 'Orange'
      }
      SetStatus '未选择 ISO'
      return
    }
    $iso = $dlg.FileName
  }

  $btnRepair.Enabled = $false; $btnDiag.Enabled = $false; $btnDeep.Enabled = $false
  $btnNet.Enabled = $false; $btnReinst.Enabled = $false
  SetStatus '正在准备安装环境...'
  try {
    $r = Do-Reinstall $iso
    if ($r) { SetStatus '安装程序已启动，请按向导操作' } else { SetStatus '安装未启动' }
  } catch {
    Log ('保资料重装出错: ' + $_.Exception.Message) 'Red'
    Log ($_.ScriptStackTrace) 'Gray'
    SetStatus '出错'
  } finally {
    $btnRepair.Enabled = $true; $btnDiag.Enabled = $true; $btnDeep.Enabled = $true
    $btnNet.Enabled = $true; $btnReinst.Enabled = $true
  }
})

$btnSave.Add_Click({
  try {
    $script:LogBuffer | Out-File -FilePath $script:LogFile -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show("日志已保存到：`n" + $script:LogFile, '保存成功', 'OK', 'Information') | Out-Null
  } catch {
    [System.Windows.Forms.MessageBox]::Show('保存失败: ' + $_.Exception.Message, '错误') | Out-Null
  }
})

$btnOpen.Add_Click({
  Ensure-BackupDir
  Start-Process explorer.exe $script:BackupDir
})

# ==================== 启动 ====================
$form.Add_Shown({
  try {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    if ($form.Width -gt $wa.Width)  { $form.Width  = $wa.Width - 16 }
    if ($form.Height -gt $wa.Height) { $form.Height = $wa.Height - 48 }
    $form.Left = [int](($wa.Width  - $form.Width)  / 2) + $wa.Left
    $form.Top  = [int](($wa.Height - $form.Height) / 2) + $wa.Top
  } catch { }

  $s = Get-SysInfo
  Log '本工具用于修复被第三方激活工具篡改的 Windows 授权组件。' 'Gray'
  Log ('支持 Windows 10 / 11 / Server，全部客户端版本（家庭/专业/企业/教育/LTSC/工作站）。') 'Gray'
  Log ''
  Log ('当前系统：' + $s.OSName + ' ' + $s.DisplayVer + '   Build ' + $s.Build + '.' + $s.UBR + '   ' + $s.InstallType) 'Gray'
  if ($s.ProductName -and ($s.ProductName -notmatch [regex]::Escape($s.OSName))) {
    Log ('注册表产品名：' + $s.ProductName + '（大版本升级后未同步，属正常现象）') 'Gray'
  }
  Log ('版本标识：' + $s.EditionID + '（' + $s.EditionName + '）') 'Gray'

  $sig = Get-SigStatus $script:SppsvcPath
  $svc = Get-Service sppsvc -ErrorAction SilentlyContinue
  if ($sig -eq 'Valid') { Log 'sppsvc.exe 签名正常。' 'Green' }
  else { Log ('警告：sppsvc.exe 签名异常（' + $sig + '），建议立即执行修复。') 'Red' }
  if ($svc -and $svc.Status -ne 'Running') {
    Log ('提示：软件保护服务当前为 ' + $svc.Status + '（按需启动的服务属正常，诊断时会实际启动验证）') 'Gray'
  }
  SetStatus '就绪'
})

[void]$form.ShowDialog()
