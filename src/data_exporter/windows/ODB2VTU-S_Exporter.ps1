Add-Type -AssemblyName PresentationFramework

# WinForms is only needed for the folder-picker dialogs; load it on first use.
function Ensure-WinForms {
    if(-not ('System.Windows.Forms.FolderBrowserDialog' -as [type])){
        Add-Type -AssemblyName System.Windows.Forms
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
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

# Remove stale export-runner temp files left behind by earlier sessions.
try {
    Get-ChildItem -Path (Join-Path $env:TEMP 'ODB2VTUS_Export_*.cmd') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
} catch { }

# ============================================================================
#  Modern UI theme (light / dark), shared by every window.
#  Colors are exposed as DynamicResource brushes, so the theme can be switched
#  at runtime without rebuilding any XAML.
# ============================================================================
$script:theme = 'light'

$script:themeColors = @{
    light = @{
        'Bg.Window'         = '#EDF0F4'
        'Bg.Panel'          = '#FFFFFF'
        'Bg.Header'         = '#F4F6F9'
        'Bg.Toolbar'        = '#FFFFFF'
        'Bg.Menu'           = '#FFFFFF'
        'Bg.Status'         = '#F4F6F9'
        'Bg.Control'        = '#FFFFFF'
        'Bg.ControlHover'   = '#F2F6FB'
        'Bg.Selection'      = '#D7E6F8'
        'Bg.SelectionHover' = '#EAF3FC'
        'Bg.Inset'          = '#FAFBFD'
        'Border.Default'    = '#DFE4EA'
        'Border.Strong'     = '#C6CED8'
        'Border.Control'    = '#C9D1DA'
        'Fg.Text'           = '#1E2733'
        'Fg.TextMuted'      = '#5A6673'
        'Fg.TextDim'        = '#8B95A1'
        'Fg.OnAccent'       = '#FFFFFF'
        'Accent'            = '#2F6FD0'
        'AccentHover'       = '#3B80E2'
        'AccentPressed'     = '#255CB0'
        'Splitter'          = '#DCE2E9'
    }
    dark = @{
        'Bg.Window'         = '#1B1D21'
        'Bg.Panel'          = '#23262B'
        'Bg.Header'         = '#2A2E34'
        'Bg.Toolbar'        = '#23262B'
        'Bg.Menu'           = '#23262B'
        'Bg.Status'         = '#1F2226'
        'Bg.Control'        = '#2B2F35'
        'Bg.ControlHover'   = '#343A42'
        'Bg.Selection'      = '#2F4E77'
        'Bg.SelectionHover' = '#35475E'
        'Bg.Inset'          = '#1F2226'
        'Border.Default'    = '#34383F'
        'Border.Strong'     = '#454B54'
        'Border.Control'    = '#3D434B'
        'Fg.Text'           = '#E7EAEE'
        'Fg.TextMuted'      = '#A6AFBA'
        'Fg.TextDim'        = '#7D8792'
        'Fg.OnAccent'       = '#FFFFFF'
        'Accent'            = '#4A86E8'
        'AccentHover'       = '#5D94EC'
        'AccentPressed'     = '#3A70C8'
        'Splitter'          = '#34383F'
    }
}

function Get-ThemeBrushXaml([string]$theme){
    $sb = New-Object System.Text.StringBuilder
    foreach($k in $script:themeColors[$theme].Keys){
        [void]$sb.AppendLine(('<SolidColorBrush x:Key="{0}" Color="{1}"/>' -f $k, $script:themeColors[$theme][$k]))
    }
    return $sb.ToString()
}

# Recolour a live window: styles reference these keys through DynamicResource,
# so assigning new brushes updates every control immediately.
function Apply-ThemeColors {
    if($window -eq $null){ return }
    $map = $script:themeColors[$script:theme]
    foreach($k in $map.Keys){
        $brush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($map[$k]))
        $brush.Freeze()
        # A ResourceDictionary must be updated through Remove/Add. Assigning with
        # `$dict[$key] = $value` makes PowerShell bind to the explicit IDictionary
        # indexer, which hands Freezable values to WPF as bare Colors; every
        # DynamicResource consumer then throws and the window dies (theme switch crash).
        $window.Resources.Remove($k)
        $window.Resources.Add($k, $brush)
    }
}

$themeStyles = @'
<Style x:Key="ScrollBarPageButton" TargetType="RepeatButton">
    <Setter Property="Focusable" Value="False"/>
    <Setter Property="IsTabStop" Value="False"/>
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="RepeatButton">
                <Border Background="Transparent"/>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>

<Style x:Key="ScrollBarThumb" TargetType="Thumb">
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Setter Property="IsTabStop" Value="False"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="Thumb">
                <Border x:Name="Bd" Background="{DynamicResource Fg.TextDim}" CornerRadius="4" Margin="2"/>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Fg.TextMuted}"/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>

<ControlTemplate x:Key="VerticalScrollBar" TargetType="ScrollBar">
    <Grid Background="Transparent" Width="12">
        <Track x:Name="PART_Track" IsDirectionReversed="True">
            <Track.DecreaseRepeatButton>
                <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="ScrollBar.PageUpCommand"/>
            </Track.DecreaseRepeatButton>
            <Track.Thumb>
                <Thumb Style="{StaticResource ScrollBarThumb}"/>
            </Track.Thumb>
            <Track.IncreaseRepeatButton>
                <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="ScrollBar.PageDownCommand"/>
            </Track.IncreaseRepeatButton>
        </Track>
    </Grid>
</ControlTemplate>

<ControlTemplate x:Key="HorizontalScrollBar" TargetType="ScrollBar">
    <Grid Background="Transparent" Height="12">
        <Track x:Name="PART_Track">
            <Track.DecreaseRepeatButton>
                <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="ScrollBar.PageLeftCommand"/>
            </Track.DecreaseRepeatButton>
            <Track.Thumb>
                <Thumb Style="{StaticResource ScrollBarThumb}"/>
            </Track.Thumb>
            <Track.IncreaseRepeatButton>
                <RepeatButton Style="{StaticResource ScrollBarPageButton}" Command="ScrollBar.PageRightCommand"/>
            </Track.IncreaseRepeatButton>
        </Track>
    </Grid>
</ControlTemplate>

<Style TargetType="ScrollBar">
    <Setter Property="Width" Value="12"/>
    <Setter Property="MinWidth" Value="12"/>
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Template" Value="{StaticResource VerticalScrollBar}"/>
    <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
            <Setter Property="Width" Value="Auto"/>
            <Setter Property="MinWidth" Value="0"/>
            <Setter Property="Height" Value="12"/>
            <Setter Property="MinHeight" Value="12"/>
            <Setter Property="Template" Value="{StaticResource HorizontalScrollBar}"/>
        </Trigger>
    </Style.Triggers>
</Style>

<ControlTemplate x:Key="StdButtonTemplate" TargetType="Button">
    <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Bg.ControlHover}"/>
            <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Bg.Selection}"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter Property="Opacity" Value="0.45"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>

<Style x:Key="StdButton" TargetType="Button">
    <Setter Property="Background" Value="{DynamicResource Bg.Control}"/>
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Border.Control}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="13,6"/>
    <Setter Property="MinHeight" Value="30"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="SnapsToDevicePixels" Value="True"/>
    <Setter Property="Template" Value="{StaticResource StdButtonTemplate}"/>
</Style>

<Style TargetType="Button" BasedOn="{StaticResource StdButton}"/>

<ControlTemplate x:Key="PrimaryButtonTemplate" TargetType="Button">
    <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentHover}"/>
            <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentHover}"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="{DynamicResource AccentPressed}"/>
            <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentPressed}"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter Property="Opacity" Value="0.45"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>

<Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource StdButton}">
    <Setter Property="Background" Value="{DynamicResource Accent}"/>
    <Setter Property="Foreground" Value="{DynamicResource Fg.OnAccent}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Template" Value="{StaticResource PrimaryButtonTemplate}"/>
</Style>

<ControlTemplate x:Key="TextBoxTemplate" TargetType="TextBox">
    <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5">
        <ScrollViewer x:Name="PART_ContentHost" Focusable="False" Margin="{TemplateBinding Padding}"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Border.Strong}"/>
        </Trigger>
        <Trigger Property="IsKeyboardFocusWithin" Value="True">
            <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter Property="Opacity" Value="0.55"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>

<Style TargetType="TextBox">
    <Setter Property="Background" Value="{DynamicResource Bg.Control}"/>
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Border.Control}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="8,5"/>
    <Setter Property="MinHeight" Value="30"/>
    <Setter Property="VerticalContentAlignment" Value="Center"/>
    <Setter Property="Template" Value="{StaticResource TextBoxTemplate}"/>
</Style>

<Style x:Key="ComboToggle" TargetType="ToggleButton">
    <Setter Property="Focusable" Value="False"/>
    <Setter Property="IsTabStop" Value="False"/>
    <Setter Property="ClickMode" Value="Press"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="ToggleButton">
                <Border Background="Transparent"/>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>

<Style TargetType="ComboBoxItem">
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="Padding" Value="10,6"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="ComboBoxItem">
                <Border x:Name="Bd" Background="Transparent" CornerRadius="4" Padding="{TemplateBinding Padding}" Margin="2,1">
                    <ContentPresenter/>
                </Border>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsHighlighted" Value="True">
                        <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Bg.SelectionHover}"/>
                    </Trigger>
                    <Trigger Property="IsSelected" Value="True">
                        <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Bg.Selection}"/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>

<ControlTemplate x:Key="ComboBoxTemplate" TargetType="ComboBox">
    <Grid>
        <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="26"/>
                </Grid.ColumnDefinitions>
                <ContentPresenter x:Name="ContentSite" Grid.Column="0" Margin="{TemplateBinding Padding}" VerticalAlignment="Center" HorizontalAlignment="Left"
                                  Content="{TemplateBinding SelectionBoxItem}"
                                  ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                  ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}"/>
                <Path Grid.Column="1" Data="M 0 0 L 4 4 L 8 0" Stroke="{DynamicResource Fg.TextMuted}" StrokeThickness="1.6" VerticalAlignment="Center" HorizontalAlignment="Center" Margin="0,2,0,0"/>
            </Grid>
        </Border>
        <ToggleButton x:Name="ToggleButton" Style="{StaticResource ComboToggle}" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"/>
        <Popup x:Name="PART_Popup" AllowsTransparency="True" Focusable="False" Placement="Bottom" PopupAnimation="Fade" IsOpen="{TemplateBinding IsDropDownOpen}">
            <Border Background="{DynamicResource Bg.Panel}" BorderBrush="{DynamicResource Border.Strong}" BorderThickness="1" CornerRadius="6" Padding="3" Margin="0,3,0,0"
                    MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                <Border.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="2" Opacity="0.20" Color="#000000"/></Border.Effect>
                <ScrollViewer><StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer>
            </Border>
        </Popup>
    </Grid>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Border.Strong}"/>
        </Trigger>
        <Trigger Property="IsDropDownOpen" Value="True">
            <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>
        </Trigger>
        <Trigger Property="IsKeyboardFocusWithin" Value="True">
            <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter Property="Opacity" Value="0.55"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>

<Style TargetType="ComboBox">
    <Setter Property="Background" Value="{DynamicResource Bg.Control}"/>
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Border.Control}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="9,0"/>
    <Setter Property="MinHeight" Value="30"/>
    <Setter Property="VerticalContentAlignment" Value="Center"/>
    <Setter Property="Template" Value="{StaticResource ComboBoxTemplate}"/>
</Style>

<Style TargetType="CheckBox">
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="Margin" Value="0,4"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="CheckBox">
                <StackPanel Orientation="Horizontal" Background="Transparent">
                    <Border x:Name="Box" Width="16" Height="16" CornerRadius="4" Background="{DynamicResource Bg.Control}" BorderBrush="{DynamicResource Border.Control}" BorderThickness="1.5" VerticalAlignment="Center">
                        <Path x:Name="Check" Data="M 0 4 L 3 7 L 8 0" Stroke="{DynamicResource Fg.OnAccent}" StrokeThickness="1.9" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Visibility="Collapsed" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center" RecognizesAccessKey="True"/>
                </StackPanel>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsChecked" Value="True">
                        <Setter TargetName="Box" Property="Background" Value="{DynamicResource Accent}"/>
                        <Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                        <Setter TargetName="Check" Property="Visibility" Value="Visible"/>
                    </Trigger>
                    <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                    </Trigger>
                    <Trigger Property="IsEnabled" Value="False">
                        <Setter Property="Opacity" Value="0.5"/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>

<Style TargetType="ListBoxItem">
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="Padding" Value="8,4"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="ListBoxItem">
                <Border x:Name="Bd" Background="Transparent" CornerRadius="4" Padding="{TemplateBinding Padding}" Margin="1">
                    <ContentPresenter/>
                </Border>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Bg.SelectionHover}"/>
                    </Trigger>
                    <Trigger Property="IsSelected" Value="True">
                        <Setter TargetName="Bd" Property="Background" Value="{DynamicResource Bg.Selection}"/>
                    </Trigger>
                    <Trigger Property="IsEnabled" Value="False">
                        <Setter Property="Opacity" Value="0.5"/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>

<Style TargetType="ListBox">
    <Setter Property="Background" Value="{DynamicResource Bg.Control}"/>
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Border.Control}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="3"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="ListBox">
                <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5">
                    <ScrollViewer Padding="{TemplateBinding Padding}" Focusable="False">
                        <ItemsPresenter/>
                    </ScrollViewer>
                </Border>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>

<Style x:Key="ExpanderToggle" TargetType="ToggleButton">
    <Setter Property="Focusable" Value="False"/>
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="ToggleButton">
                <Border x:Name="Bd" Background="{DynamicResource Bg.Header}" CornerRadius="6,6,0,0" Padding="12,9">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Path x:Name="Chevron" Data="M 0 0 L 4 4 L 8 0" Stroke="{DynamicResource Fg.TextMuted}" StrokeThickness="1.8" VerticalAlignment="Center" Margin="0,1,9,0"/>
                        <ContentPresenter Grid.Column="1" Content="{TemplateBinding Content}" VerticalAlignment="Center"/>
                    </Grid>
                </Border>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsChecked" Value="True">
                        <Setter TargetName="Chevron" Property="Data" Value="M 0 4 L 4 0 L 8 4"/>
                    </Trigger>
                    <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Chevron" Property="Stroke" Value="{DynamicResource Accent}"/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>

<Style TargetType="Expander">
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="Margin" Value="0,0,0,8"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="Expander">
                <Border Background="{DynamicResource Bg.Panel}" BorderBrush="{DynamicResource Border.Default}" BorderThickness="1" CornerRadius="6">
                    <DockPanel>
                        <ToggleButton x:Name="HeaderSite" DockPanel.Dock="Top" Style="{StaticResource ExpanderToggle}" Content="{TemplateBinding Header}" IsChecked="{Binding IsExpanded, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"/>
                        <ContentPresenter x:Name="ExpandSite" Visibility="Collapsed"/>
                    </DockPanel>
                </Border>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsExpanded" Value="True">
                        <Setter TargetName="ExpandSite" Property="Visibility" Value="Visible"/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>

<ControlTemplate x:Key="GroupBoxTemplate" TargetType="GroupBox">
    <Border Background="{DynamicResource Bg.Panel}" BorderBrush="{DynamicResource Border.Default}" BorderThickness="1" CornerRadius="6">
        <DockPanel>
            <Border DockPanel.Dock="Top" Background="{DynamicResource Bg.Header}" CornerRadius="6,6,0,0" Padding="12,9">
                <TextBlock Text="{TemplateBinding Header}" FontWeight="SemiBold" Foreground="{DynamicResource Fg.Text}"/>
            </Border>
            <ContentPresenter Margin="{TemplateBinding Padding}"/>
        </DockPanel>
    </Border>
</ControlTemplate>

<Style TargetType="GroupBox">
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="Padding" Value="12"/>
    <Setter Property="Margin" Value="0,0,0,10"/>
    <Setter Property="Template" Value="{StaticResource GroupBoxTemplate}"/>
</Style>

<Style TargetType="ToolTip">
    <Setter Property="Background" Value="#2B3038"/>
    <Setter Property="Foreground" Value="#EEF1F5"/>
    <Setter Property="BorderBrush" Value="#3C434C"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="ToolTip">
                <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="10,6">
                    <ContentPresenter/>
                </Border>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>

<ControlTemplate x:Key="HLineTemplate" TargetType="Separator">
    <Border Height="1" Background="{DynamicResource Border.Default}"/>
</ControlTemplate>

<Style TargetType="Separator">
    <Setter Property="Template" Value="{StaticResource HLineTemplate}"/>
    <Setter Property="Margin" Value="0,8"/>
</Style>

<Style x:Key="{x:Static MenuItem.SeparatorStyleKey}" TargetType="Separator">
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="Separator">
                <Border Height="1" Background="{DynamicResource Border.Default}" Margin="8,4"/>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>

<Style TargetType="GridSplitter">
    <Setter Property="Background" Value="{DynamicResource Splitter}"/>
    <Setter Property="ShowsPreview" Value="True"/>
</Style>

<ControlTemplate x:Key="TopLevelHeaderTemplate" TargetType="MenuItem">
    <Grid>
        <Border x:Name="Bd" Background="Transparent" CornerRadius="5" Padding="11,6">
            <ContentPresenter ContentSource="Header" RecognizesAccessKey="True" VerticalAlignment="Center"/>
        </Border>
        <Popup x:Name="PART_Popup" AllowsTransparency="True" Focusable="False" Placement="Bottom" PopupAnimation="Fade"
               IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}}">
            <Border Background="{DynamicResource Bg.Panel}" BorderBrush="{DynamicResource Border.Strong}" BorderThickness="1" CornerRadius="7" Padding="4" Margin="0,3,0,0" MinWidth="210">
                <Border.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="2" Opacity="0.22" Color="#000000"/></Border.Effect>
                <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
            </Border>
        </Popup>
    </Grid>
    <ControlTemplate.Triggers>
        <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Bg.SelectionHover}"/></Trigger>
        <Trigger Property="IsSubmenuOpen" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Bg.Selection}"/></Trigger>
        <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>

<ControlTemplate x:Key="TopLevelItemTemplate" TargetType="MenuItem">
    <Border x:Name="Bd" Background="Transparent" CornerRadius="5" Padding="11,6">
        <ContentPresenter ContentSource="Header" RecognizesAccessKey="True" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Bg.SelectionHover}"/></Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>

<ControlTemplate x:Key="SubmenuItemTemplate" TargetType="MenuItem">
    <Border x:Name="Bd" Background="Transparent" CornerRadius="5" Padding="10,7" Margin="2,1">
        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="22"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Path x:Name="Check" Grid.Column="0" Data="M 0 4 L 3 7 L 8 0" Stroke="{DynamicResource Accent}" StrokeThickness="1.9" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Visibility="Hidden" VerticalAlignment="Center"/>
            <ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True" VerticalAlignment="Center"/>
            <TextBlock Grid.Column="2" Text="{TemplateBinding InputGestureText}" Foreground="{DynamicResource Fg.TextDim}" Margin="18,0,0,0" VerticalAlignment="Center"/>
        </Grid>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Bg.SelectionHover}"/></Trigger>
        <Trigger Property="IsChecked" Value="True"><Setter TargetName="Check" Property="Visibility" Value="Visible"/></Trigger>
        <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>

<ControlTemplate x:Key="SubmenuHeaderTemplate" TargetType="MenuItem">
    <Grid>
        <Border x:Name="Bd" Background="Transparent" CornerRadius="5" Padding="10,7" Margin="2,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="22"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <ContentPresenter Grid.Column="1" ContentSource="Header" RecognizesAccessKey="True" VerticalAlignment="Center"/>
                <Path Grid.Column="2" Data="M 0 0 L 4 4 L 0 8" Stroke="{DynamicResource Fg.TextDim}" StrokeThickness="1.6" Margin="18,0,2,0" VerticalAlignment="Center"/>
            </Grid>
        </Border>
        <Popup x:Name="PART_Popup" AllowsTransparency="True" Focusable="False" Placement="Right" PopupAnimation="Fade"
               IsOpen="{Binding IsSubmenuOpen, RelativeSource={RelativeSource TemplatedParent}}">
            <Border Background="{DynamicResource Bg.Panel}" BorderBrush="{DynamicResource Border.Strong}" BorderThickness="1" CornerRadius="7" Padding="4" Margin="3,0,0,0" MinWidth="190">
                <Border.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="2" Opacity="0.22" Color="#000000"/></Border.Effect>
                <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
            </Border>
        </Popup>
    </Grid>
    <ControlTemplate.Triggers>
        <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource Bg.SelectionHover}"/></Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>

<Style TargetType="MenuItem">
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="Template" Value="{StaticResource SubmenuItemTemplate}"/>
    <Style.Triggers>
        <Trigger Property="Role" Value="TopLevelHeader"><Setter Property="Template" Value="{StaticResource TopLevelHeaderTemplate}"/></Trigger>
        <Trigger Property="Role" Value="TopLevelItem"><Setter Property="Template" Value="{StaticResource TopLevelItemTemplate}"/></Trigger>
        <Trigger Property="Role" Value="SubmenuHeader"><Setter Property="Template" Value="{StaticResource SubmenuHeaderTemplate}"/></Trigger>
    </Style.Triggers>
</Style>

<Style TargetType="Menu">
    <Setter Property="Background" Value="{DynamicResource Bg.Menu}"/>
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Border.Default}"/>
    <Setter Property="BorderThickness" Value="0,0,0,1"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="Menu">
                <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}">
                    <ItemsPresenter/>
                </Border>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>

<Style TargetType="StatusBar">
    <Setter Property="Background" Value="{DynamicResource Bg.Status}"/>
    <Setter Property="Foreground" Value="{DynamicResource Fg.TextMuted}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Border.Default}"/>
    <Setter Property="BorderThickness" Value="0,1,0,0"/>
</Style>

<Style x:Key="Card" TargetType="Border">
    <Setter Property="Background" Value="{DynamicResource Bg.Panel}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Border.Default}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="CornerRadius" Value="8"/>
    <Setter Property="SnapsToDevicePixels" Value="True"/>
</Style>

<Style x:Key="CardHeader" TargetType="Border">
    <Setter Property="Background" Value="{DynamicResource Bg.Header}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Border.Default}"/>
    <Setter Property="BorderThickness" Value="0,0,0,1"/>
    <Setter Property="CornerRadius" Value="7,7,0,0"/>
    <Setter Property="Padding" Value="12,9"/>
</Style>

<Style x:Key="SectionTitle" TargetType="TextBlock">
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
</Style>

<Style x:Key="FieldLabel" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource Fg.TextMuted}"/>
    <Setter Property="VerticalAlignment" Value="Center"/>
</Style>

<Style x:Key="HintText" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource Fg.TextMuted}"/>
    <Setter Property="TextWrapping" Value="Wrap"/>
    <Setter Property="Margin" Value="0,6,0,0"/>
</Style>

<Style x:Key="ToolbarSep" TargetType="Border">
    <Setter Property="Width" Value="1"/>
    <Setter Property="Background" Value="{DynamicResource Border.Default}"/>
    <Setter Property="Margin" Value="11,5"/>
</Style>

<!-- ===== vector icons: inline geometry, no external assets, theme-aware stroke ===== -->
<PathGeometry x:Key="IcoOpen"   Figures="M3.5,1.5 H9.5 L13,5 V14.5 H3.5 Z M9.5,1.5 V5 H13"/>
<PathGeometry x:Key="IcoMeta"   Figures="M3.5,1.5 H12.5 V14.5 H3.5 Z M6.5,5.5 H10 M6.5,8.5 H10 M6.5,11.5 H10"/>
<PathGeometry x:Key="IcoFields" Figures="M1.5,3.5 H14.5 V12.5 H1.5 Z M1.5,6.5 H14.5 M1.5,9.5 H14.5 M6,3.5 V12.5 M10.5,3.5 V12.5"/>
<PathGeometry x:Key="IcoExport" Figures="M2,9 V13.5 H14 V9 M8,11.5 V3 M5,6 L8,3 L11,6"/>
<PathGeometry x:Key="IcoFolder" Figures="M1.5,4 H6.2 L7.6,6 H14.5 V13 H1.5 Z"/>
<PathGeometry x:Key="IcoCheck"  Figures="M3,8.5 L6.5,12 L13,3.5"/>
<PathGeometry x:Key="IcoReset"  Figures="M6.2,4.6 H10 A3.2,3.2 0 0 1 10,11 H4.6 M6.2,4.6 L3.8,2.2 M6.2,4.6 L3.8,7"/>
<PathGeometry x:Key="IcoRun"    Figures="M5.5,3.2 L13,8 L5.5,12.8 Z"/>
<PathGeometry x:Key="IcoChart"  Figures="M2.2,13.2 H13.8 M4.6,13.2 V8.4 M8,13.2 V4.8 M11.4,13.2 V10.4"/>

<Style x:Key="ToolIcon" TargetType="Path">
    <Setter Property="Width" Value="16"/>
    <Setter Property="Height" Value="16"/>
    <Setter Property="Stretch" Value="None"/>
    <Setter Property="StrokeThickness" Value="1.4"/>
    <Setter Property="StrokeStartLineCap" Value="Round"/>
    <Setter Property="StrokeEndLineCap" Value="Round"/>
    <Setter Property="StrokeLineJoin" Value="Round"/>
    <Setter Property="Stroke" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="Fill" Value="Transparent"/>
    <Setter Property="VerticalAlignment" Value="Center"/>
    <Setter Property="Margin" Value="0,0,8,0"/>
</Style>
<Style x:Key="ToolIconOnAccent" TargetType="Path" BasedOn="{StaticResource ToolIcon}">
    <Setter Property="Stroke" Value="{DynamicResource Fg.OnAccent}"/>
</Style>
<Style x:Key="ToolIconMuted" TargetType="Path" BasedOn="{StaticResource ToolIcon}">
    <Setter Property="Stroke" Value="{DynamicResource Fg.TextMuted}"/>
</Style>

<!-- ===== guided step rail ===== -->
<Style x:Key="WizardRail" TargetType="Border">
    <Setter Property="Background" Value="{DynamicResource Bg.Inset}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Border.Default}"/>
    <Setter Property="BorderThickness" Value="0,0,0,1"/>
    <Setter Property="Padding" Value="14,9"/>
</Style>
<Style x:Key="StepDot" TargetType="Border">
    <Setter Property="Width" Value="20"/>
    <Setter Property="Height" Value="20"/>
    <Setter Property="CornerRadius" Value="10"/>
    <Setter Property="Background" Value="{DynamicResource Bg.Control}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Border.Default}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="VerticalAlignment" Value="Center"/>
</Style>
<Style x:Key="StepDotCurrent" TargetType="Border" BasedOn="{StaticResource StepDot}">
    <Setter Property="Background" Value="{DynamicResource Bg.Panel}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>
    <Setter Property="BorderThickness" Value="2"/>
</Style>
<Style x:Key="StepDotDone" TargetType="Border" BasedOn="{StaticResource StepDot}">
    <Setter Property="Background" Value="{DynamicResource Accent}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>
</Style>
<Style x:Key="StepNumber" TargetType="TextBlock">
    <Setter Property="HorizontalAlignment" Value="Center"/>
    <Setter Property="VerticalAlignment" Value="Center"/>
    <Setter Property="FontSize" Value="11"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Foreground" Value="{DynamicResource Fg.TextMuted}"/>
</Style>
<Style x:Key="StepNumberCurrent" TargetType="TextBlock" BasedOn="{StaticResource StepNumber}">
    <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
</Style>
<Style x:Key="StepNumberDone" TargetType="TextBlock" BasedOn="{StaticResource StepNumber}">
    <Setter Property="Foreground" Value="{DynamicResource Fg.OnAccent}"/>
</Style>
<Style x:Key="StepLabel" TargetType="TextBlock">
    <Setter Property="VerticalAlignment" Value="Center"/>
    <Setter Property="Margin" Value="7,0,0,0"/>
    <Setter Property="Foreground" Value="{DynamicResource Fg.TextMuted}"/>
</Style>
<Style x:Key="StepLabelCurrent" TargetType="TextBlock" BasedOn="{StaticResource StepLabel}">
    <Setter Property="Foreground" Value="{DynamicResource Fg.Text}"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
</Style>
<Style x:Key="StepLabelDone" TargetType="TextBlock" BasedOn="{StaticResource StepLabel}">
    <Setter Property="Foreground" Value="{DynamicResource Fg.TextDim}"/>
</Style>
<Style x:Key="StepArrow" TargetType="TextBlock">
    <Setter Property="Text" Value="›"/>
    <Setter Property="VerticalAlignment" Value="Center"/>
    <Setter Property="Margin" Value="11,0,11,0"/>
    <Setter Property="Foreground" Value="{DynamicResource Fg.TextDim}"/>
</Style>
'@

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ODB2VTU-S Workbench"
        Width="1380" Height="880"
        MinWidth="1080" MinHeight="700"
        WindowStartupLocation="CenterScreen"
        Background="{DynamicResource Bg.Window}"
        Foreground="{DynamicResource Fg.Text}"
        FontFamily="Segoe UI, Microsoft YaHei UI, Microsoft YaHei"
        FontSize="13"
        UseLayoutRounding="True"
        SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Ideal">

    <Window.Resources>
$(Get-ThemeBrushXaml $script:theme)
$themeStyles
    </Window.Resources>

    <DockPanel>

        <Menu DockPanel.Dock="Top" Padding="7,5">
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
                Background="{DynamicResource Bg.Toolbar}"
                BorderBrush="{DynamicResource Border.Default}"
                BorderThickness="0,0,0,1"
                Padding="12,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Orientation="Horizontal">
                    <Button x:Name="tbOpen" Style="{StaticResource PrimaryButton}">
                        <StackPanel Orientation="Horizontal">
                            <Path Style="{StaticResource ToolIconOnAccent}" Data="{StaticResource IcoOpen}"/>
                            <TextBlock x:Name="tbOpenText" Text="Open ODB" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="tbOpenFolder" Margin="8,0,0,0">
                        <StackPanel Orientation="Horizontal">
                            <Path Style="{StaticResource ToolIcon}" Data="{StaticResource IcoFolder}"/>
                            <TextBlock x:Name="tbOpenFolderText" Text="Open Output Folder" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Button>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <TextBlock x:Name="lblTheme" Text="Theme" VerticalAlignment="Center" Margin="0,0,7,0" Foreground="{DynamicResource Fg.TextMuted}"/>
                    <ComboBox x:Name="cmbTheme" Width="98" Height="30">
                        <ComboBoxItem Content="Light" Tag="light"/>
                        <ComboBoxItem Content="Dark" Tag="dark"/>
                    </ComboBox>
                    <TextBlock x:Name="lblLanguage" Text="Language" VerticalAlignment="Center" Margin="16,0,7,0" Foreground="{DynamicResource Fg.TextMuted}"/>
                    <ComboBox x:Name="cmbLanguage" Width="106" Height="30">
                        <ComboBoxItem Content="English" Tag="en"/>
                        <ComboBoxItem Content="中文" Tag="zh"/>
                    </ComboBox>
                </StackPanel>
            </Grid>
        </Border>

        <!-- ===================== guided step rail ===================== -->
        <Border DockPanel.Dock="Top" Style="{StaticResource WizardRail}">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border x:Name="stepDot1" Style="{StaticResource StepDot}"><TextBlock x:Name="stepNum1" Style="{StaticResource StepNumber}" Text="1"/></Border>
                    <TextBlock x:Name="stepLbl1" Style="{StaticResource StepLabel}" Text="Source"/>
                    <TextBlock Style="{StaticResource StepArrow}"/>
                    <Border x:Name="stepDot2" Style="{StaticResource StepDot}"><TextBlock x:Name="stepNum2" Style="{StaticResource StepNumber}" Text="2"/></Border>
                    <TextBlock x:Name="stepLbl2" Style="{StaticResource StepLabel}" Text="State"/>
                    <TextBlock Style="{StaticResource StepArrow}"/>
                    <Border x:Name="stepDot3" Style="{StaticResource StepDot}"><TextBlock x:Name="stepNum3" Style="{StaticResource StepNumber}" Text="3"/></Border>
                    <TextBlock x:Name="stepLbl3" Style="{StaticResource StepLabel}" Text="Fields"/>
                    <TextBlock Style="{StaticResource StepArrow}"/>
                    <Border x:Name="stepDot4" Style="{StaticResource StepDot}"><TextBlock x:Name="stepNum4" Style="{StaticResource StepNumber}" Text="4"/></Border>
                    <TextBlock x:Name="stepLbl4" Style="{StaticResource StepLabel}" Text="Output"/>
                    <TextBlock Style="{StaticResource StepArrow}"/>
                    <Border x:Name="stepDot5" Style="{StaticResource StepDot}"><TextBlock x:Name="stepNum5" Style="{StaticResource StepNumber}" Text="5"/></Border>
                    <TextBlock x:Name="stepLbl5" Style="{StaticResource StepLabel}" Text="Export"/>
                </StackPanel>

                <Button x:Name="btnNextStep" Grid.Column="2" VerticalAlignment="Center" MinWidth="150" Style="{StaticResource PrimaryButton}">
                    <StackPanel Orientation="Horizontal">
                        <Path Style="{StaticResource ToolIconOnAccent}" Data="{StaticResource IcoRun}"/>
                        <TextBlock x:Name="btnNextStepText" Text="Next" VerticalAlignment="Center"/>
                    </StackPanel>
                </Button>
            </Grid>
        </Border>

        <StatusBar DockPanel.Dock="Bottom" Height="28">
            <StatusBarItem><TextBlock x:Name="txtStatus" Text="Ready" Foreground="{DynamicResource Fg.TextMuted}"/></StatusBarItem>
            <Separator/>
            <StatusBarItem><TextBlock x:Name="txtStatusRight" Text="ODB: not loaded" Foreground="{DynamicResource Fg.TextMuted}"/></StatusBarItem>
        </StatusBar>

        <Grid Margin="10">
            <!-- Top row = options (wide, left) + selection summary (right).
                 Bottom row = Output and Output Messages side by side. -->
            <Grid.RowDefinitions>
                <RowDefinition Height="*" MinHeight="200"/>
                <RowDefinition Height="8"/>
                <RowDefinition Height="Auto" MinHeight="150"/>
            </Grid.RowDefinitions>
            <Grid.ColumnDefinitions>
                <ColumnDefinition x:Name="colLeftPanel" Width="*" MinWidth="430"/>
                <ColumnDefinition Width="8"/>
                <ColumnDefinition Width="390" MinWidth="270"/>
            </Grid.ColumnDefinitions>

            <!-- ============================ LEFT: properties ============================ -->
            <Border Grid.Row="0" Grid.Column="0" Style="{StaticResource Card}">
                <DockPanel>

                    <Border DockPanel.Dock="Top" Style="{StaticResource CardHeader}">
                        <TextBlock x:Name="hdrProperties" Text="Properties" Style="{StaticResource SectionTitle}"/>
                    </Border>

                    <Border DockPanel.Dock="Top"
                            Background="{DynamicResource Bg.Panel}"
                            BorderBrush="{DynamicResource Border.Default}"
                            BorderThickness="0,0,0,1"
                            Padding="12,9">
                        <StackPanel Orientation="Horizontal">
                            <Button x:Name="btnReset" Width="88">
                                <StackPanel Orientation="Horizontal">
                                    <Path Style="{StaticResource ToolIcon}" Data="{StaticResource IcoReset}"/>
                                    <TextBlock x:Name="btnResetText" Text="Reset" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                        </StackPanel>
                    </Border>

                    <!-- Option tree (left) + the selected section's options (right).
                         Only one section is shown at a time, so the properties panel
                         no longer scrolls through every group. -->
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="184" MinWidth="134"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <Border Grid.Column="0"
                                Background="{DynamicResource Bg.Panel}"
                                BorderBrush="{DynamicResource Border.Default}"
                                BorderThickness="0,0,1,0">
                            <ListBox x:Name="navList"
                                     Background="Transparent"
                                     BorderThickness="0"
                                     Margin="0,4,0,4"
                                     HorizontalContentAlignment="Left"
                                     ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                                <ListBoxItem x:Name="navGroupData" Content="Data / target" IsEnabled="False" FontSize="11" Padding="10,4,6,0"/>
                                <ListBoxItem x:Name="navSource" Content="Source" Tag="Source" Padding="22,4,8,4"/>
                                <ListBoxItem x:Name="navTarget" Content="Target" Tag="Target" Padding="22,4,8,4"/>
                                <ListBoxItem x:Name="navGroupSeries" Content="Time series" IsEnabled="False" FontSize="11" Padding="10,6,6,0"/>
                                <ListBoxItem x:Name="navSeries" Content="Time Series" Tag="Series" Padding="22,4,8,4"/>
                                <ListBoxItem x:Name="navGroupFields" Content="Field variables" IsEnabled="False" FontSize="11" Padding="10,6,6,0"/>
                                <ListBoxItem x:Name="navFields" Content="Fields" Tag="Fields" Padding="22,4,8,4"/>
                                <ListBoxItem x:Name="navDerived" Content="Derived Fields" Tag="Derived" Padding="22,4,8,4"/>
                                <ListBoxItem x:Name="navGND" Content="GND Evolution" Tag="GND" Padding="22,4,8,4"/>
                                <ListBoxItem x:Name="navDifference" Content="Difference" Tag="Difference" Padding="22,4,8,4"/>
                            </ListBox>
                        </Border>

                        <!-- Page host: every section lives in this cell, the tree shows one at a time. -->
                        <Grid Grid.Column="1" Margin="12,10,12,10">

                            <StackPanel x:Name="grpSource" VerticalAlignment="Top">
                                <TextBlock x:Name="hdrSource" Text="Source" Style="{StaticResource SectionTitle}"/>
                                <StackPanel Margin="0,8,0,0">
                                    <TextBlock x:Name="lblOdbFile" Text="ODB File" Style="{StaticResource FieldLabel}"/>
                                    <Grid Margin="0,5,0,8">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="40"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBox x:Name="txtOdb"/>
                                        <Button x:Name="btnBrowse" Grid.Column="1" Content="…" Margin="6,0,0,0"/>
                                    </Grid>
                                    <Button x:Name="btnRead" Content="Read Metadata" HorizontalAlignment="Left" Padding="16,6"/>
                                </StackPanel>
                            </StackPanel>

                            <StackPanel x:Name="grpTarget" VerticalAlignment="Top" Visibility="Collapsed">
                                <TextBlock x:Name="hdrTarget" Text="Target" Style="{StaticResource SectionTitle}"/>
                                <StackPanel Margin="0,8,0,0">

                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*" MinWidth="230"/>
                                            <ColumnDefinition Width="22"/>
                                            <ColumnDefinition Width="*" MinWidth="230"/>
                                        </Grid.ColumnDefinitions>

                                        <!-- Real selections: they define the exported region. -->
                                        <StackPanel Grid.Column="0">
                                            <TextBlock x:Name="lblTargetSel" Text="Selection" Style="{StaticResource SectionTitle}"/>
                                            <TextBlock x:Name="lblInstance" Text="Instance" Style="{StaticResource FieldLabel}" Margin="0,7,0,0"/>
                                            <ComboBox x:Name="cmbInstance" Margin="0,3"/>
                                            <TextBlock x:Name="lblElementSet" Text="Element Set" Style="{StaticResource FieldLabel}" Margin="0,7,0,0"/>
                                            <ComboBox x:Name="cmbElementSet" Margin="0,3"/>
                                        </StackPanel>

                                        <!-- Browse only: used to look at frames / read field variables. -->
                                        <StackPanel Grid.Column="2">
                                            <TextBlock x:Name="lblTargetBrowse" Text="Browse / verify" Style="{StaticResource SectionTitle}"/>
                                            <TextBlock x:Name="lblStep" Text="Step" Style="{StaticResource FieldLabel}" Margin="0,7,0,0"/>
                                            <ComboBox x:Name="cmbStep" Margin="0,3"/>
                                            <TextBlock x:Name="lblFrame" Text="Frame" Style="{StaticResource FieldLabel}" Margin="0,7,0,0"/>
                                            <ComboBox x:Name="cmbFrame" Margin="0,3"/>
                                        </StackPanel>
                                    </Grid>

                                    <TextBlock x:Name="txtTargetHint"
                                               Text="Step / Frame only browse and cross-check the ODB (used when reading field variables)."
                                               Style="{StaticResource HintText}"/>
                                </StackPanel>
                            </StackPanel>

                            <Grid x:Name="grpSeries" Visibility="Collapsed">
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>

                                <TextBlock x:Name="hdrSeries" Grid.Row="0" Text="Time Series" Style="{StaticResource SectionTitle}"/>

                                <StackPanel Grid.Row="1" Margin="0,8,0,0">
                                    <CheckBox x:Name="chkSeries"
                                              Content="Export as ParaView time series (.pvd)"/>
                                    <TextBlock x:Name="txtSeriesHint"
                                               Text="Tick Steps (Shift / Ctrl selects ranges), then tick the frames to add."
                                               Foreground="{DynamicResource Fg.TextMuted}"
                                               TextWrapping="Wrap"
                                               Margin="0,6,0,0"/>
                                </StackPanel>

                                <Border x:Name="panelSeries"
                                        Grid.Row="2"
                                        Margin="0,8,0,0"
                                        BorderBrush="{DynamicResource Border.Default}"
                                        BorderThickness="1"
                                        Background="{DynamicResource Bg.Inset}"
                                        CornerRadius="6"
                                        Padding="8">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*" MinWidth="140"/>
                                            <ColumnDefinition Width="12"/>
                                            <ColumnDefinition Width="*" MinWidth="140"/>
                                            <ColumnDefinition Width="12"/>
                                            <ColumnDefinition Width="*" MinWidth="140"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid.RowDefinitions>
                                            <RowDefinition Height="Auto"/>
                                            <RowDefinition Height="*" MinHeight="70"/>
                                            <RowDefinition Height="Auto"/>
                                        </Grid.RowDefinitions>

                                        <TextBlock x:Name="lblSeriesStep"
                                                   Grid.Row="0"
                                                   Grid.Column="0"
                                                   Text="Steps"
                                                   Style="{StaticResource FieldLabel}"
                                                   TextWrapping="Wrap"/>

                                        <Border Grid.Row="1"
                                                Grid.Column="0"
                                                Background="{DynamicResource Bg.Inset}"
                                                BorderBrush="{DynamicResource Border.Control}"
                                                BorderThickness="1"
                                                CornerRadius="6">
                                            <ScrollViewer VerticalScrollBarVisibility="Auto">
                                                <StackPanel x:Name="panelSeriesSteps" Margin="8"/>
                                            </ScrollViewer>
                                        </Border>

                                        <TextBlock x:Name="lblAvailableFrames"
                                                   Grid.Row="0"
                                                   Grid.Column="2"
                                                   Text="Common Frames"
                                                   Style="{StaticResource FieldLabel}"
                                                   TextWrapping="Wrap"/>

                                        <Border Grid.Row="1"
                                                Grid.Column="2"
                                                Background="{DynamicResource Bg.Inset}"
                                                BorderBrush="{DynamicResource Border.Control}"
                                                BorderThickness="1"
                                                CornerRadius="6">
                                            <ScrollViewer VerticalScrollBarVisibility="Auto">
                                                <StackPanel x:Name="panelAvailableFrames" Margin="8"/>
                                            </ScrollViewer>
                                        </Border>

                                        <!-- Both button pairs share one row so the lists keep as
                                             much height as possible (no panel scrolling). -->
                                        <WrapPanel Grid.Row="2"
                                                   Grid.Column="0"
                                                   Grid.ColumnSpan="5"
                                                   Orientation="Horizontal"
                                                   Margin="0,8,0,0">
                                            <Button x:Name="btnAddFrames"
                                                    Content="Add ticked frames"
                                                    Padding="10,5"/>
                                            <Button x:Name="btnAddAllFrames"
                                                    Content="Add all frames"
                                                    Margin="6,0,0,0"
                                                    Padding="10,5"/>
                                            <Button x:Name="btnRemoveStates"
                                                    Content="Remove ticked"
                                                    Margin="26,0,0,0"
                                                    Padding="10,5"/>
                                            <Button x:Name="btnClearStates"
                                                    Content="Clear all"
                                                    Margin="6,0,0,0"
                                                    Padding="10,5"/>
                                        </WrapPanel>

                                        <TextBlock x:Name="lblSelectedStates"
                                                   Grid.Row="0"
                                                   Grid.Column="4"
                                                   Text="Selected Step / Frame states"
                                                   Style="{StaticResource FieldLabel}"
                                                   TextWrapping="Wrap"/>

                                        <Border Grid.Row="1"
                                                Grid.Column="4"
                                                Background="{DynamicResource Bg.Inset}"
                                                BorderBrush="{DynamicResource Border.Control}"
                                                BorderThickness="1"
                                                CornerRadius="6">
                                            <ScrollViewer VerticalScrollBarVisibility="Auto">
                                                <StackPanel x:Name="panelSelectedStates" Margin="8"/>
                                            </ScrollViewer>
                                        </Border>
                                    </Grid>
                                </Border>
                            </Grid>

                            <Grid x:Name="grpFields" Visibility="Collapsed">
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>

                                <TextBlock x:Name="hdrFields" Grid.Row="0" Text="Fields" Style="{StaticResource SectionTitle}"/>

                                <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,8,0,8">
                                    <Button x:Name="btnReadFields"
                                            Content="Read fields from selected frame"
                                            Padding="16,6"/>
                                    <Button x:Name="btnSelectAllFields" Content="Select all" Margin="8,0,0,0" Padding="13,5"/>
                                    <Button x:Name="btnClearFields" Content="Clear" Margin="6,0,0,0" Padding="13,5"/>
                                </StackPanel>

                                <Border Grid.Row="2"
                                        Background="{DynamicResource Bg.Control}"
                                        BorderBrush="{DynamicResource Border.Control}"
                                        BorderThickness="1"
                                        CornerRadius="6"
                                        MinHeight="150">
                                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                                        <StackPanel x:Name="panelFields" Margin="9"/>
                                    </ScrollViewer>
                                </Border>
                            </Grid>

                            <StackPanel x:Name="grpDerived" VerticalAlignment="Top" Visibility="Collapsed">
                                <TextBlock x:Name="hdrDerived" Text="Derived Fields" Style="{StaticResource SectionTitle}"/>
                                <StackPanel Margin="0,8,0,0">
                                    <CheckBox x:Name="chkMises" Content="Mises Stress"/>
                                    <CheckBox x:Name="chkInitialIPF" Content="Initial IPF (HCP Ti)"/>

                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="88"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="40"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock x:Name="lblInpFile" Text="INP File" Style="{StaticResource FieldLabel}"/>
                                        <TextBox x:Name="txtInp" Grid.Column="1"/>
                                        <Button x:Name="btnBrowseInp" Grid.Column="2" Content="…" Margin="6,0,0,0"/>
                                    </Grid>

                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="88"/>
                                            <ColumnDefinition Width="130"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock x:Name="lblIPFDir" Text="IPF Direction" Style="{StaticResource FieldLabel}"/>
                                        <ComboBox x:Name="cmbIPFDir" Grid.Column="1">
                                            <ComboBoxItem Content="X" Tag="X"/>
                                            <ComboBoxItem Content="Y" Tag="Y"/>
                                            <ComboBoxItem Content="Z" Tag="Z"/>
                                        </ComboBox>
                                    </Grid>

                                    <TextBlock x:Name="txtDerivedHint"
                                               Text="Mises is derived from S. Initial IPF reads Grain material Euler angles from INP PROPS(1:3)."
                                               Style="{StaticResource HintText}"/>
                                </StackPanel>
                            </StackPanel>

                            <StackPanel x:Name="grpGND" VerticalAlignment="Top" Visibility="Collapsed">
                                <TextBlock x:Name="hdrGND" Text="GND Evolution" Style="{StaticResource SectionTitle}"/>
                                <StackPanel Margin="0,8,0,0">
                                    <CheckBox x:Name="chkGNDDiff" Content="Compare gnd_field.dat with SDV11-28"/>

                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="88"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="40"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock x:Name="lblGNDDat" Text="GND DAT" Style="{StaticResource FieldLabel}"/>
                                        <TextBox x:Name="txtGNDDat" Grid.Column="1"/>
                                        <Button x:Name="btnBrowseGNDDat" Grid.Column="2" Content="…" Margin="6,0,0,0"/>
                                    </Grid>

                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="88"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock x:Name="lblGNDMode" Text="Output" Style="{StaticResource FieldLabel}"/>
                                        <ComboBox x:Name="cmbGNDMode" Grid.Column="1">
                                            <ComboBoxItem Content="18 slip systems only" Tag="slips"/>
                                        </ComboBox>
                                    </Grid>

                                    <CheckBox x:Name="chkGNDSlideDiff"
                                              Content="Sliding-start difference (18 slip systems)"
                                              Margin="0,10,0,0"/>

                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="88"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock x:Name="lblGNDSlideRef" Text="Reference" Style="{StaticResource FieldLabel}"/>
                                        <ComboBox x:Name="cmbGNDSlideRef" Grid.Column="1">
                                            <ComboBoxItem Content="First sliding Step / Frame 0" Tag="sliding0"/>
                                            <ComboBoxItem Content="Last frame before sliding" Tag="previous_last"/>
                                        </ComboBox>
                                    </Grid>

                                    <TextBlock x:Name="txtGNDHint"
                                               Text="DAT difference uses gnd_field.dat. Sliding-start difference uses a fixed ODB baseline and outputs 18 slip-system increments."
                                               Style="{StaticResource HintText}"/>
                                </StackPanel>
                            </StackPanel>

                            <StackPanel x:Name="grpDifference" VerticalAlignment="Top" Visibility="Collapsed">
                                <TextBlock x:Name="hdrDifference" Text="Difference" Style="{StaticResource SectionTitle}"/>
                                <StackPanel Margin="0,8,0,0">
                                    <CheckBox x:Name="chkDelta" Content="Enable target - reference"/>
                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*" MinWidth="180"/>
                                            <ColumnDefinition Width="16"/>
                                            <ColumnDefinition Width="*" MinWidth="180"/>
                                            <ColumnDefinition Width="16"/>
                                            <ColumnDefinition Width="*" MinWidth="180"/>
                                        </Grid.ColumnDefinitions>
                                        <StackPanel Grid.Column="0">
                                            <TextBlock x:Name="lblDiffField" Text="Field" Style="{StaticResource FieldLabel}"/>
                                            <ComboBox x:Name="cmbDeltaField" Margin="0,3"/>
                                        </StackPanel>
                                        <StackPanel Grid.Column="2">
                                            <TextBlock x:Name="lblRefStep" Text="Reference Step" Style="{StaticResource FieldLabel}"/>
                                            <ComboBox x:Name="cmbRefStep" Margin="0,3"/>
                                        </StackPanel>
                                        <StackPanel Grid.Column="4">
                                            <TextBlock x:Name="lblRefFrame" Text="Reference Frame" Style="{StaticResource FieldLabel}"/>
                                            <ComboBox x:Name="cmbRefFrame" Margin="0,3"/>
                                        </StackPanel>
                                    </Grid>
                                </StackPanel>
                            </StackPanel>

                        </Grid>
                    </Grid>
                </DockPanel>
            </Border>

            <!-- Vertical divider: options <-> selection summary. -->
            <GridSplitter Grid.Row="0" Grid.Column="1"
                          Width="8"
                          HorizontalAlignment="Stretch"
                          VerticalAlignment="Stretch"
                          ResizeDirection="Columns"
                          ResizeBehavior="PreviousAndNext"
                          Cursor="SizeWE"
                          ToolTip="拖动调整左侧操作栏宽度 / Drag to resize the left panel"/>

            <!-- ============================ RIGHT: selection summary ============================ -->
            <Border Grid.Row="0" Grid.Column="2" Style="{StaticResource Card}">
                <DockPanel>
                    <Border DockPanel.Dock="Top" Style="{StaticResource CardHeader}">
                        <TextBlock x:Name="hdrSummary" Text="Selection Summary" Style="{StaticResource SectionTitle}"/>
                    </Border>

                    <TextBox x:Name="txtSummary"
                             Height="Auto"
                             VerticalAlignment="Stretch"
                             VerticalContentAlignment="Top"
                             IsReadOnly="True"
                             BorderThickness="0"
                             Background="{DynamicResource Bg.Panel}"
                             AcceptsReturn="True"
                             TextWrapping="Wrap"
                             VerticalScrollBarVisibility="Auto"
                             FontFamily="Consolas, Cascadia Mono"
                             FontSize="12.5"
                             Padding="12"/>
                </DockPanel>
            </Border>

            <!-- Horizontal divider between the options area and the bottom console row. -->
            <GridSplitter Grid.Row="1" Grid.ColumnSpan="3"
                          Height="8"
                          HorizontalAlignment="Stretch"
                          ResizeDirection="Rows"
                          ResizeBehavior="PreviousAndNext"
                          Cursor="SizeNS"
                          ToolTip="拖动调整底部输出区高度 / Drag to resize the bottom row"/>

            <!-- ============================ BOTTOM: output | messages ============================ -->
            <Grid Grid.Row="2" Grid.ColumnSpan="3">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="1.35*"/>
                    <ColumnDefinition Width="10"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border x:Name="cardOutput" Grid.Column="0" Style="{StaticResource Card}">
                    <DockPanel>
                        <Border DockPanel.Dock="Top" Style="{StaticResource CardHeader}">
                            <TextBlock Text="Output" Style="{StaticResource SectionTitle}"/>
                        </Border>

                        <Grid Margin="12,10,12,10">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*" MinWidth="205"/>
                                <ColumnDefinition Width="18"/>
                                <ColumnDefinition Width="2.4*" MinWidth="300"/>
                            </Grid.ColumnDefinitions>

                            <!-- Where the data goes. -->
                            <StackPanel Grid.Column="0">
                                <TextBlock x:Name="lblBBox" Text="Bounding Box" Style="{StaticResource FieldLabel}"/>
                                <TextBox x:Name="txtBBox" Margin="0,4,0,0"/>

                                <CheckBox x:Name="chkAutoOutput"
                                          Content="Auto-match ODB output folder"
                                          IsChecked="True"
                                          Margin="0,11,0,0"/>

                                <Button x:Name="btnChooseOutputFolder"
                                        Content="Select Output Folder..."
                                        Margin="0,7,0,0"
                                        Padding="13,5"
                                        HorizontalAlignment="Left"/>

                                <TextBlock x:Name="lblOutputFile" Text="Output File" Style="{StaticResource FieldLabel}" Margin="0,11,0,0"/>
                                <Grid Margin="0,4,0,0">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="40"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="txtOutput"/>
                                    <Button x:Name="btnBrowseOutput" Grid.Column="1" Content="…" Margin="6,0,0,0"/>
                                </Grid>
                            </StackPanel>

                            <!-- Incremental update policy. -->
                            <StackPanel Grid.Column="2">
                                <TextBlock x:Name="lblIncPolicy" Text="增量更新策略 / Incremental Update Policy"
                                           Style="{StaticResource SectionTitle}"/>
                                <WrapPanel Margin="0,7,0,0">
                                    <TextBlock Text="Frames" Style="{StaticResource FieldLabel}" Margin="0,0,6,0"/>
                                    <ComboBox x:Name="cmbFramePolicy" SelectedIndex="0">
                                        <ComboBoxItem Content="合并/保留既有帧 / Merge" Tag="merge"/>
                                        <ComboBoxItem Content="同步当前选择 / Sync" Tag="sync"/>
                                    </ComboBox>
                                    <TextBlock Text="Fields" Style="{StaticResource FieldLabel}" Margin="14,0,6,0"/>
                                    <ComboBox x:Name="cmbFieldPolicy" SelectedIndex="0">
                                        <ComboBoxItem Content="合并/保留既有变量 / Merge" Tag="merge"/>
                                        <ComboBoxItem Content="同步当前变量 / Sync" Tag="sync"/>
                                    </ComboBox>
                                </WrapPanel>

                                <TextBlock x:Name="lblCompatMode" Text="旧版数据兼容模式" Style="{StaticResource FieldLabel}" Margin="0,9,0,0"/>
                                <ComboBox x:Name="cmbCompatMode" Margin="0,4,0,0" SelectedIndex="1">
                                    <ComboBoxItem Tag="standard" Content="标准增量（已有 Manifest）"/>
                                    <ComboBoxItem Tag="fast" Content="快速兼容（推荐，无 Manifest 自动迁移）"/>
                                    <ComboBoxItem Tag="strict" Content="严格验证（逐帧核对数值）"/>
                                </ComboBox>

                                <WrapPanel Margin="0,9,0,0">
                                    <CheckBox x:Name="chkInPlace" Content="In-place update"
                                              IsChecked="False" Margin="0,0,16,0"/>
                                    <CheckBox x:Name="chkCleanupRemoved"
                                              Content="Delete removed-frame VTUs"
                                              IsChecked="False"/>
                                </WrapPanel>
                                <TextBlock x:Name="txtCompatHint" Text="In-place: temporary files are replaced atomically at the end."
                                           Style="{StaticResource HintText}"/>
                                <TextBlock x:Name="txtPolicyHint" Text="Merge 为安全默认；只有 Sync 才执行删除语义。"
                                           Style="{StaticResource HintText}"/>
                            </StackPanel>
                        </Grid>
                    </DockPanel>
                </Border>

                <Border Grid.Column="2" Style="{StaticResource Card}">
                    <DockPanel>
                        <Border DockPanel.Dock="Top" Style="{StaticResource CardHeader}">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock x:Name="hdrMessages" Text="Output Messages" Style="{StaticResource SectionTitle}"/>
                                <Button x:Name="btnClearMessages"
                                        Grid.Column="1"
                                        Content="Clear"
                                        MinHeight="26"
                                        Padding="11,2"/>
                            </Grid>
                        </Border>

                        <TextBox x:Name="txtMessages"
                                 Height="Auto"
                                 MinHeight="150"
                                 VerticalAlignment="Stretch"
                                 VerticalContentAlignment="Top"
                                 IsReadOnly="True"
                                 BorderThickness="0"
                                 Background="{DynamicResource Bg.Panel}"
                                 FontFamily="Consolas, Cascadia Mono"
                                 FontSize="12"
                                 AcceptsReturn="True"
                                 TextWrapping="NoWrap"
                                 VerticalScrollBarVisibility="Auto"
                                 HorizontalScrollBarVisibility="Auto"
                                 Padding="12"/>
                    </DockPanel>
                </Border>
            </Grid>
        </Grid>
    </DockPanel>
</Window>
"@

# Unified branding. The shipped application icon is applied to the main window
# and to every child window so the title bar / taskbar icon always matches the
# packaged executable. The .ico is preferred (it carries a crisp 16x16 frame),
# the .png is the fallback when the ICO frame cannot be decoded.
$script:iconIco = Join-Path $scriptDir 'icons\odb2vtu-s-exporter.ico'
$script:iconPng = Join-Path $scriptDir 'icons\odb2vtu-s-exporter.png'

function Set-AppIcon($win){
    if($win -eq $null){ return }
    foreach($p in @($script:iconIco, $script:iconPng)){
        if([string]::IsNullOrWhiteSpace($p)){ continue }
        if(-not (Test-Path -LiteralPath $p)){ continue }
        try{
            $fs = [IO.File]::Open($p, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try{
                $frame = [Windows.Media.Imaging.BitmapFrame]::Create($fs)
                if($frame -ne $null){ $win.Icon = $frame; return }
            } finally { $fs.Close() }
        } catch { }
    }
}

# Every window carries the same base name; only the role suffix differs.
function Get-AppTitle([string]$role){
    $base = L "Window"
    if([string]::IsNullOrWhiteSpace($role)){ return $base }
    return $base + " - " + $role
}

$window = [Windows.Markup.XamlReader]::Parse($xaml)
Set-AppIcon $window

$names = @(
"menuFile","miOpen","miExit","menuEdit","menuView","menuTools","miCurveData","miFieldAnalysis","miCPFEM","miDataSafety","menuHelp",
"tbOpen","tbOpenFolder","tbOpenText","tbOpenFolderText","lblTheme","cmbTheme","lblLanguage","cmbLanguage",
"stepDot1","stepNum1","stepLbl1","stepDot2","stepNum2","stepLbl2","stepDot3","stepNum3","stepLbl3","stepDot4","stepNum4","stepLbl4","stepDot5","stepNum5","stepLbl5","btnNextStep","btnNextStepText",
"hdrProperties","btnReset","btnResetText","cardOutput",
"navList","navGroupData","navSource","navTarget","navGroupSeries","navSeries","navGroupFields","navFields","navDerived","navGND","navDifference",
"hdrSource","hdrTarget","hdrSeries","hdrFields","hdrDerived","hdrGND","hdrDifference",
"grpSource","lblOdbFile","txtOdb","btnBrowse","btnRead",
"grpTarget","lblTargetSel","lblInstance","cmbInstance","lblElementSet","cmbElementSet","lblTargetBrowse","lblStep","cmbStep","lblFrame","cmbFrame","txtTargetHint",
"grpSeries","chkSeries","panelSeries","txtSeriesHint","lblSeriesStep","panelSeriesSteps",
"lblAvailableFrames","panelAvailableFrames","btnAddFrames","btnAddAllFrames",
"lblSelectedStates","panelSelectedStates","btnRemoveStates","btnClearStates",
"grpFields","btnReadFields","btnSelectAllFields","btnClearFields","panelFields",
"grpDerived","chkMises","chkInitialIPF","lblInpFile","txtInp","btnBrowseInp","lblIPFDir","cmbIPFDir","txtDerivedHint",
"grpGND","chkGNDDiff","lblGNDDat","txtGNDDat","btnBrowseGNDDat","lblGNDMode","cmbGNDMode","chkGNDSlideDiff","lblGNDSlideRef","cmbGNDSlideRef","txtGNDHint",
"grpDifference","chkDelta","lblDiffField","cmbDeltaField","lblRefStep","cmbRefStep","lblRefFrame","cmbRefFrame",
"lblBBox","txtBBox","chkAutoOutput","btnChooseOutputFolder","lblOutputFile","txtOutput","btnBrowseOutput",
"cmbFramePolicy","cmbFieldPolicy","cmbCompatMode","lblCompatMode","txtCompatHint","chkInPlace","chkCleanupRemoved",
"lblIncPolicy","txtPolicyHint",
"hdrSummary","txtSummary","hdrMessages","btnClearMessages","txtMessages",
"txtStatus","txtStatusRight"
)
foreach($n in $names){
    Set-Variable -Name $n -Value $window.FindName($n) -Scope Script
}

# ---- option tree -> page switch ---------------------------------------------
# The properties card shows one section at a time (tree item on the left, that
# section's options on the right). Every section element keeps its name, so the
# wizard gating and the language switch keep working on hidden pages.
$script:navPageByName = @{
    "Source"     = $grpSource
    "Target"     = $grpTarget
    "Series"     = $grpSeries
    "Fields"     = $grpFields
    "Derived"    = $grpDerived
    "GND"        = $grpGND
    "Difference" = $grpDifference
}

function Show-NavPage([string]$key){
    if([string]::IsNullOrEmpty($key)){ return }

    foreach($k in $script:navPageByName.Keys){
        $p = $script:navPageByName[$k]
        if($p -eq $null){ continue }
        if($k -eq $key){ $p.Visibility = [Windows.Visibility]::Visible }
        else { $p.Visibility = [Windows.Visibility]::Collapsed }
    }

    # Keep the tree highlight in sync when the wizard jumps to a section.
    if($navList -ne $null){
        foreach($it in $navList.Items){
            if($it.Tag -ne $null -and $it.Tag.ToString() -eq $key){
                if($navList.SelectedItem -ne $it){ $navList.SelectedItem = $it }
                break
            }
        }
    }
}

# Guided-rail element cache: built once because the rail is refreshed on every
# summary update (i.e. on every keystroke in the bounding-box / ODB fields).
$script:wizardUi = @()
for($wi = 1; $wi -le 5; $wi++){
    $script:wizardUi += [pscustomobject]@{
        Dot   = (Get-Variable -Name ("stepDot$wi") -Scope Script -ValueOnly)
        Num   = (Get-Variable -Name ("stepNum$wi") -Scope Script -ValueOnly)
        Label = (Get-Variable -Name ("stepLbl$wi") -Scope Script -ValueOnly)
    }
}
$script:wizardStep = 0
$script:wizardAction = $null

$global:meta = $null
$script:lang = "zh"
$script:fieldBoxes = New-Object System.Collections.Generic.List[object]
# Time-series panel lists use checkboxes (like the field list) so multi-selection
# needs no Ctrl/Shift.
$script:seriesStepBoxes = New-Object System.Collections.Generic.List[object]
$script:frameBoxes = New-Object System.Collections.Generic.List[object]
$script:stateBoxes = New-Object System.Collections.Generic.List[object]

# ---- checkbox multi-selection ------------------------------------------------
# Every checkbox list keeps working as a plain tick list, but also honours the
# familiar file-manager gestures:
#   plain click / Ctrl+click : toggle the single clicked box
#   Shift+click              : toggle every box between the last clicked box and
#                              the clicked one (the clicked box sets the value)
# The last clicked index is remembered per list in $script:checkAnchors.
$script:checkAnchors = @{}

function Set-CheckRangeValue($list, $anchors, [string]$key, [int]$idx, [bool]$shift){
    if($list -eq $null -or $anchors -eq $null){ return }
    if($idx -lt 0 -or $idx -ge $list.Count){ return }

    $val = [bool]$list[$idx].IsChecked
    $a = [int]$anchors[$key]

    if($shift -and $a -ge 0 -and $a -lt $list.Count -and $a -ne $idx){
        $lo = [Math]::Min($a, $idx)
        $hi = [Math]::Max($a, $idx)
        for($j = $lo; $j -le $hi; $j++){
            if($j -ne $idx){ $list[$j].IsChecked = $val }
        }
        # Keep the original anchor so repeated Shift+clicks grow / shrink one range.
    } else {
        $anchors[$key] = $idx
    }
}

function Enable-CheckListKeys([string]$key, $boxes, $after = $null){
    if($boxes -eq $null -or $boxes.Count -eq 0){ return }

    $anchors = $script:checkAnchors
    $anchors[$key] = -1

    for($i = 0; $i -lt $boxes.Count; $i++){
        $box   = $boxes[$i]
        $list  = $boxes
        $idx   = $i
        $k     = $key
        $tail  = $after

        $box.Add_Click({
            $shift = (([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Shift) -ne 0)
            Set-CheckRangeValue $list $anchors $k $idx $shift
            if($tail -ne $null){ & $tail }
        }.GetNewClosure())
    }
}

# Each entry: PSCustomObject {Step, Frame, Display}
$script:selectedStates = New-Object System.Collections.ArrayList

$T = @{
en = @{
Window="ODB2VTU-S Workbench"; File="_File"; Open="Open ODB..."; Exit="Exit"; Edit="_Edit"; View="_View"; Tools="_Tools"; Help="_Help";
OpenODB="Open ODB"; ReadMeta="Read Metadata"; ReadFields="Read Fields"; Export="Export Data"; OpenFolder="Open Output Folder"; Language="Language"; Theme="Theme"; ThemeLight="Light"; ThemeDark="Dark";
Properties="Properties"; CurveData="Curve Data..."; FieldAnalysis="Field Extremum Analysis..."; CPFEM="Friction CPFEM (History / PEEQCP)..."; DataSafety="Data Diagnosis and Safe Recovery..."; Apply="Apply"; Reset="Reset";
Source="Source"; ODBFile="ODB File"; Target="Target"; Instance="Instance"; ElementSet="Element Set"; Step="Step"; Frame="Frame";
NavGroupData="Data / target"; NavGroupSeries="Time series"; NavGroupFields="Field variables";
TargetSelection="Selection (export scope)"; TargetBrowse="Browse / verify (no selection needed)";
TargetHint="Step / Frame are only used to browse and cross-check the ODB (for reading field variables). In single-frame mode the exported frame is the one being browsed; in time-series mode the ticked states above decide the export.";
Series="Time Series"; EnableSeries="Export as ParaView time series (.pvd)";
SeriesHint="Tick Steps (Shift / Ctrl selects ranges), then tick the frames to add. Drag the vertical divider to widen the list area.";
SeriesStep="Steps"; AvailableFrames="Common frames"; AddFrames="Add ticked frames"; AddAllFrames="Add all frames";
SelectedStates="Selected Step / Frame states"; RemoveStates="Remove ticked"; ClearStates="Clear all";
Fields="Fields"; ReadFrameFields="Read fields from selected frame"; SelectAll="Select all"; Clear="Clear"; Derived="Derived Fields"; Mises="Mises Stress"; InitialIPF="Initial IPF (HCP Ti)"; INPFile="INP File"; IPFDirection="IPF Direction"; DerivedHint="Mises is derived from S. Initial IPF reads Grain material Euler angles from INP PROPS(1:3)."; GND="GND Evolution"; GNDDiff="Compare gnd_field.dat with SDV11-28"; GNDDat="GND DAT"; GNDMode="Output"; GNDHint="DAT difference uses gnd_field.dat. Sliding-start difference uses a fixed ODB baseline and outputs 18 slip-system increments."; GNDSlideDiff="Sliding-start difference (18 slip systems)"; GNDSlideRef="Reference";
Difference="Difference"; EnableDiff="Enable target - reference"; DiffField="Field"; RefStep="Reference Step"; RefFrame="Reference Frame";
BBox="Bounding Box"; AutoOutput="Auto-match ODB output folder"; SelectOutputFolder="Select Output Folder..."; OutputFile="Output File"; Summary="Selection Summary"; Messages="Output Messages";
IncPolicy="Incremental Update Policy"; PolicyHint="Merge is the safe default; only Sync deletes.";
Ready="Ready"; NoODB="ODB: not loaded"; Whole="<Whole Instance>"; AllGrains="<All Grains>";
SeriesCount="Selected states";
StepSource="Source"; StepState="State"; StepFields="Fields"; StepOutput="Output"; StepExport="Export"; Next="Next";
PickState="Select instance / element set"; PickFields="Select fields to export"; PickOutput="Choose output file"
}
zh = @{
Window="ODB2VTU-S 统一工作台"; File="_文件"; Open="打开 ODB..."; Exit="退出"; Edit="_编辑"; View="_视图"; Tools="_工具"; Help="_帮助";
OpenODB="打开 ODB"; ReadMeta="读取元数据"; ReadFields="读取场变量"; Export="导出数据"; OpenFolder="打开输出文件夹"; Language="语言"; Theme="主题"; ThemeLight="亮色"; ThemeDark="深色";
Properties="属性"; CurveData="曲线数据..."; FieldAnalysis="场变量极值分析..."; CPFEM="摩擦 CPFEM 后处理（History / PEEQCP）..."; DataSafety="数据诊断与安全恢复..."; Apply="应用"; Reset="重置";
Source="数据源"; ODBFile="ODB 文件"; Target="目标状态"; Instance="实例"; ElementSet="单元集"; Step="分析步"; Frame="帧";
NavGroupData="数据与目标"; NavGroupSeries="时序"; NavGroupFields="场变量";
TargetSelection="选择项（决定导出范围）"; TargetBrowse="浏览 / 核对（无需选择）";
TargetHint="分析步 / 帧 只用于浏览和核对 ODB（读取场变量时使用）。单帧模式下导出当前浏览的这一帧；时序模式下以上方勾选的分析步与帧为准。";
Series="时间序列"; EnableSeries="导出为 ParaView 时间序列 (.pvd)";
SeriesHint="勾选分析步（Shift / Ctrl 可整段勾选），再勾选要添加的帧。名称显示不全时可拖动竖向分隔条加宽。";
SeriesStep="分析步（可多选）"; AvailableFrames="公共可选帧"; AddFrames="添加勾选的帧"; AddAllFrames="添加全部帧";
SelectedStates="已选分析步 / 帧"; RemoveStates="移除勾选项"; ClearStates="清空全部";
Fields="场变量"; ReadFrameFields="读取当前帧场变量"; SelectAll="全选"; Clear="清空"; Derived="派生场"; Mises="Mises 应力"; InitialIPF="初始 IPF（HCP Ti）"; INPFile="INP 文件"; IPFDirection="IPF 方向"; DerivedHint="Mises 由 S 计算；初始 IPF 从 INP 中各 Grain 材料的 PROPS(1:3) 欧拉角生成。"; GND="GND 增量"; GNDDiff="计算 gnd_field.dat 与 SDV11-28 差值"; GNDDat="GND DAT"; GNDMode="输出"; GNDHint="DAT差值：当前SDV11-28减去gnd_field.dat初始分配值；滑动起点差值：当前SDV11-28减去滑动开始参考帧。均输出18个滑移系。"; GNDSlideDiff="滑动起点差值（18滑移系）"; GNDSlideRef="参考帧";
Difference="差值"; EnableDiff="启用 目标帧 - 参考帧"; DiffField="场变量"; RefStep="参考分析步"; RefFrame="参考帧";
BBox="包围盒"; AutoOutput="自动匹配 ODB 输出目录"; SelectOutputFolder="选择输出文件夹..."; OutputFile="输出文件"; Summary="选择摘要"; Messages="输出消息";
IncPolicy="增量更新策略"; PolicyHint="Merge 为安全默认；只有 Sync 才执行删除语义。";
Ready="就绪"; NoODB="ODB：未加载"; Whole="<整个实例>"; AllGrains="<所有晶粒>";
SeriesCount="已选状态数";
StepSource="数据源"; StepState="目标状态"; StepFields="场变量"; StepOutput="输出"; StepExport="导出"; Next="下一步";
PickState="选择实例 / 单元集"; PickFields="选择要导出的场变量"; PickOutput="选择输出文件"
}
}

function L([string]$k){ return $T[$script:lang][$k] }

# Visible WPF strings only. Never mutate Tag, x:Name, command arguments or array identifiers.
function Localize-SubwindowXaml([xml]$Document, [string]$Lang) {
    $pairs = @{
      'Field Extremum Analysis'=@('场变量极值分析','Field Extremum Analysis')
      'ODB2VTU-S Workbench - Field Extremum Analysis'=@('ODB2VTU-S 统一工作台 - 场变量极值分析','ODB2VTU-S Workbench - Field Extremum Analysis')
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
$script:exportProc = $null

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
    Ensure-WinForms
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
    return '"' + ($s -replace '"','""') + '"'
}

function FrameIndex($combo){
    if($combo.SelectedItem -eq $null){ return -1 }
    return [int](($combo.SelectedItem.ToString().Split("|")[0]).Trim())
}

function FrameIndexFromLabel([string]$label){
    return [int](($label.Split("|")[0]).Trim())
}

function Write-LogBox($box, [string]$s){
    $box.AppendText("[" + (Get-Date -Format "HH:mm:ss") + "] " + $s + "`r`n")
    # Keep the console bounded so very long series exports cannot slow the UI down.
    if($box.LineCount -gt 4000){
        $lines = $box.Text -split "`r?`n"
        $box.Text = ($lines[($lines.Count - 2000)..($lines.Count - 1)] -join "`r`n")
    }
    $box.ScrollToEnd()
}

function Msg([string]$s){
    Write-LogBox $txtMessages $s
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
    foreach($cb in $script:seriesStepBoxes){
        if($cb.IsChecked){ $steps.Add($cb.Tag.ToString()) }
    }
    return $steps
}

function PopulateCommonSeriesFrames {
    $panelAvailableFrames.Children.Clear()
    $script:frameBoxes.Clear()

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
        $cbF = New-Object Windows.Controls.CheckBox
        $cbF.Content = $lab
        $cbF.Tag = $lab
        $cbF.Margin = "0,1,0,1"
        [void]$panelAvailableFrames.Children.Add($cbF)
        $script:frameBoxes.Add($cbF)
    }

    Enable-CheckListKeys "frames" $script:frameBoxes
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
    $panelSelectedStates.Children.Clear()
    $script:stateBoxes.Clear()

    if($global:meta -eq $null){
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

    foreach($x in $sorted){
        $label = $x.Step + "  |  Frame " + $x.Frame
        $cbS = New-Object Windows.Controls.CheckBox
        $cbS.Content = $label
        $cbS.Tag = $label
        $cbS.Margin = "0,1,0,1"
        [void]$panelSelectedStates.Children.Add($cbS)
        $script:stateBoxes.Add($cbS)
    }

    Enable-CheckListKeys "states" $script:stateBoxes
    UpdateSummary
}

function AddFramesToSelectedSteps([bool]$allFrames){
    $steps = GetSelectedSeriesSteps
    if($steps.Count -eq 0){ return }

    $labels = @()

    if($allFrames){
        foreach($cb in $script:frameBoxes){
            $labels += $cb.Tag.ToString()
        }
    } else {
        foreach($cb in $script:frameBoxes){
            if($cb.IsChecked){ $labels += $cb.Tag.ToString() }
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
    foreach($cb in $script:stateBoxes){
        if($cb.IsChecked){ $labels += $cb.Tag.ToString() }
    }

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

function Set-WizardEnabled($el, [bool]$on){
    if($el -eq $null){ return }
    $el.IsEnabled = $on
    if($on){ $el.Opacity = 1.0 } else { $el.Opacity = 0.55 }
}

# Guided workflow. Five steps: 1 source, 2 target state, 3 fields, 4 output,
# 5 export. The first unfinished step becomes "current"; everything after it is
# disabled and dimmed so the user is walked through the workflow in order, while
# earlier steps stay editable so corrections are always possible. The rail's
# call-to-action button runs, or focuses, whatever the current step still needs.
function Update-WizardState {
    if($window -eq $null -or $script:wizardUi.Count -eq 0){ return }

    $s1 = ($global:meta -ne $null)

    # Step 2 is satisfied by the real selections (instance / element set, plus at
    # least one ticked Step-Frame state in time-series mode). Step and Frame are
    # browse-only helpers and never block the workflow.
    $s2 = ($cmbInstance.SelectedItem -ne $null -and $cmbElementSet.SelectedItem -ne $null)
    if([bool]$chkSeries.IsChecked){
        $s2 = $s2 -and ($script:selectedStates.Count -gt 0)
    }

    $s3 = (@(SelectedFields).Count -gt 0)
    if(-not $s3){
        $s3 = [bool]$chkMises.IsChecked -or [bool]$chkInitialIPF.IsChecked -or
              [bool]$chkGNDDiff.IsChecked -or [bool]$chkGNDSlideDiff.IsChecked
    }

    $s4 = -not [string]::IsNullOrWhiteSpace($txtOutput.Text)

    $done = @($s1, $s2, $s3, $s4)

    $cur = 5
    for($i = 0; $i -lt 4; $i++){
        if(-not $done[$i]){ $cur = $i + 1; break }
    }
    $script:wizardStep = $cur

    for($i = 1; $i -le 5; $i++){
        $u = $script:wizardUi[$i - 1]
        if($u.Dot -eq $null){ continue }
        if($i -lt $cur){
            $u.Dot.Style = $window.Resources['StepDotDone']
            $u.Num.Style = $window.Resources['StepNumberDone']
            $u.Num.Text  = [string][char]0x2713
            $u.Label.Style = $window.Resources['StepLabelDone']
        } elseif($i -eq $cur){
            $u.Dot.Style = $window.Resources['StepDotCurrent']
            $u.Num.Style = $window.Resources['StepNumberCurrent']
            $u.Num.Text  = [string]$i
            $u.Label.Style = $window.Resources['StepLabelCurrent']
        } else {
            $u.Dot.Style = $window.Resources['StepDot']
            $u.Num.Style = $window.Resources['StepNumber']
            $u.Num.Text  = [string]$i
            $u.Label.Style = $window.Resources['StepLabel']
        }
    }

    Set-WizardEnabled $grpTarget     ($cur -ge 2)
    Set-WizardEnabled $grpSeries     ($cur -ge 2)
    Set-WizardEnabled $grpFields     ($cur -ge 3)
    Set-WizardEnabled $grpDerived    ($cur -ge 3)
    Set-WizardEnabled $grpGND        ($cur -ge 3)
    Set-WizardEnabled $grpDifference ($cur -ge 3)
    Set-WizardEnabled $cardOutput    ($cur -ge 4)

    $label = L "Next"
    if($cur -eq 1){
        if([string]::IsNullOrWhiteSpace($txtOdb.Text)){
            $label = L "OpenODB"
            $script:wizardAction = { Show-NavPage "Source"; BrowseODB }
        } else {
            $label = L "ReadMeta"
            $script:wizardAction = { Show-NavPage "Source"; ReadMeta }
        }
    } elseif($cur -eq 2){
        $label = L "PickState"
        $script:wizardAction = {
            Show-NavPage "Target"
            if($cmbInstance.SelectedItem -eq $null -and $cmbInstance.Items.Count -gt 0){
                $cmbInstance.IsDropDownOpen = $true
            } elseif($cmbElementSet.SelectedItem -eq $null -and $cmbElementSet.Items.Count -gt 0){
                $cmbElementSet.IsDropDownOpen = $true
            } elseif([bool]$chkSeries.IsChecked){
                if($script:seriesStepBoxes.Count -gt 0){ $script:seriesStepBoxes[0].Focus() | Out-Null }
            } else {
                Show-NavPage "Target"
            }
        }
    } elseif($cur -eq 3){
        if($script:fieldBoxes.Count -eq 0){
            $label = L "ReadFields"
            $script:wizardAction = { Show-NavPage "Fields"; ReadFields }
        } else {
            $label = L "PickFields"
            $script:wizardAction = {
                Show-NavPage "Fields"
                if($script:fieldBoxes.Count -gt 0){ $script:fieldBoxes[0].Focus() | Out-Null }
            }
        }
    } elseif($cur -eq 4){
        $label = L "PickOutput"
        $script:wizardAction = { $txtOutput.Focus() | Out-Null }
    } else {
        $label = L "Export"
        $script:wizardAction = { RunExport }
    }
    $btnNextStepText.Text = $label
}

function ApplyLanguage {
    $window.Title = L "Window"
    $menuFile.Header = L "File"; $miOpen.Header = L "Open"; $miExit.Header = L "Exit"
    $menuEdit.Header = L "Edit"; $menuView.Header = L "View"; $menuTools.Header = L "Tools"; $miCurveData.Header = L "CurveData"; $miFieldAnalysis.Header = L "FieldAnalysis"; $menuHelp.Header = L "Help"
    $miCPFEM.Header = L "CPFEM"; $miDataSafety.Header = L "DataSafety"

    $tbOpenText.Text = L "OpenODB"; $tbOpenFolderText.Text = L "OpenFolder"
    $lblLanguage.Text = L "Language"
    $lblTheme.Text = L "Theme"
    $cmbTheme.Items[0].Content = L "ThemeLight"
    $cmbTheme.Items[1].Content = L "ThemeDark"
    if($script:lang -eq 'zh') {
        $cmbFramePolicy.Items[0].Content='合并／保留既有帧'
        $cmbFramePolicy.Items[1].Content='同步当前所选帧'
        $cmbFieldPolicy.Items[0].Content='合并／保留既有变量'
        $cmbFieldPolicy.Items[1].Content='同步当前变量'
        $chkCleanupRemoved.Content='同步时删除已移除的帧'
        $lblCompatMode.Text='旧版数据兼容模式'
        $cmbCompatMode.Items[0].Content='标准增量（已有 Manifest）'
        $cmbCompatMode.Items[1].Content='快速兼容（无 Manifest，两帧抽样）'
        $cmbCompatMode.Items[2].Content='严格验证（逐帧核对数值）'
        $chkInPlace.Content='原位增量更新'
        $txtCompatHint.Text='原位更新：同目录临时写入，成功后原子替换原 VTU。'
    } else {
        $cmbFramePolicy.Items[0].Content='Merge / preserve existing frames'
        $cmbFramePolicy.Items[1].Content='Sync current selection'
        $cmbFieldPolicy.Items[0].Content='Merge / preserve existing fields'
        $cmbFieldPolicy.Items[1].Content='Sync selected fields'
        $chkCleanupRemoved.Content='Delete removed-frame VTUs'
        $lblCompatMode.Text='Legacy compatibility mode'
        $cmbCompatMode.Items[0].Content='Standard incremental (Manifest exists)'
        $cmbCompatMode.Items[1].Content='Fast legacy (two sampled states)'
        $cmbCompatMode.Items[2].Content='Strict (verify native values per frame)'
        $chkInPlace.Content='In-place update'
        $txtCompatHint.Text='In-place: temporary files are replaced atomically at the end.'
    }
    $lblIncPolicy.Text = L "IncPolicy"
    $txtPolicyHint.Text = L "PolicyHint"

    $hdrProperties.Text = L "Properties"; $btnResetText.Text = L "Reset"

    $stepLbl1.Text = L "StepSource"; $stepLbl2.Text = L "StepState"; $stepLbl3.Text = L "StepFields"; $stepLbl4.Text = L "StepOutput"; $stepLbl5.Text = L "StepExport"

    # Option tree: group captions + the seven section items (same titles as the pages).
    $navGroupData.Content = L "NavGroupData"; $navGroupSeries.Content = L "NavGroupSeries"; $navGroupFields.Content = L "NavGroupFields"
    $navSource.Content = L "Source"; $navTarget.Content = L "Target"; $navSeries.Content = L "Series"
    $navFields.Content = L "Fields"; $navDerived.Content = L "Derived"; $navGND.Content = L "GND"; $navDifference.Content = L "Difference"

    $hdrSource.Text = L "Source"; $lblOdbFile.Text = L "ODBFile"; $btnRead.Content = L "ReadMeta"
    $hdrTarget.Text = L "Target"; $lblInstance.Text = L "Instance"; $lblElementSet.Text = L "ElementSet"; $lblStep.Text = L "Step"; $lblFrame.Text = L "Frame"
    $lblTargetSel.Text = L "TargetSelection"; $lblTargetBrowse.Text = L "TargetBrowse"; $txtTargetHint.Text = L "TargetHint"

    $hdrSeries.Text = L "Series"; $chkSeries.Content = L "EnableSeries"; $txtSeriesHint.Text = L "SeriesHint"
    $lblSeriesStep.Text = L "SeriesStep"; $lblAvailableFrames.Text = L "AvailableFrames"
    $btnAddFrames.Content = L "AddFrames"; $btnAddAllFrames.Content = L "AddAllFrames"
    $lblSelectedStates.Text = L "SelectedStates"; $btnRemoveStates.Content = L "RemoveStates"; $btnClearStates.Content = L "ClearStates"

    $hdrFields.Text = L "Fields"; $btnReadFields.Content = L "ReadFrameFields"; $btnSelectAllFields.Content = L "SelectAll"; $btnClearFields.Content = L "Clear"
    $hdrDerived.Text = L "Derived"; $chkMises.Content = L "Mises"; $chkInitialIPF.Content = L "InitialIPF"; $lblInpFile.Text = L "INPFile"; $lblIPFDir.Text = L "IPFDirection"; $txtDerivedHint.Text = L "DerivedHint"
    $hdrGND.Text = L "GND"; $chkGNDDiff.Content = L "GNDDiff"; $lblGNDDat.Text = L "GNDDat"; $lblGNDMode.Text = L "GNDMode"; $chkGNDSlideDiff.Content = L "GNDSlideDiff"; $lblGNDSlideRef.Text = L "GNDSlideRef"; $txtGNDHint.Text = L "GNDHint"

    $hdrDifference.Text = L "Difference"; $chkDelta.Content = L "EnableDiff"; $lblDiffField.Text = L "DiffField"; $lblRefStep.Text = L "RefStep"; $lblRefFrame.Text = L "RefFrame"

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

    Update-WizardState
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
        $panelSelectedStates.Children.Clear()
        $script:stateBoxes.Clear()

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

    $global:meta = $null
    try{
        $global:meta = Get-Content $metaJson -Raw | ConvertFrom-Json
    } catch {
        Msg("Metadata JSON invalid: " + $_.Exception.Message)
        [Windows.MessageBox]::Show("Metadata read failed.")
        return
    }

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

    $panelSeriesSteps.Children.Clear()
    $script:seriesStepBoxes.Clear()
    foreach($n in $global:meta.steps.PSObject.Properties.Name){
        $nf = [int]$global:meta.steps.$n.nframes
        $cbStep = New-Object Windows.Controls.CheckBox
        $cbStep.Content = $n + "  [" + $nf + " frames]"
        $cbStep.Tag = $n
        $cbStep.Margin = "0,1,0,1"
        $cbStep.Add_Checked({
            if($global:meta -eq $null){ return }
            PopulateCommonSeriesFrames
            UpdateSummary
        })
        $cbStep.Add_Unchecked({
            if($global:meta -eq $null){ return }
            PopulateCommonSeriesFrames
            UpdateSummary
        })
        [void]$panelSeriesSteps.Children.Add($cbStep)
        $script:seriesStepBoxes.Add($cbStep)
    }

    Enable-CheckListKeys "seriesSteps" $script:seriesStepBoxes

    if($cmbStep.Items.Count -gt 0){
        $cmbStep.SelectedIndex = 0
        $cmbRefStep.SelectedIndex = 0
    }

    if($script:seriesStepBoxes.Count -gt 0){
        $script:seriesStepBoxes[0].IsChecked = $true
    }

    $script:selectedStates.Clear()
    $panelSelectedStates.Children.Clear()
    $script:stateBoxes.Clear()

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

    try{ $j = Get-Content $fieldsJson -Raw | ConvertFrom-Json }
    catch { Msg("Field JSON invalid: " + $_.Exception.Message); return }

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

    # Shift / Ctrl range ticks; the summary is refreshed once after the range.
    Enable-CheckListKeys "fields" $script:fieldBoxes { UpdateSummary }

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
    if($script:exportProc -ne $null){
        try{ if(-not $script:exportProc.HasExited){
            [Windows.MessageBox]::Show("An export is already running. Wait for the export console to finish.")
            return
        } }catch{ }
    }

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
        'echo ODB2VTU-S v0.2.1-rc10 - SAFE VTU / PVD export'
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
    $script:exportProc = Start-Process cmd.exe -ArgumentList "/k",(Q $runnerPath) -PassThru
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
        Title="ODB2VTU-S Workbench - Field Extremum Analysis"
        Width="1000" Height="740" MinWidth="820" MinHeight="600"
        WindowStartupLocation="CenterOwner"
        Background="{DynamicResource Bg.Window}"
        Foreground="{DynamicResource Fg.Text}"
        FontFamily="Segoe UI, Microsoft YaHei UI, Microsoft YaHei" FontSize="13"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Window.Resources>
$(Get-ThemeBrushXaml $script:theme)
$themeStyles
  </Window.Resources>
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="{DynamicResource Bg.Toolbar}" BorderBrush="{DynamicResource Border.Default}" BorderThickness="0,0,0,1" Padding="12,10">
      <StackPanel Orientation="Horizontal">
        <Button x:Name="aBtnReadFields">
          <StackPanel Orientation="Horizontal">
            <Path Style="{StaticResource ToolIcon}" Data="{StaticResource IcoMeta}"/>
            <TextBlock Text="读取可分析变量 / Read Variables" VerticalAlignment="Center"/>
          </StackPanel>
        </Button>
        <Button x:Name="aBtnRun" Margin="8,0,0,0" Style="{StaticResource PrimaryButton}">
          <StackPanel Orientation="Horizontal">
            <Path Style="{StaticResource ToolIconOnAccent}" Data="{StaticResource IcoRun}"/>
            <TextBlock Text="运行分析 / Run Analysis" VerticalAlignment="Center"/>
          </StackPanel>
        </Button>
        <Button x:Name="aBtnOpen" Margin="8,0,0,0">
          <StackPanel Orientation="Horizontal">
            <Path Style="{StaticResource ToolIcon}" Data="{StaticResource IcoFolder}"/>
            <TextBlock Text="打开输出目录 / Open Folder" VerticalAlignment="Center"/>
          </StackPanel>
        </Button>
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
              <TextBlock Text="只分析晶粒单元；可选 Bounding Box：xmin,xmax,ymin,ymax,zmin,zmax" TextWrapping="Wrap" Foreground="{DynamicResource Fg.TextMuted}"/>
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
                         Foreground="{DynamicResource Fg.TextMuted}" TextWrapping="Wrap" Margin="0,6,0,0"/>
            </StackPanel>
          </GroupBox>
        </StackPanel>
      </ScrollViewer>

      <GridSplitter Grid.Column="1" Width="8" HorizontalAlignment="Stretch" Cursor="SizeWE"/>
      <Border Grid.Column="2" Style="{StaticResource Card}">
        <DockPanel>
          <Border DockPanel.Dock="Top" Style="{StaticResource CardHeader}"><TextBlock Text="Analysis Log / 分析结果" Style="{StaticResource SectionTitle}"/></Border>
          <TextBox x:Name="aTxtLog" IsReadOnly="True" BorderThickness="0" Height="Auto" MinHeight="120" VerticalAlignment="Stretch" VerticalContentAlignment="Top" AcceptsReturn="True" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" FontFamily="Consolas, Cascadia Mono" Background="{DynamicResource Bg.Panel}" Padding="12"/>
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
    Set-AppIcon $aw
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
        Ensure-WinForms
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
        try{ $j=Get-Content $analysisFieldsJson -Raw | ConvertFrom-Json }
        catch { [Windows.MessageBox]::Show("Field list read failed."); return }
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
        Title="ODB2VTU-S Workbench - Curve Data"
        Width="1140" Height="780"
        MinWidth="900" MinHeight="620"
        WindowStartupLocation="CenterOwner"
        Background="{DynamicResource Bg.Window}"
        Foreground="{DynamicResource Fg.Text}"
        FontFamily="Segoe UI, Microsoft YaHei UI, Microsoft YaHei"
        FontSize="13"
        UseLayoutRounding="True" SnapsToDevicePixels="True">

    <Window.Resources>
$(Get-ThemeBrushXaml $script:theme)
$themeStyles
    </Window.Resources>

    <DockPanel>
        <Border DockPanel.Dock="Top"
                Background="{DynamicResource Bg.Toolbar}"
                BorderBrush="{DynamicResource Border.Default}"
                BorderThickness="0,0,0,1"
                Padding="12,10">
            <StackPanel Orientation="Horizontal">
                <Button x:Name="cBtnReadMeta">
                    <StackPanel Orientation="Horizontal">
                        <Path Style="{StaticResource ToolIcon}" Data="{StaticResource IcoMeta}"/>
                        <TextBlock Text="Read History Metadata" VerticalAlignment="Center"/>
                    </StackPanel>
                </Button>
                <Button x:Name="cBtnExport" Margin="8,0,0,0" Style="{StaticResource PrimaryButton}">
                    <StackPanel Orientation="Horizontal">
                        <Path Style="{StaticResource ToolIconOnAccent}" Data="{StaticResource IcoExport}"/>
                        <TextBlock Text="Export CSV" VerticalAlignment="Center"/>
                    </StackPanel>
                </Button>
                <Button x:Name="cBtnFriction" Margin="8,0,0,0">
                    <StackPanel Orientation="Horizontal">
                        <Path Style="{StaticResource ToolIcon}" Data="{StaticResource IcoChart}"/>
                        <TextBlock Text="Friction CSV (ALL/NORMAL/TANGENTIAL/DIAGNOSTIC)" VerticalAlignment="Center"/>
                    </StackPanel>
                </Button>
                <Button x:Name="cBtnOpenFolder" Margin="8,0,0,0">
                    <StackPanel Orientation="Horizontal">
                        <Path Style="{StaticResource ToolIcon}" Data="{StaticResource IcoFolder}"/>
                        <TextBlock Text="Open Output Folder" VerticalAlignment="Center"/>
                    </StackPanel>
                </Button>
            </StackPanel>
        </Border>

        <StatusBar DockPanel.Dock="Bottom" Height="28">
            <StatusBarItem>
                <TextBlock x:Name="cStatus" Text="Ready" Foreground="{DynamicResource Fg.TextMuted}"/>
            </StatusBarItem>
        </StatusBar>

        <Grid>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="390" MinWidth="330"/>
                <ColumnDefinition Width="8"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <ScrollViewer Grid.Column="0"
                          VerticalScrollBarVisibility="Auto"
                          Background="{DynamicResource Bg.Window}">
                <StackPanel Margin="10">

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
                            <TextBlock x:Name="cLblSteps" Text="Steps (tick one or more)"/>
                            <Border Height="145"
                                    Margin="0,3,0,7"
                                    Background="{DynamicResource Bg.Inset}"
                                    BorderBrush="{DynamicResource Border.Control}"
                                    BorderThickness="1"
                                    CornerRadius="6">
                                <ScrollViewer VerticalScrollBarVisibility="Auto">
                                    <StackPanel x:Name="cPanelSteps" Margin="8"/>
                                </ScrollViewer>
                            </Border>

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
                          Width="8"
                          ResizeDirection="Columns"
                          ResizeBehavior="PreviousAndNext"
                          Cursor="SizeWE"/>

            <Grid Grid.Column="2" Margin="10,10,10,10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="8"/>
                    <RowDefinition Height="210"/>
                </Grid.RowDefinitions>

                <GroupBox Grid.Row="0" Header="Output" Margin="0,0,0,10">
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

                <Border Grid.Row="1" Style="{StaticResource Card}">
                    <DockPanel>
                        <Border DockPanel.Dock="Top" Style="{StaticResource CardHeader}">
                            <TextBlock x:Name="cHdrSummary" Text="Curve Summary" Style="{StaticResource SectionTitle}"/>
                        </Border>
                        <TextBox x:Name="cTxtSummary"
                                 Height="Auto"
                                 VerticalAlignment="Stretch"
                                 VerticalContentAlignment="Top"
                                 IsReadOnly="True"
                                 BorderThickness="0"
                                 Background="{DynamicResource Bg.Panel}"
                                 AcceptsReturn="True"
                                 TextWrapping="Wrap"
                                 VerticalScrollBarVisibility="Auto"
                                 FontFamily="Consolas, Cascadia Mono"
                                 FontSize="12.5"
                                 Padding="12"/>
                    </DockPanel>
                </Border>

                <GridSplitter Grid.Row="2" Height="8" HorizontalAlignment="Stretch" ResizeDirection="Rows" ResizeBehavior="PreviousAndNext" Cursor="SizeNS"/>

                <Border Grid.Row="3" Style="{StaticResource Card}">
                    <DockPanel>
                        <Border DockPanel.Dock="Top" Style="{StaticResource CardHeader}">
                            <TextBlock x:Name="cHdrMessages" Text="Messages" Style="{StaticResource SectionTitle}"/>
                        </Border>
                        <TextBox x:Name="cTxtMessages"
                                 Height="Auto"
                                 VerticalAlignment="Stretch"
                                 VerticalContentAlignment="Top"
                                 IsReadOnly="True"
                                 BorderThickness="0"
                                 Background="{DynamicResource Bg.Panel}"
                                 AcceptsReturn="True"
                                 TextWrapping="NoWrap"
                                 VerticalScrollBarVisibility="Auto"
                                 HorizontalScrollBarVisibility="Auto"
                                 FontFamily="Consolas, Cascadia Mono"
                                 FontSize="12"
                                 Padding="12"/>
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
    Set-AppIcon $cw

    $cnames = @(
        "cBtnReadMeta","cBtnExport","cBtnFriction","cBtnOpenFolder","cStatus",
        "cGrpSource","cLblOdb","cTxtOdb","cBtnBrowseOdb",
        "cGrpHistory","cLblSteps","cPanelSteps","cLblRegion","cCmbRegion","cLblRegionFilter","cTxtRegionFilter","cLblNodeLocator","cLblNodeLabel","cTxtNodeLabel","cBtnFindNode","cLblPreset","cCmbPreset",
        "cGrpXY","cLblX","cCmbX","cLblY","cCmbY","cChkAbsX","cChkAbsY",
        "cGrpTransform","cTxtXScale","cTxtXOffset","cTxtYScale","cTxtYOffset","cChkDedupe",
        "cChkAutoOutput","cBtnChooseOutputFolder","cLblOutput","cTxtOutput","cBtnBrowseOutput",
        "cHdrSummary","cTxtSummary","cHdrMessages","cTxtMessages"
    )

    foreach($n in $cnames){
        Set-Variable -Name $n -Value $cw.FindName($n) -Scope Local
    }

    $script:curveMetaV175 = $null
    # Step list uses checkboxes so multi-selection needs no Ctrl/Shift (same as
    # the main window's time-series panel).
    $curveStepBoxes = New-Object System.Collections.Generic.List[object]
    $COF = "COF=|RF1|/|CF2|"

    function CMsg([string]$s){
        Write-LogBox $cTxtMessages $s
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
        foreach($cb in $curveStepBoxes){
            if($cb.IsChecked){ $r.Add($cb.Tag.ToString()) }
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
        Ensure-WinForms
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

        try{ $script:curveMetaV175 = Get-Content $curveMetaJson -Raw | ConvertFrom-Json }
        catch { $cStatus.Text = "History metadata failed"; CMsg("Curve metadata JSON invalid: " + $_.Exception.Message); return }

        $cPanelSteps.Children.Clear()
        $curveStepBoxes.Clear()
        foreach($s in $script:curveMetaV175.steps.PSObject.Properties.Name){
            $cbSt = New-Object Windows.Controls.CheckBox
            $cbSt.Content = $s
            $cbSt.Tag = $s
            $cbSt.Margin = "0,1,0,1"
            $cbSt.Add_Checked({ RefreshCommonRegions; UpdateCurveSummary })
            $cbSt.Add_Unchecked({ RefreshCommonRegions; UpdateCurveSummary })
            [void]$cPanelSteps.Children.Add($cbSt)
            $curveStepBoxes.Add($cbSt)
        }

        if($curveStepBoxes.Count -gt 0){
            $curveStepBoxes[0].IsChecked = $true
        }

        Enable-CheckListKeys "curveSteps" $curveStepBoxes

        $stem = [IO.Path]::GetFileNameWithoutExtension($cTxtOdb.Text)
        if([string]::IsNullOrWhiteSpace($cTxtOutput.Text)){
            Set-CurveOutputPath $cTxtOdb.Text
        }

        $cStatus.Text = "History metadata ready"
        CMsg("History metadata ready.")
        CMsg("History Regions common to the ticked Steps: " + $script:allCommonRegions.Count)
        CMsg("Tick one or more Steps, then choose a History Region / Section.")
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
        $cw.Title = Get-AppTitle "曲线数据"
        $cBtnReadMeta.Content = "读取 History 元数据"
        $cBtnExport.Content = "导出 CSV"
        $cBtnFriction.Content = "导出摩擦专用 CSV（四类文件）"
        $cBtnOpenFolder.Content = "打开输出文件夹"
        $cGrpSource.Header = "数据源"
        $cLblOdb.Text = "ODB 文件"
        $cGrpHistory.Header = "History 选择"
        $cLblSteps.Text = "分析步（可多选）"
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

$cmbTheme.SelectedIndex = $(if($script:theme -eq 'dark'){1}else{0})
$cmbTheme.Add_SelectionChanged({
    if($cmbTheme.SelectedItem -eq $null){ return }
    $t = $cmbTheme.SelectedItem.Tag.ToString()
    if($t -eq $script:theme){ return }
    $prev = $script:theme
    $script:theme = $t
    try{
        Apply-ThemeColors
    }catch{
        # Never let a styling problem kill the window: fall back to the last good theme.
        $script:theme = $prev
        try{ Apply-ThemeColors }catch{}
        Msg ("Theme switch failed, reverted: " + $_.Exception.Message)
    }
})

# Option tree: selecting a tree item shows that section's options on the right.
$navList.Add_SelectionChanged({
    $item = $navList.SelectedItem
    if($item -eq $null -or $item.Tag -eq $null){ return }
    Show-NavPage $item.Tag.ToString()
})
$navList.SelectedIndex = 1

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
    if(-not (Get-Command Show-DataSafetyWorkspace -ErrorAction SilentlyContinue)){ . $script }
    $pvd = if($txtOutput.Text -and $txtOutput.Text.EndsWith('.pvd',[StringComparison]::OrdinalIgnoreCase)){$txtOutput.Text}else{''}
    Show-DataSafetyWorkspace $pvd $script:lang
})

$tbOpen.Add_Click({ BrowseODB })
$btnBrowse.Add_Click({ BrowseODB })

$btnRead.Add_Click({ ReadMeta })

$btnReadFields.Add_Click({ ReadFields })

# Guided rail: the call-to-action runs, or focuses, whatever the current step needs.
# Export is reachable only from that button (and only at step 5), so the workflow
# order cannot be bypassed.
$btnNextStep.Add_Click({
    if($script:wizardAction -ne $null){ & $script:wizardAction }
})

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

    foreach($cb in $script:seriesStepBoxes){ $cb.IsChecked = $false }
    if($script:seriesStepBoxes.Count -gt 0){
        $script:seriesStepBoxes[0].IsChecked = $true
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
$txtOdb.Add_TextChanged({ $txtOdb.ToolTip = $txtOdb.Text; Update-WizardState })

$panelSeries.IsEnabled = $false
$cmbIPFDir.SelectedIndex = 2
$cmbGNDMode.SelectedIndex = 0
$cmbGNDSlideRef.SelectedIndex = 0
UpdateDerivedEnabled
UpdateGNDEnabled
ApplyLanguage

[void]$window.ShowDialog()
