// MeshChat for Windows – `meshchat doctor`: what Windows says about Bluetooth, and what MeshChat keeps. Windows asks no
// question about Bluetooth for a program like this one; what can stand in the way is the adapter (Low Energy, and
// whether others can connect to it), the radio being off, a policy, or "Let apps control device radios" being off.
// It also listens for a few seconds and offers the service once – so it says whether MeshChats are heard nearby.

using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Radios;
using WinRadioState = Windows.Devices.Radios.RadioState;

namespace MeshChat.Windows;

public static class Doctor
{
    private static void Row(string key, string value) => Term.Line("    " + Theme.Dim(key.PadRight(13)) + value);
    private static void More(string text) => Term.Line("    " + new string(' ', 13) + Theme.Dim(text));

    public static int Run(Store store) => RunAsync(store).GetAwaiter().GetResult();

    private static async Task<int> RunAsync(Store store)
    {
        var problems = 0;
        Cli.Header("doctor");
        var v = Environment.OSVersion.Version;
        var name = v.Build >= 22000 ? "Windows 11" : "Windows 10";
        if (v.Build >= 19041)
        {
            Row("Windows", $"{name} – build {v.Build}");
        }
        else
        {
            problems++;
            Row("Windows", Theme.Red($"build {v.Build} – MeshChat needs Windows 10 version 2004 (build 19041) or newer"));
        }

        RadioAccessStatus access = RadioAccessStatus.Unspecified;
        try { access = await Radio.RequestAccessAsync(); } catch (Exception) { }
        BluetoothAdapter? adapter = null;
        try { adapter = await BluetoothAdapter.GetDefaultAsync(); } catch (Exception) { }
        Radio? radio = null;
        if (adapter != null)
        {
            try { radio = await adapter.GetRadioAsync(); } catch (Exception) { }
        }

        var ready = false;
        if (adapter == null)
        {
            problems++;
            Row("Bluetooth", Theme.Red("no Bluetooth adapter – this computer has none, or its driver is missing or turned off"));
            More("Settings › Bluetooth & devices; Device Manager › Bluetooth shows the adapter and its driver");
        }
        else
        {
            Row("Adapter", $"{Format(adapter.BluetoothAddress)}");
            if (!adapter.IsLowEnergySupported)
            {
                problems++;
                Row("Low Energy", Theme.Red("not supported – MeshChat needs Bluetooth Low Energy (4.0 or newer)"));
            }
            else if (!adapter.IsCentralRoleSupported)
            {
                problems++;
                Row("Low Energy", Theme.Red("this adapter cannot connect to others (no central role)"));
            }
            else
            {
                Row("Low Energy", Theme.Green("yes") + Theme.Dim(" – finds and reaches the others"));
            }
            if (adapter.IsPeripheralRoleSupported) Row("Be found", Theme.Green("yes") + Theme.Dim(" – the others can connect to this computer too"));
            else
            {
                Row("Be found", Theme.Yellow("no") + " – this adapter cannot offer a service");
                More("It still chats: it connects to the others. Two computers like this one cannot reach each other directly.");
            }
            switch (access)
            {
                case RadioAccessStatus.DeniedByUser:
                    problems++;
                    Row("Permission", Theme.Red("denied") + " – Settings › Privacy & security › Radios: turn on \"Let apps control device radios\"");
                    break;
                case RadioAccessStatus.DeniedBySystem:
                    problems++;
                    Row("Permission", Theme.Red("denied by Windows") + " – a policy of your organisation may not allow Bluetooth");
                    break;
                default:
                    Row("Permission", Theme.Green("allowed"));
                    break;
            }
            switch (radio?.State)
            {
                case WinRadioState.On:
                    Row("Bluetooth", Theme.Green("on"));
                    ready = adapter.IsLowEnergySupported && adapter.IsCentralRoleSupported;
                    break;
                case WinRadioState.Off:
                    problems++;
                    Row("Bluetooth", Theme.Red("off") + " – turn it on: Settings › Bluetooth & devices (or the quick settings, Win+A)");
                    break;
                case WinRadioState.Disabled:
                    problems++;
                    Row("Bluetooth", Theme.Red("disabled") + " – the adapter is turned off (airplane mode, a switch, or Device Manager)");
                    break;
                default:
                    problems++;
                    Row("Bluetooth", Theme.Yellow("unknown") + " – Windows does not say whether it is on");
                    break;
            }
        }

        if (ready)
        {
            // a few seconds of listening: is anyone with MeshChat nearby?
            var heard = new HashSet<ulong>();
            var named = new Dictionary<ulong, string>();
            var watcher = new BluetoothLEAdvertisementWatcher { ScanningMode = BluetoothLEScanningMode.Active };
            watcher.Received += (_, a) =>
            {
                lock (heard)
                {
                    if (a.Advertisement.ServiceUuids.Contains(MeshService.Service)) heard.Add(a.BluetoothAddress);
                    if (MeshService.TokenFromName(a.Advertisement.LocalName) != null) named[a.BluetoothAddress] = a.Advertisement.LocalName;
                }
            };
            try
            {
                watcher.Start();
                await Task.Delay(TimeSpan.FromSeconds(5));
                watcher.Stop();
                int n, macs;
                lock (heard)
                {
                    n = heard.Count;
                    macs = heard.Count(named.ContainsKey);
                }
                Row("Nearby", n == 0 ? "no MeshChat heard in 5 seconds" + Theme.Dim(" – is it open on the others?") : $"{n} computer{(n == 1 ? "" : "s")} with MeshChat open ({macs} Mac{(macs == 1 ? "" : "s")})");
            }
            catch (Exception e)
            {
                problems++;
                Row("Scanning", Theme.Red($"Windows refused: {e.Message}"));
            }
            if (adapter!.IsPeripheralRoleSupported)
            {
                try
                {
                    var result = await GattServiceProvider.CreateAsync(MeshService.Service);
                    Row("Advertising", result.Error == BluetoothError.Success ? "possible – the others can find this computer" : Theme.Yellow($"not possible ({result.Error}) – this computer can still find and reach the others"));
                }
                catch (Exception e)
                {
                    Row("Advertising", Theme.Yellow($"not possible ({e.Message})"));
                }
            }
        }

        var kept = store.History(100_000).Messages.Count;
        Row("History", $"{kept} message{(kept == 1 ? "" : "s")} · {Path.Combine(store.Dir, "history.jsonl")}");
        Row("Settings", $"name {store.Nickname ?? "not set yet"} · links {store.MaxLinks} · every message goes up to {Proto.HopLimit} relays far");
        var events = store.RecentLog(300);
        var failures = events.Where(e => e.Contains("could not") || e.Contains("failed") || e.Contains("timed out") || e.Contains("no answer")).ToList();
        var links = events.Count(e => e.Contains(" ready ("));
        if (events.Count == 0) Row("Links", "no chat yet on this computer");
        else
        {
            Row("Links", $"{links} made, {failures.Count} failed recently ({events.Count} events in events.log)");
            foreach (var f in failures.TakeLast(5)) More(f.Length > 110 ? f[..110] : f);
        }
        Term.Line();
        if (problems == 0) Term.Line("  " + Theme.Green("✓") + " Ready – " + Theme.Key("meshchat"));
        else Term.Line("  " + Theme.Red("✗") + $" {(problems == 1 ? "One thing" : $"{problems} things")} to fix first – see above");
        Term.Line();
        return problems == 0 ? 0 : 1;
    }

    private static string Format(ulong address) =>
        string.Join(":", Enumerable.Range(0, 6).Select(i => ((address >> (8 * (5 - i))) & 0xFF).ToString("X2")));
}
