using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using YTDLPStudio.Core;

namespace YTDLPStudio;

public partial class MainWindow : Window
{
    public StudioViewModel Model { get; }
    private readonly bool automated;
    public MainWindow(bool automated = false)
    {
        this.automated = automated;
        Model = new(); DataContext = Model;
        InitializeComponent();
        SourceInitialized += (_, _) => NativeBackdrop.Apply(this);
        PreviewKeyDown += Shortcuts;
        Model.PropertyChanged += (_, _) => UpdateEmptyStates();
        Closing += OnClosing;
        Loaded += (_, _) => { UpdateEmptyStates(); LinksBox.Focus(); };
    }
    public void SelectPage(int index)
    {
        DownloadPage.Visibility = index == 0 ? Visibility.Visible : Visibility.Collapsed;
        ActivityPage.Visibility = index == 1 ? Visibility.Visible : Visibility.Collapsed;
        CompletedPage.Visibility = index == 2 ? Visibility.Visible : Visibility.Collapsed;
        if (index == 0) DownloadTab.IsChecked = true;
        if (index == 1) ActivityTab.IsChecked = true;
        if (index == 2) CompletedTab.IsChecked = true;
    }
    private void Navigate(object sender, RoutedEventArgs e)
    { if (DownloadPage is not null && sender is RadioButton { Tag: string value }) SelectPage(int.Parse(value)); }
    private void UpdateEmptyStates()
    {
        RecentEmpty.Visibility = Model.Jobs.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        ActivityEmpty.Visibility = Model.ActivityEmpty ? Visibility.Visible : Visibility.Collapsed;
        CompletedEmpty.Visibility = Model.DoneCount == 0 ? Visibility.Visible : Visibility.Collapsed;
    }
    private void ComposerSizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (OptionsPanel is null) return;
        bool compact = ComposerGrid.ActualWidth < 820;
        Grid.SetColumn(OptionsPanel, compact ? 0 : 2); Grid.SetRow(OptionsPanel, compact ? 1 : 0);
        Grid.SetColumnSpan(LinksPanel, compact ? 3 : 1); Grid.SetColumnSpan(OptionsPanel, compact ? 3 : 1);
        OptionsPanel.Margin = compact ? new Thickness(0, 20, 0, 0) : new Thickness(0);
    }
    private void KindChanged(object sender, RoutedEventArgs e)
    { if (IsInitialized) Model.Kind = AudioKind.IsChecked == true ? MediaKind.Audio : MediaKind.Video; }
    private void PasteLinks(object sender, RoutedEventArgs e)
    {
        try
        {
            if (!Clipboard.ContainsText()) return;
            string text = Clipboard.GetText().Trim();
            if (text.Length > 0) Model.Links = string.IsNullOrWhiteSpace(Model.Links) ? text : Model.Links.TrimEnd() + Environment.NewLine + text;
            LinksBox.Focus(); LinksBox.CaretIndex = LinksBox.Text.Length;
        }
        catch (System.Runtime.InteropServices.COMException) { MessageBox.Show(this, "A área de transferência está ocupada. Tente novamente ou cole com Ctrl+V.", "Colar links"); }
    }
    private void ChooseDirectory(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Escolher pasta dos downloads" };
        if (System.IO.Directory.Exists(Model.Directory)) dialog.InitialDirectory = Model.Directory;
        if (dialog.ShowDialog(this) == true) Model.Directory = dialog.FolderName;
    }
    private void AddDownloads(object? sender, RoutedEventArgs? e)
    {
        if (!Model.CanAdd) return;
        try { Model.AddLinks(); SelectPage(1); }
        catch (Exception ex) { MessageBox.Show(this, "Não foi possível usar a pasta de destino. " + ex.Message, "Pasta de destino", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }
    private void ViewActivity(object sender, RoutedEventArgs e) => SelectPage(1);
    private void NewDownload(object? sender, RoutedEventArgs? e) { SelectPage(0); LinksBox.Focus(); }
    private void CancelJob(object sender, RoutedEventArgs e) { if (((FrameworkElement)sender).DataContext is StudioJob job) Model.Cancel(job); }
    private void RetryJob(object sender, RoutedEventArgs e) { if (((FrameworkElement)sender).DataContext is StudioJob job) Model.Retry(job); }
    private void RevealJob(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not StudioJob job) return;
        try
        {
            if (!File.Exists(job.File)) { MessageBox.Show(this, "O arquivo foi movido ou removido. Confira a pasta de destino.", "Localizar arquivo"); return; }
            var start = new ProcessStartInfo("explorer.exe") { UseShellExecute = false };
            start.ArgumentList.Add("/select,"); start.ArgumentList.Add(job.File); Process.Start(start)?.Dispose();
        }
        catch (Exception ex) { MessageBox.Show(this, "Não foi possível abrir o Explorador de Arquivos. " + ex.Message, "Localizar arquivo"); }
    }
    private void ShowFormats(object sender, RoutedEventArgs e)
    {
        if (!Model.CanProbe) return;
        var dialog = new FormatsWindow(Model.LinkList[0]) { Owner = this };
        if (dialog.ShowDialog() == true && dialog.SelectedFormat is { } format)
        {
            Model.Kind = format.HasVideo ? MediaKind.Video : MediaKind.Audio;
            VideoKind.IsChecked = format.HasVideo; AudioKind.IsChecked = !format.HasVideo;
            Model.Container = format.HasVideo ? "auto" : "best";
            Model.Selector = format.Selector; AdvancedOptions.IsExpanded = true;
        }
    }
    private void Shortcuts(object sender, KeyEventArgs e)
    {
        if (Keyboard.Modifiers != ModifierKeys.Control) return;
        switch (e.Key)
        {
            case Key.Enter: AddDownloads(null, null); e.Handled = true; break;
            case Key.N: NewDownload(null, null); e.Handled = true; break;
            case Key.D1: SelectPage(0); e.Handled = true; break;
            case Key.D2: SelectPage(1); e.Handled = true; break;
            case Key.D3: SelectPage(2); e.Handled = true; break;
        }
    }
    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (!automated && (Model.ActiveCount > 0 || Model.QueuedCount > 0) && MessageBox.Show(this,
            "Fechar o app cancela os downloads em andamento e os itens da fila. Deseja fechar?", "Downloads em andamento", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes)
        { e.Cancel = true; return; }
        Model.Stop();
    }
}
