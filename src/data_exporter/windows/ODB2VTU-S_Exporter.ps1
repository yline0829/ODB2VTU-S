Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Resolve the directory containing the GUI/backend files in both script and PS2EXE-compiled modes.
# PS2EXE 1.0.18 provides $ScriptRoot because $PSScriptRoot/$MyInvocation are not reliable in a compiled EXE.
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $ScriptRoot }
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = Split-Path -Parent ([Environment]::GetCommandLineArgs()[0])
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }
$metaPy = Join-Path $scriptDir "odb_metadata.py"
$fieldsPy = Join-Path $scriptDir "odb_list_fields.py"
$exportPy = Join-Path $scriptDir "odb_export_vtu.py"
$seriesPy = Join-Path $scriptDir "odb_export_series.py"

$metaJson = Join-Path $scriptDir "_last_odb_metadata.json"
$fieldsJson = Join-Path $scriptDir "_last_fields.json"
$curveMetaPy = Join-Path $scriptDir "odb_curve_history_meta.py"
$curveExportPy = Join-Path $scriptDir "odb_curve_history_export.py"
$curveMetaJson = Join-Path $scriptDir "_curve_history_meta.json"
$curveStepsFile = Join-Path $scriptDir "_curve_selected_steps.txt"
$selectionFile = Join-Path $scriptDir "_selected_step_frames.txt"
$analysisPy = Join-Path $scriptDir "odb_field_analysis.py"
$analysisFieldsJson = Join-Path $scriptDir "_analysis_fields.json"

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ODB2VTU-S Workbench"
        Width="1360" Height="850"
        MinWidth="1080" MinHeight="700"
        WindowStartupLocation="CenterScreen"
        Background="#E2E2E2"
        FontFamily="Segoe UI"
        FontSize="12">

    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#A6A6A6"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="4,2"/>
            <Setter Property="Height" Value="25"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#A6A6A6"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Height" Value="25"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#E7E7E7"/>
            <Setter Property="BorderBrush" Value="#999999"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,3"/>
            <Setter Property="MinHeight" Value="25"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Margin" Value="0,2"/>
        </Style>
        <Style TargetType="Expander">
            <Setter Property="Margin" Value="0,0,0,2"/>
            <Setter Property="Background" Value="#F2F2F2"/>
            <Setter Property="BorderBrush" Value="#B5B5B5"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
        </Style>
    </Window.Resources>

    <DockPanel>

        <Menu DockPanel.Dock="Top" Height="24" Background="#F4F4F4">
            <MenuItem x:Name="menuFile" Header="_File">
                <MenuItem x:Name="miOpen" Header="Open ODB..."/>
                <Separator/>
                <MenuItem x:Name="miExit" Header="Exit"/>
            </MenuItem>
            <MenuItem x:Name="menuEdit" Header="_Edit">
                <MenuItem x:Name="miCurveData" Header="Curve Data..."/>
                <MenuItem x:Name="miFieldAnalysis" Header="Field Extremum Analysis..."/>
                <Separator/>
                <MenuItem x:Name="miCPFEM" Header="Friction CPFEM (History / PEEQCP)..."/>
            </MenuItem>
            <MenuItem x:Name="menuView" Header="_View"/>
            <MenuItem x:Name="menuTools" Header="_Tools">
                <MenuItem x:Name="miDataSafety" Header="Data Diagnosis and Safe Recovery..."/>
            </MenuItem>
            <MenuItem x:Name="menuHelp" Header="_Help"/>
        </Menu>

        <Border DockPanel.Dock="Top"
                Background="#EBEBEB"
                BorderBrush="#B7B7B7"
                BorderThickness="0,0,0,1"
                Padding="4,2">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Orientation="Horizontal">
                    <Button x:Name="tbOpen" Content="Open ODB"/>
                    <Button x:Name="tbRead" Content="Read Metadata" Margin="4,0,0,0"/>
                    <Button x:Name="tbFields" Content="Read Fields" Margin="12,0,0,0"/>
                    <Button x:Name="tbExport" Content="Export Data" Margin="4,0,0,0"/>
                    <Button x:Name="tbOpenFolder" Content="Open Output Folder" Margin="4,0,0,0"/>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <TextBlock x:Name="lblLanguage" Text="Language" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <ComboBox x:Name="cmbLanguage" Width="105" Height="24">
                        <ComboBoxItem Content="English" Tag="en"/>
                        <ComboBoxItem Content="中文" Tag="zh"/>
                    </ComboBox>
                </StackPanel>
            </Grid>
        </Border>

        <StatusBar DockPanel.Dock="Bottom"
                   Height="25"
                   Background="#E8E8E8"
                   BorderBrush="#B5B5B5"
                   BorderThickness="0,1,0,0">
            <StatusBarItem><TextBlock x:Name="txtStatus" Text="Ready"/></StatusBarItem>
            <Separator/>
            <StatusBarItem><TextBlock x:Name="txtStatusRight" Text="ODB: not loaded"/></StatusBarItem>
        </StatusBar>

        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition x:Name="colLeftPanel" Width="470" MinWidth="360"/>
                <ColumnDefinition Width="7"/>
                <ColumnDefinition Width="*" MinWidth="420"/>
            </Grid.ColumnDefinitions>

            <!-- LEFT PROPERTIES -->
            <Border Grid.Column="0"
                    Background="#F2F2F2"
                    BorderBrush="#A7A7A7"
                    BorderThickness="0,0,1,0">
                <DockPanel>

                    <Border DockPanel.Dock="Top"
                            Background="#DCDCDC"
                            BorderBrush="#A7A7A7"
                            BorderThickness="0,0,0,1"
                            Padding="7,4">
                        <TextBlock x:Name="hdrProperties" Text="Properties" FontWeight="SemiBold"/>
                    </Border>

                    <Border DockPanel.Dock="Top"
                            Background="#F5F5F5"
                            BorderBrush="#C0C0C0"
                            BorderThickness="0,0,0,1"
                            Padding="5,4">
                        <StackPanel Orientation="Horizontal">
                            <Button x:Name="btnApply" Content="Apply" Width="82" Background="#E2EEF8"/>
                            <Button x:Name="btnReset" Content="Reset" Width="76" Margin="5,0,0,0"/>
                        </StackPanel>
                    </Border>

                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Margin="5">

                            <Expander x:Name="grpSource" Header="Source" IsExpanded="True">
                                <StackPanel Margin="8,5">
                                    <TextBlock x:Name="lblOdbFile" Text="ODB File"/>
                                    <Grid Margin="0,3,0,4">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="36"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBox x:Name="txtOdb"/>
                                        <Button x:Name="btnBrowse" Grid.Column="1" Content="..." Margin="4,0,0,0"/>
                                    </Grid>
                                    <Button x:Name="btnRead" Content="Read Metadata" Width="118" HorizontalAlignment="Left"/>
                                </StackPanel>
                            </Expander>

                            <Expander x:Name="grpTarget" Header="Target" IsExpanded="True">
                                <Grid Margin="8,5">
                                    <Grid.RowDefinitions>
                                        <RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/>
                                    </Grid.RowDefinitions>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="100"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>

                                    <TextBlock x:Name="lblInstance" Grid.Row="0" Text="Instance" VerticalAlignment="Center"/>
                                    <ComboBox x:Name="cmbInstance" Grid.Row="0" Grid.Column="1" Margin="0,2"/>

                                    <TextBlock x:Name="lblElementSet" Grid.Row="1" Text="Element Set" VerticalAlignment="Center"/>
                                    <ComboBox x:Name="cmbElementSet" Grid.Row="1" Grid.Column="1" Margin="0,2"/>

                                    <TextBlock x:Name="lblStep" Grid.Row="2" Text="Step" VerticalAlignment="Center"/>
                                    <ComboBox x:Name="cmbStep" Grid.Row="2" Grid.Column="1" Margin="0,2"/>

                                    <TextBlock x:Name="lblFrame" Grid.Row="3" Text="Frame" VerticalAlignment="Center"/>
                                    <ComboBox x:Name="cmbFrame" Grid.Row="3" Grid.Column="1" Margin="0,2"/>
                                </Grid>
                            </Expander>

                            <Expander x:Name="grpSeries" Header="Time Series" IsExpanded="True">
                                <StackPanel Margin="8,5">

                                    <CheckBox x:Name="chkSeries"
                                              Content="Export as ParaView time series (.pvd)"
                                              Margin="0,0,0,6"/>

                                    <Border x:Name="panelSeries"
                                            BorderBrush="#BDBDBD"
                                            BorderThickness="1"
                                            Background="#FAFAFA"
                                            Padding="7">

                                        <StackPanel>
                                            <TextBlock x:Name="txtSeriesHint"
                                                       Text="Select one Step, then Ctrl/Shift-select any frames to add."
                                                       Foreground="#555"
                                                       TextWrapping="Wrap"
                                                       Margin="0,0,0,6"/>

                                            <Grid>
                                                <Grid.RowDefinitions>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="150"/>
                                                    <RowDefinition Height="Auto"/>
                                                    <RowDefinition Height="150"/>
                                                    <RowDefinition Height="Auto"/>
                                                </Grid.RowDefinitions>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="92"/>
                                                    <ColumnDefinition Width="*" MinWidth="220"/>
                                                </Grid.ColumnDefinitions>

                                                <TextBlock x:Name="lblSeriesStep"
                                                           Grid.Row="0"
                                                           Text="Steps"
                                                           VerticalAlignment="Top"
                                                           Margin="0,4,0,0"/>

                                                <ListBox x:Name="lstSeriesSteps"
                                                         Grid.Row="0"
                                                         Grid.Column="1"
                                                         Height="105"
                                                         Margin="0,2,0,5"
                                                         SelectionMode="Extended"
                                                         BorderBrush="#A8A8A8"
                                                         BorderThickness="1"
                                                         Background="White"
                                                         ScrollViewer.HorizontalScrollBarVisibility="Auto"/>

                                                <TextBlock x:Name="lblAvailableFrames"
                                                           Grid.Row="1"
                                                           Text="Common Frames"
                                                           VerticalAlignment="Top"
                                                           Margin="0,4,0,0"/>

                                                <ListBox x:Name="lstAvailableFrames"
                                                         Grid.Row="1"
                                                         Grid.Column="1"
                                                         SelectionMode="Extended"
                                                         BorderBrush="#A8A8A8"
                                                         BorderThickness="1"
                                                         Background="White"
                                                         ScrollViewer.HorizontalScrollBarVisibility="Auto"/>

                                                <StackPanel Grid.Row="2"
                                                            Grid.Column="1"
                                                            Orientation="Horizontal"
                                                            Margin="0,5,0,7">
                                                    <Button x:Name="btnAddFrames"
                                                            Content="Add selected frames to selected Steps"
                                                            Width="225"/>
                                                    <Button x:Name="btnAddAllFrames"
                                                            Content="Add all common frames"
                                                            Width="150"
                                                            Margin="5,0,0,0"/>
                                                </StackPanel>

                                                <TextBlock x:Name="lblSelectedStates"
                                                           Grid.Row="3"
                                                           Text="Selected Step / Frame states"
                                                           VerticalAlignment="Top"
                                                           Margin="0,4,0,0"/>

                                                <ListBox x:Name="lstSelectedStates"
                                                         Grid.Row="3"
                                                         Grid.Column="1"
                                                         SelectionMode="Extended"
                                                         BorderBrush="#A8A8A8"
                                                         BorderThickness="1"
                                                         Background="White"
                                                         ScrollViewer.HorizontalScrollBarVisibility="Auto"/>

                                                <StackPanel Grid.Row="4"
                                                            Grid.Column="1"
                                                            Orientation="Horizontal"
                                                            Margin="0,5,0,0">
                                                    <Button x:Name="btnRemoveStates"
                                                            Content="Remove selected"
                                                            Width="120"/>
                                                    <Button x:Name="btnClearStates"
                                                            Content="Clear all"
                                                            Width="82"
                                                            Margin="5,0,0,0"/>
                                                </StackPanel>
                                            </Grid>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </Expander>

                            <Expander x:Name="grpFields" Header="Fields" IsExpanded="True">
                                <StackPanel Margin="8,5">
                                    <Button x:Name="btnReadFields"
                                            Content="Read fields from selected frame"
                                            Width="190"
                                            HorizontalAlignment="Left"/>
                                    <StackPanel Orientation="Horizontal" Margin="0,5,0,4">
                                        <Button x:Name="btnSelectAllFields" Content="Select all" Width="78"/>
                                        <Button x:Name="btnClearFields" Content="Clear" Width="68" Margin="5,0,0,0"/>
                                    </StackPanel>
                                    <Border Background="White"
                                            BorderBrush="#AEAEAE"
                                            BorderThickness="1"
                                            Height="170">
                                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                                            <StackPanel x:Name="panelFields" Margin="5"/>
                                        </ScrollViewer>
                                    </Border>
                                </StackPanel>
                            </Expander>

                            <Expander x:Name="grpDerived" Header="Derived Fields" IsExpanded="True">
                                <StackPanel Margin="8,5">
                                    <CheckBox x:Name="chkMises" Content="Mises Stress"/>
                                    <CheckBox x:Name="chkInitialIPF" Content="Initial IPF (HCP Ti)"/>

                                    <Grid Margin="0,5,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="82"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="36"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock x:Name="lblInpFile" Text="INP File" VerticalAlignment="Center"/>
                                        <TextBox x:Name="txtInp" Grid.Column="1"/>
                                        <Button x:Name="btnBrowseInp" Grid.Column="2" Content="..." Margin="4,0,0,0"/>
                                    </Grid>

                                    <Grid Margin="0,5,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="82"/>
                                            <ColumnDefinition Width="120"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock x:Name="lblIPFDir" Text="IPF Direction" VerticalAlignment="Center"/>
                                        <ComboBox x:Name="cmbIPFDir" Grid.Column="1">
                                            <ComboBoxItem Content="X" Tag="X"/>
                                            <ComboBoxItem Content="Y" Tag="Y"/>
                                            <ComboBoxItem Content="Z" Tag="Z"/>
                                        </ComboBox>
                                    </Grid>

                                    <TextBlock x:Name="txtDerivedHint"
                                               Text="Mises is derived from S. Initial IPF reads Grain material Euler angles from INP PROPS(1:3)."
                                               Foreground="#555" TextWrapping="Wrap" Margin="0,5,0,0"/>
                                </StackPanel>
                            </Expander>

                            <Expander x:Name="grpGND" Header="GND Evolution" IsExpanded="True">
                                <StackPanel Margin="8,5">
                                    <CheckBox x:Name="chkGNDDiff" Content="Compare gnd_field.dat with SDV11-28"/>

                                    <Grid Margin="0,5,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="82"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="36"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock x:Name="lblGNDDat" Text="GND DAT" VerticalAlignment="Center"/>
                                        <TextBox x:Name="txtGNDDat" Grid.Column="1"/>
                                        <Button x:Name="btnBrowseGNDDat" Grid.Column="2" Content="..." Margin="4,0,0,0"/>
                                    </Grid>

                                    <Grid Margin="0,5,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="82"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock x:Name="lblGNDMode" Text="Output" VerticalAlignment="Center"/>
                                        <ComboBox x:Name="cmbGNDMode" Grid.Column="1">
                                            <ComboBoxItem Content="18 slip systems only" Tag="slips"/>
                                        </ComboBox>
                                    </Grid>

                                    <CheckBox x:Name="chkGNDSlideDiff"
                                              Content="Sliding-start difference (18 slip systems)"
                                              Margin="0,8,0,0"/>

                                    <Grid Margin="0,5,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="82"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock x:Name="lblGNDSlideRef" Text="Reference" VerticalAlignment="Center"/>
                                        <ComboBox x:Name="cmbGNDSlideRef" Grid.Column="1">
                                            <ComboBoxItem Content="First sliding Step / Frame 0" Tag="sliding0"/>
                                            <ComboBoxItem Content="Last frame before sliding" Tag="previous_last"/>
                                        </ComboBox>
                                    </Grid>

                                    <TextBlock x:Name="txtGNDHint"
                                               Text="DAT difference uses gnd_field.dat. Sliding-start difference uses a fixed ODB baseline and outputs 18 slip-system increments."
                                               Foreground="#555" TextWrapping="Wrap" Margin="0,5,0,0"/>
                                </StackPanel>
                            </Expander>

                            <Expander x:Name="grpDifference" Header="Difference" IsExpanded="False">
                                <StackPanel Margin="8,5">
                                    <CheckBox x:Name="chkDelta" Content="Enable target - reference"/>
                                    <TextBlock x:Name="lblDiffField" Text="Field" Margin="0,5,0,2"/>
                                    <ComboBox x:Name="cmbDeltaField"/>
                                    <TextBlock x:Name="lblRefStep" Text="Reference Step" Margin="0,5,0,2"/>
                                    <ComboBox x:Name="cmbRefStep"/>
                                    <TextBlock x:Name="lblRefFrame" Text="Reference Frame" Margin="0,5,0,2"/>
                                    <ComboBox x:Name="cmbRefFrame"/>
                                </StackPanel>
                            </Expander>

                        </StackPanel>
                    </ScrollViewer>
                </DockPanel>
            </Border>

            <GridSplitter Grid.Column="1"
                          Width="7"
                          HorizontalAlignment="Stretch"
                          VerticalAlignment="Stretch"
                          ResizeDirection="Columns"
                          ResizeBehavior="PreviousAndNext"
                          ShowsPreview="True"
                          Background="#AFAFAF"
                          Cursor="SizeWE"
                          ToolTip="拖动调整左侧操作栏宽度 / Drag to resize the left panel"/>

            <!-- RIGHT: useful information only -->
            <Grid Grid.Column="2" Background="#D7D7D7">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="5"/>
                    <RowDefinition Height="230"/>
                </Grid.RowDefinitions>

                <Border Grid.Row="0"
                        Background="#F3F3F3"
                        BorderBrush="#A8A8A8"
                        BorderThickness="1"
                        Margin="6,6,6,0"
                        Padding="8">
                    <Grid>
                        <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="120"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="36"/>
                        </Grid.ColumnDefinitions>

                        <TextBlock x:Name="lblBBox" Grid.Row="0" Text="Bounding Box" VerticalAlignment="Center"/>
                        <TextBox x:Name="txtBBox" Grid.Row="0" Grid.Column="1"/>

                        <StackPanel Grid.Row="1" Grid.ColumnSpan="3" Margin="0,6,0,0">
                            <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                                <CheckBox x:Name="chkAutoOutput"
                                          Content="Auto-match ODB output folder"
                                          IsChecked="True"
                                          VerticalAlignment="Center"/>
                                <Button x:Name="btnChooseOutputFolder"
                                        Content="Select Output Folder..."
                                        Margin="12,0,0,0"/>
                            </StackPanel>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="120"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="36"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock x:Name="lblOutputFile" Text="Output File" VerticalAlignment="Center"/>
                                <TextBox x:Name="txtOutput" Grid.Column="1"/>
                                <Button x:Name="btnBrowseOutput" Grid.Column="2" Content="..." Margin="4,0,0,0"/>
                            </Grid>
                        </StackPanel>

                        <StackPanel Grid.Row="2" Grid.ColumnSpan="3" Margin="0,8,0,0">
                            <Separator Margin="0,0,0,7"/>
                            <TextBlock Text="增量更新策略 / Incremental Update Policy"
                                       FontWeight="SemiBold" Margin="0,0,0,5"/>
                            <WrapPanel>
                                <TextBlock Text="Frames" VerticalAlignment="Center" Margin="0,0,5,0"/>
                                <ComboBox x:Name="cmbFramePolicy" Width="210" SelectedIndex="0">
                                    <ComboBoxItem Content="合并/保留既有帧 / Merge" Tag="merge"/>
                                    <ComboBoxItem Content="同步当前选择 / Sync" Tag="sync"/>
                                </ComboBox>
                                <TextBlock Text="Fields" VerticalAlignment="Center" Margin="12,0,5,0"/>
                                <ComboBox x:Name="cmbFieldPolicy" Width="225" SelectedIndex="0">
                                    <ComboBoxItem Content="合并/保留既有变量 / Merge" Tag="merge"/>
                                    <ComboBoxItem Content="同步当前变量 / Sync" Tag="sync"/>
                                </ComboBox>
                            </WrapPanel>
                            <WrapPanel Margin="0,7,0,0">
                                <TextBlock x:Name="lblCompatMode" Text="旧版数据兼容模式" VerticalAlignment="Center" Margin="0,0,6,0"/>
                                <ComboBox x:Name="cmbCompatMode" Width="325" SelectedIndex="1">
                                    <ComboBoxItem Tag="standard" Content="标准增量（已有 Manifest）"/>
                                    <ComboBoxItem Tag="fast" Content="快速兼容（推荐，无 Manifest 自动迁移）"/>
                                    <ComboBoxItem Tag="strict" Content="严格验证（逐帧核对数值）"/>
                                </ComboBox>
                            </WrapPanel>
                            <CheckBox x:Name="chkInPlace" Content="原位增量更新（不新建复制目录，保留原 VTU 文件名）"
                                      IsChecked="False" Margin="0,5,0,0"/>
                            <TextBlock x:Name="txtCompatHint" Text="勾选原位更新后使用同目录临时文件和回滚硬链接，成功后替换原 VTU。"
                                       Foreground="#555" TextWrapping="Wrap" Margin="0,4,0,0"/>
                            <CheckBox x:Name="chkCleanupRemoved"
                                      Content="同步帧时同时删除已移除帧的 VTU / Delete removed-frame VTU files"
                                      IsChecked="False" Margin="0,5,0,0"/>
                            <TextBlock Text="Merge 为安全默认；只有 Sync 才执行删除语义。"
                                       Foreground="#555" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Grid>
                </Border>

                <Border Grid.Row="1"
                        Background="White"
                        BorderBrush="#A7A7A7"
                        BorderThickness="1"
                        Margin="6">
                    <DockPanel>
                        <Border DockPanel.Dock="Top"
                                Background="#E3E3E3"
                                BorderBrush="#A7A7A7"
                                BorderThickness="0,0,0,1"
                                Padding="7,4">
                            <TextBlock x:Name="hdrSummary" Text="Selection Summary" FontWeight="SemiBold"/>
                        </Border>

                        <TextBox x:Name="txtSummary"
                                 Height="Auto"
                                 VerticalAlignment="Stretch"
                                 IsReadOnly="True"
                                 BorderThickness="0"
                                 Background="White"
                                 AcceptsReturn="True"
                                 TextWrapping="Wrap"
                                 VerticalScrollBarVisibility="Auto"
                                 FontFamily="Consolas"
                                 FontSize="12"
                                 Padding="8"/>
                    </DockPanel>
                </Border>

                <GridSplitter Grid.Row="2" Height="5" Background="#B6B6B6"/>

                <Border Grid.Row="3"
                        Background="White"
                        BorderBrush="#A7A7A7"
                        BorderThickness="1"
                        Margin="6,0,6,6">
                    <DockPanel>
                        <Border DockPanel.Dock="Top"
                                Background="#E3E3E3"
                                BorderBrush="#A7A7A7"
                                BorderThickness="0,0,0,1"
                                Padding="7,4">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock x:Name="hdrMessages" Text="Output Messages" FontWeight="SemiBold"/>
                                <Button x:Name="btnClearMessages"
                                        Grid.Column="1"
                                        Content="Clear"
                                        MinHeight="21"
                                        Padding="7,1"/>
                            </Grid>
                        </Border>

                        <TextBox x:Name="txtMessages"
                                 Height="Auto"
                                 VerticalAlignment="Stretch"
                                 IsReadOnly="True"
                                 BorderThickness="0"
                                 Background="White"
                                 FontFamily="Consolas"
                                 FontSize="11"
                                 AcceptsReturn="True"
                                 TextWrapping="NoWrap"
                                 VerticalScrollBarVisibility="Auto"
                                 HorizontalScrollBarVisibility="Auto"
                                 Padding="7"/>
                    </DockPanel>
                </Border>
            </Grid>
        </Grid>
    </DockPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$names = @(
"menuFile","miOpen","miExit","menuEdit","menuView","menuTools","miCurveData","miFieldAnalysis","miCPFEM","miDataSafety","menuHelp",
"tbOpen","tbRead","tbFields","tbExport","tbOpenFolder","lblLanguage","cmbLanguage",
"hdrProperties","btnApply","btnReset",
"grpSource","lblOdbFile","txtOdb","btnBrowse","btnRead",
"grpTarget","lblInstance","cmbInstance","lblElementSet","cmbElementSet","lblStep","cmbStep","lblFrame","cmbFrame",
"grpSeries","chkSeries","panelSeries","txtSeriesHint","lblSeriesStep","lstSeriesSteps",
"lblAvailableFrames","lstAvailableFrames","btnAddFrames","btnAddAllFrames",
"lblSelectedStates","lstSelectedStates","btnRemoveStates","btnClearStates",
"grpFields","btnReadFields","btnSelectAllFields","btnClearFields","panelFields",
"grpDerived","chkMises","chkInitialIPF","lblInpFile","txtInp","btnBrowseInp","lblIPFDir","cmbIPFDir","txtDerivedHint",
"grpGND","chkGNDDiff","lblGNDDat","txtGNDDat","btnBrowseGNDDat","lblGNDMode","cmbGNDMode","chkGNDSlideDiff","lblGNDSlideRef","cmbGNDSlideRef","txtGNDHint",
"grpDifference","chkDelta","lblDiffField","cmbDeltaField","lblRefStep","cmbRefStep","lblRefFrame","cmbRefFrame",
"lblBBox","txtBBox","chkAutoOutput","btnChooseOutputFolder","lblOutputFile","txtOutput","btnBrowseOutput",
"cmbFramePolicy","cmbFieldPolicy","cmbCompatMode","lblCompatMode","txtCompatHint","chkInPlace","chkCleanupRemoved",
"hdrSummary","txtSummary","hdrMessages","btnClearMessages","txtMessages",
"txtStatus","txtStatusRight"
)
foreach($n in $names){
    Set-Variable -Name $n -Value $window.FindName($n) -Scope Script
}

$global:meta = $null
$script:lang = "zh"
$script:fieldBoxes = New-Object System.Collections.Generic.List[object]

# Each entry: PSCustomObject {Step, Frame, Display}
$script:selectedStates = New-Object System.Collections.ArrayList

$T = @{
en = @{
Window="ODB2VTU-S Workbench"; File="_File"; Open="Open ODB..."; Exit="Exit"; Edit="_Edit"; View="_View"; Tools="_Tools"; Help="_Help";
OpenODB="Open ODB"; ReadMeta="Read Metadata"; ReadFields="Read Fields"; Export="Export Data"; OpenFolder="Open Output Folder"; Language="Language";
Properties="Properties"; CurveData="Curve Data..."; FieldAnalysis="Field Extremum Analysis..."; Apply="Apply"; Reset="Reset";
Source="Source"; ODBFile="ODB File"; Target="Target"; Instance="Instance"; ElementSet="Element Set"; Step="Step"; Frame="Frame";
Series="Time Series"; EnableSeries="Export as ParaView time series (.pvd)";
SeriesHint="Ctrl/Shift-select one or more Steps, then select frame indices to add to all selected Steps. Drag the vertical divider to widen the left panel if names are truncated.";
SeriesStep="Steps"; AvailableFrames="Common frames"; AddFrames="Add selected frames to selected Steps"; AddAllFrames="Add all common frames";
SelectedStates="Selected Step / Frame states"; RemoveStates="Remove selected"; ClearStates="Clear all";
Fields="Fields"; ReadFrameFields="Read fields from selected frame"; SelectAll="Select all"; Clear="Clear"; Derived="Derived Fields"; Mises="Mises Stress"; InitialIPF="Initial IPF (HCP Ti)"; INPFile="INP File"; IPFDirection="IPF Direction"; DerivedHint="Mises is derived from S. Initial IPF reads Grain material Euler angles from INP PROPS(1:3)."; GND="GND Evolution"; GNDDiff="Compare gnd_field.dat with SDV11-28"; GNDDat="GND DAT"; GNDMode="Output"; GNDHint="DAT difference uses gnd_field.dat. Sliding-start difference uses a fixed ODB baseline and outputs 18 slip-system increments."; GNDSlideDiff="Sliding-start difference (18 slip systems)"; GNDSlideRef="Reference";
Difference="Difference"; EnableDiff="Enable target - reference"; DiffField="Field"; RefStep="Reference Step"; RefFrame="Reference Frame";
BBox="Bounding Box"; AutoOutput="Auto-match ODB output folder"; SelectOutputFolder="Select Output Folder..."; OutputFile="Output File"; Summary="Selection Summary"; Messages="Output Messages";
Ready="Ready"; NoODB="ODB: not loaded"; Whole="<Whole Instance>"; AllGrains="<All Grains>";
SeriesCount="Selected states"
}
zh = @{
Window="ODB2VTU-S 统一工作台"; File="_文件"; Open="打开 ODB..."; Exit="退出"; Edit="_编辑"; View="_视图"; Tools="_工具"; Help="_帮助";
OpenODB="打开 ODB"; ReadMeta="读取元数据"; ReadFields="读取场变量"; Export="导出数据"; OpenFolder="打开输出文件夹"; Language="语言";
Properties="属性"; CurveData="曲线数据..."; FieldAnalysis="场变量极值分析..."; Apply="应用"; Reset="重置";
Source="数据源"; ODBFile="ODB 文件"; Target="目标状态"; Instance="实例"; ElementSet="单元集"; Step="分析步"; Frame="帧";
Series="时间序列"; EnableSeries="导出为 ParaView 时间序列 (.pvd)";
SeriesHint="用 Ctrl/Shift 同时选择一个或多个分析步，再选择帧编号；所选帧会同时添加到这些分析步。若名称显示不全，可拖动中间竖向分隔条加宽左侧操作栏。";
SeriesStep="分析步（可多选）"; AvailableFrames="公共可选帧"; AddFrames="将所选帧添加到所选分析步"; AddAllFrames="添加全部公共帧";
SelectedStates="已选分析步 / 帧"; RemoveStates="移除所选"; ClearStates="清空全部";
Fields="场变量"; ReadFrameFields="读取当前帧场变量"; SelectAll="全选"; Clear="清空"; Derived="派生场"; Mises="Mises 应力"; InitialIPF="初始 IPF（HCP Ti）"; INPFile="INP 文件"; IPFDirection="IPF 方向"; DerivedHint="Mises 由 S 计算；初始 IPF 从 INP 中各 Grain 材料的 PROPS(1:3) 欧拉角生成。"; GND="GND 增量"; GNDDiff="计算 gnd_field.dat 与 SDV11-28 差值"; GNDDat="GND DAT"; GNDMode="输出"; GNDHint="DAT差值：当前SDV11-28减去gnd_field.dat初始分配值；滑动起点差值：当前SDV11-28减去滑动开始参考帧。均输出18个滑移系。"; GNDSlideDiff="滑动起点差值（18滑移系）"; GNDSlideRef="参考帧";
Difference="差值"; EnableDiff="启用 目标帧 - 参考帧"; DiffField="场变量"; RefStep="参考分析步"; RefFrame="参考帧";
BBox="包围盒"; AutoOutput="自动匹配 ODB 输出目录"; SelectOutputFolder="选择输出文件夹..."; OutputFile="输出文件"; Summary="选择摘要"; Messages="输出消息";
Ready="就绪"; NoODB="ODB：未加载"; Whole="<整个实例>"; AllGrains="<所有晶粒>";
SeriesCount="已选状态数"
}
}

function L([string]$k){ return $T[$script:lang][$k] }

# Visible WPF strings only. Never mutate Tag, x:Name, command arguments or array identifiers.
function Localize-SubwindowXaml([xml]$Document, [string]$Lang) {
    $pairs = @{
      'Field Extremum Analysis'=@('场变量极值分析','Field Extremum Analysis')
      'Top N grains'=@('晶粒数量 Top N','Top N grains')
      'Rank statistic'=@('排序统计量','Rank statistic')
      'Direction'=@('排序方向','Direction')
      'Extreme band (%)'=@('极值区间（%）','Extreme band (%)')
      'Mean'=@('平均值','Mean')
      'Maximum'=@('最大值','Maximum')
      'Minimum'=@('最小值','Minimum')
      'Instance'=@('实例','Instance')
      'Step'=@('分析步','Step')
      'Frame'=@('帧','Frame')
      'Field'=@('场变量','Field')
      'ODB'=@('ODB 文件','ODB')
      'Running...'=@('正在运行...','Running...')
      'Analysis Log / 分析结果'=@('分析日志','Analysis Log')
      'Percent of the full grain-statistic span from the selected extreme.'=@('相对于全部晶粒统计值范围的极值百分比。','Percentage of the full grain-statistic range measured from the selected extreme.')
      '默认只写出 Top N 晶粒的几何体；其他晶粒不会进入该 VTU。可切换为极值范围、单个极值晶粒或全部晶粒。'=@('默认只导出 Top N 晶粒；可切换为极值区间、极值晶粒或全部晶粒。','By default, only Top N grain geometry is exported. Other options: extreme band, one extreme grain, or all grains.')
      '只分析晶粒单元；可选 Bounding Box：xmin,xmax,ymin,ymax,zmin,zmax'=@('仅分析晶粒单元；可选包围盒：xmin,xmax,ymin,ymax,zmin,zmax','Analyze grain elements only. Optional bounding box: xmin,xmax,ymin,ymax,zmin,zmax')
    }
    foreach($attr in $Document.SelectNodes('//@*')) {
      if($attr.LocalName -notin @('Title','Header','Text','Content','ToolTip')) { continue }
      $v=$attr.Value
      if($pairs.ContainsKey($v)) { $attr.Value=$pairs[$v][[int]($Lang -eq 'en')]; continue }
      if($v -match '^(.*?) / (.*?)$') {
         $left=$Matches[1];$right=$Matches[2]
         $lc=[regex]::IsMatch($left,'[\u3400-\u9fff]')
         $rc=[regex]::IsMatch($right,'[\u3400-\u9fff]')
         if($lc -and -not $rc) { $attr.Value=$(if($Lang -eq 'zh'){$left}else{$right}) }
         elseif($rc -and -not $lc) { $attr.Value=$(if($Lang -eq 'zh'){$right}else{$left}) }
      }
    }
}



$script:customFieldOutputDir = ""
$script:customCurveOutputDir = ""

function Get-AutoOutputDirectory([string]$odbPath){
    if([string]::IsNullOrWhiteSpace($odbPath)){ return "" }

    try{
        $odbDir = Split-Path $odbPath -Parent
        if([string]::IsNullOrWhiteSpace($odbDir)){ return "" }

        $outDir = Join-Path $odbDir "ODB2VTU_Output"

        if(-not (Test-Path $outDir)){
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }

        return $outDir
    }
    catch{
        return ""
    }
}

function Get-FieldOutputDirectory([string]$odbPath){
    if($chkAutoOutput -ne $null -and $chkAutoOutput.IsChecked){
        return Get-AutoOutputDirectory $odbPath
    }

    if(-not [string]::IsNullOrWhiteSpace($script:customFieldOutputDir)){
        if(-not (Test-Path $script:customFieldOutputDir)){
            New-Item -ItemType Directory -Path $script:customFieldOutputDir -Force | Out-Null
        }
        return $script:customFieldOutputDir
    }

    return Get-AutoOutputDirectory $odbPath
}

function Set-FieldOutputPath([string]$odbPath){
    if([string]::IsNullOrWhiteSpace($odbPath)){ return }

    $outDir = Get-FieldOutputDirectory $odbPath
    if([string]::IsNullOrWhiteSpace($outDir)){ return }

    $stem = [IO.Path]::GetFileNameWithoutExtension($odbPath)

    if($chkSeries -ne $null -and $chkSeries.IsChecked){
        $txtOutput.Text = Join-Path $outDir ($stem + "_series.pvd")
    }
    else{
        $txtOutput.Text = Join-Path $outDir ($stem + "_selected.vtu")
    }
}

function Choose-FieldOutputFolder {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "选择导出文件夹 / Select output folder"

    if(-not [string]::IsNullOrWhiteSpace($script:customFieldOutputDir) -and (Test-Path $script:customFieldOutputDir)){
        $dlg.SelectedPath = $script:customFieldOutputDir
    }
    elseif(-not [string]::IsNullOrWhiteSpace($txtOdb.Text) -and (Test-Path $txtOdb.Text)){
        $dlg.SelectedPath = Split-Path $txtOdb.Text -Parent
    }

    if($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
        $script:customFieldOutputDir = $dlg.SelectedPath
        $chkAutoOutput.IsChecked = $false
        Set-FieldOutputPath $txtOdb.Text
        UpdateSummary
    }
}

function Q([string]$s){
    return '"' + $s.Replace('"','\"') + '"'
}

function FrameIndex($combo){
    if($combo.SelectedItem -eq $null){ return -1 }
    return [int](($combo.SelectedItem.ToString().Split("|")[0]).Trim())
}

function FrameIndexFromLabel([string]$label){
    return [int](($label.Split("|")[0]).Trim())
}

function Msg([string]$s){
    $txtMessages.AppendText("[" + (Get-Date -Format "HH:mm:ss") + "] " + $s + "`r`n")
    $txtMessages.ScrollToEnd()
}

function PopulateFrameCombo($combo, [string]$stepName, [bool]$lastDefault){
    $combo.Items.Clear()
    if($global:meta -eq $null -or [string]::IsNullOrWhiteSpace($stepName)){ return }

    $nf = [int]$global:meta.steps.$stepName.nframes
    for($i=0; $i -lt $nf; $i++){
        if($i -eq 0){ $lab = "$i | First" }
        elseif($i -eq $nf-1){ $lab = "$i | Last" }
        else{ $lab = "$i" }
        [void]$combo.Items.Add($lab)
    }

    if($combo.Items.Count -gt 0){
        if($lastDefault){ $combo.SelectedIndex = $combo.Items.Count - 1 }
        else{ $combo.SelectedIndex = 0 }
    }
}

function GetSelectedSeriesSteps {
    $steps = New-Object System.Collections.Generic.List[string]
    foreach($item in $lstSeriesSteps.SelectedItems){
        $label = $item.ToString()
        # Display format: StepName  [N frames]
        $idx = $label.LastIndexOf("  [")
        if($idx -gt 0){
            $steps.Add($label.Substring(0,$idx))
        } else {
            $steps.Add($label)
        }
    }
    return $steps
}

function PopulateCommonSeriesFrames {
    $lstAvailableFrames.Items.Clear()

    if($global:meta -eq $null){ return }

    $steps = GetSelectedSeriesSteps
    if($steps.Count -eq 0){ return }

    # Common frame indices = 0 ... min(nframes)-1.
    # This guarantees that every selected frame exists in every selected Step.
    $minFrames = [int]::MaxValue

    foreach($stepName in $steps){
        $nf = [int]$global:meta.steps.$stepName.nframes
        if($nf -lt $minFrames){ $minFrames = $nf }
    }

    if($minFrames -le 0 -or $minFrames -eq [int]::MaxValue){ return }

    for($i=0; $i -lt $minFrames; $i++){
        if($i -eq 0){
            $lab = "$i | First"
        } else {
            $allLast = $true
            foreach($stepName in $steps){
                $nf = [int]$global:meta.steps.$stepName.nframes
                if($i -ne ($nf-1)){
                    $allLast = $false
                    break
                }
            }

            if($allLast){
                $lab = "$i | Last (all selected Steps)"
            } else {
                $lab = "$i"
            }
        }
        [void]$lstAvailableFrames.Items.Add($lab)
    }
}

function SelectedFields {
    $r = New-Object System.Collections.Generic.List[string]
    foreach($cb in $script:fieldBoxes){
        if($cb.IsChecked){ $r.Add($cb.Tag.ToString()) }
    }
    return $r
}

function StateExists([string]$step, [int]$frame){
    foreach($x in $script:selectedStates){
        if($x.Step -eq $step -and [int]$x.Frame -eq $frame){ return $true }
    }
    return $false
}

function RefreshSelectedStates {
    if($global:meta -eq $null){
        $lstSelectedStates.Items.Clear()
        return
    }

    # Sort by actual ODB Step order, then frame index.
    $order = @{}
    $i = 0
    foreach($s in $global:meta.steps.PSObject.Properties.Name){
        $order[$s] = $i
        $i++
    }

    $sorted = @(
        $script:selectedStates |
        Sort-Object @{Expression={$order[$_.Step]}}, @{Expression={[int]$_.Frame}}
    )

    $lstSelectedStates.Items.Clear()
    foreach($x in $sorted){
        $label = $x.Step + "  |  Frame " + $x.Frame
        [void]$lstSelectedStates.Items.Add($label)
    }

    UpdateSummary
}

function AddFramesToSelectedSteps([bool]$allFrames){
    $steps = GetSelectedSeriesSteps
    if($steps.Count -eq 0){ return }

    $labels = @()

    if($allFrames){
        foreach($item in $lstAvailableFrames.Items){
            $labels += $item.ToString()
        }
    } else {
        foreach($item in $lstAvailableFrames.SelectedItems){
            $labels += $item.ToString()
        }
    }

    if($labels.Count -eq 0){ return }

    foreach($step in $steps){
        $nf = [int]$global:meta.steps.$step.nframes

        foreach($lab in $labels){
            $fi = FrameIndexFromLabel $lab

            # Defensive validation even though the GUI only shows common frames.
            if($fi -ge 0 -and $fi -lt $nf){
                if(-not (StateExists $step $fi)){
                    [void]$script:selectedStates.Add(
                        [PSCustomObject]@{
                            Step=$step
                            Frame=$fi
                        }
                    )
                }
            }
        }
    }

    RefreshSelectedStates
}

function RemoveSelectedStates {
    $labels = @()
    foreach($item in $lstSelectedStates.SelectedItems){ $labels += $item.ToString() }

    foreach($label in $labels){
        # Display syntax: StepName  |  Frame N
        $parts = $label -split '\s+\|\s+Frame\s+'
        if($parts.Count -eq 2){
            $step = $parts[0]
            $frame = [int]$parts[1]

            for($i=$script:selectedStates.Count-1; $i -ge 0; $i--){
                $x = $script:selectedStates[$i]
                if($x.Step -eq $step -and [int]$x.Frame -eq $frame){
                    $script:selectedStates.RemoveAt($i)
                }
            }
        }
    }

    RefreshSelectedStates
}

function ToggleSeries {
    $on = [bool]$chkSeries.IsChecked
    $panelSeries.IsEnabled = $on

    if(-not [string]::IsNullOrWhiteSpace($txtOdb.Text)){
        Set-FieldOutputPath $txtOdb.Text
    }

    UpdateSummary
}


function RefreshElementSetLanguage {
    if($global:meta -eq $null -or $cmbInstance.SelectedItem -eq $null){ return }

    $old = ""
    if($cmbElementSet.SelectedItem -ne $null){
        $old = $cmbElementSet.SelectedItem.ToString()
    }

    $wasWhole = ($old -eq $T.en.Whole -or $old -eq $T.zh.Whole)
    $wasAllGrains = ($old -eq $T.en.AllGrains -or $old -eq $T.zh.AllGrains)

    $iname = $cmbInstance.SelectedItem.ToString()
    $sets = @($global:meta.instances.$iname.element_sets)

    $cmbElementSet.Items.Clear()
    [void]$cmbElementSet.Items.Add((L "Whole"))

    if([int]$global:meta.instances.$iname.grain_set_count -gt 0){
        [void]$cmbElementSet.Items.Add((L "AllGrains"))
    }

    foreach($s in $sets){
        [void]$cmbElementSet.Items.Add($s)
    }

    if($wasAllGrains -and [int]$global:meta.instances.$iname.grain_set_count -gt 0){
        $cmbElementSet.SelectedIndex = 1
        return
    }

    if(-not $wasWhole -and -not [string]::IsNullOrWhiteSpace($old)){
        for($i=0;$i -lt $cmbElementSet.Items.Count;$i++){
            if($cmbElementSet.Items[$i].ToString() -eq $old){
                $cmbElementSet.SelectedIndex = $i
                return
            }
        }
    }

    $cmbElementSet.SelectedIndex = 0
}

function ApplyLanguage {
    $window.Title = L "Window"
    $menuFile.Header = L "File"; $miOpen.Header = L "Open"; $miExit.Header = L "Exit"
    $menuEdit.Header = L "Edit"; $menuView.Header = L "View"; $menuTools.Header = L "Tools"; $miCurveData.Header = L "CurveData"; $miFieldAnalysis.Header = L "FieldAnalysis"; $menuHelp.Header = L "Help"
    if($script:lang -eq 'zh'){ $miCPFEM.Header='摩擦 CPFEM 后处理（History / PEEQCP）...'; $miDataSafety.Header='数据诊断与安全恢复...' }
    else { $miCPFEM.Header='Friction CPFEM (History / PEEQCP)...'; $miDataSafety.Header='Data Diagnosis and Safe Recovery...' }

    $tbOpen.Content = L "OpenODB"; $tbRead.Content = L "ReadMeta"; $tbFields.Content = L "ReadFields"; $tbExport.Content = L "Export"; $tbOpenFolder.Content = L "OpenFolder"
    $lblLanguage.Text = L "Language"
    if($script:lang -eq 'zh') {
        $cmbFramePolicy.Items[0].Content='合并／保留既有帧'
        $cmbFramePolicy.Items[1].Content='同步当前所选帧'
        $cmbFieldPolicy.Items[0].Content='合并／保留既有变量'
        $cmbFieldPolicy.Items[1].Content='同步当前变量'
        $chkCleanupRemoved.Content='同步帧时物理删除已移除的 VTU（危险）'
        $lblCompatMode.Text='旧版数据兼容模式'
        $cmbCompatMode.Items[0].Content='标准增量（已有 Manifest）'
        $cmbCompatMode.Items[1].Content='快速兼容（无 Manifest，两帧抽样）'
        $cmbCompatMode.Items[2].Content='严格验证（逐帧核对数值）'
        $chkInPlace.Content='原位增量更新已有 VTU（不新建文件夹）'
        $txtCompatHint.Text='勾选原位更新：同目录临时写入并原子替换，保留临时回滚硬链接直至完成。'
    } else {
        $cmbFramePolicy.Items[0].Content='Merge / preserve existing frames'
        $cmbFramePolicy.Items[1].Content='Sync current selection'
        $cmbFieldPolicy.Items[0].Content='Merge / preserve existing fields'
        $cmbFieldPolicy.Items[1].Content='Sync selected fields'
        $chkCleanupRemoved.Content='Delete removed-frame VTU files (dangerous)'
        $lblCompatMode.Text='Legacy compatibility mode'
        $cmbCompatMode.Items[0].Content='Standard incremental (Manifest exists)'
        $cmbCompatMode.Items[1].Content='Fast legacy (two sampled states)'
        $cmbCompatMode.Items[2].Content='Strict (verify native values per frame)'
        $chkInPlace.Content='Update existing VTUs in place (no new data directory)'
        $txtCompatHint.Text='In-place: write adjacent temporary files then atomically replace VTUs; rollback hardlinks are temporary.'
    }

    $hdrProperties.Text = L "Properties"; $btnApply.Content = L "Apply"; $btnReset.Content = L "Reset"

    $grpSource.Header = L "Source"; $lblOdbFile.Text = L "ODBFile"; $btnRead.Content = L "ReadMeta"
    $grpTarget.Header = L "Target"; $lblInstance.Text = L "Instance"; $lblElementSet.Text = L "ElementSet"; $lblStep.Text = L "Step"; $lblFrame.Text = L "Frame"

    $grpSeries.Header = L "Series"; $chkSeries.Content = L "EnableSeries"; $txtSeriesHint.Text = L "SeriesHint"
    $lblSeriesStep.Text = L "SeriesStep"; $lblAvailableFrames.Text = L "AvailableFrames"
    $btnAddFrames.Content = L "AddFrames"; $btnAddAllFrames.Content = L "AddAllFrames"
    $lblSelectedStates.Text = L "SelectedStates"; $btnRemoveStates.Content = L "RemoveStates"; $btnClearStates.Content = L "ClearStates"

    $grpFields.Header = L "Fields"; $btnReadFields.Content = L "ReadFrameFields"; $btnSelectAllFields.Content = L "SelectAll"; $btnClearFields.Content = L "Clear"
    $grpDerived.Header = L "Derived"; $chkMises.Content = L "Mises"; $chkInitialIPF.Content = L "InitialIPF"; $lblInpFile.Text = L "INPFile"; $lblIPFDir.Text = L "IPFDirection"; $txtDerivedHint.Text = L "DerivedHint"
    $grpGND.Header = L "GND"; $chkGNDDiff.Content = L "GNDDiff"; $lblGNDDat.Text = L "GNDDat"; $lblGNDMode.Text = L "GNDMode"; $chkGNDSlideDiff.Content = L "GNDSlideDiff"; $lblGNDSlideRef.Text = L "GNDSlideRef"; $txtGNDHint.Text = L "GNDHint"

    $grpDifference.Header = L "Difference"; $chkDelta.Content = L "EnableDiff"; $lblDiffField.Text = L "DiffField"; $lblRefStep.Text = L "RefStep"; $lblRefFrame.Text = L "RefFrame"

    $lblBBox.Text = L "BBox"; $chkAutoOutput.Content = L "AutoOutput"; $btnChooseOutputFolder.Content = L "SelectOutputFolder"; $lblOutputFile.Text = L "OutputFile"; $hdrSummary.Text = L "Summary"; $hdrMessages.Text = L "Messages"; $btnClearMessages.Content = L "Clear"

    if($global:meta -eq $null){ $txtStatus.Text = L "Ready" }
    if([string]::IsNullOrWhiteSpace($txtOdb.Text)){ $txtStatusRight.Text = L "NoODB" }

    RefreshElementSetLanguage
    ToggleSeries
    UpdateSummary
}

function UpdateSummary {
    $fs = SelectedFields

    $s = ""
    $s += (L "Instance") + " : " + ($(if($cmbInstance.SelectedItem){$cmbInstance.SelectedItem}else{"-"})) + "`r`n"
    $s += (L "ElementSet") + " : " + ($(if($cmbElementSet.SelectedItem){$cmbElementSet.SelectedItem}else{"-"})) + "`r`n"
    $s += (L "Step") + " : " + ($(if($cmbStep.SelectedItem){$cmbStep.SelectedItem}else{"-"})) + "`r`n"
    $s += (L "Frame") + " : " + ($(if($cmbFrame.SelectedItem){$cmbFrame.SelectedItem}else{"-"})) + "`r`n"

    if($chkSeries.IsChecked){
        $seriesSteps = GetSelectedSeriesSteps
        $s += (L "SeriesStep") + " : " + $seriesSteps.Count + "`r`n"
        $s += (L "SeriesCount") + " : " + $script:selectedStates.Count + "`r`n"

        if($script:selectedStates.Count -gt 0){
            $order = @{}
            $i=0
            foreach($sn in $global:meta.steps.PSObject.Properties.Name){
                $order[$sn]=$i
                $i++
            }

            foreach($x in ($script:selectedStates | Sort-Object @{Expression={$order[$_.Step]}}, @{Expression={[int]$_.Frame}})){
                $s += "  " + $x.Step + " / Frame " + $x.Frame + "`r`n"
            }
        }
    }

    $s += (L "Fields") + " : " + ($fs -join ", ") + "`r`n"
    $derived = @()
    if($chkMises.IsChecked){ $derived += "Mises" }
    if($chkInitialIPF.IsChecked){ $derived += "Initial IPF (" + $cmbIPFDir.SelectedItem.Content + ")" }
    $s += (L "Derived") + " : " + ($(if($derived.Count -gt 0){$derived -join ", "}else{"-"})) + "`r`n"
    if($chkInitialIPF.IsChecked){ $s += (L "INPFile") + " : " + $txtInp.Text + "`r`n" }

    if($chkGNDDiff.IsChecked){
        $gm = "-"
        if($cmbGNDMode.SelectedItem -ne $null){ $gm = $cmbGNDMode.SelectedItem.Content.ToString() }
        $s += (L "GND") + " : " + $gm + "`r`n"
        $s += (L "GNDDat") + " : " + $txtGNDDat.Text + "`r`n"
    } else {
        $s += (L "GND") + " : -`r`n"
    }

    if($chkGNDSlideDiff.IsChecked){
        $sr = "-"
        if($cmbGNDSlideRef.SelectedItem -ne $null){ $sr = $cmbGNDSlideRef.SelectedItem.Content.ToString() }
        $s += "GND Sliding Start : " + $sr + "`r`n"
    }

    if($chkDelta.IsChecked -and $cmbDeltaField.SelectedItem){
        $s += (L "Difference") + " : " + $cmbDeltaField.SelectedItem + "`r`n"
    }

    if(-not [string]::IsNullOrWhiteSpace($txtBBox.Text)){
        $s += (L "BBox") + " : " + $txtBBox.Text + "`r`n"
    }

    if($chkAutoOutput.IsChecked){
        $s += "Output mode : Auto -> ODB2VTU_Output`r`n"
    } else {
        $s += "Output mode : Custom folder -> " + $script:customFieldOutputDir + "`r`n"
    }

    $fp = "merge"; if($cmbFramePolicy.SelectedItem){ $fp = $cmbFramePolicy.SelectedItem.Tag.ToString() }
    $fldp = "merge"; if($cmbFieldPolicy.SelectedItem){ $fldp = $cmbFieldPolicy.SelectedItem.Tag.ToString() }
    $s += "Frame policy : " + $fp + "`r`n"
    $s += "Field policy : " + $fldp + "`r`n"
    if($chkCleanupRemoved.IsChecked){ $s += "Cleanup removed VTU : yes`r`n" }
    $s += "Write mode : " + $(if($chkInPlace.IsChecked){'in_place'}else{'safe_copy'}) + "`r`n"
    
    $s += (L "OutputFile") + " : " + $txtOutput.Text
    $txtSummary.Text = $s
}

function TryAutoMatchInp([string]$odbPath){
    if([string]::IsNullOrWhiteSpace($odbPath)){ return }
    try{
        $dir = Split-Path $odbPath -Parent
        $stem = [IO.Path]::GetFileNameWithoutExtension($odbPath)
        $exact = Join-Path $dir ($stem + ".inp")
        if(Test-Path $exact){ $txtInp.Text = $exact; return }

        $files = @(Get-ChildItem -Path $dir -Filter *.inp -File -ErrorAction SilentlyContinue)
        $matches = @()
        foreach($f in $files){
            $bs = [IO.Path]::GetFileNameWithoutExtension($f.Name)
            if($stem.StartsWith($bs) -or $bs.StartsWith($stem)){ $matches += $f.FullName }
        }
        if($matches.Count -eq 1){ $txtInp.Text = $matches[0]; return }
        if($files.Count -eq 1){ $txtInp.Text = $files[0].FullName }
    }catch{}
}

function TryAutoMatchGNDDat([string]$odbPath){
    if([string]::IsNullOrWhiteSpace($odbPath)){ return }
    try{
        $dir = Split-Path $odbPath -Parent
        $exact = Join-Path $dir "gnd_field.dat"
        if(Test-Path $exact){ $txtGNDDat.Text = $exact; return }
        $files = @(Get-ChildItem -Path $dir -Filter *.dat -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match "(?i)gnd" })
        if($files.Count -eq 1){ $txtGNDDat.Text = $files[0].FullName }
    }catch{}
}

function BrowseGNDDat {
    $d = New-Object Microsoft.Win32.OpenFileDialog
    $d.Filter = "GND field DAT (*.dat)|*.dat|All files (*.*)|*.*"
    if(-not [string]::IsNullOrWhiteSpace($txtGNDDat.Text) -and (Test-Path $txtGNDDat.Text)){
        $d.InitialDirectory = Split-Path $txtGNDDat.Text -Parent
    } elseif(-not [string]::IsNullOrWhiteSpace($txtOdb.Text) -and (Test-Path $txtOdb.Text)){
        $d.InitialDirectory = Split-Path $txtOdb.Text -Parent
    }
    if($d.ShowDialog()){ $txtGNDDat.Text = $d.FileName; UpdateSummary }
}

function UpdateGNDEnabled {
    $on = [bool]$chkGNDDiff.IsChecked
    $txtGNDDat.IsEnabled = $on
    $btnBrowseGNDDat.IsEnabled = $on
    $cmbGNDMode.IsEnabled = $on
    $slideOn = [bool]$chkGNDSlideDiff.IsChecked
    $cmbGNDSlideRef.IsEnabled = $slideOn
}

function BrowseInp {
    $d = New-Object Microsoft.Win32.OpenFileDialog
    $d.Filter = "Abaqus INP (*.inp)|*.inp|All files (*.*)|*.*"
    if(-not [string]::IsNullOrWhiteSpace($txtInp.Text) -and (Test-Path $txtInp.Text)){
        $d.InitialDirectory = Split-Path $txtInp.Text -Parent
    } elseif(-not [string]::IsNullOrWhiteSpace($txtOdb.Text) -and (Test-Path $txtOdb.Text)){
        $d.InitialDirectory = Split-Path $txtOdb.Text -Parent
    }
    if($d.ShowDialog()){ $txtInp.Text = $d.FileName; UpdateSummary }
}

function UpdateDerivedEnabled {
    $on = [bool]$chkInitialIPF.IsChecked
    $txtInp.IsEnabled = $on
    $btnBrowseInp.IsEnabled = $on
    $cmbIPFDir.IsEnabled = $on
}

function BrowseODB {
    $d = New-Object Microsoft.Win32.OpenFileDialog
    $d.Filter = "Abaqus ODB (*.odb)|*.odb"

    if($d.ShowDialog()){
        $txtOdb.Text = $d.FileName
        $stem = [IO.Path]::GetFileNameWithoutExtension($d.FileName)

        $txtStatus.Text = "ODB selected"
        $txtStatusRight.Text = "ODB: " + $stem
        Set-FieldOutputPath $d.FileName
        TryAutoMatchInp $d.FileName
        TryAutoMatchGNDDat $d.FileName

        $script:selectedStates.Clear()
        $lstSelectedStates.Items.Clear()

        Msg("Selected ODB: " + $d.FileName)
        UpdateSummary
    }
}

function ReadMeta {
    if(-not (Test-Path $txtOdb.Text)){ return }

    $cmd = "abaqus python " + (Q $metaPy) +
           " --odb " + (Q $txtOdb.Text) +
           " --json " + (Q $metaJson)

    $p = Start-Process cmd.exe -ArgumentList "/c",$cmd -Wait -PassThru

    if($p.ExitCode -ne 0 -or -not (Test-Path $metaJson)){
        [Windows.MessageBox]::Show("Metadata read failed.")
        return
    }

    $global:meta = Get-Content $metaJson -Raw | ConvertFrom-Json

    $cmbInstance.Items.Clear()
    foreach($n in $global:meta.instances.PSObject.Properties.Name){
        [void]$cmbInstance.Items.Add($n)
    }
    if($cmbInstance.Items.Count -gt 0){ $cmbInstance.SelectedIndex = 0 }

    foreach($c in @($cmbStep,$cmbRefStep)){
        $c.Items.Clear()
        foreach($n in $global:meta.steps.PSObject.Properties.Name){
            [void]$c.Items.Add($n)
        }
    }

    $lstSeriesSteps.Items.Clear()
    foreach($n in $global:meta.steps.PSObject.Properties.Name){
        $nf = [int]$global:meta.steps.$n.nframes
        [void]$lstSeriesSteps.Items.Add($n + "  [" + $nf + " frames]")
    }

    if($cmbStep.Items.Count -gt 0){
        $cmbStep.SelectedIndex = 0
        $cmbRefStep.SelectedIndex = 0
    }

    if($lstSeriesSteps.Items.Count -gt 0){
        $lstSeriesSteps.SelectedIndex = 0
    }

    $script:selectedStates.Clear()
    $lstSelectedStates.Items.Clear()

    $txtStatus.Text = "Metadata ready"
    Msg("Metadata ready.")
    UpdateSummary
}

function ReadFields {
    if($global:meta -eq $null){ return }
    if($cmbStep.SelectedItem -eq $null -or $cmbFrame.SelectedItem -eq $null){ return }

    $cmd = "abaqus python " + (Q $fieldsPy) +
           " --odb " + (Q $txtOdb.Text) +
           " --step " + (Q $cmbStep.SelectedItem.ToString()) +
           " --frame " + (FrameIndex $cmbFrame) +
           " --json " + (Q $fieldsJson)

    $p = Start-Process cmd.exe -ArgumentList "/c",$cmd -Wait -PassThru
    if($p.ExitCode -ne 0 -or -not (Test-Path $fieldsJson)){ return }

    $j = Get-Content $fieldsJson -Raw | ConvertFrom-Json

    $panelFields.Children.Clear()
    $script:fieldBoxes.Clear()
    $cmbDeltaField.Items.Clear()

    foreach($f in $j.fields){
        $cb = New-Object Windows.Controls.CheckBox
        $cb.Content = $f.name
        $cb.Tag = $f.name
        $cb.Margin = "0,1,0,1"

        if($f.name -eq "SDV29" -or $f.name -eq "SDV78"){
            $cb.IsChecked = $true
        }

        $cb.Add_Click({ UpdateSummary })

        [void]$panelFields.Children.Add($cb)
        $script:fieldBoxes.Add($cb)
        [void]$cmbDeltaField.Items.Add($f.name)
    }

    if($cmbDeltaField.Items.Count -gt 0){
        $cmbDeltaField.SelectedIndex = 0
    }

    Msg("Fields ready: " + $j.fields.Count)
    UpdateSummary
}

function WriteSelectionFile {
    $lines = New-Object System.Collections.Generic.List[string]

    if($global:meta -eq $null){ return $false }

    $order = @{}
    $i=0
    foreach($sn in $global:meta.steps.PSObject.Properties.Name){
        $order[$sn]=$i
        $i++
    }

    $sorted = @(
        $script:selectedStates |
        Sort-Object @{Expression={$order[$_.Step]}}, @{Expression={[int]$_.Frame}}
    )

    foreach($x in $sorted){
        $lines.Add($x.Step + "`t" + $x.Frame)
    }

    if($lines.Count -eq 0){ return $false }

    [System.IO.File]::WriteAllLines(
        $selectionFile,
        $lines,
        (New-Object System.Text.UTF8Encoding($true))
    )

    return $true
}

function RunExport {
    if($global:meta -eq $null){ return }
    if($cmbInstance.SelectedItem -eq $null){ return }

    $fs = SelectedFields
    if($fs.Count -eq 0 -and -not $chkDelta.IsChecked -and -not $chkMises.IsChecked -and -not $chkInitialIPF.IsChecked -and -not $chkGNDDiff.IsChecked -and -not $chkGNDSlideDiff.IsChecked){ return }
    if($chkInitialIPF.IsChecked -and -not (Test-Path $txtInp.Text)){
        [Windows.MessageBox]::Show("Initial IPF requires a valid INP file.")
        return
    }
    if($chkGNDDiff.IsChecked -and -not (Test-Path $txtGNDDat.Text)){
        [Windows.MessageBox]::Show("GND difference requires a valid gnd_field.dat file.")
        return
    }

    $fields = $fs -join ","
    $inst = $cmbInstance.SelectedItem.ToString()

    $setArg = ""
    if($cmbElementSet.SelectedIndex -gt 0){
        $v = $cmbElementSet.SelectedItem.ToString()

        if($v -eq $T.en.AllGrains -or $v -eq $T.zh.AllGrains){
            $setArg = ' --element-set "__ALL_GRAINS__"'
        } else {
            $setArg = " --element-set " + (Q $v)
        }
    }

    $bboxArg = ""
    if(-not [string]::IsNullOrWhiteSpace($txtBBox.Text)){
        $bboxArg = " --bbox " + (Q $txtBBox.Text)
    }

    $diffArg = ""
    if($chkDelta.IsChecked -and $cmbDeltaField.SelectedItem){
        $diffArg = " --delta-field " + (Q $cmbDeltaField.SelectedItem.ToString()) +
                   " --ref-step " + (Q $cmbRefStep.SelectedItem.ToString()) +
                   " --ref-frame " + (FrameIndex $cmbRefFrame)
    }

    $derivedArg = ""
    if($chkMises.IsChecked){ $derivedArg += " --mises 1" }
    if($chkInitialIPF.IsChecked){
        $dir = $cmbIPFDir.SelectedItem.Tag.ToString()
        $derivedArg += " --initial-ipf 1 --inp " + (Q $txtInp.Text) + " --ipf-dir " + $dir
    }
    if($chkGNDDiff.IsChecked){
        $gmode = "slips"
        if($cmbGNDMode.SelectedItem -ne $null){ $gmode = $cmbGNDMode.SelectedItem.Tag.ToString() }
        $derivedArg += " --gnd-diff 1 --gnd-dat " + (Q $txtGNDDat.Text) + " --gnd-diff-mode " + $gmode
    }
    if($chkGNDSlideDiff.IsChecked){
        $sref = "sliding0"
        if($cmbGNDSlideRef.SelectedItem -ne $null){ $sref = $cmbGNDSlideRef.SelectedItem.Tag.ToString() }
        $derivedArg += " --gnd-slide-diff 1 --gnd-slide-ref " + $sref
    }

    $framePolicy = "merge"
    if($cmbFramePolicy.SelectedItem -ne $null){ $framePolicy = $cmbFramePolicy.SelectedItem.Tag.ToString() }
    $fieldPolicy = "merge"
    if($cmbFieldPolicy.SelectedItem -ne $null){ $fieldPolicy = $cmbFieldPolicy.SelectedItem.Tag.ToString() }
    $cleanupRemoved = 0
    if($chkCleanupRemoved.IsChecked){ $cleanupRemoved = 1 }
    # v0.2.1 safety: Sync is destructive, and is never silently confirmed.
    $confirmFrameSync = 0
    $confirmFieldSync = 0
    $confirmDeleteFiles = 0
    if($chkSeries.IsChecked -and $framePolicy -eq "sync"){
        $answer = [Windows.MessageBox]::Show(
            $(if($script:lang -eq "zh"){"帧同步会从当前 PVD 时间序列中移除所有未选中的帧（默认保留物理文件）。仅添加 SDV 时应使用帧合并。确定执行帧同步？"}else{"FRAME SYNC removes every unselected Step/Frame from the active PVD series (files remain unless cleanup enabled). For adding SDVs use Frame Merge. Continue?"}),
            $(if($script:lang -eq "zh"){"ODB2VTU-S - 确认帧同步"}else{"ODB2VTU-S - Confirm Frame Sync"}), "YesNo", "Warning")
        if($answer -ne "Yes"){ return }
        $confirmFrameSync = 1
    }
    if($fieldPolicy -eq "sync"){
        $answer = [Windows.MessageBox]::Show(
            $(if($script:lang -eq "zh"){"字段同步会删除本次未选择的既有变量和 GND/IPF 派生场；新增 SDV 应选择字段合并。确定执行字段同步？"}else{"FIELD SYNC removes all previously exported variables and derived fields not selected now. Use Field Merge to preserve existing fields. Continue?"}),
            $(if($script:lang -eq "zh"){"ODB2VTU-S - 确认删除字段"}else{"ODB2VTU-S - Confirm Field Deletion"}), "YesNo", "Warning")
        if($answer -ne "Yes"){ return }
        $confirmFieldSync = 1
    }
    if($chkSeries.IsChecked -and $cleanupRemoved -eq 1){
        $answer = [Windows.MessageBox]::Show(
            $(if($script:lang -eq "zh"){"危险：此操作将在帧同步后永久删除未选中帧的 VTU 文件，不仅仅是将它们移出 PVD。确认永久删除？"}else{"DANGER: this PHYSICALLY DELETES unselected VTU files after Frame Sync, not just removes them from PVD. Continue?"}),
            $(if($script:lang -eq "zh"){"ODB2VTU-S - 确认永久删除文件"}else{"ODB2VTU-S - Confirm File Deletion"}), "YesNo", "Error")
        if($answer -ne "Yes"){ return }
        $confirmDeleteFiles = 1
    }
    $policyArg = " --field-policy " + $fieldPolicy +
                 " --confirm-field-sync " + $confirmFieldSync

    if(-not $chkSeries.IsChecked){
        $cmd = "abaqus python " + (Q $exportPy) +
               " --odb " + (Q $txtOdb.Text) +
               " --instance " + (Q $inst) +
               " --step " + (Q $cmbStep.SelectedItem.ToString()) +
               " --frame " + (FrameIndex $cmbFrame) +
               " --out " + (Q $txtOutput.Text) +
               " --fields " + (Q $fields) +
               $setArg + $bboxArg + $diffArg + $derivedArg + $policyArg
    }
    else{
        if(-not (WriteSelectionFile)){
            [Windows.MessageBox]::Show("No Step/Frame states selected.")
            return
        }

        $compatMode = 'fast'
        if($cmbCompatMode.SelectedItem){$compatMode=$cmbCompatMode.SelectedItem.Tag.ToString()}
        $writeMode = 'safe_copy'
        if($chkInPlace.IsChecked){
            if(-not (Test-Path $txtOutput.Text -PathType Leaf)){
                [Windows.MessageBox]::Show($(if($script:lang -eq 'zh'){'原位更新必须选择一个已经存在的 PVD。首次导出请取消此选项。'}else{'In-place update requires an existing PVD; uncheck for first export.'}))
                return
            }
            if($framePolicy -ne 'merge' -or $fieldPolicy -ne 'merge' -or $cleanupRemoved -ne 0){
                [Windows.MessageBox]::Show($(if($script:lang -eq 'zh'){'原位更新只允许 Frame Merge + Field Merge，且不能删除 VTU。'}else{'In-place update requires Frame Merge + Field Merge and no deletion.'}))
                return
            }
            if($compatMode -eq 'standard'){
                # Standard remains valid for already manifest-backed datasets.
                $stem=[System.IO.Path]::GetFileNameWithoutExtension($txtOutput.Text)
                $fd=Join-Path (Split-Path $txtOutput.Text -Parent) ($stem + '_frames')
                if(-not (Test-Path (Join-Path $fd '_ODB2VTUS_manifest.json'))){
                    [Windows.MessageBox]::Show($(if($script:lang -eq 'zh'){'无 Manifest 时请选择快速兼容或严格验证。'}else{'Choose Fast or Strict for a dataset without Manifest.'}))
                    return
                }
            }
            $note=if($script:lang -eq 'zh'){
                '将直接更新已有 VTU，原文件名和 PVD 路径不变。不复制到新目录。每帧使用同目录临时文件进行校验，随后原子替换；如异常终止会保留回滚硬链接及日志供恢复。请确保数据已经有独立备份。确定继续？'
            }else{
                'Update existing VTUs at their original paths. No migration folder. Each frame uses an adjacent temp file and atomic replacement; hardlink rollback aliases and a journal protect interruptions. Ensure you have an independent backup. Continue?'
            }
            if([Windows.MessageBox]::Show($note,'ODB2VTU-S - In-place update','YesNo','Warning') -ne 'Yes'){return}
            $writeMode = 'in_place'
        }
        # A missing Manifest in an early-version export is normal. Fast/strict
        # mode automatically creates a separately verified MIGRATED_SAFE copy.
        # Standard mode keeps the old provenance guard and adoption option.
        $adoptArg = ''
        if($compatMode -eq 'standard' -and (Test-Path $txtOutput.Text -PathType Leaf)){
            $targetPvdDir=Split-Path $txtOutput.Text -Parent
            $targetPvdStem=[System.IO.Path]::GetFileNameWithoutExtension($txtOutput.Text)
            $targetManifest=Join-Path (Join-Path $targetPvdDir ($targetPvdStem + '_frames')) '_ODB2VTUS_manifest.json'
            if(-not (Test-Path $targetManifest -PathType Leaf)){
                $info=if($script:lang -eq 'zh'){
                    '标准模式需要匹配的 Manifest；早期无 Manifest 数据推荐选快速兼容模式。是否选择已有原始 Manifest？'
                } else {'Standard mode requires Manifest. Use Fast mode for legacy data. Browse an original Manifest instead?'}
                if([Windows.MessageBox]::Show($info,'ODB2VTU-S','YesNo','Warning') -ne 'Yes'){return}
                $picker=New-Object Microsoft.Win32.OpenFileDialog
                $picker.Filter='Manifest JSON (*.json)|*.json'
                if($picker.ShowDialog() -ne $true){return}
                $adoptArg=' --adopt-manifest-path ' + (Q $picker.FileName)
            }
        }
        if($writeMode -eq 'safe_copy' -and $compatMode -ne 'standard' -and (Test-Path $txtOutput.Text -PathType Leaf)){
            $targetPvdDir=Split-Path $txtOutput.Text -Parent
            $targetPvdStem=[System.IO.Path]::GetFileNameWithoutExtension($txtOutput.Text)
            $targetManifest=Join-Path (Join-Path $targetPvdDir ($targetPvdStem + '_frames')) '_ODB2VTUS_manifest.json'
            if(-not (Test-Path $targetManifest -PathType Leaf)){
                if($framePolicy -ne 'merge' -or $fieldPolicy -ne 'merge' -or $cleanupRemoved -ne 0){
                    [Windows.MessageBox]::Show($(if($script:lang -eq 'zh'){'旧版兼容导出只允许 Frame Merge + Field Merge，且禁止删除文件。'}else{'Legacy compatibility requires Frame Merge + Field Merge with deletion disabled.'}))
                    return
                }
                $hint=if($script:lang -eq 'zh'){
                    '检测到无 Manifest 的早期数据。程序将核验后复制全部 PVD/VTU 至新 MIGRATED_SAFE 目录，并在那里追加字段。原目录只读。继续？'
                }else{'Legacy PVD without Manifest found. Verify/copy to NEW MIGRATED_SAFE folder, then append fields there. Originals stay read-only. Continue?'}
                if([Windows.MessageBox]::Show($hint,'ODB2VTU-S','YesNo','Warning') -ne 'Yes'){return}
            }
        }

        $cmd = "abaqus python " + (Q $seriesPy) +
               " --odb " + (Q $txtOdb.Text) +
               " --instance " + (Q $inst) +
               " --selection-file " + (Q $selectionFile) +
               " --out-pvd " + (Q $txtOutput.Text) +
               " --fields " + (Q $fields) +
               $setArg + $bboxArg + $diffArg + $derivedArg + $policyArg +
               " --frame-policy " + $framePolicy +
               " --cleanup-removed-frames " + $cleanupRemoved +
               " --confirm-frame-sync " + $confirmFrameSync +
               " --confirm-delete-files " + $confirmDeleteFiles +
               " --compatibility-mode " + $compatMode +
               " --write-mode " + $writeMode +
               $adoptArg
    }

    # Launch through a small progress wrapper. The banner appears before
    # Abaqus/Python starts, so long ODB initialization is not mistaken for a
    # blank or frozen console. The window stays open with an explicit status.
    $runnerPath = Join-Path $env:TEMP ("ODB2VTUS_Export_" + [Guid]::NewGuid().ToString("N") + ".cmd")
    $runnerLines = @(
        '@echo off'
        'title ODB2VTU-S Export - Active'
        'echo ============================================================'
        'echo ODB2VTU-S v0.2.1 - SAFE VTU / PVD export'
        'echo ============================================================'
        'echo Status: STARTING Abaqus Python'
        'echo Large ODB files may take time to open or read field arrays.'
        'echo Do NOT close this window while export is in progress.'
        'echo The backend will report Step/Frame and completed VTU files.'
        'echo ------------------------------------------------------------'
        'echo.'
        ('call ' + $cmd)
        'set "ODB2VTUS_RC=%errorlevel%"'
        'echo.'
        'if not "%ODB2VTUS_RC%"=="0" goto export_failed'
        'title ODB2VTU-S Export - SUCCESS'
        'echo ============================================================'
        'echo SUCCESS: export finished. You may close this window.'
        'echo ============================================================'
        'goto export_end'
        ':export_failed'
        'title ODB2VTU-S Export - FAILED'
        'echo ============================================================'
        'echo FAILED: backend returned error %ODB2VTUS_RC%.'
        'echo Review the messages above before closing this window.'
        'echo ============================================================'
        ':export_end'
    )
    [System.IO.File]::WriteAllLines($runnerPath, [string[]]$runnerLines, [System.Text.Encoding]::Default)
    Msg("Starting export; CMD will show progress immediately.")
    Msg("Output console remains open until you close it.")
    $txtStatus.Text = "Export running - see CMD status"
    Start-Process cmd.exe -ArgumentList "/k",(Q $runnerPath)
}


# ================================================================
# Field Extremum / Grain Analysis Page
# ================================================================
function ShowFieldAnalysisWindow {
    if(-not (Test-Path $txtOdb.Text)){
        [Windows.MessageBox]::Show("Select an ODB first.")
        return
    }
    if($global:meta -eq $null){ ReadMeta }
    if($global:meta -eq $null){ return }

    [xml]$axaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Field Extremum Analysis"
        Width="980" Height="720" MinWidth="820" MinHeight="600"
        WindowStartupLocation="CenterOwner" Background="#E2E2E2"
        FontFamily="Segoe UI" FontSize="12">
  <Window.Resources>
    <Style TargetType="TextBox"><Setter Property="Height" Value="25"/><Setter Property="Padding" Value="4,2"/><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#A6A6A6"/></Style>
    <Style TargetType="ComboBox"><Setter Property="Height" Value="25"/><Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#A6A6A6"/></Style>
    <Style TargetType="Button"><Setter Property="MinHeight" Value="25"/><Setter Property="Padding" Value="8,3"/><Setter Property="Background" Value="#E7E7E7"/><Setter Property="BorderBrush" Value="#999999"/></Style>
  </Window.Resources>
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#EBEBEB" BorderBrush="#B7B7B7" BorderThickness="0,0,0,1" Padding="6,4">
      <StackPanel Orientation="Horizontal">
        <Button x:Name="aBtnReadFields" Content="读取可分析变量 / Read Variables"/>
        <Button x:Name="aBtnRun" Content="运行分析 / Run Analysis" Margin="5,0,0,0" Background="#E2EEF8"/>
        <Button x:Name="aBtnOpen" Content="打开输出目录 / Open Folder" Margin="5,0,0,0"/>
      </StackPanel>
    </Border>
    <Grid Margin="8">
      <Grid.ColumnDefinitions><ColumnDefinition Width="400"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <GroupBox Header="数据状态 / Data State" Margin="0,0,0,7" Padding="8">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="100"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
              <TextBlock Grid.Row="0" Text="ODB" VerticalAlignment="Center"/><TextBox x:Name="aTxtOdb" Grid.Row="0" Grid.Column="1" IsReadOnly="True"/>
              <TextBlock Grid.Row="1" Text="Instance" VerticalAlignment="Center"/><ComboBox x:Name="aCmbInstance" Grid.Row="1" Grid.Column="1" Margin="0,3"/>
              <TextBlock Grid.Row="2" Text="Step" VerticalAlignment="Center"/><ComboBox x:Name="aCmbStep" Grid.Row="2" Grid.Column="1" Margin="0,3"/>
              <TextBlock Grid.Row="3" Text="Frame" VerticalAlignment="Center"/><ComboBox x:Name="aCmbFrame" Grid.Row="3" Grid.Column="1" Margin="0,3"/>
              <TextBlock Grid.Row="4" Text="Field" VerticalAlignment="Center"/><ComboBox x:Name="aCmbField" Grid.Row="4" Grid.Column="1" Margin="0,3" IsTextSearchEnabled="True"/>
            </Grid>
          </GroupBox>

          <GroupBox Header="区域 / Region" Margin="0,0,0,7" Padding="8">
            <StackPanel>
              <TextBlock Text="只分析晶粒单元；可选 Bounding Box：xmin,xmax,ymin,ymax,zmin,zmax" TextWrapping="Wrap" Foreground="#555"/>
              <TextBox x:Name="aTxtBBox" Margin="0,5,0,0"/>
            </StackPanel>
          </GroupBox>

          <GroupBox Header="晶粒排序 / Grain Ranking" Margin="0,0,0,7" Padding="8">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
              <TextBlock Grid.Row="0" Text="Top N grains" VerticalAlignment="Center"/><TextBox x:Name="aTxtTopN" Grid.Row="0" Grid.Column="1" Text="10"/>
              <TextBlock Grid.Row="1" Text="Rank statistic" VerticalAlignment="Center"/><ComboBox x:Name="aCmbRank" Grid.Row="1" Grid.Column="1" Margin="0,3"><ComboBoxItem Content="Mean" Tag="mean"/><ComboBoxItem Content="Maximum" Tag="max"/><ComboBoxItem Content="Minimum" Tag="min"/></ComboBox>
              <TextBlock Grid.Row="2" Text="Direction" VerticalAlignment="Center"/><ComboBox x:Name="aCmbDirection" Grid.Row="2" Grid.Column="1" Margin="0,3"><ComboBoxItem Content="Maximum" Tag="max"/><ComboBoxItem Content="Minimum" Tag="min"/></ComboBox>
              <TextBlock Grid.Row="3" Text="Extreme band (%)" VerticalAlignment="Center"/><TextBox x:Name="aTxtBand" Grid.Row="3" Grid.Column="1" Text="5" ToolTip="Percent of the full grain-statistic span from the selected extreme."/>
            </Grid>
          </GroupBox>

          <GroupBox Header="输出 / Output" Padding="8">
            <StackPanel>
              <CheckBox x:Name="aChkExportVtu"
                        Content="同时导出分析 VTU / Export analysis VTU"
                        IsChecked="True"
                        Margin="0,0,0,6"/>

              <Grid Margin="0,0,0,6">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="110"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="VTU范围 / Scope" VerticalAlignment="Center"/>
                <ComboBox x:Name="aCmbVtuScope" Grid.Column="1">
                  <ComboBoxItem Content="仅 Top N 晶粒 / Top N grains only" Tag="top"/>
                  <ComboBoxItem Content="仅极值范围晶粒 / Extreme-band grains only" Tag="band"/>
                  <ComboBoxItem Content="仅极值所在晶粒 / Extreme-value grain only" Tag="extreme"/>
                  <ComboBoxItem Content="全部分析晶粒 / All analyzed grains" Tag="all"/>
                </ComboBox>
              </Grid>

              <CheckBox x:Name="aChkSplitGrains"
                        Content="每个选中晶粒再单独导出 VTU / Split each selected grain"
                        IsChecked="False"
                        Margin="0,0,0,6"/>

              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="36"/></Grid.ColumnDefinitions>
                <TextBox x:Name="aTxtOut"/><Button x:Name="aBtnBrowseOut" Grid.Column="1" Content="..." Margin="4,0,0,0"/>
              </Grid>
              <TextBlock Text="默认只写出 Top N 晶粒的几何体；其他晶粒不会进入该 VTU。可切换为极值范围、单个极值晶粒或全部晶粒。"
                         Foreground="#555" TextWrapping="Wrap" Margin="0,6,0,0"/>
            </StackPanel>
          </GroupBox>
        </StackPanel>
      </ScrollViewer>

      <GridSplitter Grid.Column="1" Width="8" HorizontalAlignment="Stretch" Background="#B6B6B6"/>
      <Border Grid.Column="2" Background="White" BorderBrush="#AAAAAA" BorderThickness="1">
        <DockPanel>
          <Border DockPanel.Dock="Top" Background="#E3E3E3" BorderBrush="#AAAAAA" BorderThickness="0,0,0,1" Padding="7,4"><TextBlock Text="Analysis Log / 分析结果" FontWeight="SemiBold"/></Border>
          <TextBox x:Name="aTxtLog" IsReadOnly="True" BorderThickness="0" Height="Auto" MinHeight="120" VerticalAlignment="Stretch" VerticalContentAlignment="Top" AcceptsReturn="True" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" FontFamily="Consolas" Padding="8"/>
        </DockPanel>
      </Border>
    </Grid>
  </DockPanel>
</Window>
"@
    Localize-SubwindowXaml $axaml $script:lang
    $ar = New-Object System.Xml.XmlNodeReader $axaml
    $aw = [Windows.Markup.XamlReader]::Load($ar)
    $aw.Owner = $window
    foreach($n in @("aBtnReadFields","aBtnRun","aBtnOpen","aTxtOdb","aCmbInstance","aCmbStep","aCmbFrame","aCmbField","aTxtBBox","aTxtTopN","aCmbRank","aCmbDirection","aTxtBand","aChkExportVtu","aCmbVtuScope","aChkSplitGrains","aTxtOut","aBtnBrowseOut","aTxtLog")){
        Set-Variable -Name $n -Value $aw.FindName($n)
    }

    $aTxtOdb.Text = $txtOdb.Text
    $aTxtBBox.Text = $txtBBox.Text
    $aTxtOut.Text = Get-FieldOutputDirectory $txtOdb.Text
    foreach($n in $global:meta.instances.PSObject.Properties.Name){ [void]$aCmbInstance.Items.Add($n) }
    foreach($n in $global:meta.steps.PSObject.Properties.Name){ [void]$aCmbStep.Items.Add($n) }
    if($cmbInstance.SelectedItem){ $aCmbInstance.SelectedItem = $cmbInstance.SelectedItem.ToString() }
    if($aCmbInstance.SelectedIndex -lt 0 -and $aCmbInstance.Items.Count -gt 0){ $aCmbInstance.SelectedIndex=0 }
    if($cmbStep.SelectedItem){ $aCmbStep.SelectedItem = $cmbStep.SelectedItem.ToString() }
    if($aCmbStep.SelectedIndex -lt 0 -and $aCmbStep.Items.Count -gt 0){ $aCmbStep.SelectedIndex=0 }
    $aCmbRank.SelectedIndex=0; $aCmbDirection.SelectedIndex=0; $aCmbVtuScope.SelectedIndex=0

    function APopulateFrames {
        $aCmbFrame.Items.Clear()
        if($aCmbStep.SelectedItem -eq $null){ return }
        $sn=$aCmbStep.SelectedItem.ToString(); $nf=[int]$global:meta.steps.$sn.nframes
        for($i=0;$i -lt $nf;$i++){ [void]$aCmbFrame.Items.Add($i.ToString()) }
        if($aCmbFrame.Items.Count -gt 0){ $aCmbFrame.SelectedIndex=$aCmbFrame.Items.Count-1 }
    }
    APopulateFrames

    $aCmbStep.Add_SelectionChanged({ APopulateFrames })

    $aBtnBrowseOut.Add_Click({
        $d=New-Object System.Windows.Forms.FolderBrowserDialog
        $d.Description="选择场变量分析输出目录"
        if(Test-Path $aTxtOut.Text){ $d.SelectedPath=$aTxtOut.Text }
        if($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){ $aTxtOut.Text=$d.SelectedPath }
    })

    $aBtnOpen.Add_Click({ if(Test-Path $aTxtOut.Text){ Start-Process explorer.exe $aTxtOut.Text } })

    $aBtnReadFields.Add_Click({
        if($aCmbStep.SelectedItem -eq $null -or $aCmbFrame.SelectedItem -eq $null){ return }
        $cmd="abaqus python " + (Q $fieldsPy) + " --odb " + (Q $aTxtOdb.Text) + " --step " + (Q $aCmbStep.SelectedItem.ToString()) + " --frame " + $aCmbFrame.SelectedItem.ToString() + " --json " + (Q $analysisFieldsJson)
        $p=Start-Process cmd.exe -ArgumentList "/c",$cmd -Wait -PassThru
        if($p.ExitCode -ne 0 -or -not (Test-Path $analysisFieldsJson)){ [Windows.MessageBox]::Show("Field list read failed."); return }
        $j=Get-Content $analysisFieldsJson -Raw | ConvertFrom-Json
        $aCmbField.Items.Clear(); $hasS=$false
        foreach($f in $j.fields){
            if($f.name -eq "S"){ $hasS=$true }
            if($f.components.Count -eq 0){ [void]$aCmbField.Items.Add($f.name) }
            else { foreach($c in $f.components){ [void]$aCmbField.Items.Add($c) } }
        }
        if($hasS){ [void]$aCmbField.Items.Insert(0,"Mises") }
        if($aCmbField.Items.Count -gt 0){ $aCmbField.SelectedIndex=0 }
        $aTxtLog.AppendText("Variables ready: " + $aCmbField.Items.Count + "`r`n")
    })

    $aBtnRun.Add_Click({
        if($aCmbField.SelectedItem -eq $null){ [Windows.MessageBox]::Show("Read and select a field first."); return }
        $rank=$aCmbRank.SelectedItem.Tag.ToString(); $dir=$aCmbDirection.SelectedItem.Tag.ToString()
        $cmd="abaqus python " + (Q $analysisPy) + " --odb " + (Q $aTxtOdb.Text) + " --instance " + (Q $aCmbInstance.SelectedItem.ToString()) + " --step " + (Q $aCmbStep.SelectedItem.ToString()) + " --frame " + $aCmbFrame.SelectedItem.ToString() + " --field-token " + (Q $aCmbField.SelectedItem.ToString()) + " --top-n " + $aTxtTopN.Text + " --rank-stat " + $rank + " --direction " + $dir + " --band-percent " + $aTxtBand.Text + " --outdir " + (Q $aTxtOut.Text)
        if(-not [string]::IsNullOrWhiteSpace($aTxtBBox.Text)){ $cmd += " --bbox " + (Q $aTxtBBox.Text) }
        if($aChkExportVtu.IsChecked){
            $cmd += " --export-vtu 1"
            $scope=$aCmbVtuScope.SelectedItem.Tag.ToString()
            $cmd += " --vtu-scope " + $scope
            if($aChkSplitGrains.IsChecked){ $cmd += " --split-grains 1" } else { $cmd += " --split-grains 0" }
        } else {
            $cmd += " --export-vtu 0"
        }
        $aTxtLog.Text="Running...`r`n" + $cmd + "`r`n`r`n"
        $out = & cmd.exe /c $cmd 2>&1
        $aTxtLog.AppendText(($out -join "`r`n") + "`r`n")
    })

    [void]$aw.ShowDialog()
}


# ================================================================
# Curve Data Page
# ================================================================
function ShowCurveDataWindow {
    [xml]$curveXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Curve Data"
        Width="1120" Height="760"
        MinWidth="900" MinHeight="620"
        WindowStartupLocation="CenterOwner"
        Background="#E2E2E2"
        FontFamily="Segoe UI"
        FontSize="12">

    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#A6A6A6"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="4,2"/>
            <Setter Property="Height" Value="25"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#A6A6A6"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Height" Value="25"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#E7E7E7"/>
            <Setter Property="BorderBrush" Value="#999999"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,3"/>
            <Setter Property="MinHeight" Value="25"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Margin" Value="0,2"/>
        </Style>
        <Style TargetType="GroupBox">
            <Setter Property="Margin" Value="6"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="BorderBrush" Value="#AAAAAA"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
    </Window.Resources>

    <DockPanel>
        <Border DockPanel.Dock="Top"
                Background="#E9E9E9"
                BorderBrush="#B6B6B6"
                BorderThickness="0,0,0,1"
                Padding="6,4">
            <StackPanel Orientation="Horizontal">
                <Button x:Name="cBtnReadMeta" Content="Read History Metadata"/>
                <Button x:Name="cBtnExport" Content="Export CSV" Margin="5,0,0,0" Background="#E2EEF8"/>
                <Button x:Name="cBtnFriction" Content="Friction CSV (ALL/NORMAL/TANGENTIAL/DIAGNOSTIC)" Margin="5,0,0,0"/>
                <Button x:Name="cBtnOpenFolder" Content="Open Output Folder" Margin="5,0,0,0"/>
            </StackPanel>
        </Border>

        <StatusBar DockPanel.Dock="Bottom"
                   Height="25"
                   Background="#E7E7E7"
                   BorderBrush="#B5B5B5"
                   BorderThickness="0,1,0,0">
            <StatusBarItem>
                <TextBlock x:Name="cStatus" Text="Ready"/>
            </StatusBarItem>
        </StatusBar>

        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="390" MinWidth="330"/>
                <ColumnDefinition Width="6"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <ScrollViewer Grid.Column="0"
                          VerticalScrollBarVisibility="Auto"
                          Background="#F2F2F2">
                <StackPanel Margin="5">

                    <GroupBox x:Name="cGrpSource" Header="Source">
                        <StackPanel>
                            <TextBlock x:Name="cLblOdb" Text="ODB File"/>
                            <Grid Margin="0,3,0,6">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="36"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="cTxtOdb"/>
                                <Button x:Name="cBtnBrowseOdb" Grid.Column="1" Content="..." Margin="4,0,0,0"/>
                            </Grid>
                        </StackPanel>
                    </GroupBox>

                    <GroupBox x:Name="cGrpHistory" Header="History Selection">
                        <StackPanel>
                            <TextBlock x:Name="cLblSteps" Text="Steps (Ctrl/Shift multi-select)"/>
                            <ListBox x:Name="cLstSteps"
                                     Height="145"
                                     SelectionMode="Extended"
                                     Background="White"
                                     BorderBrush="#A6A6A6"
                                     BorderThickness="1"
                                     Margin="0,3,0,7"/>

                            <TextBlock x:Name="cLblRegion" Text="History Region / Section"/>
                            <ComboBox x:Name="cCmbRegion"
                                      Margin="0,3,0,5"
                                      IsTextSearchEnabled="True"/>

                            <Grid Margin="0,0,0,4">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="72"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <TextBlock x:Name="cLblRegionFilter"
                                           Text="Filter"
                                           VerticalAlignment="Center"/>

                                <TextBox x:Name="cTxtRegionFilter"
                                         Grid.Column="1"
                                         ToolTip="Filter History Region / Section name or description"/>
                            </Grid>

                            <TextBlock x:Name="cLblNodeLocator"
                                       Text="Node locator (optional)"
                                       FontWeight="SemiBold"
                                       Margin="0,4,0,2"/>

                            <Grid Margin="0,0,0,7">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="72"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="72"/>
                                </Grid.ColumnDefinitions>

                                <TextBlock x:Name="cLblNodeLabel"
                                           Text="Node ID"
                                           VerticalAlignment="Center"/>

                                <TextBox x:Name="cTxtNodeLabel"
                                         Grid.Column="1"
                                         ToolTip="Enter a node label, e.g. 12345"/>

                                <Button x:Name="cBtnFindNode"
                                        Grid.Column="2"
                                        Content="Find"
                                        Margin="4,0,0,0"/>
                            </Grid>

                            <TextBlock x:Name="cLblPreset" Text="Curve Preset"/>
                            <ComboBox x:Name="cCmbPreset" Margin="0,3,0,7"/>
                        </StackPanel>
                    </GroupBox>

                    <GroupBox x:Name="cGrpXY" Header="X / Y">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition/><RowDefinition/>
                                <RowDefinition/><RowDefinition/>
                            </Grid.RowDefinitions>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="82"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <TextBlock x:Name="cLblX" Grid.Row="0" Text="X Source" VerticalAlignment="Center"/>
                            <ComboBox x:Name="cCmbX" Grid.Row="0" Grid.Column="1" Margin="0,2"/>

                            <TextBlock x:Name="cLblY" Grid.Row="1" Text="Y Source" VerticalAlignment="Center"/>
                            <ComboBox x:Name="cCmbY" Grid.Row="1" Grid.Column="1" Margin="0,2"/>

                            <CheckBox x:Name="cChkAbsX" Grid.Row="2" Grid.Column="1" Content="Absolute X"/>
                            <CheckBox x:Name="cChkAbsY" Grid.Row="3" Grid.Column="1" Content="Absolute Y"/>
                        </Grid>
                    </GroupBox>

                    <GroupBox x:Name="cGrpTransform" Header="Transform">
                        <StackPanel>
                            <Grid>
                                <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="55"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="58"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <TextBlock Grid.Row="0" Grid.Column="0" Text="X ×" VerticalAlignment="Center"/>
                                <TextBox x:Name="cTxtXScale" Grid.Row="0" Grid.Column="1" Text="1.0" Margin="0,2"/>
                                <TextBlock Grid.Row="0" Grid.Column="2" Text="X +" VerticalAlignment="Center" Margin="8,0,0,0"/>
                                <TextBox x:Name="cTxtXOffset" Grid.Row="0" Grid.Column="3" Text="0.0" Margin="0,2"/>

                                <TextBlock Grid.Row="1" Grid.Column="0" Text="Y ×" VerticalAlignment="Center"/>
                                <TextBox x:Name="cTxtYScale" Grid.Row="1" Grid.Column="1" Text="1.0" Margin="0,2"/>
                                <TextBlock Grid.Row="1" Grid.Column="2" Text="Y +" VerticalAlignment="Center" Margin="8,0,0,0"/>
                                <TextBox x:Name="cTxtYOffset" Grid.Row="1" Grid.Column="3" Text="0.0" Margin="0,2"/>
                            </Grid>

                            <CheckBox x:Name="cChkDedupe"
                                      Content="Remove duplicated Step-boundary point"
                                      IsChecked="True"
                                      Margin="0,6,0,0"/>
                        </StackPanel>
                    </GroupBox>

                </StackPanel>
            </ScrollViewer>

            <GridSplitter Grid.Column="1"
                          Width="6"
                          ResizeDirection="Columns"
                          ResizeBehavior="PreviousAndNext"
                          Cursor="SizeWE"
                          Background="#B2B2B2"/>

            <Grid Grid.Column="2" Background="#D7D7D7">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="6"/>
                    <RowDefinition Height="200"/>
                </Grid.RowDefinitions>

                <GroupBox Grid.Row="0" Header="Output" Margin="6,6,6,0">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="95"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="36"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.ColumnSpan="3">
                            <StackPanel Orientation="Horizontal" Margin="0,0,0,5">
                                <CheckBox x:Name="cChkAutoOutput"
                                          Content="Auto-match ODB output folder"
                                          IsChecked="True"
                                          VerticalAlignment="Center"/>
                                <Button x:Name="cBtnChooseOutputFolder"
                                        Content="Select Output Folder..."
                                        Margin="12,0,0,0"/>
                            </StackPanel>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="95"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="36"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock x:Name="cLblOutput" Text="CSV File" VerticalAlignment="Center"/>
                                <TextBox x:Name="cTxtOutput" Grid.Column="1"/>
                                <Button x:Name="cBtnBrowseOutput" Grid.Column="2" Content="..." Margin="4,0,0,0"/>
                            </Grid>
                        </StackPanel>
                    </Grid>
                </GroupBox>

                <Border Grid.Row="1"
                        Background="White"
                        BorderBrush="#A7A7A7"
                        BorderThickness="1"
                        Margin="6">
                    <DockPanel>
                        <Border DockPanel.Dock="Top"
                                Background="#E3E3E3"
                                BorderBrush="#A7A7A7"
                                BorderThickness="0,0,0,1"
                                Padding="7,4">
                            <TextBlock x:Name="cHdrSummary" Text="Curve Summary" FontWeight="SemiBold"/>
                        </Border>
                        <TextBox x:Name="cTxtSummary"
                                 Height="Auto"
                                 VerticalAlignment="Stretch"
                                 IsReadOnly="True"
                                 BorderThickness="0"
                                 Background="White"
                                 AcceptsReturn="True"
                                 TextWrapping="Wrap"
                                 VerticalScrollBarVisibility="Auto"
                                 FontFamily="Consolas"
                                 FontSize="12"
                                 Padding="8"/>
                    </DockPanel>
                </Border>

                <GridSplitter Grid.Row="2" Height="6" Background="#B2B2B2"/>

                <Border Grid.Row="3"
                        Background="White"
                        BorderBrush="#A7A7A7"
                        BorderThickness="1"
                        Margin="6,0,6,6">
                    <DockPanel>
                        <Border DockPanel.Dock="Top"
                                Background="#E3E3E3"
                                BorderBrush="#A7A7A7"
                                BorderThickness="0,0,0,1"
                                Padding="7,4">
                            <TextBlock x:Name="cHdrMessages" Text="Messages" FontWeight="SemiBold"/>
                        </Border>
                        <TextBox x:Name="cTxtMessages"
                                 Height="Auto"
                                 VerticalAlignment="Stretch"
                                 IsReadOnly="True"
                                 BorderThickness="0"
                                 Background="White"
                                 AcceptsReturn="True"
                                 TextWrapping="NoWrap"
                                 VerticalScrollBarVisibility="Auto"
                                 HorizontalScrollBarVisibility="Auto"
                                 FontFamily="Consolas"
                                 FontSize="11"
                                 Padding="7"/>
                    </DockPanel>
                </Border>
            </Grid>
        </Grid>
    </DockPanel>
</Window>
"@

    $curveReader = New-Object System.Xml.XmlNodeReader $curveXaml
    $cw = [Windows.Markup.XamlReader]::Load($curveReader)
    $cw.Owner = $window

    $cnames = @(
        "cBtnReadMeta","cBtnExport","cBtnFriction","cBtnOpenFolder","cStatus",
        "cGrpSource","cLblOdb","cTxtOdb","cBtnBrowseOdb",
        "cGrpHistory","cLblSteps","cLstSteps","cLblRegion","cCmbRegion","cLblRegionFilter","cTxtRegionFilter","cLblNodeLocator","cLblNodeLabel","cTxtNodeLabel","cBtnFindNode","cLblPreset","cCmbPreset",
        "cGrpXY","cLblX","cCmbX","cLblY","cCmbY","cChkAbsX","cChkAbsY",
        "cGrpTransform","cTxtXScale","cTxtXOffset","cTxtYScale","cTxtYOffset","cChkDedupe",
        "cChkAutoOutput","cBtnChooseOutputFolder","cLblOutput","cTxtOutput","cBtnBrowseOutput",
        "cHdrSummary","cTxtSummary","cHdrMessages","cTxtMessages"
    )

    foreach($n in $cnames){
        Set-Variable -Name $n -Value $cw.FindName($n) -Scope Local
    }

    $script:curveMetaV175 = $null
    $COF = "COF=|RF1|/|CF2|"

    function CMsg([string]$s){
        $cTxtMessages.AppendText("["+(Get-Date -Format "HH:mm:ss")+"] "+$s+"`r`n")
        $cTxtMessages.ScrollToEnd()
    }

    function Get-JsonPropertyValue($obj,[string]$name){
        if($obj -eq $null){ return $null }
        foreach($p in $obj.PSObject.Properties){
            if($p.Name -eq $name){ return $p.Value }
        }
        return $null
    }

    function Get-StepInfo([string]$stepName){
        if($script:curveMetaV175 -eq $null){ return $null }
        return Get-JsonPropertyValue $script:curveMetaV175.steps $stepName
    }

    function Get-RegionInfo($stepInfo,[string]$regionName){
        if($stepInfo -eq $null){ return $null }
        return Get-JsonPropertyValue $stepInfo.regions $regionName
    }

    function SelectedCurveSteps {
        $r = New-Object System.Collections.Generic.List[string]
        foreach($item in $cLstSteps.SelectedItems){
            $r.Add($item.ToString())
        }
        return $r
    }

    $script:allCommonRegions = @()

    function SelectedRegionName {
        if($cCmbRegion.SelectedItem -eq $null){ return "" }
        $display = $cCmbRegion.SelectedItem.ToString()

        # Display syntax:
        # RegionName
        # or RegionName  ::  Description
        $idx = $display.IndexOf("  ::  ")
        if($idx -gt 0){ return $display.Substring(0,$idx) }
        return $display
    }

    function RegionDisplayText([string]$name,$info){
        $desc = ""
        if($info -ne $null){
            try{ $desc = [string]$info.description }catch{}
        }

        if([string]::IsNullOrWhiteSpace($desc) -or $desc -eq $name){
            return $name
        }
        return $name + "  ::  " + $desc
    }

    function ApplyRegionFilter {
        $oldRegion = SelectedRegionName
        $cCmbRegion.Items.Clear()

        $filter = $cTxtRegionFilter.Text.Trim().ToLower()

        foreach($entry in $script:allCommonRegions){
            $display = $entry.Display

            if(
                [string]::IsNullOrWhiteSpace($filter) -or
                $display.ToLower().Contains($filter)
            ){
                [void]$cCmbRegion.Items.Add($display)
            }
        }

        if($cCmbRegion.Items.Count -eq 0){ return }

        # Restore previous region if it survives filtering.
        if(-not [string]::IsNullOrWhiteSpace($oldRegion)){
            for($i=0;$i -lt $cCmbRegion.Items.Count;$i++){
                $d = $cCmbRegion.Items[$i].ToString()
                $name = $d
                $idx = $d.IndexOf("  ::  ")
                if($idx -gt 0){ $name = $d.Substring(0,$idx) }

                if($name -eq $oldRegion){
                    $cCmbRegion.SelectedIndex = $i
                    return
                }
            }
        }

        # Otherwise prefer RP / rigid-body region.
        for($i=0;$i -lt $cCmbRegion.Items.Count;$i++){
            $u = $cCmbRegion.Items[$i].ToString().ToUpper()
            if($u.Contains("RIGID") -or $u.Contains("RP")){
                $cCmbRegion.SelectedIndex = $i
                return
            }
        }

        $cCmbRegion.SelectedIndex = 0
    }

    function RefreshCommonRegions {
        $script:allCommonRegions = @()
        $cCmbRegion.Items.Clear()

        $steps = SelectedCurveSteps
        if($steps.Count -eq 0 -or $script:curveMetaV175 -eq $null){ return }

        $common = $null

        foreach($s in $steps){
            $si = Get-StepInfo $s
            if($si -eq $null){ continue }

            $names = @($si.regions.PSObject.Properties.Name)

            if($common -eq $null){
                $common = New-Object System.Collections.Generic.HashSet[string]
                foreach($x in $names){ [void]$common.Add($x) }
            } else {
                $keep = @()
                foreach($x in $common){
                    if($names -contains $x){ $keep += $x }
                }

                $common.Clear()
                foreach($x in $keep){ [void]$common.Add($x) }
            }
        }

        if($common -eq $null){ return }

        $firstStepInfo = Get-StepInfo $steps[0]

        foreach($x in ($common | Sort-Object)){
            $ri = Get-RegionInfo $firstStepInfo $x

            $script:allCommonRegions += [PSCustomObject]@{
                Name=$x
                Info=$ri
                Display=(RegionDisplayText $x $ri)
            }
        }

        ApplyRegionFilter

        if($script:allCommonRegions.Count -eq 0){
            CMsg("No common History Region / Section exists across the selected Steps.")
            CMsg("Try selecting fewer Steps, or verify that the same History Output Region exists in each Step.")
        }
    }

    function SelectRegionByName([string]$regionName){
        for($i=0;$i -lt $cCmbRegion.Items.Count;$i++){
            $d = $cCmbRegion.Items[$i].ToString()
            $name = $d
            $idx = $d.IndexOf("  ::  ")
            if($idx -gt 0){ $name = $d.Substring(0,$idx) }

            if($name -eq $regionName){
                $cCmbRegion.SelectedIndex = $i
                return $true
            }
        }

        # The region may be hidden by a current text filter.
        $cTxtRegionFilter.Text = ""
        ApplyRegionFilter

        for($i=0;$i -lt $cCmbRegion.Items.Count;$i++){
            $d = $cCmbRegion.Items[$i].ToString()
            $name = $d
            $idx = $d.IndexOf("  ::  ")
            if($idx -gt 0){ $name = $d.Substring(0,$idx) }

            if($name -eq $regionName){
                $cCmbRegion.SelectedIndex = $i
                return $true
            }
        }

        return $false
    }

    function FindNodeRegion {
        $needle = $cTxtNodeLabel.Text.Trim()
        if([string]::IsNullOrWhiteSpace($needle)){ return }

        $matches = @()

        foreach($entry in $script:allCommonRegions){
            $ri = $entry.Info
            $hit = $false

            try{
                if($ri.node_label -ne $null -and ([string]$ri.node_label) -eq $needle){
                    $hit = $true
                }
            }catch{}

            if(-not $hit){
                $u = $entry.Display.ToUpper()

                if(
                    $u.Contains("." + $needle.ToUpper()) -or
                    $u.Contains(" " + $needle.ToUpper())
                ){
                    $hit = $true
                }
            }

            if($hit){ $matches += $entry }
        }

        if($matches.Count -eq 0){
            CMsg("Node " + $needle + " was not found in the available History Regions.")
            CMsg("A node can be selected only when Abaqus actually stored History Output for that node.")
            return
        }

        [void](SelectRegionByName $matches[0].Name)
        CMsg("Node located in History Region: " + $matches[0].Name)
    }

    function RefreshCommonVariables {
        $cCmbX.Items.Clear()
        $cCmbY.Items.Clear()

        $steps = SelectedCurveSteps
        if($steps.Count -eq 0 -or $cCmbRegion.SelectedItem -eq $null){ return }

        $regionName = SelectedRegionName
        $common = $null

        foreach($s in $steps){
            $ri = Get-RegionInfo (Get-StepInfo $s) $regionName
            if($ri -eq $null){ return }

            $vars = @($ri.variables)

            if($common -eq $null){
                $common = New-Object System.Collections.Generic.HashSet[string]
                foreach($x in $vars){ [void]$common.Add($x) }
            } else {
                $keep = @()
                foreach($x in $common){
                    if($vars -contains $x){ $keep += $x }
                }
                $common.Clear()
                foreach($x in $keep){ [void]$common.Add($x) }
            }
        }

        [void]$cCmbX.Items.Add("StepTime")
        [void]$cCmbX.Items.Add("GlobalTime")

        if($common -ne $null){
            foreach($v in ($common | Sort-Object)){
                [void]$cCmbX.Items.Add($v)
                [void]$cCmbY.Items.Add($v)
            }

            if(($common -contains "RF1") -and ($common -contains "CF2")){
                [void]$cCmbY.Items.Add($COF)
            }
        }

        if($cCmbX.Items.Count -gt 0){ $cCmbX.SelectedIndex = 0 }
        if($cCmbY.Items.Count -gt 0){ $cCmbY.SelectedIndex = 0 }

        ApplyCurvePreset
    }

    function SelectComboValue($combo,[string]$value){
        for($i=0;$i -lt $combo.Items.Count;$i++){
            if($combo.Items[$i].ToString() -eq $value){
                $combo.SelectedIndex = $i
                return $true
            }
        }
        return $false
    }

    function ApplyCurvePreset {
        if($cCmbPreset.SelectedItem -eq $null){ return }
        $p = $cCmbPreset.SelectedItem.ToString()

        $cChkAbsX.IsChecked = $false
        $cChkAbsY.IsChecked = $false

        switch($p){
            "RF1-U1" {
                [void](SelectComboValue $cCmbX "U1")
                [void](SelectComboValue $cCmbY "RF1")
            }
            "CF2-U2" {
                [void](SelectComboValue $cCmbX "U2")
                [void](SelectComboValue $cCmbY "CF2")
                $cChkAbsY.IsChecked = $true
            }
            "RF2-U2" {
                [void](SelectComboValue $cCmbX "U2")
                [void](SelectComboValue $cCmbY "RF2")
            }
            "COF-Time" {
                [void](SelectComboValue $cCmbX "GlobalTime")
                [void](SelectComboValue $cCmbY $COF)
            }
            "COF-U1" {
                [void](SelectComboValue $cCmbX "U1")
                [void](SelectComboValue $cCmbY $COF)
            }
            "U2-Time" {
                [void](SelectComboValue $cCmbX "GlobalTime")
                [void](SelectComboValue $cCmbY "U2")
            }
        }

        UpdateCurveSummary
    }

    function UpdateCurveSummary {
        $steps = SelectedCurveSteps
        $s = ""

        $s += "ODB: " + $cTxtOdb.Text + "`r`n"
        $s += "Steps: " + $steps.Count + "`r`n"
        foreach($st in $steps){ $s += "  " + $st + "`r`n" }

        $s += "Region: " + ($(if($cCmbRegion.SelectedItem){(SelectedRegionName)}else{"-"})) + "`r`n"
        $s += "Preset: " + ($(if($cCmbPreset.SelectedItem){$cCmbPreset.SelectedItem}else{"-"})) + "`r`n"
        $s += "X: " + ($(if($cCmbX.SelectedItem){$cCmbX.SelectedItem}else{"-"})) + "`r`n"
        $s += "Y: " + ($(if($cCmbY.SelectedItem){$cCmbY.SelectedItem}else{"-"})) + "`r`n"
        $s += "|X|: " + $cChkAbsX.IsChecked + "    |Y|: " + $cChkAbsY.IsChecked + "`r`n"
        $s += "X scale/offset: " + $cTxtXScale.Text + " / " + $cTxtXOffset.Text + "`r`n"
        $s += "Y scale/offset: " + $cTxtYScale.Text + " / " + $cTxtYOffset.Text + "`r`n"
        if($cChkAutoOutput.IsChecked){
            $s += "Output mode: Auto -> ODB2VTU_Output`r`n"
        } else {
            $s += "Output mode: Custom folder -> " + $script:customCurveOutputDir + "`r`n"
        }
        $s += "Output: " + $cTxtOutput.Text

        $cTxtSummary.Text = $s
    }

    function Get-CurveOutputDirectory([string]$odbPath){
        if($cChkAutoOutput.IsChecked){
            return Get-AutoOutputDirectory $odbPath
        }

        if(-not [string]::IsNullOrWhiteSpace($script:customCurveOutputDir)){
            if(-not (Test-Path $script:customCurveOutputDir)){
                New-Item -ItemType Directory -Path $script:customCurveOutputDir -Force | Out-Null
            }
            return $script:customCurveOutputDir
        }

        return Get-AutoOutputDirectory $odbPath
    }

    function Set-CurveOutputPath([string]$odbPath){
        if([string]::IsNullOrWhiteSpace($odbPath)){ return }

        $outDir = Get-CurveOutputDirectory $odbPath
        if([string]::IsNullOrWhiteSpace($outDir)){ return }

        $stem = [IO.Path]::GetFileNameWithoutExtension($odbPath)
        $cTxtOutput.Text = Join-Path $outDir ($stem + "_curve.csv")
    }

    function Choose-CurveOutputFolder {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "选择曲线输出文件夹 / Select curve output folder"

        if(-not [string]::IsNullOrWhiteSpace($script:customCurveOutputDir) -and (Test-Path $script:customCurveOutputDir)){
            $dlg.SelectedPath = $script:customCurveOutputDir
        }
        elseif(-not [string]::IsNullOrWhiteSpace($cTxtOdb.Text) -and (Test-Path $cTxtOdb.Text)){
            $dlg.SelectedPath = Split-Path $cTxtOdb.Text -Parent
        }

        if($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){
            $script:customCurveOutputDir = $dlg.SelectedPath
            $cChkAutoOutput.IsChecked = $false
            Set-CurveOutputPath $cTxtOdb.Text
            UpdateCurveSummary
        }
    }

    function CurveReadMeta {
        if(-not (Test-Path $cTxtOdb.Text)){ return }

        $cmd = "abaqus python " + (Q $curveMetaPy) +
               " --odb " + (Q $cTxtOdb.Text) +
               " --json " + (Q $curveMetaJson)

        CMsg($cmd)
        $cStatus.Text = "Reading history metadata..."

        $p = Start-Process cmd.exe -ArgumentList "/c",$cmd -Wait -PassThru

        if($p.ExitCode -ne 0 -or -not (Test-Path $curveMetaJson)){
            $cStatus.Text = "History metadata failed"
            return
        }

        $script:curveMetaV175 = Get-Content $curveMetaJson -Raw | ConvertFrom-Json

        $cLstSteps.Items.Clear()
        foreach($s in $script:curveMetaV175.steps.PSObject.Properties.Name){
            [void]$cLstSteps.Items.Add($s)
        }

        if($cLstSteps.Items.Count -gt 0){
            $cLstSteps.SelectedIndex = 0
            RefreshCommonRegions
        }

        $stem = [IO.Path]::GetFileNameWithoutExtension($cTxtOdb.Text)
        if([string]::IsNullOrWhiteSpace($cTxtOutput.Text)){
            Set-CurveOutputPath $cTxtOdb.Text
        }

        $cStatus.Text = "History metadata ready"
        CMsg("History metadata ready.")
        CMsg("History Regions for current Step selection: " + $script:allCommonRegions.Count)
        CMsg("Select one or more Steps. Then choose a History Region / Section.")
        CMsg("Node search is optional and only locates an existing History Region; it does not replace Region / Section selection.")
        UpdateCurveSummary
    }

    function CurveExport {
        $steps = SelectedCurveSteps

        if($steps.Count -eq 0){ return }
        if($cCmbRegion.SelectedItem -eq $null){ return }
        if($cCmbX.SelectedItem -eq $null -or $cCmbY.SelectedItem -eq $null){ return }
        if([string]::IsNullOrWhiteSpace($cTxtOutput.Text)){ return }

        [System.IO.File]::WriteAllLines(
            $curveStepsFile,
            $steps,
            (New-Object System.Text.UTF8Encoding($true))
        )

        $xabs = 0; if($cChkAbsX.IsChecked){ $xabs = 1 }
        $yabs = 0; if($cChkAbsY.IsChecked){ $yabs = 1 }
        $dedupe = 0; if($cChkDedupe.IsChecked){ $dedupe = 1 }

        $xs = 1.0; $ys = 1.0; $xo = 0.0; $yo = 0.0
        if(-not [double]::TryParse($cTxtXScale.Text,[ref]$xs)){ return }
        if(-not [double]::TryParse($cTxtYScale.Text,[ref]$ys)){ return }
        if(-not [double]::TryParse($cTxtXOffset.Text,[ref]$xo)){ return }
        if(-not [double]::TryParse($cTxtYOffset.Text,[ref]$yo)){ return }

        $cmd = "abaqus python " + (Q $curveExportPy) +
               " --odb " + (Q $cTxtOdb.Text) +
               " --steps-file " + (Q $curveStepsFile) +
               " --region " + (Q (SelectedRegionName)) +
               " --xsource " + (Q $cCmbX.SelectedItem.ToString()) +
               " --ysource " + (Q $cCmbY.SelectedItem.ToString()) +
               " --out " + (Q $cTxtOutput.Text) +
               " --x-abs " + $xabs +
               " --y-abs " + $yabs +
               " --x-scale " + $xs +
               " --y-scale " + $ys +
               " --x-offset " + $xo +
               " --y-offset " + $yo +
               " --dedupe-boundary " + $dedupe

        CMsg($cmd)
        $cStatus.Text = "Curve export running..."
        Start-Process cmd.exe -ArgumentList "/k",$cmd
    }

    # Presets
    foreach($p in @("Custom","RF1-U1","CF2-U2","RF2-U2","COF-Time","COF-U1","U2-Time")){
        [void]$cCmbPreset.Items.Add($p)
    }
    $cCmbPreset.SelectedIndex = 0

    # Follow current main ODB.
    $cTxtOdb.Text = $txtOdb.Text
    if(-not [string]::IsNullOrWhiteSpace($cTxtOdb.Text)){
        Set-CurveOutputPath $cTxtOdb.Text
    }

    # Minimal bilingual labels, based on current main language.
    if($script:lang -eq "zh"){
        $cw.Title = "曲线数据"
        $cBtnReadMeta.Content = "读取 History 元数据"
        $cBtnExport.Content = "导出 CSV"
        $cBtnFriction.Content = "导出摩擦专用 CSV（四类文件）"
        $cBtnOpenFolder.Content = "打开输出文件夹"
        $cGrpSource.Header = "数据源"
        $cLblOdb.Text = "ODB 文件"
        $cGrpHistory.Header = "History 选择"
        $cLblSteps.Text = "分析步（Ctrl/Shift 多选）"
        $cLblRegion.Text = "History 区域 / Section"
        $cLblRegionFilter.Text = "区域筛选"
        $cLblNodeLocator.Text = "节点定位（可选）"
        $cLblNodeLabel.Text = "节点编号"
        $cBtnFindNode.Content = "查找"
        $cLblPreset.Text = "曲线预设"
        $cGrpXY.Header = "X / Y 数据"
        $cLblX.Text = "X 数据"
        $cLblY.Text = "Y 数据"
        $cChkAbsX.Content = "X 取绝对值"
        $cChkAbsY.Content = "Y 取绝对值"
        $cGrpTransform.Header = "数据变换"
        $cChkDedupe.Content = "去除重复的分析步边界点"
        $cChkAutoOutput.Content = "自动匹配 ODB 输出目录"
        $cBtnChooseOutputFolder.Content = "选择输出文件夹..."
        $cLblOutput.Text = "CSV 文件"
        $cHdrSummary.Text = "曲线摘要"
        $cHdrMessages.Text = "输出消息"
    }

    # Events
    $cBtnBrowseOdb.Add_Click({
        $d = New-Object Microsoft.Win32.OpenFileDialog
        $d.Filter = "Abaqus ODB (*.odb)|*.odb"
        if($d.ShowDialog()){
            $cTxtOdb.Text = $d.FileName
            $stem = [IO.Path]::GetFileNameWithoutExtension($d.FileName)
            Set-CurveOutputPath $d.FileName
            UpdateCurveSummary
        }
    })

    $cBtnReadMeta.Add_Click({ CurveReadMeta })
    $cBtnExport.Add_Click({ CurveExport })
    $cBtnFriction.Add_Click({
        if(-not (Test-Path -LiteralPath $cTxtOdb.Text -PathType Leaf)) {
            [Windows.MessageBox]::Show($(if($script:lang -eq 'zh'){'请先选择有效的 ODB 文件。'}else{'Select a valid ODB first.'}))
            return
        }
        $backend = Join-Path $scriptDir 'abaqus_postprocess_master.py'
        if(-not (Test-Path -LiteralPath $backend)) { [Windows.MessageBox]::Show('History backend not found.'); return }
        $outroot = if($cChkAutoOutput.IsChecked) { Split-Path -Parent $cTxtOdb.Text } else { Get-CurveOutputDirectory $cTxtOdb.Text }
        $cmd = 'abaqus python ' + (Q $backend) + ' --operation history --odb ' + (Q $cTxtOdb.Text) + ' --outroot ' + (Q $outroot)
        CMsg('Friction history exporter: ' + $cmd)
        $cStatus.Text = $(if($script:lang -eq 'zh'){'正在导出摩擦专用曲线...'}else{'Exporting friction-specific curves...'})
        Start-Process -FilePath 'cmd.exe' -ArgumentList @('/k', $cmd) | Out-Null
    })

    $cBtnOpenFolder.Add_Click({
        if(-not [string]::IsNullOrWhiteSpace($cTxtOutput.Text)){
            $d = Split-Path $cTxtOutput.Text -Parent
            if(Test-Path $d){ Start-Process explorer.exe $d }
        }
    })

    $cChkAutoOutput.Add_Click({
        if($cChkAutoOutput.IsChecked){
            $script:customCurveOutputDir = ""
        }
        Set-CurveOutputPath $cTxtOdb.Text
        UpdateCurveSummary
    })

    $cBtnChooseOutputFolder.Add_Click({
        Choose-CurveOutputFolder
    })

    $cBtnBrowseOutput.Add_Click({
        $d = New-Object Microsoft.Win32.SaveFileDialog
        $d.Filter = "CSV (*.csv)|*.csv"
        $d.DefaultExt = ".csv"
        if($d.ShowDialog()){
            $cTxtOutput.Text = $d.FileName
            UpdateCurveSummary
        }
    })

    $cLstSteps.Add_SelectionChanged({
        RefreshCommonRegions
        UpdateCurveSummary
    })

    $cCmbRegion.Add_SelectionChanged({
        RefreshCommonVariables
        UpdateCurveSummary
    })

    $cTxtRegionFilter.Add_TextChanged({
        ApplyRegionFilter
    })

    $cBtnFindNode.Add_Click({
        FindNodeRegion
    })

    $cCmbPreset.Add_SelectionChanged({ ApplyCurvePreset })

    foreach($c in @($cCmbX,$cCmbY)){
        $c.Add_SelectionChanged({ UpdateCurveSummary })
    }

    foreach($c in @($cChkAbsX,$cChkAbsY,$cChkDedupe)){
        $c.Add_Click({ UpdateCurveSummary })
    }

    foreach($c in @($cTxtXScale,$cTxtXOffset,$cTxtYScale,$cTxtYOffset,$cTxtOutput)){
        $c.Add_TextChanged({ UpdateCurveSummary })
    }

    [void]$cw.ShowDialog()
}


# ---------------- EVENTS ----------------

$cmbLanguage.SelectedIndex = 1
$cmbLanguage.Add_SelectionChanged({
    $script:lang = $cmbLanguage.SelectedItem.Tag.ToString()
    ApplyLanguage
})

$miOpen.Add_Click({ BrowseODB })
$miExit.Add_Click({ $window.Close() })
$miCurveData.Add_Click({ ShowCurveDataWindow })
$miFieldAnalysis.Add_Click({ ShowFieldAnalysisWindow })
$miCPFEM.Add_Click({
    $script = Join-Path $scriptDir 'cpfem_integrated.ps1'
    if(-not (Test-Path -LiteralPath $script)) { [Windows.MessageBox]::Show('Integrated CPFEM module missing.'); return }
    & $script -InitialODB $txtOdb.Text -Language $script:lang
})
$miDataSafety.Add_Click({
    $script = Join-Path $scriptDir 'odb_gui_recovery.ps1'
    if(-not (Test-Path -LiteralPath $script)) { [Windows.MessageBox]::Show('Data safety module missing.'); return }
    . $script
    $pvd = if($txtOutput.Text -and $txtOutput.Text.EndsWith('.pvd',[StringComparison]::OrdinalIgnoreCase)){$txtOutput.Text}else{''}
    Show-DataSafetyWorkspace $pvd $script:lang
})

$tbOpen.Add_Click({ BrowseODB })
$btnBrowse.Add_Click({ BrowseODB })

$tbRead.Add_Click({ ReadMeta })
$btnRead.Add_Click({ ReadMeta })

$tbFields.Add_Click({ ReadFields })
$btnReadFields.Add_Click({ ReadFields })

$tbExport.Add_Click({ RunExport })
$btnApply.Add_Click({ RunExport })

$btnBrowseInp.Add_Click({ BrowseInp })
$chkMises.Add_Click({ UpdateSummary })
$chkInitialIPF.Add_Click({ UpdateDerivedEnabled; UpdateSummary })
$cmbIPFDir.Add_SelectionChanged({ UpdateSummary })
$txtInp.Add_TextChanged({ $txtInp.ToolTip = $txtInp.Text; UpdateSummary })

$btnBrowseGNDDat.Add_Click({ BrowseGNDDat })
$chkGNDDiff.Add_Click({ UpdateGNDEnabled; UpdateSummary })
$cmbGNDMode.Add_SelectionChanged({ UpdateSummary })
$txtGNDDat.Add_TextChanged({ $txtGNDDat.ToolTip = $txtGNDDat.Text; UpdateSummary })
$chkGNDSlideDiff.Add_Click({ UpdateGNDEnabled; UpdateSummary })
$cmbGNDSlideRef.Add_SelectionChanged({ UpdateSummary })

$tbOpenFolder.Add_Click({
    if(-not [string]::IsNullOrWhiteSpace($txtOutput.Text)){
        $d = Split-Path $txtOutput.Text -Parent
        if(Test-Path $d){ Start-Process explorer.exe $d }
    }
})

$chkAutoOutput.Add_Click({
    if($chkAutoOutput.IsChecked){
        $script:customFieldOutputDir = ""
    }
    Set-FieldOutputPath $txtOdb.Text
    UpdateSummary
})

$btnChooseOutputFolder.Add_Click({
    Choose-FieldOutputFolder
})

$btnBrowseOutput.Add_Click({
    $d = New-Object Microsoft.Win32.SaveFileDialog

    if($chkSeries.IsChecked){
        $d.Filter = "ParaView Data Collection (*.pvd)|*.pvd"
    } else {
        $d.Filter = "VTU (*.vtu)|*.vtu"
    }

    if($d.ShowDialog()){
        $txtOutput.Text = $d.FileName
        UpdateSummary
    }
})

$btnAddFrames.Add_Click({ AddFramesToSelectedSteps $false })
$btnAddAllFrames.Add_Click({ AddFramesToSelectedSteps $true })
$btnRemoveStates.Add_Click({ RemoveSelectedStates })

$btnClearStates.Add_Click({
    $script:selectedStates.Clear()
    RefreshSelectedStates
})

$btnSelectAllFields.Add_Click({
    foreach($cb in $script:fieldBoxes){ $cb.IsChecked = $true }
    UpdateSummary
})

$btnClearFields.Add_Click({
    foreach($cb in $script:fieldBoxes){ $cb.IsChecked = $false }
    UpdateSummary
})

$btnClearMessages.Add_Click({ $txtMessages.Clear() })

$btnReset.Add_Click({
    $chkAutoOutput.IsChecked = $true
    $script:customFieldOutputDir = ""
    $chkSeries.IsChecked = $false
    $chkDelta.IsChecked = $false
    $chkMises.IsChecked = $false
    $chkInitialIPF.IsChecked = $false
    $chkGNDDiff.IsChecked = $false
    $chkGNDSlideDiff.IsChecked = $false
    $cmbIPFDir.SelectedIndex = 2
    $cmbGNDMode.SelectedIndex = 0
    $cmbGNDSlideRef.SelectedIndex = 0
    $txtBBox.Text = ""

    $script:selectedStates.Clear()
    RefreshSelectedStates

    if($lstSeriesSteps.Items.Count -gt 0){
        $lstSeriesSteps.UnselectAll()
        $lstSeriesSteps.SelectedIndex = 0
        PopulateCommonSeriesFrames
    }

    foreach($cb in $script:fieldBoxes){
        $cb.IsChecked = ($cb.Tag -eq "SDV29" -or $cb.Tag -eq "SDV78")
    }

    ToggleSeries
    UpdateSummary
})

$cmbInstance.Add_SelectionChanged({
    if($global:meta -eq $null -or $cmbInstance.SelectedItem -eq $null){ return }
    RefreshElementSetLanguage
    UpdateSummary
})

$cmbStep.Add_SelectionChanged({
    if($global:meta -eq $null -or $cmbStep.SelectedItem -eq $null){ return }
    PopulateFrameCombo $cmbFrame $cmbStep.SelectedItem.ToString() $true
    UpdateSummary
})

$lstSeriesSteps.Add_SelectionChanged({
    if($global:meta -eq $null){ return }
    PopulateCommonSeriesFrames
    UpdateSummary
})

$cmbRefStep.Add_SelectionChanged({
    if($global:meta -eq $null -or $cmbRefStep.SelectedItem -eq $null){ return }
    PopulateFrameCombo $cmbRefFrame $cmbRefStep.SelectedItem.ToString() $false
})

$chkSeries.Add_Click({ ToggleSeries })
$chkDelta.Add_Click({ UpdateSummary })

foreach($c in @($cmbElementSet,$cmbFrame,$cmbDeltaField,$cmbRefFrame)){
    $c.Add_SelectionChanged({ UpdateSummary })
}

$txtBBox.Add_TextChanged({ UpdateSummary })
$txtOutput.Add_TextChanged({ UpdateSummary })
$cmbFramePolicy.Add_SelectionChanged({ UpdateSummary })
$cmbFieldPolicy.Add_SelectionChanged({ UpdateSummary })
$chkCleanupRemoved.Add_Click({ UpdateSummary })
$txtOdb.Add_TextChanged({ $txtOdb.ToolTip = $txtOdb.Text })

$panelSeries.IsEnabled = $false
$cmbIPFDir.SelectedIndex = 2
$cmbGNDMode.SelectedIndex = 0
$cmbGNDSlideRef.SelectedIndex = 0
UpdateDerivedEnabled
UpdateGNDEnabled
ApplyLanguage

[void]$window.ShowDialog()
