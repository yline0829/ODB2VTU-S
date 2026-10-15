# ODB2VTU-S v0.2.1 unified Tools -> Diagnosis & Safe Recovery dialog.
# This file is loaded within the main application; no separate application is installed.
function Show-DataSafetyWorkspace([string]$InitialPVD, [string]$Language = "zh") {
[xml]$safetyXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="ODB2VTU-S | Data Diagnosis and Safe Recovery" Height="570" Width="890"
        MinWidth="720" MinHeight="500" WindowStartupLocation="CenterOwner"
        Background="#F2F2F2" FontFamily="Segoe UI" FontSize="13">
  <DockPanel Margin="12">
    <TextBlock DockPanel.Dock="Top" Text="Data Safety | 数据诊断与恢复" FontSize="20" FontWeight="SemiBold" Margin="2,0,0,10"/>
    <TextBlock DockPanel.Dock="Bottom" Foreground="#A32C2C" FontWeight="SemiBold" Margin="1,10,1,0"
               Text="Never overwrite original ODB / VTU / PVD / Manifest. Always back up the original dataset first."/>
    <TabControl>
      <TabItem Header="1 只读诊断 / Audit"><StackPanel Margin="13">
        <TextBlock Text="Existing PVD file (.pvd)" FontWeight="SemiBold"/>
        <DockPanel Margin="0,4,0,12"><Button Name="auditBrowse" DockPanel.Dock="Right" Width="90" Content="Browse..."/><TextBox Name="auditPvd" MinHeight="27"/></DockPanel>
        <TextBlock TextWrapping="Wrap" Foreground="#454545" Text="Reads every VTU's array names, PVD references and manifest; identifies duplicate Step/Frame states, missing files and fields. Does NOT change original results."/>
        <Button Name="auditRun" Content="Run full read-only audit / 开始全量只读检查" Padding="11,7" Margin="0,18,0,10" HorizontalAlignment="Left" Background="#DCEEF8"/>
        <Button Name="auditFolder" Content="Open diagnostic report folder / 打开诊断报告目录" Padding="9,5" HorizontalAlignment="Left"/>
        <TextBlock Margin="0,16,0,0" TextWrapping="Wrap" Text="The diagnostic command opens a separate progress console and writes a JSON report. Source files are never modified."/>
      </StackPanel></TabItem>
      <TabItem Header="2 安全恢复 / Recover"><StackPanel Margin="13">
        <TextBlock Text="Original PVD (recovery source)" FontWeight="SemiBold"/>
        <DockPanel Margin="0,4,0,10"><Button Name="recoverBrowse" DockPanel.Dock="Right" Width="90" Content="Browse..."/><TextBox Name="recoverPvd" MinHeight="27"/></DockPanel>
        <TextBlock Text="Native ODB field names to add (only missing arrays, comma separated)"/>
        <TextBox Name="recoverFields" Text="U,UR,SDV27,SDV49" Margin="0,5,0,10" MinHeight="27"/>
        <TextBlock TextWrapping="Wrap" Text="First run CHECK ONLY to verify every referenced VTU and the original ODB. Recovery writes NEW verified VTU and PVD files into a separate RECOVERED_SAFE folder. It never deletes originals."/>
        <StackPanel Orientation="Horizontal" Margin="0,14,0,5">
          <Button Name="recoverCheck" Content="1. CHECK ONLY / 预检查" Padding="12,8" Margin="0,0,12,0" Background="#DCEEF8"/>
          <Button Name="recoverStart" Content="2. RESTORE to NEW folder / 安全恢复" Padding="12,8" Background="#F7E2C5"/>
        </StackPanel>
        <CheckBox Name="recoverConsent" Content="I have backed up the dataset and successfully completed CHECK ONLY / 已备份并通过预检查" Margin="0,9,0,6"/>
        <TextBlock Foreground="#A32C2C" TextWrapping="Wrap" Text="Fail-closed: ambiguous filenames, incomplete VTU, changed ODB, missing ODB field, incompatible geometry, and existing foreign recovery folders cause a safe stop."/>
      </StackPanel></TabItem>
      <TabItem Header="3 旧版迁移 / Legacy Import"><StackPanel Margin="13">
        <TextBlock Text="无 Manifest 的早期版本 PVD / Pre-manifest legacy PVD" FontWeight="SemiBold"/>
        <DockPanel Margin="0,5,0,12"><Button Name="legacyBrowse" DockPanel.Dock="Right" Width="90" Content="浏览..."/><TextBox Name="legacyPvd" MinHeight="27"/></DockPanel>
        <TextBlock TextWrapping="Wrap" Text="本功能使用主界面选择的 ODB、实例、单元集、包围盒。逐帧对照原 ODB 的网格与一个共有原生场变量的全部数值；无须旧 Manifest。"/>
        <TextBlock TextWrapping="Wrap" Foreground="#A32C2C" Margin="0,12,0,5" Text="只读预检查后，将完整旧 PVD/VTU 复制到全新 *_MIGRATED_SAFE 目录，并在新目录内建立可追溯 Manifest。不会写入原始文件。"/>
        <StackPanel Orientation="Horizontal" Margin="0,12,0,5">
          <Button Name="legacyCheck" Content="1. 只读预检查 / CHECK" Padding="12,8" Margin="0,0,12,0" Background="#DCEEF8"/>
          <Button Name="legacyStart" Content="2. 迁移到新目录 / MIGRATE" Padding="12,8" Background="#F7E2C5"/>
        </StackPanel>
        <CheckBox Name="legacyConsent" Content="已备份，知悉需要额外磁盘空间；迁移不覆盖原目录" Margin="0,10,0,7"/>
        <TextBlock TextWrapping="Wrap" Text="迁移成功后，请将主界面的输出 PVD 改成 *_MIGRATED_SAFE 文件夹内同名 PVD，再使用 Frame Merge + Field Merge 追加变量。"/>
      </StackPanel></TabItem>
    </TabControl>
  </DockPanel>
</Window>
"@
$safeTranslations = @{
  'ODB2VTU-S | Data Diagnosis and Safe Recovery'=@('ODB2VTU-S | 数据诊断与安全恢复','ODB2VTU-S | Data Diagnosis and Safe Recovery')
  'Data Safety | 数据诊断与恢复'=@('数据诊断与恢复','Data Diagnosis & Recovery')
  'Never overwrite original ODB / VTU / PVD / Manifest. Always back up the original dataset first.'=@('严禁覆盖原始 ODB／VTU／PVD／Manifest；操作前务必备份。','Never overwrite original ODB / VTU / PVD / Manifest. Back up the dataset first.')
  'Existing PVD file (.pvd)'=@('现有 PVD 文件（.pvd）','Existing PVD file (.pvd)')
  'Original PVD (recovery source)'=@('用于恢复的原始 PVD','Original PVD (recovery source)')
  'Native ODB field names to add (only missing arrays, comma separated)'=@('需要补充的原生场变量（逗号分隔，只补缺失字段）','Native ODB fields to add (missing arrays only, comma separated)')
  'Browse...'=@('浏览...','Browse...')
  'Reads every VTU''s array names, PVD references and manifest; identifies duplicate Step/Frame states, missing files and fields. Does NOT change original results.'=@('逐帧检查字段清单、PVD 引用、Manifest、重复 Step/Frame 与缺失文件；只读，不更改原始数据。','Read VTU arrays, PVD references and manifest; detect duplicate frames, missing files and fields. Read-only.')
  'The diagnostic command opens a separate progress console and writes a JSON report. Source files are never modified.'=@('检查将在独立命令行窗口显示进度并生成 JSON 报告；不修改原始文件。','Audit opens a separate progress console and creates a JSON report. Source files are unchanged.')
  'First run CHECK ONLY to verify every referenced VTU and the original ODB. Recovery writes NEW verified VTU and PVD files into a separate RECOVERED_SAFE folder. It never deletes originals.'=@('请先执行预检查，确认原 ODB 和全部 VTU 正常；恢复只写入独立 RECOVERED_SAFE 目录，不删除旧文件。','Run CHECK ONLY before restoration. New verified files are written to a separate RECOVERED_SAFE folder.')
  'Fail-closed: ambiguous filenames, incomplete VTU, changed ODB, missing ODB field, incompatible geometry, and existing foreign recovery folders cause a safe stop.'=@('安全中止：文件名歧义、VTU 不完整、ODB 变化、缺少变量、网格不兼容或恢复目录冲突时立即停止。','Fail closed on filename ambiguity, truncated VTU, modified ODB, missing fields, geometry mismatch or directory conflicts.')
}
foreach($attr in $safetyXaml.SelectNodes('//@*')) {
  if($attr.LocalName -in @('Title','Header','Text','Content') -and $safeTranslations.ContainsKey($attr.Value)) {
    $attr.Value=$safeTranslations[$attr.Value][[int]($Language -eq 'en')]
  }
}
Localize-SubwindowXaml $safetyXaml $Language
$dialog = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $safetyXaml))
$dialog.Owner = $window
$controls = @{}
foreach($name in 'auditBrowse','auditPvd','auditRun','auditFolder','recoverBrowse','recoverPvd','recoverFields','recoverCheck','recoverStart','recoverConsent','legacyBrowse','legacyPvd','legacyCheck','legacyStart','legacyConsent') { $controls[$name] = $dialog.FindName($name) }
$controls['auditPvd'].Text = $InitialPVD
$controls['recoverPvd'].Text = $InitialPVD
$controls['legacyPvd'].Text = $InitialPVD
$choose = {
  $picker = New-Object Microsoft.Win32.OpenFileDialog
  $picker.Filter = 'PVD files (*.pvd)|*.pvd'
  if($picker.ShowDialog($dialog)) { return $picker.FileName }
  return ''
}
$controls['auditBrowse'].Add_Click({ $v=& $choose; if($v){$controls['auditPvd'].Text=$v} })
$controls['recoverBrowse'].Add_Click({ $v=& $choose; if($v){$controls['recoverPvd'].Text=$v} })
$controls['legacyBrowse'].Add_Click({ $v=& $choose; if($v){$controls['legacyPvd'].Text=$v} })
$controls['auditFolder'].Add_Click({ Start-Process explorer.exe -ArgumentList ('"' + $scriptDir + '"') })
$controls['auditRun'].Add_Click({
  $pvd=$controls['auditPvd'].Text.Trim().Trim('"')
  if(-not (Test-Path -LiteralPath $pvd -PathType Leaf)) { [Windows.MessageBox]::Show('Select a valid .pvd file.');return }
  $script=Join-Path $scriptDir 'Audit_ReadOnly.ps1'
  if(-not (Test-Path -LiteralPath $script)) { [Windows.MessageBox]::Show('Missing read-only audit script.');return }
  $command='powershell.exe -NoProfile -ExecutionPolicy Bypass -File ' + (Q $script) + ' -PvdPath ' + (Q $pvd)
  Start-Process -FilePath 'cmd.exe' -ArgumentList @('/k',$command) | Out-Null
})
$runRecovery={param([string]$mode)
  $pvd=$controls['recoverPvd'].Text.Trim().Trim('"')
  $fields=$controls['recoverFields'].Text.Trim()
  if(-not (Test-Path -LiteralPath $pvd -PathType Leaf) -or -not $pvd.EndsWith('.pvd',[StringComparison]::OrdinalIgnoreCase)) {
    [Windows.MessageBox]::Show('Select an existing PVD source.');return
  }
  if($fields -notmatch '^[A-Za-z][A-Za-z0-9_]*(,[A-Za-z][A-Za-z0-9_]*)*$') {
    [Windows.MessageBox]::Show('Use comma-separated native field names without spaces; e.g. U,UR,SDV27,SDV49');return
  }
  $script=Join-Path $scriptDir 'odb_recovery_safe.py'
  if(-not (Test-Path -LiteralPath $script)) { [Windows.MessageBox]::Show('Missing recovery backend.');return }
  if($mode -eq 'restore') {
    if($controls['recoverConsent'].IsChecked -ne $true) {
      [Windows.MessageBox]::Show('Back up the dataset, pass CHECK ONLY and check the confirmation box first.');return
    }
    $answer=[Windows.MessageBox]::Show('Restore into a NEW RECOVERED_SAFE folder? Original ODB/VTU/PVD are read-only. This may require substantial disk space.','Confirm recovery','YesNo','Warning')
    if($answer -ne 'Yes'){return}
  }
  $command='abaqus python ' + (Q $script) + ' --mode ' + $mode + ' --pvd ' + (Q $pvd) + ' --fields ' + (Q $fields)
  Start-Process -FilePath 'cmd.exe' -ArgumentList @('/k',$command) | Out-Null
}
$controls['recoverCheck'].Add_Click({ & $runRecovery 'check' })
$controls['recoverStart'].Add_Click({ & $runRecovery 'restore' })
$runLegacy = { param([string]$mode)
  $sourcePvd=$controls['legacyPvd'].Text.Trim().Trim('"')
  if(-not (Test-Path -LiteralPath $sourcePvd -PathType Leaf) -or -not $sourcePvd.EndsWith('.pvd',[StringComparison]::OrdinalIgnoreCase)) {
    [Windows.MessageBox]::Show($(if($Language -eq 'zh'){'请选择已有的旧版 PVD 文件。'}else{'Select an existing legacy PVD file.'}));return
  }
  if(-not (Test-Path -LiteralPath $txtOdb.Text -PathType Leaf) -or $cmbInstance.SelectedItem -eq $null) {
    [Windows.MessageBox]::Show($(if($Language -eq 'zh'){'请先在主界面选定 ODB 并读取实例信息。'}else{'Select an ODB and read its instances in the main page first.'}));return
  }
  $py=Join-Path $scriptDir 'odb_legacy_migration.py'
  if(-not (Test-Path -LiteralPath $py)) { [Windows.MessageBox]::Show('Missing odb_legacy_migration.py');return }
  if($mode -eq 'migrate') {
    if($controls['legacyConsent'].IsChecked -ne $true){[Windows.MessageBox]::Show('请先备份，并勾选迁移确认。');return}
    $answer=[Windows.MessageBox]::Show(
      $(if($Language -eq 'zh'){'将核对全部帧的网格与数值，之后完整复制 VTU 至独立 MIGRATED_SAFE 目录。原目录不会被修改。确认迁移？'}else{'Verify every frame numerically and copy VTUs to a NEW MIGRATED_SAFE directory. Continue?'}),
      'Legacy migration','YesNo','Warning')
    if($answer -ne 'Yes'){return}
  }
  $arg=''
  if($cmbElementSet.SelectedIndex -gt 0){
    $value=$cmbElementSet.SelectedItem.ToString()
    if($value -eq $T.en.AllGrains -or $value -eq $T.zh.AllGrains){$value='__ALL_GRAINS__'}
    $arg += ' --element-set ' + (Q $value)
  }
  if(-not [string]::IsNullOrWhiteSpace($txtBBox.Text)){$arg += ' --bbox ' + (Q $txtBBox.Text)}
  $command='abaqus python ' + (Q $py) + ' --mode ' + $mode + ' --pvd ' + (Q $sourcePvd) +
       ' --odb ' + (Q $txtOdb.Text) + ' --instance ' + (Q $cmbInstance.SelectedItem.ToString()) + $arg
  Start-Process -FilePath 'cmd.exe' -ArgumentList @('/k',$command) | Out-Null
}
$controls['legacyCheck'].Add_Click({ & $runLegacy 'check' })
$controls['legacyStart'].Add_Click({ & $runLegacy 'migrate' })
[void]$dialog.ShowDialog()
}
