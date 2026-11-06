// MeshChat tests – the mesh on a simulated radio: computers that find and link to each other, messages over many relays
// – as far as the hop limit – each shown once, catching up after being out of range, hostile neighbours, floods,
// relays, who is here, and Bluetooth switched off. The radio is simulated (Sim.cs), the mesh is the real one.
// As lib/meshchat/Tests/MeshTests.swift – the same scenarios with the same expectations.

using static MeshChat.TestRun;

namespace MeshChat;

public sealed class TestMesh
{
    public readonly SimNetwork Net;
    public readonly Dictionary<string, MeshNode> Nodes = new();
    public readonly Dictionary<string, SimRadio> Radios = new();
    public readonly Dictionary<string, List<MeshEvent>> Events = new();

    public TestMesh(ulong seed = 1) => Net = new SimNetwork(seed: seed);

    public MeshNode Add(string name, int maxFrame = 182, MeshConfig? config = null, byte[]? identity = null)
    {
        var radio = Net.Radio(name, maxFrame);
        var net = Net;
        Events[name] = new List<MeshEvent>();
        var node = new MeshNode(radio, name, Signer.FromIdentity(identity ?? CryptoBackend.RandomBytes(32)), e => Events[name].Add(e), config, () => net.Now);
        Nodes[name] = node;
        Radios[name] = radio;
        Net.Tickers.Add(node.Tick);
        node.Start();
        return node;
    }

    public MeshNode Node(string name) => Nodes[name];
    public void RunFor(double seconds) => Net.Advance(seconds);

    public void Say(string name, string text)
    {
        try { Nodes[name].Send(text); } catch (Exception) { }
        Net.Pump();
    }

    public List<ChatMessage> Received(string name) =>
        Events[name].OfType<MeshEvent.Message>().Select(m => m.M).Where(m => !m.Mine).ToList();

    public List<string> Texts(string name) => Received(name).Select(m => m.Text).ToList();
    public List<string> Notices(string name) => Events[name].OfType<MeshEvent.NoticeEvent>().Select(n => n.N.Text).ToList();
    public List<Participant> People(string name) => Nodes[name].Snapshot().Participants;
    public Participant? Person(string who, string seenBy) => People(seenBy).FirstOrDefault(p => p.Nickname == who);
    public bool Linked(string a, string b) => Net.LinkPairs.Contains(string.CompareOrdinal(a, b) < 0 ? $"{a}|{b}" : $"{b}|{a}");
    public MeshStats Stats(string name) => Nodes[name].Stats;

    public void Adopt(MeshNode node, SimRadio radio, string name)
    {
        Nodes[name] = node;
        Radios[name] = radio;
        Events.TryAdd(name, new List<MeshEvent>());
        Net.Tickers.Add(node.Tick);
    }
}

// A neighbour that sends whatever a test wants
public sealed class Rogue : ILinkTransportDelegate
{
    public readonly SimRadio Radio;
    public int? Link;
    public readonly List<byte[]> ReceivedFrames = new();
    public bool Closed;
    public int Opened;
    private ushort seq = 100;

    public Rogue(SimNetwork net, string name = "rogue", int maxFrame = 512)
    {
        Radio = net.Radio(name, maxFrame);
        Radio.Delegate = this;
        Radio.Start(0);
    }

    public void ConnectTo(string name, SimNetwork net, bool hello = true)
    {
        Radio.Connect(name);
        net.Pump();
        if (hello) Send(LinkFrame.HelloFrame(new Hello(CryptoBackend.RandomBytes(8))));
        net.Pump();
    }

    public void Send(LinkFrame f) => SendRaw(f.Encode());

    public void SendRaw(byte[] d)
    {
        if (Link is int l) Radio.Send(d, l);
    }

    public void SendPacket(MeshPacket p)
    {
        seq = unchecked((ushort)(seq + 1));
        foreach (var f in Fragmenter.Frames(p.Encode(), seq, 512)) SendRaw(f);
    }

    public void RadioStateChanged(RadioState state) { }
    public void RadioSighted(Sighting s) { }

    public void RadioOpened(LinkInfo link)
    {
        Link = link.Id;
        Opened++;
    }

    public void RadioClosed(int link, string reason)
    {
        Closed = true;
        Link = null;
    }

    public void RadioReceived(byte[] frame, int link) => ReceivedFrames.Add(frame);
    public void RadioConnectFailed(string endpoint, string reason) { }
    public void RadioSignal(int rssi, int link) { }
}

public static class MeshTests
{
    // A packet as any MeshChat makes it – properly signed, by whoever `signer` is
    private static MeshPacket SignedPacket(TestMesh m, string text, string from = "Mallory", double? time = null, ulong id = 777, Signer? signer = null, byte ttl = Proto.HopLimit)
    {
        var s = signer ?? Signer.FromIdentity(CryptoBackend.RandomBytes(32));
        var inner = new InnerMessage { Kind = InnerKind.Chat, SenderKey = s.PublicKey, Session = CryptoBackend.RandomBytes(8), Nickname = from, Text = text };
        return Signing.Make(inner, s, ttl, id, (ulong)((time ?? m.Net.Now) * 1000));
    }

    public static void Run()
    {
        Test("two computers find each other, link once and chat", () =>
        {
            var m = new TestMesh();
            m.Add("Ada");
            m.Add("Bob");
            m.Net.AllInRange("Ada", "Bob");
            m.RunFor(15);
            Check(m.Linked("Ada", "Bob"), "linked");
            CheckEqual(m.Net.LinkCount, 1, "one link, not two");
            CheckEqual(m.Node("Ada").ReadyLinks, 1, "Ada has the link");
            m.Say("Ada", "Hello, Bob!");
            CheckList(m.Texts("Bob"), new[] { "Hello, Bob!" }, "Bob reads it");
            CheckEqual(m.Received("Bob").FirstOrDefault()?.Nickname, "Ada", "from Ada");
            CheckEqual(m.Received("Bob").FirstOrDefault()?.Hops, 0, "straight from her");
            m.Say("Bob", "Hi Ada");
            CheckList(m.Texts("Ada"), new[] { "Hi Ada" }, "and Ada his answer");
            Check(m.Person("Bob", "Ada")?.Direct == true, "Ada sees Bob as a neighbour");
            Check(m.Notices("Ada").Any(n => n.Contains("Bob is here")), "and was told he is here");
        });

        Test("multi-hop: A reaches C through B, though A and C cannot hear each other", () =>
        {
            var m = new TestMesh();
            foreach (var n in new[] { "A", "B", "C" }) m.Add(n);
            m.Net.SetRange("A", "B", true);
            m.Net.SetRange("B", "C", true);
            m.RunFor(40);
            Check(m.Linked("A", "B") && m.Linked("B", "C"), "A–B and B–C are linked");
            Check(!m.Linked("A", "C"), "A–C cannot be");
            m.Say("A", "over the hill");
            CheckList(m.Texts("C"), new[] { "over the hill" }, "C reads A's message");
            CheckEqual(m.Received("C").FirstOrDefault()?.Hops, 1, "through one relay");
            CheckList(m.Texts("B"), new[] { "over the hill" }, "B reads it too");
            m.Say("C", "got it");
            CheckList(m.Texts("A"), new[] { "got it" }, "and the answer comes back");
            var a = m.Person("A", "C");
            Check(a != null && !a.Direct && a.Hops == 1, "C sees A one relay away");
            Check(m.Person("B", "C")?.Direct == true, "and B as its neighbour");
            Check(m.Stats("B").Relayed >= 2, "B passed both on");
        });

        Test("each message is shown once, however many paths it takes", () =>
        {
            var m = new TestMesh();
            var names = new[] { "A", "B", "C", "D", "E" };
            foreach (var n in names) m.Add(n);
            m.Net.AllInRange(names);
            m.RunFor(60);
            Check(m.Net.LinkCount >= 7, $"a dense mesh ({m.Net.LinkCount} links)");
            foreach (var n in names) m.Say(n, $"from {n}");
            m.RunFor(2);
            foreach (var n in names)
                CheckList(m.Texts(n).OrderBy(x => x, StringComparer.Ordinal), names.Where(x => x != n).Select(x => $"from {x}").OrderBy(x => x, StringComparer.Ordinal), $"{n} got each other message exactly once");
            Check(names.Sum(n => m.Stats(n).Duplicates) > 0, "copies over other paths were recognized and dropped");
        });

        Test("as far as it goes: every computer passes a message on, 16 relays far – and no further", () =>
        {
            var m = new TestMesh();
            var chain = Enumerable.Range(0, 19).Select(i => $"N{i}").ToArray();
            foreach (var n in chain) m.Add(n);
            for (var i = 0; i < 18; i++) m.Net.SetRange(chain[i], chain[i + 1], true);
            m.RunFor(90);
            CheckEqual(m.Net.LinkCount, 18, "a chain of 19 computers, each hearing only the next");
            m.Say("N0", "as far as it goes");
            m.RunFor(3);
            var reached = chain.Where(n => m.Texts(n).Contains("as far as it goes"));
            CheckList(reached, chain[1..18], "the neighbour and 16 relays: N1 to N17 – not N18");
            CheckEqual(m.Received("N17").FirstOrDefault(x => x.Text == "as far as it goes")?.Hops, 16, "N17 got it after 16 relays");
            m.Say("N9", "from the middle");
            m.RunFor(3);
            CheckEqual(chain.Count(n => m.Texts(n).Contains("from the middle")), 18, "from the middle it reaches both ends");
        });

        Test("old messages, ones from the future and replays are refused", () =>
        {
            var m = new TestMesh();
            m.Add("A");
            var rogue = new Rogue(m.Net);
            m.Net.AllInRange("A", "rogue");
            m.RunFor(3);
            rogue.ConnectTo("A", m.Net);
            Check(rogue.Link != null, "a computer linked to A");
            rogue.SendPacket(SignedPacket(m, "stale", time: m.Net.Now - 20 * 60, id: 1));
            rogue.SendPacket(SignedPacket(m, "from the future", time: m.Net.Now + 30 * 60, id: 2));
            rogue.SendPacket(SignedPacket(m, "fresh", id: 3));
            m.Net.Pump();
            CheckList(m.Texts("A"), new[] { "fresh" }, "only the fresh one is shown");
            CheckEqual(m.Stats("A").Expired, 2, "two refused for their time");
            Check(m.Notices("A").Any(n => n.Contains("clocks of the two computers differ")), "and A is told why");
            var replay = SignedPacket(m, "once", id: 4);
            rogue.SendPacket(replay);
            rogue.SendPacket(replay);
            m.Net.Pump();
            CheckEqual(m.Texts("A").Count(t => t == "once"), 1, "a replayed packet is shown once");
        });

        Test("forged or damaged packets are not shown, not passed on, and cannot block the real one", () =>
        {
            var m = new TestMesh();
            m.Add("B");
            m.Add("C");
            var rogue = new Rogue(m.Net);
            m.Net.AllInRange("B", "C", "rogue");
            m.RunFor(15);
            rogue.ConnectTo("B", m.Net);
            var genuine = SignedPacket(m, "the real one", id: 99);
            var forged = genuine.Copy();
            forged.Payload = (byte[])genuine.Payload.Clone();
            forged.Payload[5] ^= 0xFF;
            rogue.SendPacket(forged);
            m.Net.Pump();
            CheckEqual(m.Stats("B").Forged, 1, "B refuses the damaged copy");
            Check(m.Texts("B").Count == 0 && m.Texts("C").Count == 0, "nobody sees it");
            rogue.SendPacket(genuine);
            m.Net.Pump();
            CheckList(m.Texts("B"), new[] { "the real one" }, "the real one with the same ID gets through after it");
            CheckList(m.Texts("C"), new[] { "the real one" }, "and is passed on");
            var alice = Signer.FromIdentity(CryptoBackend.RandomBytes(32));
            var mallory = Signer.FromIdentity(CryptoBackend.RandomBytes(32));
            var lie = new InnerMessage { Kind = InnerKind.Chat, SenderKey = alice.PublicKey, Session = new byte[8], Nickname = "Alice", Text = "I am Alice" };
            rogue.SendPacket(Signing.Make(lie, mallory, 16, 5, (ulong)(m.Net.Now * 1000)));
            m.Net.Pump();
            Check(!m.Texts("B").Contains("I am Alice"), "a message signed with another key than its sender's is refused");
            CheckEqual(m.Stats("B").Forged, 2, "counted");
        });

        Test("broken frames and floods: refused, counted, and the chat goes on", () =>
        {
            var m = new TestMesh();
            m.Add("A");
            m.Add("B");
            var rogue = new Rogue(m.Net);
            m.Net.AllInRange("A", "B", "rogue");
            m.RunFor(15);
            rogue.ConnectTo("A", m.Net, hello: false);
            rogue.Send(LinkFrame.Data(1, 0, 1, "before hello"u8.ToArray()));
            m.Net.Pump();
            Check(m.Stats("A").Malformed >= 1, "data before the handshake is refused");
            rogue.Send(LinkFrame.HelloFrame(new Hello(CryptoBackend.RandomBytes(8))));
            var gen = new SeededGenerator(42);
            for (var i = 0; i < 200; i++)
            {
                var noise = new byte[gen.Int(2, 60)];
                for (var j = 0; j < noise.Length; j++) noise[j] = gen.Byte();
                if (i % 2 == 0) noise[0] = 1;                               // half of it looks like this version's frames …
                if (noise[0] == 1 && noise[1] == (byte)LinkKind.Bye) noise[1] = 0x77;   // … but a goodbye would end the link
                rogue.SendRaw(noise);
            }
            rogue.SendRaw(new byte[] { 1, 2, 0, 1, 0, 1 }.Concat(new byte[600]).ToArray());
            var bad = SignedPacket(m, "x", id: 8).Encode();
            bad[3] = 16;
            bad[4] = 1;          // ttl + hops = 17
            rogue.Send(LinkFrame.Data(2, 0, 1, bad));
            m.Net.Pump();
            Check(m.Stats("A").Malformed > 100, $"random bytes are refused ({m.Stats("A").Malformed})");
            Check(m.Stats("A").Incompatible < 20, $"noise is not taken for a newer MeshChat ({m.Stats("A").Incompatible})");
            for (var i = 0; i < 400; i++) rogue.Send(LinkFrame.Data((ushort)(1000 + i), 0, 2, new byte[10]));
            m.Net.Pump();
            Check(m.Stats("A").RateLimited > 0, $"a flood is cut off ({m.Stats("A").RateLimited} frames)");
            m.RunFor(2);
            m.Say("B", "still working?");
            CheckList(m.Texts("A"), new[] { "still working?" }, "A still chats with B");
        });

        Test("one sender cannot flood everyone: a share for each, the rest dropped", () =>
        {
            var m = new TestMesh();
            m.Add("A");
            m.Add("B");
            var rogue = new Rogue(m.Net);
            m.Net.SetRange("A", "B", true);
            m.Net.SetRange("A", "rogue", true);
            m.RunFor(15);
            rogue.ConnectTo("A", m.Net);
            var spammer = Signer.FromIdentity(CryptoBackend.RandomBytes(32));
            for (var i = 0; i < 100; i++)
            {
                rogue.SendPacket(SignedPacket(m, $"spam {i}", "Spammer", id: (ulong)(10_000 + i), signer: spammer));
                m.Net.Pump();
                m.RunFor(0.1);          // slower than a link may send: only the sender's share stops it
            }
            var shown = m.Texts("A").Count(t => t.StartsWith("spam"));
            Check(shown >= 40 && shown <= 55, $"A shows the sender's share: 40 at once, then one a second ({shown} of 100)");
            Check(m.Stats("A").RateLimited >= 40, $"the rest is dropped ({m.Stats("A").RateLimited})");
            Check(m.Texts("B").Count(t => t.StartsWith("spam")) <= shown, "and not passed on to B");
            Check(m.Notices("A").Any(n => n.Contains("Spammer sends very many messages")), "A is told");
            rogue.SendPacket(SignedPacket(m, "someone else", "Carol", id: 99_999));
            m.Net.Pump();
            Check(m.Texts("A").Contains("someone else"), "another sender still gets through");
        });

        Test("a relay passes everything on and says nothing", () =>
        {
            var m = new TestMesh();
            m.Add("A");
            m.Add("R", config: new MeshConfig { Silent = true });
            m.Add("C");
            m.Net.SetRange("A", "R", true);
            m.Net.SetRange("R", "C", true);
            m.RunFor(45);
            m.Say("A", "through the relay");
            m.RunFor(2);
            CheckList(m.Texts("C"), new[] { "through the relay" }, "C gets A's message through R");
            CheckEqual(m.Received("C").FirstOrDefault()?.Hops, 1, "one relay");
            CheckList(m.People("A").Select(p => p.Nickname), new[] { "C" }, "A knows C – and not the relay, which never speaks");
            CheckList(m.People("C").Select(p => p.Nickname), new[] { "A" }, "nor does C");
            Check(m.Stats("R").Relayed >= 1, "R passed it on");
        });

        Test("out of range and back: links come again, missed messages arrive, nothing twice", () =>
        {
            var m = new TestMesh();
            foreach (var n in new[] { "A", "B", "C" }) m.Add(n);
            m.Net.SetRange("A", "B", true);
            m.Net.SetRange("B", "C", true);
            m.RunFor(40);
            m.Say("A", "before");
            CheckList(m.Texts("C"), new[] { "before" }, "C has the first message");
            m.Net.SetRange("B", "C", false);
            m.Net.Pump();
            Check(!m.Linked("B", "C"), "C is out of range");
            Check(m.Notices("B").Any(n => n.Contains("link to C ended")), "B is told the link to C ended");
            m.RunFor(5);
            m.Say("A", "while you were away");
            Check(!m.Texts("C").Contains("while you were away"), "C misses it while away");
            m.RunFor(30);
            m.Net.SetRange("B", "C", true);
            m.RunFor(30);
            Check(m.Linked("B", "C"), "C linked again");
            CheckList(m.Texts("C"), new[] { "before", "while you were away" }, "C caught up – each message once");
            Check(m.Stats("B").CaughtUp > 0, "B sent C what it missed");
            m.Say("C", "back");
            CheckEqual(m.Texts("A").Count(t => t == "back"), 1, "and C is heard again");
        });

        Test("a computer that connects but never answers is tried less and less, not forever", () =>
        {
            var m = new TestMesh();
            m.Add("A");
            var rogue = new Rogue(m.Net);
            rogue.Radio.SetAdvertising(true);        // found and connected to – and it never says hello
            m.Net.AllInRange("A", "rogue");
            m.RunFor(600);
            Check(rogue.Opened >= 3, $"A tried again ({rogue.Opened} times)");
            Check(rogue.Opened <= 12, $"but not every few seconds: {rogue.Opened} attempts in 10 minutes");
            Check(m.Stats("A").ConnectFailures >= 3, "each one a failed connection");
            CheckEqual(m.Node("A").ReadyLinks, 0, "and no link");
        });

        Test("two computers that connect to each other at once keep one link", () =>
        {
            var m = new TestMesh();
            m.Add("A", config: new MeshConfig { InitiatorGrace = 0 });     // neither waits for the other
            m.Add("B", config: new MeshConfig { InitiatorGrace = 0 });
            m.Net.AllInRange("A", "B");
            m.RunFor(60);
            CheckEqual(m.Node("A").ReadyLinks, 1, "A keeps one link");
            CheckEqual(m.Node("B").ReadyLinks, 1, "B keeps one link");
            CheckEqual(m.Net.LinkCount, 1, "the second link was closed");
            m.Say("A", "once");
            CheckList(m.Texts("B"), new[] { "once" }, "messages go once");
        });

        Test("a computer with another protocol version is named, not linked", () =>
        {
            var m = new TestMesh();
            m.Add("A");
            var rogue = new Rogue(m.Net);
            m.Net.AllInRange("A", "rogue");
            m.RunFor(3);
            rogue.ConnectTo("A", m.Net, hello: false);
            rogue.Send(LinkFrame.HelloFrame(new Hello(CryptoBackend.RandomBytes(8), 3, 4)));
            m.Net.Pump();
            Check(m.Notices("A").Any(n => n.Contains("newer MeshChat")), "A says a newer MeshChat is nearby");
            Check(rogue.ReceivedFrames.Any(f => B.Eq(f, LinkFrame.Bye(ByeReason.Incompatible).Encode())), "and tells it why it ends the link");
            CheckEqual(m.Node("A").ReadyLinks, 0, "no link");
            var old = new Rogue(m.Net, "meshchat1");
            m.Net.AllInRange("A", "meshchat1");
            old.ConnectTo("A", m.Net, hello: false);
            old.Send(LinkFrame.HelloFrame(new Hello(CryptoBackend.RandomBytes(8), 1, 1)));
            m.Net.Pump();
            Check(m.Notices("A").Any(n => n.Contains("older MeshChat (protocol 1)") && n.Contains("update")), "a computer with MeshChat 1 is told to update");
            var r2 = new Rogue(m.Net, "rogue2");
            m.Net.AllInRange("A", "rogue2");
            r2.ConnectTo("A", m.Net, hello: false);
            r2.SendRaw(new byte[] { 2, 1, 9, 9 });
            m.Net.Pump();
            Check(m.Notices("A").Any(n => n.Contains("link protocol 2")), "a newer link format is named too");
        });

        Test("who is here: neighbours, people further away, goodbyes and silence", () =>
        {
            var m = new TestMesh();
            foreach (var n in new[] { "A", "B", "C" }) m.Add(n);
            m.Net.SetRange("A", "B", true);
            m.Net.SetRange("B", "C", true);
            m.RunFor(45);
            CheckList(m.People("A").Select(p => p.Nickname), new[] { "B", "C" }, "A knows B and C without them writing anything");
            Check(m.Person("B", "A")?.Direct == true, "B is A's neighbour");
            Check(m.Person("C", "A") is { Direct: false, Hops: 1 }, "C is one relay away");
            CheckEqual(m.Person("C", "A")?.Links, 1, "C said it has one link");
            m.Node("C").Goodbye();
            m.Net.Pump();
            m.Node("C").Stop();
            Check(m.Person("C", "A")?.Left == true, "C said goodbye");
            Check(m.Notices("A").Contains("C left the chat."), "and A was told");
            m.Radios["B"].SetPower(false);
            m.RunFor(100);
            Check(m.Person("B", "A")?.Away == true, "B is away after 80 silent seconds");
            Check(m.Notices("A").Any(n => n.Contains("B has not been heard")), "and A was told");
            m.RunFor(600);
            Check(m.Person("B", "A") == null, "after 10 minutes B is off the list");
        });

        Test("Bluetooth switched off and on again", () =>
        {
            var m = new TestMesh();
            m.Add("A");
            m.Add("B");
            m.Net.AllInRange("A", "B");
            m.RunFor(15);
            Check(m.Linked("A", "B"), "linked");
            m.Radios["B"].SetPower(false);
            m.Net.Pump();
            CheckEqual(m.Node("B").Snapshot().Radio, RadioState.Off, "B's radio is off");
            CheckEqual(m.Node("A").ReadyLinks, 0, "A lost the link");
            m.RunFor(10);
            m.Radios["B"].SetPower(true);
            m.RunFor(30);
            Check(m.Linked("A", "B"), "linked again once it is on");
            m.Say("B", "I'm back");
            CheckList(m.Texts("A"), new[] { "I'm back" }, "and chatting");
        });

        Test("long messages over the smallest links, frames that come twice", () =>
        {
            var m = new TestMesh();
            m.Add("A", maxFrame: 20);
            m.Add("B", maxFrame: 20);
            m.Net.AllInRange("A", "B");
            m.RunFor(15);
            var longText = string.Concat(Enumerable.Repeat("Ünïcödé 🌸 ", 60));
            var sent = Sanitize.Text(Sanitize.Cut(longText, int.MaxValue, 990));
            m.Say("A", sent);
            CheckList(m.Texts("B"), new[] { Sanitize.Text(sent) }, "a long message over 20-byte frames arrives whole");
            m.Net.DuplicateRate = 0.5;
            for (var i = 0; i < 10; i++) m.Say("B", $"dup {i}");
            m.RunFor(2);
            CheckList(m.Texts("A"), Enumerable.Range(0, 10).Select(i => $"dup {i}"), "doubled frames: each message once, in order");
            m.Net.DuplicateRate = 0;
            m.Net.LossRate = 0.3;
            for (var i = 0; i < 10; i++) m.Say("A", $"lossy {i}");
            m.RunFor(20);
            m.Net.LossRate = 0;
            var arrived = m.Texts("B").Where(t => t.StartsWith("lossy")).ToList();
            Check(arrived.All(t => Enumerable.Range(0, 10).Any(i => $"lossy {i}" == t)), $"lost frames never make a wrong message ({arrived.Count} of 10 arrived)");
        });

        Test("at most as many links as allowed, and the mesh still reaches everyone", () =>
        {
            var m = new TestMesh();
            var names = new[] { "A", "B", "C", "D", "E", "F" };
            foreach (var n in names) m.Add(n, config: n == "A" ? new MeshConfig { MaxLinks = 2 } : null);
            m.Net.AllInRange(names);
            m.RunFor(90);
            Check(m.Node("A").ReadyLinks <= 2, $"A has at most 2 links ({m.Node("A").ReadyLinks})");
            m.Say("A", "to all");
            m.RunFor(2);
            foreach (var n in names.Skip(1)) CheckList(m.Texts(n), new[] { "to all" }, $"{n} got it");
        });

        Test("a computer that restarts gets its own old messages back as its own", () =>
        {
            var m = new TestMesh();
            var identity = CryptoBackend.RandomBytes(32);
            m.Add("A", identity: identity);
            m.Add("B");
            m.Net.AllInRange("A", "B");
            m.RunFor(15);
            m.Say("A", "before the restart");
            m.Node("A").Stop();
            m.RunFor(5);
            // a second MeshNode for the same computer (same identity), as after a restart
            var messages = new List<ChatMessage>();
            var radio = m.Net.Radio("A2");
            var net = m.Net;
            var again = new MeshNode(radio, "A", Signer.FromIdentity(identity), e =>
            {
                if (e is MeshEvent.Message msg) messages.Add(msg.M);
            }, clock: () => net.Now);
            m.Adopt(again, radio, "A2");
            again.Start();
            foreach (var other in m.Nodes.Keys.Where(k => k != "A2").ToList()) m.Net.SetRange("A2", other, true);
            m.RunFor(30);
            Check(messages.Where(x => x.Mine).Any(x => x.Text == "before the restart"), "it comes back marked as A's own");
            Check(!m.Node("A2").Snapshot().Participants.Any(p => p.Nickname == "A"), "A is not listed as someone else");
        });
    }
}
