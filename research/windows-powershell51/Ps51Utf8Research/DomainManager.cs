using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;

namespace Ps51Utf8Research
{
    // Research only. The private PowerShell field below is not a supported API.
    public sealed class DomainManager : AppDomainManager
    {
        public override void InitializeNewDomain(AppDomainSetup appDomainInfo)
        {
            base.InitializeNewDomain(appDomainInfo);
            try
            {
                string executable;
                using (var process = Process.GetCurrentProcess())
                    executable = process.MainModule.FileName;
                if (!string.Equals(Path.GetFileName(executable), "powershell.exe", StringComparison.OrdinalIgnoreCase))
                {
                    AppDomain.CurrentDomain.SetData("Ps51Utf8Research.Status", "Skipped");
                    return;
                }

                var utf8 = new UTF8Encoding(false);
                Console.InputEncoding = utf8;
                Console.OutputEncoding = utf8;
                AppDomain.CurrentDomain.SetData("Ps51Utf8Research.Status", "ConsoleOnly");
                if (Environment.GetEnvironmentVariable("PS51_UTF8_RESEARCH_CONSOLE_ONLY") == "1")
                    return;

                var engine = Assembly.Load("System.Management.Automation, Version=3.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35");
                var stateType = engine.GetType("System.Management.Automation.Runspaces.InitialSessionState", true);
                var field = stateType.GetField("BuiltInVariables", BindingFlags.Static | BindingFlags.NonPublic);
                if (field == null || !(field.GetValue(null) is Array entries))
                    throw new MissingFieldException(stateType.FullName, "BuiltInVariables");

                for (int i = 0; i < entries.Length; i++)
                {
                    var entry = entries.GetValue(i);
                    var type = entry.GetType();
                    if ((string)type.GetProperty("Name").GetValue(entry, null) != "OutputEncoding")
                        continue;
                    // Preserve the existing description, options and type conversion attributes.
                    var replacement = Activator.CreateInstance(type, new[]
                    {
                        "OutputEncoding", (object)utf8,
                        type.GetProperty("Description").GetValue(entry, null),
                        type.GetProperty("Options").GetValue(entry, null),
                        type.GetProperty("Attributes").GetValue(entry, null)
                    });
                    entries.SetValue(replacement, i);
                    AppDomain.CurrentDomain.SetData("Ps51Utf8Research.Status", "ConsoleAndPipeline");
                    return;
                }
                throw new MissingFieldException("OutputEncoding was not found in BuiltInVariables.");
            }
            catch (Exception error)
            {
                // Keep diagnostics in this child AppDomain, never in stdout/stderr.
                AppDomain.CurrentDomain.SetData("Ps51Utf8Research.Status", error.ToString());
            }
        }
    }
}
