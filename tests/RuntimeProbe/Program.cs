using System;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

internal static class Program
{
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "echo")
        {
            Console.InputEncoding = new UTF8Encoding(false);
            Console.OutputEncoding = new UTF8Encoding(false);
            Console.Write(Console.ReadLine());
            return 0;
        }

        Console.Write(JsonSerializer.Serialize(new
        {
            Runtime = RuntimeInformation.FrameworkDescription,
            InputCP = Console.InputEncoding.CodePage,
            OutputCP = Console.OutputEncoding.CodePage,
            HookLoaded = AppDomain.CurrentDomain.GetAssemblies().Any(a => a.GetName().Name == "PwshUtf8Hook")
        }));
        Console.Error.Write("control-error");
        return 17;
    }
}
