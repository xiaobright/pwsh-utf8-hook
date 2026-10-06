using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

// Required by the .NET startup-hook contract: global type, public static method.
internal static class StartupHook
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern uint GetModuleFileNameW(IntPtr module, StringBuilder name, uint size);

    public static void Initialize()
    {
        try
        {
            if (Environment.OSVersion.Platform != PlatformID.Win32NT)
                return;

            // Check the real executable, not argv, PATH, or the calling application.
            var path = new StringBuilder(32768);
            uint length = GetModuleFileNameW(IntPtr.Zero, path, (uint)path.Capacity);
            if (length == 0 || length >= path.Capacity ||
                !string.Equals(Path.GetFileName(path.ToString()), "pwsh.exe", StringComparison.OrdinalIgnoreCase))
                return;

            var utf8 = new UTF8Encoding(false);
            // Some hosts have no usable input/output handle. Configure independently.
            try { Console.InputEncoding = utf8; } catch (Exception) { }
            try { Console.OutputEncoding = utf8; } catch (Exception) { }
        }
        catch (Exception)
        {
            // Optional initialization must not add output or terminate the host.
            // Loader failures before Initialize (e.g. a missing DLL) cannot be caught here.
        }
    }
}
