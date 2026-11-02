// MeshChat – the mesh, as lib/meshchat/Sources/Mesh.swift: links to computers nearby, the handshake, flooding with
// duplicate detection and a hop limit, signatures, who is here and what they say. One chat for everyone nearby: every
// computer with MeshChat – Mac or Windows – shows every message and passes it on, as far as the mesh reaches. Runs on
// one queue; the radio calls it there.
//
// Routing is managed flooding – there is no central server and no routing table:
//   1. A message goes to every neighbour (a computer with a link to this one).
//   2. A computer that gets a packet looks at its ID: seen in the last 30 minutes → dropped (a loop, a second path).
//   3. Otherwise it checks the sender's signature, how many messages that sender sent lately, and the age
//      (≤ 15 minutes). A packet that fails is dropped and never passed on – nobody relays what they could not check.
//   4. It shows the message and passes the packet to all its other neighbours with ttl - 1 and hops + 1. Every message
//      starts with the most the protocol allows – 16 relays.
//   5. A neighbour that connects gets the last 32 packets (ones younger than 14 minutes).
// Links: every computer advertises and scans. When two see each other, the one with the smaller token (4 random bytes
// in its advertised name) connects; the other waits 8 seconds before it tries itself. A computer without a token in
// its advertisement (Windows cannot set the name) is connected to at once. Should both connect at once, the link whose
// central has the smaller session is kept and the other one closed – both computers decide alike.

namespace MeshChat;

public sealed class MeshConfig
{
    public int Hops = Proto.HopLimit;           // how many relays a new message may take: as far as possible
    public int MaxLinks = 8;                    // Bluetooth links at most (each costs the radio time)
    public bool Silent;                         // pass on, but never say anything – not even "I am here" (relay)
    public double PresenceInterval = 30;        // "I am here" to everyone
    public double AwayAfter = 80;               // not heard for so long: away
    public double ForgetAfter = 600;            // … and gone from the list
    public double PingInterval = 15;            // a quiet link is asked whether it is still there
    public double LinkTimeout = 45;             // a link silent for so long is closed
    public double HelloTimeout = 10;
    public double ConnectTimeout = 15;
    public double MaxBackoff = 60;              // between attempts to reach a computer that does not answer
    public double MaxAge = 15 * 60;             // older messages are refused …
    public double MaxSkew = 10 * 60;            // … and ones from that far in the future (clocks that differ)
    public int CatchUp = 32;                    // recent packets a new neighbour gets
    public double SenderBurst = 40;             // packets of one sender taken in at once (more than a catch-up) …
    public double SenderRate = 1;               // … and one a second after that: one person cannot flood everyone
    public double InitiatorGrace = 8;           // the computer with the larger token waits so long for the other one
    public double SightingExpiry = 120;         // a computer not heard advertising for so long is forgotten
    public double ScanOnLinked = 10;            // scanning once linked: 10 s of every 30 s
    public double ScanOffLinked = 20;
    public double ScanOnAlone = 25;             // with no link: nearly always, restarted every 27 s
    public double ScanOffAlone = 2;
    public double MeasureEvery = 5;             // the signal of each link this computer made is read so often
    public double SignalFresh = 60;             // a signal older than this says nothing about now
}

public sealed record ChatMessage(ulong Id, string Nickname, string Fingerprint, string Text, double Sent, double Received, int Hops, bool Mine);

public sealed class Participant
{
    public byte[] Key = Array.Empty<byte>();
    public string Fingerprint = "";
    public string Nickname = "";
    public byte[] Session = Array.Empty<byte>();
    public double LastSeen;
    public int Hops;                    // relays the last packet took
    public int Links;                   // how many computers it said it is connected to
    public bool Direct;                 // a link to this computer right now
    public bool Left;                   // said goodbye
    public bool Away;                   // not heard for a while
    public int? Signal;                 // how strong this computer hears theirs (dBm), measured in the last minute
    public string Via = "";             // the neighbour their last message came through ("" when straight from them)
    public Dictionary<uint, int> Neighbours = new();    // the computers they have a link to, and how strong they hear them

    public uint Token => B.Token(Session);
    public Participant Copy()
    {
        var p = (Participant)MemberwiseClone();
        p.Neighbours = new Dictionary<uint, int>(Neighbours);
        return p;
    }
}

// One leg of the way to someone: the computer it reaches, and how strong that leg's signal is (null: not measured)
public readonly record struct RouteLeg(string Name, int? Rssi);

public sealed class MeshStats
{
    public int FramesIn, FramesOut;
    public int Delivered;               // messages shown (or presence taken in)
    public int Relayed;                 // packets passed on
    public int Duplicates;
    public int Malformed;
    public int Forged;                  // failed the signature (or damaged inside)
    public int Expired;                 // too old, or from the future
    public int RateLimited;
    public int Incompatible;
    public int ConnectFailures;
    public int CaughtUp;                // packets sent to a neighbour that connected

    public MeshStats Copy() => (MeshStats)MemberwiseClone();
}

public sealed class MeshSnapshot
{
    public RadioState Radio = RadioState.Starting;
    public int Links;                   // ready links
    public int Connecting;
    public List<Participant> Participants = new();     // the others, by name
    public bool Scanning;
    public bool Advertising;
    public MeshStats Stats = new();
}

public enum NoticeLevel { Info, Warning, Error }

public readonly record struct Notice(NoticeLevel Level, string Text);

public abstract record MeshEvent
{
    public sealed record Message(ChatMessage M) : MeshEvent;            // someone wrote (or this computer did)
    public sealed record Sent(ulong Id, int Links) : MeshEvent;         // a message of ours left on so many links
    public sealed record NoticeEvent(Notice N) : MeshEvent;
    public sealed record Snapshot(MeshSnapshot S) : MeshEvent;
    public sealed record Log(string Text) : MeshEvent;                  // for the diagnostics log: never secrets or what people wrote
}

public struct TokenBucket
{
    private readonly double capacity;
    private readonly double rate;
    private double tokens;
    private double? last;

    public TokenBucket(double capacity, double rate)
    {
        this.capacity = capacity;
        this.rate = rate;
        tokens = capacity;
        last = null;
    }

    public bool Take(double now)
    {
        if (last is double l) tokens = Math.Min(capacity, tokens + Math.Max(0, now - l) * rate);
        last = now;
        if (tokens < 1) return false;
        tokens -= 1;
        return true;
    }
}

// Where the texts of the mesh point people – the Windows app says it differently than a Mac
public static class MeshTexts
{
    public static string Update = "get the newest MeshChat";
    public static string CheckClock = "check the date and time of the two computers";
}

public sealed class MeshNode : ILinkTransportDelegate
{
    private enum LinkState { Hello, Ready, Redundant, Closed }

    private sealed class Link
    {
        public readonly int Id;
        public readonly bool Outbound;
        public readonly string Endpoint;
        public LinkState State = LinkState.Hello;
        public byte[]? Session;         // set by the handshake
        public string Software = "";
        public string? CloseReason;
        public bool Pruned;             // a second link to the same computer, closed on purpose
        public readonly double HelloDeadline;
        public double LastHeard;
        public double LastSent;
        private ushort seq;
        public readonly Reassembler Reassembler = new();
        public TokenBucket Frames = new(300, 150);      // frames a second it may send us
        public TokenBucket Packets = new(40, 15);       // whole packets a second

        public Link(LinkInfo info, double now, double helloTimeout)
        {
            Id = info.Id;
            Outbound = info.Outbound;
            Endpoint = info.Endpoint;
            HelloDeadline = now + helloTimeout;
            LastHeard = now;
            LastSent = now;
        }

        public ushort NextSeq() => unchecked(++seq);
    }

    private sealed class Candidate
    {
        public string Endpoint = "";
        public uint? Token;
        public int Rssi;
        public double FirstSeen;
        public double LastSeen;
        public double? ConnectingSince;
        public int Failures;
        public double NextAttempt;
    }

    private sealed record Recent(MeshPacket Packet, bool Mine);

    public ILinkTransport Transport { get; }
    public MeshConfig Config { get; }
    public byte[] Session { get; }
    public uint Token { get; }
    public Signer Signer { get; }
    public string Nickname { get; private set; }
    private readonly Func<double> clock;
    private readonly Action<MeshEvent> emit;

    private readonly Dictionary<int, Link> links = new();
    private readonly Dictionary<string, Candidate> candidates = new();
    private readonly Dictionary<string, byte[]> endpointSessions = new();
    private readonly DedupCache dedup = new();
    private readonly List<Recent> recent = new();
    private readonly Dictionary<byte[], Participant> people = new(B.Comparer);
    private readonly Dictionary<byte[], TokenBucket> senders = new(B.Comparer);
    private readonly Dictionary<uint, (double Rssi, double At)> signals = new();     // by token, smoothed
    private double lastMeasure = double.NegativeInfinity;
    private readonly HashSet<ulong> undelivered = new();
    private double presenceDue = double.PositiveInfinity;
    private double lastPresence = double.NegativeInfinity;
    private readonly Dictionary<string, double> noticed = new();
    private double scanEpoch;
    private bool scanning;
    private bool advertising;
    private bool running;
    private bool dirty = true;
    public MeshStats Stats { get; } = new();

    public MeshNode(ILinkTransport transport, string nickname, Signer signer, Action<MeshEvent> events, MeshConfig? config = null, Func<double>? clock = null)
    {
        Transport = transport;
        Config = config ?? new MeshConfig();
        Signer = signer;
        var clean = Sanitize.Nickname(nickname);
        Nickname = clean.Length == 0 ? "anon" : clean;
        this.clock = clock ?? (() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0);
        emit = events;
        Session = CryptoBackend.RandomBytes(Proto.SessionLength);
        Token = B.Token(Session);
        transport.Delegate = this;
    }

    public string Fingerprint => Signer.Fingerprint;
    public int ReadyLinks => links.Values.Count(l => l.State == LinkState.Ready);

    // ── Starting, speaking ────────────────────────────────────

    public void Start()
    {
        if (running) return;
        running = true;
        scanEpoch = clock();
        if (!Config.Silent) presenceDue = clock() + 0.5;      // "who is here?" as soon as there is a link
        Transport.Start(Token);
        Flush();
    }

    // Goodbye to everyone and every neighbour; the radio goes off with Stop()
    public void Goodbye()
    {
        if (running && !Config.Silent)
        {
            try { Flood(InnerKind.Bye); } catch (Exception) { }
        }
        foreach (var link in links.Values.Where(l => l.State == LinkState.Ready).ToList()) SendFrame(LinkFrame.Bye(ByeReason.Leaving), link);
    }

    // IDs of messages this computer has already (its history): copies that come again are not shown twice
    public void MarkSeen(IEnumerable<ulong> ids)
    {
        var t = clock();
        foreach (var id in ids) dedup.Insert(id, t);
    }

    public void Stop()
    {
        if (!running) return;
        running = false;
        Transport.Stop();
        links.Clear();
        candidates.Clear();
        scanning = false;
        advertising = false;
        dirty = true;
        Flush();
    }

    public void Rename(string name)
    {
        var clean = Sanitize.Nickname(name);
        if (clean.Length == 0) return;
        Nickname = clean;
        if (running && !Config.Silent) SendPresence(false);
        Flush();
    }

    public sealed class SendError : Exception
    {
        public SendError(string message) : base(message) { }
        public static SendError Empty() => new("There is nothing to send.");
        public static SendError TooLong() => new($"A message can be up to {Proto.MaxTextBytes} bytes long – that is about {Proto.MaxTextBytes} letters, fewer with emoji or accents.");
    }

    public ChatMessage Send(string text)
    {
        var clean = Sanitize.Line(text, int.MaxValue, int.MaxValue);
        if (clean.Length == 0) throw SendError.Empty();
        if (System.Text.Encoding.UTF8.GetByteCount(clean) > Proto.MaxTextBytes) throw SendError.TooLong();
        var (packet, n) = Flood(InnerKind.Chat, clean);
        var msg = new ChatMessage(packet.MessageId, Nickname, Signer.Fingerprint, clean, packet.Timestamp / 1000.0, clock(), 0, true);
        Stats.Delivered++;
        emit(new MeshEvent.Message(msg));
        emit(new MeshEvent.Sent(packet.MessageId, n));
        Flush();
        return msg;
    }

    // ── The radio ─────────────────────────────────────────────

    public void RadioStateChanged(RadioState state)
    {
        Log($"Bluetooth: {state.Label()}");
        if (state == RadioState.On)
        {
            scanEpoch = clock();
            scanning = false;
            advertising = false;
        }
        else
        {
            foreach (var c in candidates.Values) c.ConnectingSince = null;
            scanning = false;
            advertising = false;
        }
        ManageRadio(clock());
        dirty = true;
        Flush();
    }

    public void RadioSighted(Sighting s)
    {
        var t = clock();
        if (s.Token is uint theirs && theirs != Token) NoteSignal(theirs, s.Rssi, t);
        if (candidates.TryGetValue(s.Endpoint, out var c))
        {
            c.LastSeen = t;
            c.Rssi = s.Rssi;
            if (s.Token != null) c.Token = s.Token;
        }
        else
        {
            candidates[s.Endpoint] = new Candidate { Endpoint = s.Endpoint, Token = s.Token, Rssi = s.Rssi, FirstSeen = t, LastSeen = t };
            Log($"sighted a computer with MeshChat ({Short(s.Endpoint)}, signal {s.Rssi} dBm)");
        }
        ConnectCandidates(t);
        Flush();
    }

    public void RadioOpened(LinkInfo info)
    {
        var t = clock();
        var link = new Link(info, t, Config.HelloTimeout);
        links[info.Id] = link;
        if (info.Outbound && candidates.TryGetValue(info.Endpoint, out var c)) c.ConnectingSince = null;
        Log($"link {info.Id} open – {(info.Outbound ? "this computer connected" : "the other computer connected")}, frames of up to {info.MaxFrame} bytes");
        if (links.Values.Count(l => l.State != LinkState.Closed) > Config.MaxLinks)
        {
            SendFrame(LinkFrame.Bye(ByeReason.Full), link);
            CloseLink(link, "too many links");
        }
        else
        {
            SendFrame(LinkFrame.HelloFrame(new Hello(Session)), link);
        }
        dirty = true;
        Flush();
    }

    public void RadioClosed(int id, string reason)
    {
        if (!links.Remove(id, out var link)) return;
        var t = clock();
        var wasReady = link.Session != null && !link.Pruned;
        reason = link.CloseReason ?? reason;
        Log($"link {id} closed: {reason}");
        if (link.Outbound && candidates.TryGetValue(link.Endpoint, out var c))
        {
            c.ConnectingSince = null;
            if (link.Session == null)
            {
                // connected, but no handshake (or no version in common): a failed attempt, so it is not retried every
                // few seconds forever
                c.Failures++;
                Stats.ConnectFailures++;
            }
            // a computer that was there a moment ago: try again soon, it may only have moved a little
            c.NextAttempt = t + (wasReady ? 2 : Backoff(c.Failures));
        }
        if (wasReady && link.Session is byte[] s && !links.Values.Any(l => l.State == LinkState.Ready && B.Eq(l.Session, s)))
        {
            var p = people.Values.FirstOrDefault(x => B.Eq(x.Session, s));
            if (p != null && !p.Left)
                Tell($"The Bluetooth link to {p.Nickname} ended ({reason}) – the mesh may still reach {p.Nickname} through others.");
        }
        dirty = true;
        Flush();
    }

    public void RadioReceived(byte[] frame, int id)
    {
        if (!links.TryGetValue(id, out var link) || link.State == LinkState.Closed) return;
        var t = clock();
        link.LastHeard = t;
        Stats.FramesIn++;
        if (!link.Frames.Take(t))
        {
            Stats.RateLimited++;
            return;
        }
        LinkFrame decoded;
        try
        {
            decoded = LinkFrame.Decode(frame);
        }
        catch (WireError e) when (e.Kind == WireError.Kinds.UnsupportedVersion)
        {
            Stats.Incompatible++;
            NoticeOnce($"link-version-{e.Version}", $"A computer nearby speaks a newer MeshChat (link protocol {e.Version}) – update this one: {MeshTexts.Update}", NoticeLevel.Warning);
            return;
        }
        catch (WireError)
        {
            Stats.Malformed++;
            return;
        }
        switch (decoded.Kind)
        {
            case LinkKind.Hello:
                HandleHello(decoded.Hello!, link);
                break;
            case LinkKind.Data:
                if (link.State != LinkState.Ready)
                {
                    if (link.State == LinkState.Hello) Stats.Malformed++;     // data before the handshake
                    break;                                                    // (or on a second link that is going)
                }
                switch (link.Reassembler.Add(decoded.Seq, decoded.Index, decoded.Count, decoded.Payload, t, out var whole))
                {
                    case Reassembler.Outcome.Complete: Received(whole!, link); break;
                    case Reassembler.Outcome.Duplicate: Stats.Duplicates++; break;
                    case Reassembler.Outcome.Rejected: Stats.Malformed++; break;
                }
                break;
            case LinkKind.Ping:
                SendFrame(LinkFrame.Pong, link);
                break;
            case LinkKind.Pong:
                break;
            case LinkKind.Bye:
                Log($"link {id}: the other computer ended it (reason {decoded.Reason})");
                CloseLink(link, decoded.Reason == ByeReason.Leaving ? "it left" : "it ended the link");
                break;
        }
        Flush();
    }

    public void RadioConnectFailed(string endpoint, string reason)
    {
        Failed(endpoint, reason);
        Flush();
    }

    public void RadioSignal(int rssi, int id)
    {
        if (!links.TryGetValue(id, out var l) || l.Session == null) return;
        NoteSignal(B.Token(l.Session), rssi, clock());
        dirty = true;
        Flush();
    }

    private void Failed(string endpoint, string reason)
    {
        if (!candidates.TryGetValue(endpoint, out var c)) return;
        c.ConnectingSince = null;
        c.Failures++;
        c.NextAttempt = clock() + Backoff(c.Failures);
        Stats.ConnectFailures++;
        Log($"could not connect to {Short(endpoint)}: {reason} (attempt {c.Failures})");
        dirty = true;
    }

    // Once a second: timeouts, pings, scanning, connecting, "I am here", who is away
    public void Tick()
    {
        if (!running) return;
        var t = clock();
        foreach (var link in links.Values.ToList())
        {
            if (link.State == LinkState.Hello && t > link.HelloDeadline)
                CloseLink(link, "no handshake");
            else if (link.State != LinkState.Closed && t - link.LastHeard > Config.LinkTimeout)
                CloseLink(link, $"no answer for {(int)Config.LinkTimeout} seconds");
            else if (link.State == LinkState.Ready && t - link.LastSent >= Config.PingInterval)
                SendFrame(LinkFrame.Ping, link);
            link.Reassembler.Expire(t);
        }
        ConnectCandidates(t);
        ManageRadio(t);
        if (t - lastMeasure >= Config.MeasureEvery)
        {
            lastMeasure = t;
            foreach (var link in links.Values.Where(l => l.State == LinkState.Ready && l.Outbound).ToList()) Transport.MeasureSignal(link.Id);
        }
        if (!Config.Silent && t >= presenceDue) SendPresence(double.IsNegativeInfinity(lastPresence));
        Age(t);
        dirty = true;
        Flush();
    }

    // ── Links ─────────────────────────────────────────────────

    private void HandleHello(Hello h, Link link)
    {
        if (link.State != LinkState.Hello) return;
        if (!(h.MinVersion <= Proto.Version && h.MaxVersion >= Proto.Version))
        {
            Stats.Incompatible++;
            if (h.MinVersion > Proto.Version)
                NoticeOnce($"newer-{h.MinVersion}", $"A computer nearby runs a newer MeshChat (protocol {h.MinVersion}) – update this one to chat with it: {MeshTexts.Update}", NoticeLevel.Warning);
            else
                NoticeOnce($"older-{h.MaxVersion}", $"A computer nearby runs an older MeshChat (protocol {h.MaxVersion}) – it needs an update to chat with this one: {MeshTexts.Update}", NoticeLevel.Warning);
            SendFrame(LinkFrame.Bye(ByeReason.Incompatible), link);
            CloseLink(link, "no protocol version in common");
            return;
        }
        if (B.Eq(h.Session, Session))
        {
            CloseLink(link, "this computer itself");
            return;
        }
        link.Session = h.Session;
        link.Software = h.Software;
        link.State = LinkState.Ready;
        endpointSessions[link.Endpoint] = h.Session;
        if (link.Outbound && candidates.TryGetValue(link.Endpoint, out var c)) c.Failures = 0;   // a link that works: a clean slate
        Log($"link {link.Id} ready ({h.Software})");
        if (!KeepOne(link)) return;
        CatchUp(link);
        if (!Config.Silent) presenceDue = Math.Min(presenceDue, clock() + 1);
        dirty = true;
    }

    // Two links to the same computer: keep the one whose central has the smaller session, close the others. Both
    // computers decide alike. false when `link` itself is one that goes.
    private bool KeepOne(Link link)
    {
        var same = links.Values.Where(l => l.State == LinkState.Ready && B.Eq(l.Session, link.Session)).ToList();
        if (same.Count <= 1) return true;
        bool Preferred(Link l)
        {
            if (l.Session is not byte[] remote) return false;
            return l.Outbound ? B.Less(Session, remote) : B.Less(remote, Session);
        }
        var keep = same.Aggregate((a, b) =>
        {
            bool pa = Preferred(a), pb = Preferred(b);
            var aFirst = pa != pb ? pa : a.Id < b.Id;
            return aFirst ? a : b;
        });
        foreach (var other in same.Where(o => o != keep))
        {
            Log($"link {other.Id} is a second link to the same computer – closed");
            SendFrame(LinkFrame.Bye(ByeReason.Redundant), other);
            other.State = LinkState.Redundant;
            other.Pruned = true;
            if (other.Outbound) CloseLink(other, "a second link to the same computer");
        }
        return keep == link;
    }

    private void CloseLink(Link link, string reason)
    {
        if (link.State == LinkState.Closed) return;
        link.CloseReason ??= reason;
        link.State = LinkState.Closed;
        dirty = true;
        Transport.Close(link.Id);
    }

    private void SendFrame(LinkFrame frame, Link link)
    {
        if (link.State == LinkState.Closed) return;
        Transport.Send(frame.Encode(), link.Id);
        link.LastSent = clock();
        Stats.FramesOut++;
    }

    private void SendPacket(MeshPacket packet, Link link)
    {
        if (link.State != LinkState.Ready) return;
        try
        {
            foreach (var f in Fragmenter.Frames(packet.Encode(), link.NextSeq(), Transport.MaxFrame(link.Id)))
            {
                Transport.Send(f, link.Id);
                Stats.FramesOut++;
            }
            link.LastSent = clock();
        }
        catch (WireError e)
        {
            Log($"could not send on link {link.Id}: {e.Message}");
        }
    }

    private bool IsLinked(byte[] s) => links.Values.Any(l => l.State == LinkState.Ready && B.Eq(l.Session, s));

    private bool ShouldConnect(Candidate c, double t)
    {
        if (links.Values.Any(l => l.Endpoint == c.Endpoint && l.Outbound)) return false;
        if (endpointSessions.TryGetValue(c.Endpoint, out var s) && IsLinked(s)) return false;
        if (c.Token is uint theirs)
        {
            var linkedTokens = links.Values.Where(l => l.State != LinkState.Closed && l.Session != null).Select(l => B.Token(l.Session!));
            if (linkedTokens.Contains(theirs)) return false;
            if (theirs == Token) return t - c.FirstSeen > 30;                               // the same 4 bytes as ours: very rare
            if (theirs < Token && t - c.FirstSeen < Config.InitiatorGrace) return false;    // theirs connects
        }
        return true;
    }

    private void ConnectCandidates(double t)
    {
        if (!running || Transport.State != RadioState.On) return;
        foreach (var (endpoint, c) in candidates.ToList())
        {
            if (c.ConnectingSince is double since && t - since > Config.ConnectTimeout)
            {
                Transport.CancelConnect(endpoint);
                Failed(endpoint, $"no answer within {(int)Config.ConnectTimeout} seconds");
            }
            else if (c.ConnectingSince == null && t - c.LastSeen > Config.SightingExpiry && !links.Values.Any(l => l.Endpoint == endpoint))
            {
                candidates.Remove(endpoint);
            }
        }
        var busy = links.Values.Count(l => l.State != LinkState.Closed) + candidates.Values.Count(c => c.ConnectingSince != null);
        foreach (var c in candidates.Values.OrderByDescending(c => c.Rssi).ToList())
        {
            if (busy >= Config.MaxLinks) break;
            if (c.ConnectingSince != null || t < c.NextAttempt || !ShouldConnect(c, t)) continue;
            c.ConnectingSince = t;
            busy++;
            Log($"connecting to {Short(c.Endpoint)}");
            Transport.Connect(c.Endpoint);
        }
    }

    // 2, 4, 8 … 60 seconds between attempts; after 8 failures in a row, 5 minutes
    private double Backoff(int failures) =>
        failures >= 8 ? 300 : Math.Min(Config.MaxBackoff, 2 * Math.Pow(2, Math.Max(0, failures - 1)));

    // Advertising while there is room for another link; scanning in bursts – nearly always while alone, a third of
    // the time once linked, never when full
    private void ManageRadio(double t)
    {
        if (!running || Transport.State != RadioState.On) return;
        var open = links.Values.Count(l => l.State != LinkState.Closed);
        var full = open >= Config.MaxLinks;
        if (advertising != !full)
        {
            advertising = !full;
            Transport.SetAdvertising(advertising);
        }
        var alone = ReadyLinks == 0;
        var on = alone ? Config.ScanOnAlone : Config.ScanOnLinked;
        var cycle = on + (alone ? Config.ScanOffAlone : Config.ScanOffLinked);
        var want = !full && Mod(t - scanEpoch, cycle) < on;
        if (want != scanning)
        {
            scanning = want;
            Transport.SetScanning(want);
        }
    }

    // Swift's truncatingRemainder: the sign of the dividend
    private static double Mod(double a, double b) => a - b * Math.Truncate(a / b);

    // ── Packets ───────────────────────────────────────────────

    private void Received(byte[] bytes, Link link)
    {
        var t = clock();
        if (!link.Packets.Take(t))
        {
            Stats.RateLimited++;
            return;
        }
        MeshPacket packet;
        try
        {
            packet = MeshPacket.Decode(bytes);
        }
        catch (WireError e) when (e.Kind == WireError.Kinds.UnsupportedVersion)
        {
            Stats.Incompatible++;
            NoticeOnce($"packet-version-{e.Version}", e.Version > Proto.Version
                ? $"A computer nearby sends messages of a newer MeshChat (protocol {e.Version}) – update this one: {MeshTexts.Update}"
                : $"A computer nearby sends messages of an older MeshChat (protocol {e.Version}) – it needs an update.", NoticeLevel.Warning);
            return;
        }
        catch (WireError)
        {
            Stats.Malformed++;
            return;
        }
        if (dedup.Contains(packet.MessageId, t))
        {
            Stats.Duplicates++;
            return;
        }
        InnerMessage inner;
        try
        {
            inner = Signing.Open(packet);
        }
        catch (Signing.OpenError)
        {
            // not remembered as seen: a forged copy must not keep the real message out
            Stats.Forged++;
            NoticeOnce("forged", "Ignored a forged or damaged message – it was not shown and not passed on.", NoticeLevel.Warning, 120);
            return;
        }
        dedup.Insert(packet.MessageId, t);
        // one sender cannot flood everyone: what is over its share is dropped here, and not passed on
        if (!senders.TryGetValue(inner.SenderKey, out var bucket)) bucket = new TokenBucket(Config.SenderBurst, Config.SenderRate);
        var allowed = bucket.Take(t);
        senders[inner.SenderKey] = bucket;
        if (!allowed)
        {
            Stats.RateLimited++;
            NoticeOnce($"flood-{Hex.Encode(inner.SenderKey)}", $"{inner.Nickname} sends very many messages – some are not shown and not passed on.", NoticeLevel.Warning, 120);
            return;
        }
        var sent = packet.Timestamp / 1000.0;
        if (t - sent > Config.MaxAge || sent - t > Config.MaxSkew)
        {
            Stats.Expired++;
            var minutes = (int)((sent - t) / 60);
            NoticeOnce($"clock-{Hex.Encode(inner.SenderKey)}",
                $"Ignored a message from {inner.Nickname} dated {Math.Abs(minutes)} minutes {(minutes > 0 ? "ahead" : "ago")} – if it was just sent, the clocks of the two computers differ: {MeshTexts.CheckClock}.",
                NoticeLevel.Warning, 300);
            return;
        }
        Remember(packet, false);
        Deliver(inner, packet, link, t);
        if (packet.Relayed() is MeshPacket next)
        {
            if (Forward(next, link) > 0) Stats.Relayed++;
        }
    }

    private int Forward(MeshPacket packet, Link? except)
    {
        var n = 0;
        foreach (var l in links.Values.Where(l => l.State == LinkState.Ready && l != except).ToList())
        {
            SendPacket(packet, l);
            n++;
        }
        return n;
    }

    // A new message of this computer to everyone → the packet and how many links it left on
    private (MeshPacket Packet, int Links) Flood(InnerKind kind, string text = "", bool request = false)
    {
        var inner = new InnerMessage
        {
            Kind = kind, Flags = request ? InnerMessage.RequestFlag : (byte)0, SenderKey = Signer.PublicKey, Session = Session,
            Nickname = Nickname, Text = text, Links = (byte)Math.Min(255, ReadyLinks),
        };
        if (kind == InnerKind.Presence)
        {
            var now = clock();
            inner.Neighbours = links.Values.Where(l => l.State == LinkState.Ready && l.Session != null)
                .Select(l => B.Token(l.Session!)).Distinct()
                .Select(tk => new Neighbour(tk, Signal(tk, now) ?? Distance.Unknown))
                .OrderBy(n => n.Token).ToList();
        }
        ulong id;
        do { id = BitConverter.ToUInt64(CryptoBackend.RandomBytes(8)); } while (id == 0);
        var packet = Signing.Make(inner, Signer, (byte)Math.Max(1, Math.Min((int)Proto.HopLimit, Config.Hops)), id, (ulong)Math.Max(0, clock() * 1000));
        dedup.Insert(id, clock());
        Remember(packet, true);
        var n = Forward(packet, null);
        if (n == 0 && kind == InnerKind.Chat) undelivered.Add(id);
        return (packet, n);
    }

    private void SendPresence(bool request)
    {
        try { Flood(InnerKind.Presence, request: request); } catch (WireError) { }
        lastPresence = clock();
        presenceDue = clock() + Config.PresenceInterval * (0.8 + Random.Shared.NextDouble() * 0.4);
    }

    private void Remember(MeshPacket packet, bool mine)
    {
        recent.Add(new Recent(packet, mine));
        if (recent.Count > Config.CatchUp) recent.RemoveRange(0, recent.Count - Config.CatchUp);
    }

    // What a new neighbour may have missed: the recent packets, as they would have been passed on
    private void CatchUp(Link link)
    {
        var t = clock();
        var n = 0;
        foreach (var r in recent.ToList())
        {
            if (!(t - r.Packet.Timestamp / 1000.0 < Config.MaxAge - 60)) continue;
            var p = r.Mine ? r.Packet : r.Packet.Relayed();
            if (p == null) continue;
            SendPacket(p, link);
            n++;
            if (undelivered.Remove(r.Packet.MessageId)) emit(new MeshEvent.Sent(r.Packet.MessageId, 1));
        }
        if (n > 0)
        {
            Stats.CaughtUp += n;
            Log($"link {link.Id}: sent the {n} most recent packets");
        }
    }

    // ── People ────────────────────────────────────────────────

    private void Deliver(InnerMessage inner, MeshPacket packet, Link link, double t)
    {
        var sent = packet.Timestamp / 1000.0;
        var fingerprint = Signer.FingerprintOf(inner.SenderKey);
        if (B.Eq(inner.SenderKey, Signer.PublicKey))
        {
            // this computer's own, from before it was restarted: a neighbour still had it
            if (inner.Kind == InnerKind.Chat)
                emit(new MeshEvent.Message(new ChatMessage(packet.MessageId, inner.Nickname, fingerprint, inner.Text, sent, t, packet.Hops, true)));
            return;
        }
        var seen = t - sent < 60 ? t : Math.Min(t, sent);            // a late packet does not make someone "here"
        var known = people.TryGetValue(inner.SenderKey, out var existing);
        var p = existing ?? new Participant
        {
            Key = inner.SenderKey, Fingerprint = fingerprint, Nickname = inner.Nickname, Session = inner.Session,
            LastSeen = double.NegativeInfinity, Hops = packet.Hops, Links = 0,
        };
        var isNew = !known || p.Left || p.Away;
        var fresh = seen >= p.LastSeen;
        if (fresh)
        {
            if (p.Nickname != inner.Nickname && known && inner.Kind != InnerKind.Bye) Tell($"{p.Nickname} is now called {inner.Nickname}.");
            p.Nickname = inner.Nickname;
            p.Session = inner.Session;
            p.LastSeen = seen;
            p.Hops = packet.Hops;
            p.Away = t - seen > Config.AwayAfter;
            if (inner.Kind == InnerKind.Presence)
            {
                p.Links = inner.Links;
                p.Neighbours = new Dictionary<uint, int>();
                foreach (var nb in inner.Neighbours) p.Neighbours.TryAdd(nb.Token, nb.Rssi);
            }
            p.Via = packet.Hops == 0 ? "" : (link.Session is byte[] ls ? people.Values.FirstOrDefault(x => B.Eq(x.Session, ls))?.Nickname : null) ?? "a relay";
            p.Left = inner.Kind == InnerKind.Bye;
        }
        people[inner.SenderKey] = p;
        Stats.Delivered++;
        switch (inner.Kind)
        {
            case InnerKind.Chat:
                emit(new MeshEvent.Message(new ChatMessage(packet.MessageId, inner.Nickname, fingerprint, inner.Text, sent, t, packet.Hops, false)));
                break;
            case InnerKind.Presence:
                if (!Config.Silent && (inner.Flags & InnerMessage.RequestFlag) != 0 && clock() - lastPresence > 5)
                    presenceDue = Math.Min(presenceDue, t + 0.3 + Random.Shared.NextDouble() * 1.7);
                break;
            case InnerKind.Bye:
                if (fresh) Tell($"{inner.Nickname} left the chat.");
                break;
        }
        if (isNew && fresh && !p.Left && !p.Away)
        {
            var how = p.Hops == 0 ? "a neighbour" : $"{p.Hops} relay{(p.Hops == 1 ? "" : "s")} away";
            Tell($"{inner.Nickname} is here – {how}.");
        }
        dirty = true;
    }

    private void Age(double t)
    {
        foreach (var (key, p) in people.ToList())
        {
            if ((p.Left && t - p.LastSeen > 120) || t - p.LastSeen > Config.ForgetAfter)
            {
                people.Remove(key);
                senders.Remove(key);
                continue;
            }
            var away = !p.Left && t - p.LastSeen > Config.AwayAfter;
            if (away && !p.Away) Tell($"{p.Nickname} has not been heard for a while – out of range?");
            p.Away = away;
        }
        // senders that never got through (made up keys, a flood) are not kept forever
        if (senders.Count > 1000)
            foreach (var k in senders.Keys.Where(k => !people.ContainsKey(k)).ToList()) senders.Remove(k);
    }

    // ── How far ───────────────────────────────────────────────

    // A new reading, smoothed with the last one while that is recent: single readings jump by several dBm
    private void NoteSignal(uint who, int rssi, double t)
    {
        if (rssi >= 0 || rssi <= -127) return;
        if (signals.TryGetValue(who, out var old) && t - old.At < 20)
            signals[who] = (old.Rssi * 0.6 + rssi * 0.4, t);
        else
            signals[who] = (rssi, t);
    }

    private int? Signal(uint who, double t)
    {
        if (!signals.TryGetValue(who, out var s) || t - s.At > Config.SignalFresh) return null;
        return (int)Math.Round(s.Rssi, MidpointRounding.AwayFromZero);
    }

    // The way to someone through the mesh, as far as the "I am here"s of everyone tell it: the computers on it, each
    // with the signal of the leg that reaches it. null when no way is known (yet).
    public List<RouteLeg>? Route(byte[] key)
    {
        if (!people.TryGetValue(key, out var target)) return null;
        var t = clock();
        var map = new Dictionary<uint, Dictionary<uint, int>>();
        void Add(uint a, uint b, int rssi)
        {
            if (a == b) return;
            foreach (var (x, y) in new[] { (a, b), (b, a) })
            {
                // a measured signal wins over none; this computer's own measurement wins over the others'
                if (map.TryGetValue(x, out var row) && row.TryGetValue(y, out var known) && known != Distance.Unknown && rssi == Distance.Unknown) continue;
                if (!map.TryGetValue(x, out row)) map[x] = row = new Dictionary<uint, int>();
                row[y] = rssi;
            }
        }
        foreach (var p in people.Values.Where(p => !p.Left))
            foreach (var (n, rssi) in p.Neighbours) Add(p.Token, n, rssi);
        foreach (var n in links.Values.Where(l => l.State == LinkState.Ready && l.Session != null).Select(l => B.Token(l.Session!)).Distinct())
        {
            var measured = Signal(n, t) ?? (map.TryGetValue(n, out var r) && r.TryGetValue(Token, out var v) ? v : Distance.Unknown);
            Add(Token, n, measured);
        }
        var way = Distance.Route(Token, target.Token, map);
        if (way == null) return null;
        var names = new Dictionary<uint, string>();
        foreach (var p in people.Values) names.TryAdd(p.Token, p.Nickname);
        return way.Select(w => new RouteLeg(names.TryGetValue(w.Mac, out var nm) ? nm : "a relay", w.Rssi)).ToList();
    }

    // ── Telling the app ───────────────────────────────────────

    public MeshSnapshot Snapshot()
    {
        var direct = links.Values.Where(l => l.State == LinkState.Ready && l.Session != null).Select(l => l.Session!).ToHashSet(B.Comparer);
        var t = clock();
        var list = people.Values.Select(p => p.Copy()).ToList();
        foreach (var p in list)
        {
            p.Direct = direct.Contains(p.Session) && !p.Left;
            p.Signal = Signal(p.Token, t);
        }
        list.Sort((a, b) =>
        {
            var la = a.Nickname.ToLowerInvariant();
            var lb = b.Nickname.ToLowerInvariant();
            return la != lb ? string.CompareOrdinal(la, lb) : string.CompareOrdinal(a.Fingerprint, b.Fingerprint);
        });
        return new MeshSnapshot
        {
            Radio = Transport.State, Links = ReadyLinks, Connecting = candidates.Values.Count(c => c.ConnectingSince != null),
            Participants = list, Scanning = scanning, Advertising = advertising, Stats = Stats.Copy(),
        };
    }

    private void Flush()
    {
        if (!dirty) return;
        dirty = false;
        emit(new MeshEvent.Snapshot(Snapshot()));
    }

    private void Tell(string text, NoticeLevel level = NoticeLevel.Info) => emit(new MeshEvent.NoticeEvent(new Notice(level, text)));

    // The same notice at most once (or once every `every` seconds)
    private void NoticeOnce(string key, string text, NoticeLevel level, double every = double.PositiveInfinity)
    {
        var t = clock();
        if (noticed.TryGetValue(key, out var last) && (double.IsPositiveInfinity(every) || t - last < every)) return;
        noticed[key] = t;
        Tell(text, level);
    }

    private void Log(string text) => emit(new MeshEvent.Log(text));

    private static string Short(string endpoint) => endpoint.Length <= 8 ? endpoint : endpoint[..8];
}
