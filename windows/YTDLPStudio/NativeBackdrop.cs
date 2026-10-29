using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Win32;

namespace YTDLPStudio;

internal static class NativeBackdrop
{
    [StructLayout(LayoutKind.Sequential)] private struct Margins { public int Left, Right, Top, Bottom; }
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmExtendFrameIntoClientArea(IntPtr window, ref Margins margins);

    public static void Apply(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        int dark = 1;
        DwmSetWindowAttribute(handle, 20, ref dark, sizeof(int));
        int round = 2;
        DwmSetWindowAttribute(handle, 33, ref round, sizeof(int));
        bool transparency = Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "EnableTransparency", 1) is not int enabled || enabled != 0;
        if (SystemParameters.HighContrast || !transparency || !OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22621))
        {
            window.Background = (Brush)Application.Current.Resources["CanvasBrush"];
            return;
        }
        int acrylic = 3;
        if (DwmSetWindowAttribute(handle, 38, ref acrylic, sizeof(int)) == 0)
        {
            var source = HwndSource.FromHwnd(handle);
            if (source?.CompositionTarget is not null) source.CompositionTarget.BackgroundColor = Colors.Transparent;
            var margins = new Margins { Left = -1, Right = -1, Top = -1, Bottom = -1 };
            DwmExtendFrameIntoClientArea(handle, ref margins);
            window.Background = Brushes.Transparent;
        }
        else window.Background = new SolidColorBrush(Color.FromRgb(24, 27, 33));
    }

    public static void ApplyAccessibleTheme()
    {
        if (!SystemParameters.HighContrast) return;
        var resources = Application.Current.Resources;
        foreach (string key in new[] { "CanvasBrush", "PanelBrush", "InputBrush" }) resources[key] = SystemColors.WindowBrush;
        foreach (string key in new[] { "TextBrush", "MutedBrush", "ErrorBrush" }) resources[key] = SystemColors.WindowTextBrush;
        resources["BorderBrush"] = SystemColors.WindowTextBrush;
        resources["AccentBrush"] = SystemColors.HighlightBrush;
        resources["FocusBrush"] = SystemColors.HighlightBrush;
    }
}
