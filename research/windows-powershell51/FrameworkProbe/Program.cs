using System;
using System.IO;
using System.Text;

internal static class Program
{
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "echo")
        {
            using (var input = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false, true)))
            using (var output = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)))
                output.Write(input.ReadToEnd());
            return 0;
        }
        Console.Write("IN=" + Console.InputEncoding.CodePage + ";OUT=" + Console.OutputEncoding.CodePage +
            ";HOOK=" + AppDomain.CurrentDomain.GetData("Ps51Utf8Research.Status"));
        return 17;
    }
}
