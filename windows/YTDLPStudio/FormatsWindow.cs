using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using YTDLPStudio.Core;

namespace YTDLPStudio;

public sealed class FormatsWindow : Window
{
    private readonly CancellationTokenSource cancellation = new(TimeSpan.FromSeconds(90));
    private readonly TextBlock status;
    private readonly DataGrid table;
    private readonly Button use;
    public SourceFormat? SelectedFormat => table.SelectedItem as SourceFormat;
    public FormatsWindow(string url)
    {
        Title = "Formatos do link"; Width = 940; Height = 560; MinWidth = 680; MinHeight = 400; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var layout = new DockPanel { Margin = new Thickness(24) };
        var heading = new TextBlock { Text = "Escolha a faixa da fonte.", FontSize = 24, FontWeight = FontWeights.SemiBold, Margin = new(0, 0, 0, 8) }; DockPanel.SetDock(heading, Dock.Top); layout.Children.Add(heading);
        status = new TextBlock { Text = "Consultando os formatos disponíveis…", Style = (Style)FindResource("Muted"), Margin = new(0, 0, 0, 18) }; DockPanel.SetDock(status, Dock.Top); layout.Children.Add(status);
        var footer = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new(0, 18, 0, 0) }; DockPanel.SetDock(footer, Dock.Bottom);
        var cancel = new Button { Content = "Cancelar", IsCancel = true, Margin = new(0, 0, 10, 0) }; cancel.Click += (_, _) => Close();
        use = new Button { Content = "Usar formato", IsEnabled = false, IsDefault = true, Style = (Style)FindResource("PrimaryButton") }; use.Click += (_, _) => { if (SelectedFormat is not null) DialogResult = true; };
        footer.Children.Add(cancel); footer.Children.Add(use); layout.Children.Add(footer);
        table = new DataGrid { AutoGenerateColumns = false, IsReadOnly = true, SelectionMode = DataGridSelectionMode.Single, SelectionUnit = DataGridSelectionUnit.FullRow, CanUserAddRows = false };
        System.Windows.Automation.AutomationProperties.SetName(table, "Formatos disponíveis no link");
        foreach (var (name, property, width) in new[] { ("ID", "Id", 75d), ("Formato", "Extension", 75d), ("Resolução", "Resolution", 115d), ("Vídeo", "VideoCodec", 140d), ("Áudio", "AudioCodec", 120d), ("Tamanho", "SizeLabel", 90d), ("Detalhes", "Detail", 170d) }) table.Columns.Add(new DataGridTextColumn { Header = name, Binding = new Binding(property), Width = width });
        table.SelectionChanged += (_, _) => use.IsEnabled = SelectedFormat is not null;
        table.MouseDoubleClick += (_, _) => { if (SelectedFormat is not null) DialogResult = true; };
        layout.Children.Add(table); Content = layout;
        Loaded += async (_, _) =>
        {
            try { var result = await new DownloadService().ProbeAsync(url, cancellation.Token); if (cancellation.IsCancellationRequested) return; status.Text = result.Title; table.ItemsSource = result.Formats; }
            catch (OperationCanceledException) { status.Text = "Consulta cancelada ou tempo limite atingido. Feche e tente novamente."; }
            catch (Exception ex) { status.Text = ex.Message; }
        };
        Closed += (_, _) => cancellation.Cancel();
        SourceInitialized += (_, _) => NativeBackdrop.Apply(this);
    }
}
