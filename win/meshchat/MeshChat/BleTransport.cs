// MeshChat for Windows – the real radio: Bluetooth Low Energy with Windows' own WinRT APIs, the same service as a Mac's
// (lib/meshchat/Sources/BLETransport.swift), so Windows computers and Macs link to each other:
//   central     it scans for the MeshChat service, connects, subscribes to TX and writes frames to RX (without
//               response). A Mac's advertised name ("mc" + 8 hex digits) is its token.
//   peripheral  where the Bluetooth adapter can (most can; `meshchat doctor` says), it offers the same service – RX
//               for frames written to it, TX it notifies frames on – and advertises it. Windows decides what goes into
//               the advertisement and cannot add the name with the token, so a Mac connects to it at once.
// One link is one connection, in either direction. Frames wait in a queue per link and go one after the other. Windows
// cannot read the signal of a device it is connected to: the signal comes from the advertisements it keeps hearing.
// Everything the mesh is told goes through its queue; the WinRT calls run on the thread pool.

using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Radios;
using Windows.Security.Cryptography;
using Windows.Storage.Streams;
using MeshRadioState = MeshChat.RadioState;
using WinRadioState = Windows.Devices.Radios.RadioState;

namespace MeshChat.Windows;

public static class MeshService
{
    public static readonly Guid Service = Guid.Parse("31FF69C7-51D3-4241-AD2F-A4ADB116CD77");
    public static readonly Guid Rx = Guid.Parse("6292E318-9208-4000-8CD4-3A6EF318B275");     // frames to this computer
    public static readonly Guid Tx = Guid.Parse("A4F81D3A-0BAA-4433-9D11-98BD9B97B79C");     // frames from this computer

    // "mc1a2b3c4d" → the token; anything else → null
    public static uint? TokenFromName(string? name)
    {
        if (name == null || name.Length != 10 || !name.StartsWith("mc", StringComparison.Ordinal)) return null;
        return Hex.Decode(name[2..]) is byte[] d && d.Length == 4 ? B.Token(d) : null;
    }

    public static IBuffer Buffer(byte[] d) => CryptographicBuffer.CreateFromByteArray(d);

    public static byte[] Bytes(IBuffer? b)
    {
        if (b == null || b.Length == 0) return Array.Empty<byte>();
        CryptographicBuffer.CopyToByteArray(b, out var d);
        return d ?? Array.Empty<byte>();
    }

    public static int Clamp(int n) => Math.Max(Proto.MinFrame, Math.Min(Proto.MaxFrame, n));
}

public sealed class BleTransport : ILinkTransport
{
    private const int MaxQueue = 4096;          // frames waiting on one link before it counts as stuck

    private sealed class Seen
    {
        public ulong Address;
        public BluetoothAddressType Type;
        public uint? Token;
    }

    private sealed class OutLink
    {
        public int Id;
        public string Endpoint = "";
        public ulong Address;
        public BluetoothAddressType Type;
        public BluetoothLEDevice? Device;
        public GattSession? Session;
        public GattDeviceService? Service;
        public GattCharacteristic? Rx;
        public GattCharacteristic? Tx;
        public bool Open;
        public bool Cancelled;
        public bool Closed;
        public int MaxFrame = Proto.MinFrame;
        public double LastSignal;
        public readonly Queue<byte[]> Pending = new();
        public bool Sending;
    }

    private sealed class InLink
    {
        public int Id;
        public string Device = "";
        public GattSubscribedClient Client = null!;
        public int MaxFrame = Proto.MinFrame;
        public bool Closed;
        public readonly Queue<byte[]> Pending = new();
        public bool Sending;
    }

    private readonly SerialQueue queue;
    private readonly Action<string> log;
    public ILinkTransportDelegate? Delegate { get; set; }
    public MeshRadioState State { get; private set; } = MeshRadioState.Starting;

    private BluetoothAdapter? adapter;
    private Radio? radio;
    private RadioAccessStatus access = RadioAccessStatus.Unspecified;
    private BluetoothLEAdvertisementWatcher? watcher;
    private GattServiceProvider? provider;
    private GattLocalCharacteristic? tx;
    private bool wantScan;
    private bool wantAdvertise;
    private bool started;
    private readonly Dictionary<string, Seen> known = new();       // computers heard advertising, by endpoint
    private readonly HashSet<ulong> mesh = new();                    // addresses that advertised the service: their scan responses count too
    private readonly HashSet<string> reported = new();               // told the mesh in this scan
    private readonly HashSet<string> waitingName = new();            // heard, its name (in the scan response) not yet
    private readonly Dictionary<int, OutLink> outLinks = new();
    private readonly Dictionary<string, OutLink> outByEndpoint = new();
    private readonly Dictionary<int, InLink> inLinks = new();
    private readonly Dictionary<string, InLink> inByDevice = new();
    private readonly HashSet<string> ignored = new();                // centrals of links this computer closed
    private int nextId = 1;

    // The transport is called on this queue only, and calls the mesh there
    public BleTransport(SerialQueue queue, Action<string> log)
    {
        this.queue = queue;
        this.log = log;
    }

    private static double Now() => Environment.TickCount64 / 1000.0;

    // ── Starting ──────────────────────────────────────────────

    public void Start(uint token)
    {
        if (started) return;
        started = true;
        _ = Task.Run(StartAsync);
    }

    private async Task StartAsync()
    {
        RadioAccessStatus a = RadioAccessStatus.Unspecified;
        BluetoothAdapter? ad = null;
        Radio? r = null;
        try { a = await Radio.RequestAccessAsync(); }
        catch (Exception e) { log($"radio access: {e.Message}"); }
        try
        {
            ad = await BluetoothAdapter.GetDefaultAsync();
            if (ad != null) r = await ad.GetRadioAsync();
        }
        catch (Exception e) { log($"no Bluetooth adapter: {e.Message}"); }
        queue.Post(() =>
        {
            access = a;
            adapter = ad;
            radio = r;
            if (radio != null) radio.StateChanged += (_, _) => queue.Post(UpdateState);
            if (adapter != null && adapter.IsLowEnergySupported && adapter.IsCentralRoleSupported)
            {
                watcher = new BluetoothLEAdvertisementWatcher { ScanningMode = BluetoothLEScanningMode.Active };
                watcher.Received += OnReceived;
                // stopping takes a moment, and a start meanwhile is refused: once stopped, it starts again if it should
                watcher.Stopped += (_, args) => queue.Post(() =>
                {
                    if (args.Error != BluetoothError.Success) log($"scanning stopped: {args.Error}");
                    ApplyScanning();
                });
            }
            log($"Bluetooth: adapter {(adapter == null ? "none" : $"{adapter.BluetoothAddress:X12}")}, radio {radio?.State.ToString() ?? "none"}, access {access}, peripheral role {(adapter?.IsPeripheralRoleSupported == true ? "yes" : "no")}");
            UpdateState();
        });
        if (ad != null && ad.IsPeripheralRoleSupported) await PublishService();
    }

    private void UpdateState()
    {
        MeshRadioState s;
        if (adapter == null || !adapter.IsLowEnergySupported || !adapter.IsCentralRoleSupported) s = MeshRadioState.Unsupported;
        else if (access == RadioAccessStatus.DeniedByUser || access == RadioAccessStatus.DeniedBySystem) s = MeshRadioState.Unauthorized;
        else if (radio == null) s = MeshRadioState.Unsupported;
        else s = radio.State switch
        {
            WinRadioState.On => MeshRadioState.On,
            WinRadioState.Off or WinRadioState.Disabled => MeshRadioState.Off,
            _ => MeshRadioState.Starting,
        };
        if (s == State) return;
        State = s;
        log($"Bluetooth: {s.Label()}");
        if (s != MeshRadioState.On) DropAll($"Bluetooth is {s.Label()}");
        Delegate?.RadioStateChanged(s);
        ApplyScanning();
        ApplyAdvertising();
    }

    private void DropAll(string reason)
    {
        var ids = outLinks.Values.Where(l => l.Open).Select(l => l.Id).Concat(inLinks.Keys).ToList();
        foreach (var l in outLinks.Values) Dispose(l);
        outLinks.Clear();
        outByEndpoint.Clear();
        inLinks.Clear();
        inByDevice.Clear();
        foreach (var id in ids) Delegate?.RadioClosed(id, reason);
    }

    public void Stop()
    {
        wantScan = false;
        wantAdvertise = false;
        try
        {
            if (watcher?.Status == BluetoothLEAdvertisementWatcherStatus.Started) watcher.Stop();
        }
        catch (Exception) { }
        try { provider?.StopAdvertising(); } catch (Exception) { }
        foreach (var l in outLinks.Values) Dispose(l);
        outLinks.Clear();
        outByEndpoint.Clear();
        inLinks.Clear();
        inByDevice.Clear();
        known.Clear();
        State = MeshRadioState.Off;
    }

    // ── Scanning: finding the others ──────────────────────────

    public void SetScanning(bool on)
    {
        wantScan = on;
        if (on) reported.Clear();           // a fresh scan: computers already seen are reported again
        ApplyScanning();
    }

    private void ApplyScanning()
    {
        if (watcher == null) return;
        try
        {
            var running = watcher.Status == BluetoothLEAdvertisementWatcherStatus.Started;
            if (wantScan && State == MeshRadioState.On && !running) watcher.Start();
            else if ((!wantScan || State != MeshRadioState.On) && running) watcher.Stop();
        }
        catch (Exception e) { log($"could not scan: {e.Message}"); }
    }

    private void OnReceived(BluetoothLEAdvertisementWatcher w, BluetoothLEAdvertisementReceivedEventArgs a)
    {
        ulong address = a.BluetoothAddress;
        var type = a.BluetoothAddressType;
        int rssi = a.RawSignalStrengthInDBm;
        var ours = false;
        string name = "";
        try
        {
            ours = a.Advertisement.ServiceUuids.Contains(MeshService.Service);
            name = a.Advertisement.LocalName ?? "";
        }
        catch (Exception) { }
        queue.Post(() => Heard(address, type, rssi, ours, name));
    }

    private void Heard(ulong address, BluetoothAddressType type, int rssi, bool ours, string name)
    {
        if (ours)
        {
            if (mesh.Count > 1024) mesh.Clear();
            mesh.Add(address);
        }
        else if (!mesh.Contains(address)) return;         // not a MeshChat – or a scan response of one: the name is there
        var endpoint = address.ToString("X12");
        if (!known.TryGetValue(endpoint, out var seen))
        {
            if (known.Count >= 64)
                foreach (var k in known.Keys.Where(k => !outByEndpoint.ContainsKey(k)).ToList()) known.Remove(k);
            known[endpoint] = seen = new Seen { Address = address };
        }
        seen.Type = type;
        var token = MeshService.TokenFromName(name);
        var newToken = token != null && seen.Token != token;
        if (token != null) seen.Token = token;
        if (rssi == Distance.Unknown) rssi = -100;
        // a link this computer made: the advertisements it keeps hearing say how strong the other computer is
        if (outByEndpoint.TryGetValue(endpoint, out var link) && link.Open && Now() - link.LastSignal >= 5)
        {
            link.LastSignal = Now();
            Delegate?.RadioSignal(rssi, link.Id);
        }
        if (!wantScan || (reported.Contains(endpoint) && !newToken)) return;
        if (seen.Token == null && !reported.Contains(endpoint))
        {
            // a Mac's name – its token – comes in its scan response, a moment after the advertisement: wait for it, so
            // that both decide alike who connects. A Windows computer advertises no name: reported without one.
            if (!waitingName.Add(endpoint)) return;
            var r = rssi;
            queue.PostAfter(0.8, () =>
            {
                if (!waitingName.Remove(endpoint) || !wantScan || reported.Contains(endpoint)) return;
                reported.Add(endpoint);
                Delegate?.RadioSighted(new Sighting(endpoint, known.TryGetValue(endpoint, out var s) ? s.Token : null, r));
            });
            return;
        }
        waitingName.Remove(endpoint);
        reported.Add(endpoint);
        Delegate?.RadioSighted(new Sighting(endpoint, seen.Token, rssi));
    }

    // ── Links this computer makes (central) ───────────────────

    public void Connect(string endpoint)
    {
        if (!known.TryGetValue(endpoint, out var seen) || State != MeshRadioState.On)
        {
            queue.Post(() => Delegate?.RadioConnectFailed(endpoint, "that computer is no longer seen"));
            return;
        }
        if (outByEndpoint.ContainsKey(endpoint)) return;
        var link = new OutLink { Id = nextId++, Endpoint = endpoint, Address = seen.Address, Type = seen.Type };
        outLinks[link.Id] = link;
        outByEndpoint[endpoint] = link;
        _ = Task.Run(() => ConnectAsync(link));
    }

    private sealed class SetupFailure : Exception
    {
        public SetupFailure(string message) : base(message) { }
    }

    private async Task ConnectAsync(OutLink link)
    {
        string failure;
        try
        {
            var device = await BluetoothLEDevice.FromBluetoothAddressAsync(link.Address, link.Type) ?? throw new SetupFailure("it could not be reached");
            lock (link) link.Device = device;
            var session = await GattSession.FromDeviceIdAsync(device.BluetoothDeviceId);
            if (session != null)
            {
                session.MaintainConnection = true;
                lock (link) link.Session = session;
            }
            var services = await device.GetGattServicesForUuidAsync(MeshService.Service, BluetoothCacheMode.Uncached);
            if (services.Status != GattCommunicationStatus.Success) throw new SetupFailure($"its services could not be read ({services.Status})");
            if (services.Services.Count == 0) throw new SetupFailure("it has no MeshChat service");
            var service = services.Services[0];
            lock (link) link.Service = service;
            var rxs = await service.GetCharacteristicsForUuidAsync(MeshService.Rx, BluetoothCacheMode.Uncached);
            var txs = await service.GetCharacteristicsForUuidAsync(MeshService.Tx, BluetoothCacheMode.Uncached);
            if (rxs.Status != GattCommunicationStatus.Success || txs.Status != GattCommunicationStatus.Success
                || rxs.Characteristics.Count == 0 || txs.Characteristics.Count == 0) throw new SetupFailure("its MeshChat service is incomplete");
            link.Rx = rxs.Characteristics[0];
            link.Tx = txs.Characteristics[0];
            link.Tx.ValueChanged += (_, args) =>
            {
                var bytes = MeshService.Bytes(args.CharacteristicValue);
                queue.Post(() =>
                {
                    if (link.Open && !link.Closed) Delegate?.RadioReceived(bytes, link.Id);
                });
            };
            var sub = await link.Tx.WriteClientCharacteristicConfigurationDescriptorWithResultAsync(GattClientCharacteristicConfigurationDescriptorValue.Notify);
            if (sub.Status != GattCommunicationStatus.Success) throw new SetupFailure($"it did not let this computer subscribe ({sub.Status})");
            device.ConnectionStatusChanged += (d, _) =>
            {
                if (d.ConnectionStatus == BluetoothConnectionStatus.Disconnected) queue.Post(() => Lost(link, "disconnected"));
            };
            var frame = MeshService.Clamp((session?.MaxPduSize ?? 23) - 3);
            if (session != null)
                session.MaxPduSizeChanged += (s, _) =>
                {
                    var n = MeshService.Clamp(s.MaxPduSize - 3);
                    queue.Post(() => link.MaxFrame = n);
                };
            queue.Post(() =>
            {
                if (link.Cancelled || link.Closed || !outLinks.ContainsKey(link.Id))
                {
                    Dispose(link);
                    return;
                }
                link.Open = true;
                link.MaxFrame = frame;
                log($"link {link.Id}: connected to {link.Endpoint}, frames of up to {frame} bytes");
                Delegate?.RadioOpened(new LinkInfo(link.Id, true, link.Endpoint, frame));
            });
            return;
        }
        catch (SetupFailure e) { failure = e.Message; }
        catch (Exception e) { failure = e.Message; }
        queue.Post(() => FailSetup(link, failure));
    }

    private void FailSetup(OutLink link, string reason)
    {
        if (link.Open) return;
        log($"link setup with {link.Endpoint} failed: {reason}");
        Forget(link);
        if (!link.Cancelled) Delegate?.RadioConnectFailed(link.Endpoint, reason);
    }

    // The connection is gone (or this computer ended it): the mesh is told once
    private void Lost(OutLink link, string reason)
    {
        if (link.Closed) return;
        var wasOpen = link.Open;
        Forget(link);
        if (wasOpen) Delegate?.RadioClosed(link.Id, reason);
        else if (!link.Cancelled) Delegate?.RadioConnectFailed(link.Endpoint, reason);
    }

    private void Forget(OutLink link)
    {
        outLinks.Remove(link.Id);
        if (outByEndpoint.TryGetValue(link.Endpoint, out var l) && l == link) outByEndpoint.Remove(link.Endpoint);
        Dispose(link);
    }

    private static void Dispose(OutLink link)
    {
        lock (link)
        {
            link.Closed = true;
            link.Open = false;
            try { link.Service?.Dispose(); } catch (Exception) { }
            try { link.Session?.Dispose(); } catch (Exception) { }
            try { link.Device?.Dispose(); } catch (Exception) { }
            link.Service = null;
            link.Session = null;
            link.Device = null;
        }
    }

    public void CancelConnect(string endpoint)
    {
        if (!outByEndpoint.TryGetValue(endpoint, out var link) || link.Open) return;
        link.Cancelled = true;
        Forget(link);
    }

    // ── Links others make (peripheral) ────────────────────────

    private async Task PublishService()
    {
        try
        {
            var result = await GattServiceProvider.CreateAsync(MeshService.Service);
            if (result.Error != BluetoothError.Success)
            {
                log($"could not offer the MeshChat service: {result.Error}");
                return;
            }
            var p = result.ServiceProvider;
            var rxResult = await p.Service.CreateCharacteristicAsync(MeshService.Rx, new GattLocalCharacteristicParameters
            {
                CharacteristicProperties = GattCharacteristicProperties.WriteWithoutResponse,
                WriteProtectionLevel = GattProtectionLevel.Plain,
            });
            var txResult = await p.Service.CreateCharacteristicAsync(MeshService.Tx, new GattLocalCharacteristicParameters
            {
                CharacteristicProperties = GattCharacteristicProperties.Notify,
                ReadProtectionLevel = GattProtectionLevel.Plain,
            });
            if (rxResult.Error != BluetoothError.Success || txResult.Error != BluetoothError.Success)
            {
                log($"could not offer the MeshChat service: {rxResult.Error}, {txResult.Error}");
                return;
            }
            rxResult.Characteristic.WriteRequested += OnWriteRequested;
            txResult.Characteristic.SubscribedClientsChanged += (_, _) => queue.Post(SubscribersChanged);
            p.AdvertisementStatusChanged += (_, args) => log($"advertising: {args.Status}{(args.Error != BluetoothError.Success ? $" ({args.Error})" : "")}");
            queue.Post(() =>
            {
                provider = p;
                tx = txResult.Characteristic;
                ApplyAdvertising();
            });
        }
        catch (Exception e)
        {
            log($"could not offer the MeshChat service: {e.Message}");
        }
    }

    public void SetAdvertising(bool on)
    {
        wantAdvertise = on;
        ApplyAdvertising();
    }

    private void ApplyAdvertising()
    {
        if (provider == null) return;
        try
        {
            var status = provider.AdvertisementStatus;
            var running = status == GattServiceProviderAdvertisementStatus.Started || status == GattServiceProviderAdvertisementStatus.StartedWithoutAllAdvertisementData;
            if (wantAdvertise && State == MeshRadioState.On && !running)
                provider.StartAdvertising(new GattServiceProviderAdvertisingParameters { IsConnectable = true, IsDiscoverable = true });
            else if ((!wantAdvertise || State != MeshRadioState.On) && running)
                provider.StopAdvertising();
        }
        catch (Exception e) { log($"could not advertise: {e.Message}"); }
    }

    private void SubscribersChanged()
    {
        if (tx == null) return;
        List<GattSubscribedClient> now;
        try { now = tx.SubscribedClients.ToList(); }
        catch (Exception) { return; }
        var devices = new HashSet<string>();
        foreach (var client in now)
        {
            var device = client.Session.DeviceId.Id;
            devices.Add(device);
            if (inByDevice.ContainsKey(device)) continue;
            ignored.Remove(device);
            var link = new InLink { Id = nextId++, Device = device, Client = client, MaxFrame = MeshService.Clamp(client.MaxNotificationSize) };
            client.MaxNotificationSizeChanged += (c, _) =>
            {
                var n = MeshService.Clamp(c.MaxNotificationSize);
                queue.Post(() => link.MaxFrame = n);
            };
            inLinks[link.Id] = link;
            inByDevice[device] = link;
            log($"link {link.Id}: {Short(device)} connected, frames of up to {link.MaxFrame} bytes");
            Delegate?.RadioOpened(new LinkInfo(link.Id, false, device, link.MaxFrame));
        }
        foreach (var (device, link) in inByDevice.ToList())
        {
            if (devices.Contains(device)) continue;
            inByDevice.Remove(device);
            inLinks.Remove(link.Id);
            link.Closed = true;
            ignored.Remove(device);
            Delegate?.RadioClosed(link.Id, "the other computer disconnected");
        }
    }

    // RX takes writes without response: there is nothing to answer
    private async void OnWriteRequested(GattLocalCharacteristic sender, GattWriteRequestedEventArgs args)
    {
        var deferral = args.GetDeferral();
        try
        {
            var request = await args.GetRequestAsync();
            if (request == null) return;
            var bytes = MeshService.Bytes(request.Value);
            var device = args.Session.DeviceId.Id;
            if (request.Option == GattWriteOption.WriteWithResponse) request.Respond();
            queue.Post(() =>
            {
                if (ignored.Contains(device)) return;
                if (!inByDevice.ContainsKey(device)) SubscribersChanged();        // a write before the subscription was seen
                if (inByDevice.TryGetValue(device, out var link)) Delegate?.RadioReceived(bytes, link.Id);
            });
        }
        catch (Exception e)
        {
            log($"a write could not be read: {e.Message}");
        }
        finally
        {
            deferral.Complete();
        }
    }

    // ── Sending ───────────────────────────────────────────────

    public void Send(byte[] frame, int id)
    {
        if (outLinks.TryGetValue(id, out var o))
        {
            if (!o.Open || o.Closed) return;
            lock (o.Pending)
            {
                if (o.Pending.Count >= MaxQueue)
                {
                    queue.Post(() => Lost(o, "the link is not keeping up"));
                    return;
                }
                o.Pending.Enqueue(frame);
                if (o.Sending) return;
                o.Sending = true;
            }
            _ = Task.Run(() => PumpOut(o));
        }
        else if (inLinks.TryGetValue(id, out var i))
        {
            if (i.Closed) return;
            lock (i.Pending)
            {
                if (i.Pending.Count >= MaxQueue)
                {
                    queue.Post(() => Close(id, "the link is not keeping up"));
                    return;
                }
                i.Pending.Enqueue(frame);
                if (i.Sending) return;
                i.Sending = true;
            }
            _ = Task.Run(() => PumpIn(i));
        }
    }

    private async Task PumpOut(OutLink o)
    {
        while (true)
        {
            byte[] f;
            GattCharacteristic? rx;
            lock (o.Pending)
            {
                if (o.Pending.Count == 0 || o.Closed)
                {
                    o.Sending = false;
                    return;
                }
                f = o.Pending.Dequeue();
                rx = o.Rx;
            }
            string? failure = null;
            try
            {
                var result = rx == null ? null : await rx.WriteValueWithResultAsync(MeshService.Buffer(f), GattWriteOption.WriteWithoutResponse);
                if (result == null || result.Status != GattCommunicationStatus.Success) failure = $"a write failed ({result?.Status.ToString() ?? "no link"})";
            }
            catch (Exception e) { failure = $"a write failed: {e.Message}"; }
            if (failure != null)
            {
                lock (o.Pending) o.Sending = false;
                queue.Post(() => Lost(o, failure));
                return;
            }
        }
    }

    private async Task PumpIn(InLink i)
    {
        while (true)
        {
            byte[] f;
            lock (i.Pending)
            {
                if (i.Pending.Count == 0 || i.Closed)
                {
                    i.Sending = false;
                    return;
                }
                f = i.Pending.Dequeue();
            }
            string? failure = null;
            try
            {
                var t = tx;
                var result = t == null ? null : await t.NotifyValueAsync(MeshService.Buffer(f), i.Client);
                if (result == null || result.Status != GattCommunicationStatus.Success) failure = $"a notification failed ({result?.Status.ToString() ?? "no service"})";
            }
            catch (Exception e) { failure = $"a notification failed: {e.Message}"; }
            if (failure != null)
            {
                lock (i.Pending) i.Sending = false;
                queue.Post(() => Close(i.Id, failure));
                return;
            }
        }
    }

    // ── Closing ───────────────────────────────────────────────

    public void Close(int id) => Close(id, "closed by this computer");

    private void Close(int id, string reason)
    {
        if (outLinks.TryGetValue(id, out var o))
        {
            // the mesh is told after this call, as the radio would tell it
            var wasOpen = o.Open;
            Forget(o);
            if (wasOpen) queue.Post(() => Delegate?.RadioClosed(id, reason));
        }
        else if (inLinks.Remove(id, out var i))
        {
            // a peripheral cannot hang up: forget the link and ignore what still comes on it
            inByDevice.Remove(i.Device);
            i.Closed = true;
            ignored.Add(i.Device);
            queue.Post(() => Delegate?.RadioClosed(id, reason));
        }
    }

    public int MaxFrame(int id) =>
        outLinks.TryGetValue(id, out var o) ? o.MaxFrame : inLinks.TryGetValue(id, out var i) ? i.MaxFrame : Proto.MinFrame;

    // Windows has no reading of a connected device's signal: it comes with the advertisements (Heard)
    public void MeasureSignal(int id) { }

    private static string Short(string device) => device.Length <= 20 ? device : device[^17..];
}
