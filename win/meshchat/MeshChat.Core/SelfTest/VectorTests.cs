// MeshChat tests – the same bytes on Windows and on a Mac. lib/meshchat/Tests/vectors.txt holds what fixed inputs must
// give: the keys of an identity, a HELLO, the kinds of messages as signed packets – a private one sealed with a fixed
// one-time key and nonce, so it is the same bytes too – and the frames they are cut into.
// This program made the file (meshchat selftest --write-vectors); here it is checked byte for byte, and the Mac's tests
// (lib/meshchat/Tests/VectorTests.swift) check the same file with CryptoKit – they verify these signatures and make the
// same bytes. A Mac's own signatures differ every time (CryptoKit's Ed25519 is randomized), so the Mac writes its
// packets out in CI and VerifyForeign checks them here: both directions are covered.

using System.Globalization;
using System.Reflection;
using System.Text;
using static MeshChat.TestRun;

namespace MeshChat;

public static class VectorTests
{
    // ── The fixed inputs ──────────────────────────────────────

    public static readonly byte[] Identity = Enumerable.Range(0, 32).Select(i => (byte)i).ToArray();
    public static readonly byte[] Session = { 0xA1, 0xB2, 0xC3, 0xD4, 0x05, 0x06, 0x07, 0x08 };
    public const string Software = "meshchat/2.0.0";
    public const ushort Seq = 7;
    // a private message: to the recipient, sealed with these instead of random ones
    public static readonly byte[] RecipientIdentity = Enumerable.Range(0x20, 32).Select(i => (byte)i).ToArray();
    public static readonly byte[] OneTime = Enumerable.Range(0x40, 32).Select(i => (byte)i).ToArray();
    public static readonly byte[] TellNonce = Enumerable.Range(0x60, 12).Select(i => (byte)i).ToArray();
    public const string TellText = "Only you can read this – Grüezi 🌸";

    private sealed record Case(string Name, InnerMessage Inner, ulong Id, ulong Time, byte Ttl);

    private static InnerMessage Tell(Signer s)
    {
        var r = Signer.FromIdentity(RecipientIdentity);
        var sealedText = Sealing.Seal(TellText, s.PublicKey, r.PublicKey, r.BoxKey, OneTime, TellNonce);
        return new InnerMessage
        {
            Kind = InnerKind.Tell, SenderKey = s.PublicKey, Session = Session, Nickname = "Ada",
            Recipient = r.PublicKey, OneTimeKey = sealedText.OneTimeKey, Nonce = sealedText.Nonce, Sealed = sealedText.Sealed,
        };
    }

    private static List<Case> Cases(Signer s) => new()
    {
        new("chat", new InnerMessage
        {
            Kind = InnerKind.Chat, SenderKey = s.PublicKey, Session = Session, Nickname = "Ada",
            Text = "Grüezi – the same chat on Windows and on a Mac 🌸",
        }, 0x0123456789ABCDEF, 1_761_570_000_000, 16),
        new("presence", new InnerMessage
        {
            Kind = InnerKind.Presence, Flags = InnerMessage.RequestFlag, SenderKey = s.PublicKey, Session = Session, Nickname = "Ada", Links = 2,
            Neighbours = new() { new Neighbour(0x00000007, Distance.Unknown), new Neighbour(0xA1B2C3D4, -67) },
        }, 0x1111111111111111, 1_761_570_001_000, 16),
        new("bye", new InnerMessage { Kind = InnerKind.Bye, SenderKey = s.PublicKey, Session = Session, Nickname = "Ada" },
            0xFEDCBA9876543210, 1_761_570_002_000, 16),
        // since MeshChat 2.2: a presence with its box key, and a private message
        new("presence-box", new InnerMessage
        {
            Kind = InnerKind.Presence, SenderKey = s.PublicKey, Session = Session, Nickname = "Ada", Links = 1,
            Neighbours = new() { new Neighbour(0xA1B2C3D4, -67) }, BoxKey = s.BoxKey,
        }, 0x2222222222222222, 1_761_570_003_000, 16),
        new("tell", Tell(s), 0x3333333333333333, 1_761_570_004_000, 16),
    };

    // ── The file ──────────────────────────────────────────────

    public static Dictionary<string, string>? Load(string? path = null)
    {
        string? text;
        if (path != null) text = File.ReadAllText(path, Encoding.UTF8);
        else
        {
            using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("vectors.txt");
            if (s == null) return null;
            using var r = new StreamReader(s, Encoding.UTF8);
            text = r.ReadToEnd();
        }
        var d = new Dictionary<string, string>();
        foreach (var raw in text.Split('\n'))
        {
            var line = raw.TrimEnd('\r');
            if (line.StartsWith('#') || !line.Contains(" = ")) continue;
            var at = line.IndexOf(" = ", StringComparison.Ordinal);
            d[line[..at].Trim()] = line[(at + 3)..];
        }
        return d;
    }

    // What this program says the file must hold
    public static string Generate()
    {
        var s = Signer.FromIdentity(Identity);
        var sb = new StringBuilder();
        sb.Append("# MeshChat protocol 2 – test vectors. Made by the Windows app (win/meshchat: meshchat selftest --write-vectors),\n");
        sb.Append("# checked byte for byte by it and by the Mac's tests (lib/meshchat/Tests/VectorTests.swift). Hex unless it is a text.\n");
        sb.Append("# Do not change by hand: a change here is a change of the protocol.\n\n");
        void Put(string k, string v) => sb.Append($"{k} = {v}\n");
        Put("identity", Hex.Encode(Identity));
        Put("seed", Hex.Encode(s.Seed));
        Put("public-key", Hex.Encode(s.PublicKey));
        Put("fingerprint", s.Fingerprint);
        Put("session", Hex.Encode(Session));
        Put("hello.software", Software);
        Put("hello", Hex.Encode(LinkFrame.HelloFrame(new Hello(Session, Software: Software)).Encode()));
        Put("ping", Hex.Encode(LinkFrame.Ping.Encode()));
        Put("pong", Hex.Encode(LinkFrame.Pong.Encode()));
        Put("bye-frame", Hex.Encode(LinkFrame.Bye(ByeReason.Leaving).Encode()));
        Put("box-key", Hex.Encode(s.BoxKey));
        var r = Signer.FromIdentity(RecipientIdentity);
        Put("recipient.identity", Hex.Encode(RecipientIdentity));
        Put("recipient.public-key", Hex.Encode(r.PublicKey));
        Put("recipient.box-key", Hex.Encode(r.BoxKey));
        Put("tell.one-time", Hex.Encode(OneTime));
        Put("tell.nonce", Hex.Encode(TellNonce));
        Put("tell.text", TellText);
        foreach (var c in Cases(s))
        {
            sb.Append('\n');
            Put($"{c.Name}.id", Hex.U64(c.Id));
            Put($"{c.Name}.time", c.Time.ToString(CultureInfo.InvariantCulture));
            Put($"{c.Name}.ttl", c.Ttl.ToString(CultureInfo.InvariantCulture));
            if (c.Inner.Kind == InnerKind.Chat) Put($"{c.Name}.text", c.Inner.Text);
            Put($"{c.Name}.body", Hex.Encode(c.Inner.Body()));
            var p = Signing.Make(c.Inner, s, c.Ttl, c.Id, c.Time);
            Put($"{c.Name}.header", Hex.Encode(p.SignedHeader));
            Put($"{c.Name}.packet", Hex.Encode(p.Encode()));
            Put($"{c.Name}.frames.20", string.Join(" ", Fragmenter.Frames(p.Encode(), Seq, 20).Select(Hex.Encode)));
            Put($"{c.Name}.frames.182", string.Join(" ", Fragmenter.Frames(p.Encode(), Seq, 182).Select(Hex.Encode)));
        }
        return sb.ToString();
    }

    // ── Checked here ──────────────────────────────────────────

    public static void Run()
    {
        Test("the same bytes as the Mac: the test vectors both check (lib/meshchat/Tests/vectors.txt)", () =>
        {
            var v = Load();
            if (v == null)
            {
                Check(false, "vectors.txt is part of this program");
                return;
            }
            var s = Signer.FromIdentity(Identity);
            CheckEqual(Hex.Encode(s.Seed), v["seed"], "the identity gives the same key (HKDF)");
            CheckEqual(Hex.Encode(s.PublicKey), v["public-key"], "and the same public key (Ed25519)");
            CheckEqual(s.Fingerprint, v["fingerprint"], "and the same fingerprint");
            CheckEqual(Hex.Encode(LinkFrame.HelloFrame(new Hello(Session, Software: Software)).Encode()), v["hello"], "a HELLO");
            CheckEqual(Hex.Encode(LinkFrame.Ping.Encode()), v["ping"], "a PING");
            CheckEqual(Hex.Encode(LinkFrame.Bye(ByeReason.Leaving).Encode()), v["bye-frame"], "a BYE");
            CheckEqual(Hex.Encode(s.BoxKey), v["box-key"], "the identity gives the same box key (HKDF, X25519)");
            var recipient = Signer.FromIdentity(RecipientIdentity);
            CheckEqual(Hex.Encode(recipient.BoxKey), v["recipient.box-key"], "and so does the recipient's");
            foreach (var c in Cases(s))
            {
                if (c.Inner.Kind == InnerKind.Chat) CheckEqual(c.Inner.Text, v[$"{c.Name}.text"], "the text of the chat message");
                CheckEqual(Hex.Encode(c.Inner.Body()), v[$"{c.Name}.body"], $"{c.Name}: the message");
                var p = Signing.Make(c.Inner, s, c.Ttl, c.Id, c.Time);
                CheckEqual(Hex.Encode(p.SignedHeader), v[$"{c.Name}.header"], $"{c.Name}: the signed header");
                CheckEqual(Hex.Encode(p.Encode()), v[$"{c.Name}.packet"], $"{c.Name}: the signed packet, byte for byte");
                CheckEqual(string.Join(" ", Fragmenter.Frames(p.Encode(), Seq, 20).Select(Hex.Encode)), v[$"{c.Name}.frames.20"], $"{c.Name}: its frames on the smallest link");
                CheckEqual(string.Join(" ", Fragmenter.Frames(p.Encode(), Seq, 182).Select(Hex.Encode)), v[$"{c.Name}.frames.182"], $"{c.Name}: and on a usual one");
                var opened = Signing.Open(MeshPacket.Decode(Hex.Decode(v[$"{c.Name}.packet"])!));
                Check(opened.Same(c.Inner), $"{c.Name}: the packet of the file opens, signature and all");
                if (c.Inner.Kind == InnerKind.Tell)
                {
                    CheckEqual(Sealing.Open(opened, recipient), v["tell.text"], "tell: the recipient reads it");
                    CheckEqual(Sealing.Open(opened, s), null, "and no one else – not even its sender");
                }
            }
        });
    }

    // Packets a Mac made (CI: the Mac's tests write them with MESHCHAT_VECTORS_OUT) – they must open here, and hold
    // exactly what was put in. → the exit status
    public static int VerifyForeign(string path)
    {
        TestRun.Passed = 0;
        TestRun.Failed = 0;
        var v = Load(path);
        if (v == null) return 1;
        Test($"packets a Mac signed with CryptoKit open on Windows ({Path.GetFileName(path)})", () =>
        {
            var s = Signer.FromIdentity(Identity);
            CheckEqual(v.GetValueOrDefault("public-key"), Hex.Encode(s.PublicKey), "the Mac made the same key of the identity");
            foreach (var c in Cases(s))
            {
                if (!v.TryGetValue($"swift.{c.Name}.packet", out var hex))
                {
                    Check(false, $"{c.Name}: the Mac's packet is in the file");
                    continue;
                }
                var p = MeshPacket.Decode(Hex.Decode(hex)!);
                var inner = Signing.Open(p);
                Check(inner.Same(c.Inner), $"{c.Name}: the Mac's signature verifies, and the message is what was put in");
                Check(p.MessageId == c.Id && p.Timestamp == c.Time && p.Ttl == c.Ttl && p.Hops == 0, $"{c.Name}: and the header");
                var mine = Signing.Make(c.Inner, s, c.Ttl, c.Id, c.Time);
                CheckEqual(Hex.Encode(p.Payload[..^Proto.SignatureLength]), Hex.Encode(mine.Payload[..^Proto.SignatureLength]), $"{c.Name}: all but the signature is the same as here");
                if (c.Inner.Kind == InnerKind.Tell)
                    CheckEqual(Sealing.Open(inner, Signer.FromIdentity(RecipientIdentity)), TellText, "tell: the Mac sealed it with CryptoKit, it opens here");
            }
        });
        Term.Line($"  {TestRun.Passed} passed, {TestRun.Failed} failed");
        return TestRun.Failed == 0 ? 0 : 1;
    }
}
