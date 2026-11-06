// MeshChat – a simulated radio, for the tests and `meshchat demo` only – never for a real chat (that is Bluetooth).
// As lib/meshchat/Sources/SimTransport.swift: computers in memory, who hears whom (range), advertising and scanning,
// links with a frame size, and frames delivered in order on each link. It behaves like Bluetooth where the mesh
// relies on it:
//   - a scan reports each computer it hears once, until scanning is switched on again
//   - a connection to a computer out of range waits (the mesh gives up after its timeout), and completes when it comes
//   - only the central can end a link; when the peripheral closes one, it just stops listening, and the central
//     notices when the link goes silent
//   - out of range, a link breaks on both sides
//   - the signal strength follows the distance between two computers (3 m unless a test says otherwise)
// A test can also lose or double frames, and switch "Bluetooth" off.

namespace MeshChat;

public sealed class SimNetwork
{
    private sealed class SimLink
    {
        public SimRadio Central = null!;
        public int CentralId;
        public SimRadio Peripheral = null!;
        public int PeripheralId;
        public bool CentralOpen = true;
        public bool PeripheralOpen = true;
    }

    public double LossRate;                 // frames lost on the way (0…1)
    public double DuplicateRate;            // frames that arrive twice
    public double ManualNow { get; private set; }
    private readonly SerialQueue? live;     // the demo: events on this queue, time from the clock
    private ulong rng;
    private readonly Dictionary<string, SimRadio> radios = new();
    private readonly HashSet<string> range = new();
    private readonly Dictionary<string, double> distances = new();
    private readonly Dictionary<int, SimLink> links = new();
    private int nextLink = 1;
    private readonly Queue<Action> pending = new();
    public readonly List<Action> Tickers = new();      // called once a simulated second (the meshes' tick)

    public SimNetwork(double start = 1_700_000_000, ulong seed = 0x9E3779B97F4A7C15, SerialQueue? live = null)
    {
        ManualNow = start;
        rng = seed;
        this.live = live;
    }

    public double Now => live == null ? ManualNow : DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;

    public SimRadio Radio(string name, int maxFrame = 182)
    {
        var r = new SimRadio(name, this, maxFrame);
        radios[name] = r;
        return r;
    }

    // ── Range ─────────────────────────────────────────────────

    private static string Key(string a, string b) => string.CompareOrdinal(a, b) < 0 ? $"{a}|{b}" : $"{b}|{a}";

    public bool Hears(string a, string b) => range.Contains(Key(a, b));

    public void SetRange(string a, string b, bool inRange)
    {
        if (inRange)
        {
            range.Add(Key(a, b));
            return;
        }
        range.Remove(Key(a, b));
        foreach (var (id, l) in links.ToList())
        {
            if ((l.Central.Name == a && l.Peripheral.Name == b) || (l.Central.Name == b && l.Peripheral.Name == a)) BreakLink(id, "out of range");
        }
    }

    // How far apart two computers are – what their signal strength comes from
    public void SetDistance(string a, string b, double metres) => distances[Key(a, b)] = metres;

    public int Signal(string a, string b) => Distance.Rssi(distances.TryGetValue(Key(a, b), out var m) ? m : 3);

    // Everyone hears everyone of these
    public void AllInRange(params string[] names)
    {
        foreach (var a in names)
            foreach (var b in names)
                if (string.CompareOrdinal(a, b) < 0) SetRange(a, b, true);
    }

    // ── Time and events ───────────────────────────────────────

    public void Schedule(Action e)
    {
        if (live != null) live.Post(e);
        else pending.Enqueue(e);
    }

    // Runs what is queued until nothing is left → how many events ran
    public int Pump(int limit = 2_000_000)
    {
        var n = 0;
        while (pending.Count > 0 && n < limit)
        {
            pending.Dequeue()();
            n++;
        }
        return n;
    }

    // Time passes in steps of a second: scans hear, waiting connections complete, the meshes tick
    public void Advance(double seconds)
    {
        var left = seconds;
        while (left > 0)
        {
            var step = Math.Min(1, left);
            ManualNow += step;
            left -= step;
            SecondPassed();
            Pump();
        }
    }

    // One second of the radio's own work – the demo calls it from its timer
    public void SecondPassed()
    {
        foreach (var r in radios.Values.ToList())
        {
            if (!r.Running || !r.Powered) continue;
            if (r.Scanning)
            {
                foreach (var other in radios.Values.ToList())
                {
                    if (other == r || !other.Running || !other.Powered || !other.Advertising || !Hears(r.Name, other.Name) || r.Reported.Contains(other.Name)) continue;
                    r.Reported.Add(other.Name);
                    uint token = other.Token;
                    var rssi = Signal(r.Name, other.Name);
                    var name = other.Name;
                    Schedule(() => r.Delegate?.RadioSighted(new Sighting(name, token, rssi)));
                }
            }
            foreach (var target in r.Waiting.ToList()) TryConnect(r, target);
        }
        foreach (var t in Tickers.ToList()) t();
    }

    // ── Links ─────────────────────────────────────────────────

    internal void TryConnect(SimRadio from, string to)
    {
        if (!radios.TryGetValue(to, out var target) || !from.Waiting.Contains(to) || !target.Running || !target.Powered || !from.Running || !from.Powered
            || !Hears(from.Name, to) || !target.Advertising) return;
        from.Waiting.Remove(to);
        var id = nextLink++;
        int cid = from.NewLocal(id), pid = target.NewLocal(id);
        links[id] = new SimLink { Central = from, CentralId = cid, Peripheral = target, PeripheralId = pid };
        var frame = Math.Min(from.MaxFrameSize, target.MaxFrameSize);
        var fromName = from.Name;
        Schedule(() =>
        {
            from.Delegate?.RadioOpened(new LinkInfo(cid, true, to, frame));
            target.Delegate?.RadioOpened(new LinkInfo(pid, false, fromName, frame));
        });
    }

    internal void Measure(int id, int local, SimRadio radio)
    {
        if (!links.TryGetValue(id, out var l)) return;
        var other = l.Central == radio ? l.Peripheral : l.Central;
        if (l.Central != radio) return;         // as on a Mac: only the central reads it
        var rssi = Signal(radio.Name, other.Name);
        Schedule(() => radio.Delegate?.RadioSignal(rssi, local));
    }

    internal int MaxFrame(int id) => links.TryGetValue(id, out var l) ? Math.Min(l.Central.MaxFrameSize, l.Peripheral.MaxFrameSize) : Proto.MinFrame;

    internal void Send(byte[] frame, int id, SimRadio radio)
    {
        if (!links.TryGetValue(id, out var l)) return;
        var toCentral = radio == l.Peripheral;
        if (!(toCentral ? l.PeripheralOpen : l.CentralOpen)) return;
        var to = toCentral ? l.Central : l.Peripheral;
        var local = toCentral ? l.CentralId : l.PeripheralId;
        radio.FramesSent++;
        if (LossRate > 0 && Random() < LossRate) return;
        var copies = DuplicateRate > 0 && Random() < DuplicateRate ? 2 : 1;
        for (var i = 0; i < copies; i++)
        {
            Schedule(() =>
            {
                // still there, and still listening on that side?
                if (!links.TryGetValue(id, out var now) || !(toCentral ? now.CentralOpen : now.PeripheralOpen)) return;
                to.Delegate?.RadioReceived(frame, local);
            });
        }
    }

    internal void Close(int id, SimRadio radio)
    {
        if (!links.TryGetValue(id, out var l)) return;
        if (radio == l.Central)
        {
            BreakLink(id, "disconnected");
        }
        else if (l.PeripheralOpen)
        {
            // a peripheral cannot end a connection: it stops listening, the central finds out by itself
            l.PeripheralOpen = false;
            var pid = l.PeripheralId;
            var p = l.Peripheral;
            p.Forget(pid);
            Schedule(() => p.Delegate?.RadioClosed(pid, "closed by this computer"));
        }
    }

    private void BreakLink(int id, string reason)
    {
        if (!links.Remove(id, out var l)) return;
        l.Central.Forget(l.CentralId);
        l.Peripheral.Forget(l.PeripheralId);
        if (l.CentralOpen) Schedule(() => l.Central.Delegate?.RadioClosed(l.CentralId, reason));
        if (l.PeripheralOpen) Schedule(() => l.Peripheral.Delegate?.RadioClosed(l.PeripheralId, reason));
    }

    internal void DropAll(SimRadio radio, string reason)
    {
        foreach (var id in links.Where(kv => kv.Value.Central == radio || kv.Value.Peripheral == radio).Select(kv => kv.Key).ToList()) BreakLink(id, reason);
    }

    public int LinkCount => links.Values.Count(l => l.CentralOpen && l.PeripheralOpen);

    // Which radios have an open link to each other, as "a|b" sorted pairs
    public HashSet<string> LinkPairs => links.Values.Where(l => l.CentralOpen && l.PeripheralOpen).Select(l => Key(l.Central.Name, l.Peripheral.Name)).ToHashSet();

    private double Random()
    {
        // SplitMix64: the same run every time for a given seed
        unchecked
        {
            rng += 0x9E3779B97F4A7C15;
            var z = rng;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EB;
            z ^= z >> 31;
            return (z >> 11) / (double)(1UL << 53);
        }
    }
}

public sealed class SimRadio : ILinkTransport
{
    public string Name { get; }
    private readonly SimNetwork network;
    public ILinkTransportDelegate? Delegate { get; set; }
    public RadioState State { get; private set; } = RadioState.Starting;
    public int MaxFrameSize { get; }
    internal bool Running;
    internal bool Scanning;
    internal bool Advertising;
    internal uint Token;
    internal readonly HashSet<string> Reported = new();
    internal readonly HashSet<string> Waiting = new();
    public int FramesSent { get; internal set; }
    private readonly Dictionary<int, int> locals = new();      // this radio's link id → the network's
    private int nextLocal = 1;
    internal bool Powered = true;

    public SimRadio(string name, SimNetwork network, int maxFrame)
    {
        Name = name;
        this.network = network;
        MaxFrameSize = maxFrame;
    }

    internal int NewLocal(int link)
    {
        var id = nextLocal++;
        locals[id] = link;
        return id;
    }

    internal void Forget(int local) => locals.Remove(local);

    public int OpenLinks => locals.Count;

    // "Bluetooth" switched off or on in a test: links break, the mesh is told
    public void SetPower(bool on)
    {
        if (on == Powered) return;
        Powered = on;
        if (!on)
        {
            Scanning = false;
            Advertising = false;
            Waiting.Clear();
            network.DropAll(this, "Bluetooth is off");
        }
        if (!Running) return;
        State = on ? RadioState.On : RadioState.Off;
        var s = State;
        network.Schedule(() => Delegate?.RadioStateChanged(s));
    }

    public void Start(uint token)
    {
        Token = token;
        Running = true;
        State = Powered ? RadioState.On : RadioState.Off;
        var s = State;
        network.Schedule(() => Delegate?.RadioStateChanged(s));
    }

    public void Stop()
    {
        Running = false;
        Scanning = false;
        Advertising = false;
        Waiting.Clear();
        network.DropAll(this, "stopped");
        locals.Clear();
        State = RadioState.Off;
    }

    public void SetScanning(bool on)
    {
        if (!Powered) return;
        Scanning = on;
        if (on) Reported.Clear();
    }

    public void SetAdvertising(bool on)
    {
        if (!Powered) return;
        Advertising = on;
    }

    public void Connect(string endpoint)
    {
        Waiting.Add(endpoint);
        network.Schedule(() => network.TryConnect(this, endpoint));
    }

    public void CancelConnect(string endpoint) => Waiting.Remove(endpoint);

    public void Send(byte[] frame, int link)
    {
        if (locals.TryGetValue(link, out var id)) network.Send(frame, id, this);
    }

    public void Close(int link)
    {
        if (locals.TryGetValue(link, out var id)) network.Close(id, this);
    }

    public int MaxFrame(int link) => locals.TryGetValue(link, out var id) ? network.MaxFrame(id) : Proto.MinFrame;

    public void MeasureSignal(int link)
    {
        if (locals.TryGetValue(link, out var id)) network.Measure(id, link, this);
    }
}
