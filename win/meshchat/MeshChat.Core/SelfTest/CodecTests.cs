// MeshChat tests – the bytes: link frames, mesh packets, the messages in them, and texts from other computers.
// As lib/meshchat/Tests/CodecTests.swift.

using System.Text;
using static MeshChat.TestRun;

namespace MeshChat;

public static class CodecTests
{
    private static byte[] U(string s) => Encoding.UTF8.GetBytes(s);

    public static void Run()
    {
        Test("bytes: writer and reader agree, the reader never reads past the end", () =>
        {
            var w = new ByteWriter();
            w.U8(7);
            w.U16(0xBEEF);
            w.U64(0x0102030405060708);
            w.Str8("Grüße 👋");
            w.Str16(new string('x', 300));
            var r = new ByteReader(w.Data);
            CheckEqual(r.U8(), (byte)7, "u8");
            CheckEqual(r.U16(), (ushort)0xBEEF, "u16");
            CheckEqual(r.U64(), 0x0102030405060708UL, "u64");
            CheckEqual(r.Str8(64), "Grüße 👋", "str8 with UTF-8");
            CheckEqual(r.Str16(1000).Length, 300, "str16");
            Check(r.IsAtEnd, "nothing left");
            CheckThrows("reading past the end", () => r.U8());
            var shortOne = new ByteReader(new byte[] { 0, 5, 65 });
            shortOne.U8();
            CheckThrows("a length longer than the rest", () => shortOne.Str8(255));
            var bad = new ByteReader(new byte[] { 2, 0xC3, 0x28 });
            CheckThrows("invalid UTF-8", () => bad.Str8(255));
            var longOne = new ByteReader(new byte[] { 10 }.Concat(Enumerable.Repeat((byte)65, 10)).ToArray());
            CheckThrows("a text over its limit", () => longOne.Str8(5));
        });

        Test("hex and base32", () =>
        {
            CheckEqual(Hex.Encode(new byte[] { 0, 0xAB, 0xFF }), "00abff", "hex");
            CheckBytes(Hex.Decode("00ABff"), new byte[] { 0, 0xAB, 0xFF }, "hex back, any case");
            Check(Hex.Decode("abc") == null && Hex.Decode("zz") == null, "not hex");
            CheckEqual(Hex.U64(255), "00000000000000ff", "a 64-bit ID as 16 digits");
            CheckEqual(Base32.Encode(new byte[] { 0xFF }), "ZW", "base32 bits in order");
            CheckEqual(Base32.Encode(U("f")), "CR", "Crockford's alphabet");
            CheckEqual(Base32.Encode(CryptoBackend.RandomBytes(32)).Length, 52, "32 bytes are 52 characters");
            Check(!Base32.Alphabet.Any(c => "ILOU".Contains(c)), "no I, L, O or U to mistake for others");
        });

        Test("link frames: every kind round trips", () =>
        {
            var session = new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 };
            var frames = new[]
            {
                LinkFrame.HelloFrame(new Hello(session)),
                LinkFrame.HelloFrame(new Hello(session, 1, 3, 999, 1, "meshchat/9")),
                LinkFrame.Data(65535, 3, 4, U("part")),
                LinkFrame.Ping, LinkFrame.Pong, LinkFrame.Bye(ByeReason.Leaving),
            };
            foreach (var f in frames) CheckBytes(LinkFrame.Decode(f.Encode()).Encode(), f.Encode(), $"frame {f.Kind}");
            var h = LinkFrame.Decode(frames[1].Encode()).Hello!;
            Check(h.MinVersion == 1 && h.MaxVersion == 3 && h.MaxPacket == 999 && h.Flags == 1 && h.Software == "meshchat/9" && B.Eq(h.Session, session), "a hello's fields come back");
            CheckBytes(LinkFrame.Ping.Encode(), new byte[] { 1, 3 }, "a ping is two bytes: version 1, kind 3");
        });

        Test("link frames: broken or hostile ones are refused, not crashed on", () =>
        {
            CheckThrows("empty", () => LinkFrame.Decode(Array.Empty<byte>()));
            CheckThrows("only a version", () => LinkFrame.Decode(new byte[] { 1 }));
            CheckThrows("an unknown kind", () => LinkFrame.Decode(new byte[] { 1, 99 }));
            try
            {
                LinkFrame.Decode(new byte[] { 2, 3 });
                Check(false, "a newer link version is reported as such");
            }
            catch (WireError e) when (e.Kind == WireError.Kinds.UnsupportedVersion)
            {
                CheckEqual(e.Version, 2, "a newer link version is reported as such");
            }
            CheckThrows("a hello cut short", () => LinkFrame.Decode(LinkFrame.HelloFrame(new Hello(new byte[8])).Encode()[..6]));
            CheckThrows("a hello with lowest > highest version", () => LinkFrame.Decode(new byte[] { 1, 1, 3, 2 }.Concat(new byte[12]).ToArray()));
            CheckThrows("fragment index ≥ count", () => LinkFrame.Decode(new byte[] { 1, 2, 0, 1, 4, 4, 65 }));
            CheckThrows("fragment count 0", () => LinkFrame.Decode(new byte[] { 1, 2, 0, 1, 0, 0, 65 }));
            CheckThrows("data without payload", () => LinkFrame.Decode(new byte[] { 1, 2, 0, 1, 0, 1 }));
            CheckThrows("a frame over 512 bytes", () => LinkFrame.Decode(new byte[] { 1, 3 }.Concat(new byte[600]).ToArray()));
            var hostile = new byte[] { 1, 1, 1, 1 }.Concat(new byte[8]).Concat(new byte[] { 0, 10, 0, 5 }).Concat(U("a\u001b[2Jb")).Concat(new byte[] { 0, 0 }).ToArray();
            try
            {
                var h = LinkFrame.Decode(hostile).Hello;
                Check(h != null && !h.Software.Contains('\u001b'), "no escape sequence gets through a hello");
            }
            catch (WireError)
            {
                Check(false, "a hello with control characters in its name is still read");
            }
            // nothing at all may crash the decoder
            var gen = new SeededGenerator(7);
            for (var n = 0; n < 2000; n++)
            {
                var d = new byte[gen.Int(0, 40)];
                for (var i = 0; i < d.Length; i++) d[i] = gen.Byte();
                if (n % 2 == 0 && d.Length > 0) d[0] = 1;
                try { LinkFrame.Decode(d); } catch (WireError) { }
                try { MeshPacket.Decode(d); } catch (WireError) { }
                try { InnerMessage.Decode(d); } catch (WireError) { }
            }
            Check(true, "2000 random frames decoded without a crash");
        });

        Test("mesh packets: round trip, the signed header without ttl and hops, relaying", () =>
        {
            var p = new MeshPacket { Ttl = 16, Hops = 0, MessageId = 0x1122334455667788, Timestamp = 1_700_000_000_123, Payload = Enumerable.Repeat((byte)1, 80).ToArray() };
            var bytes = p.Encode();
            CheckEqual(bytes.Length, Proto.HeaderLength + 80, "a header of 21 bytes");
            CheckBytes(MeshPacket.Decode(bytes).Encode(), bytes, "decoded again");
            var r = p.Relayed()!;
            CheckEqual(r.Ttl, (byte)15, "a relay takes one from ttl");
            CheckEqual(r.Hops, (byte)1, "and adds one to hops");
            CheckBytes(r.SignedHeader, p.SignedHeader, "what is signed does not change on the way");
            var other = p.Copy();
            other.MessageId ^= 1;
            Check(!B.Eq(other.SignedHeader, p.SignedHeader), "but it covers the message ID");
            other = p.Copy();
            other.Timestamp += 1;
            Check(!B.Eq(other.SignedHeader, p.SignedHeader), "and the time");
            var last = p.Copy();
            last.Ttl = 0;
            Check(last.Relayed() == null, "ttl 0 is not relayed");
        });

        Test("mesh packets: hop limit, version and size are enforced", () =>
        {
            var p = new MeshPacket { Ttl = 16, Hops = 0, MessageId = 1, Timestamp = 0, Payload = new byte[65] };
            Check(Try(() => MeshPacket.Decode(p.Encode())), "ttl 16, hops 0 is allowed – every message starts so");
            p.Ttl = 10;
            p.Hops = 7;
            CheckThrows("ttl + hops over 16", () => MeshPacket.Decode(p.Encode()));
            p.Ttl = 17;
            p.Hops = 0;
            CheckThrows("ttl over 16", () => MeshPacket.Decode(p.Encode()));
            p.Ttl = 1;
            foreach (var (v, what) in new[] { ((byte)3, "a newer version is named as such"), ((byte)1, "and MeshChat 1's packets too") })
            {
                var other = p.Encode();
                other[0] = v;
                try
                {
                    MeshPacket.Decode(other);
                    Check(false, what);
                }
                catch (WireError e)
                {
                    Check(e.Kind == WireError.Kinds.UnsupportedVersion && e.Version == v, what);
                }
            }
            var noise = p.Encode();
            noise[0] = 200;
            try
            {
                MeshPacket.Decode(noise);
                Check(false, "a version byte of 200 is noise");
            }
            catch (WireError e)
            {
                Check(e.Kind != WireError.Kinds.UnsupportedVersion, "a version byte of 200 is noise, not a version");
            }
            var type = p.Encode();
            type[1] = 9;
            CheckThrows("an unknown packet type", () => MeshPacket.Decode(type));
            CheckThrows("only a signature, no message", () => MeshPacket.Decode(p.Encode()[..(Proto.HeaderLength + 64)]));
            CheckThrows("a packet over 2048 bytes", () => MeshPacket.Decode(p.Encode().Concat(new byte[2100]).ToArray()));
        });

        Test("inside: every kind round trips, with its signature at the end", () =>
        {
            var key = Enumerable.Repeat((byte)3, 32).ToArray();
            var session = Enumerable.Repeat((byte)4, 8).ToArray();
            var msgs = new[]
            {
                new InnerMessage { Kind = InnerKind.Chat, SenderKey = key, Session = session, Nickname = "Ada", Text = "Hello, mesh! 🌸" },
                new InnerMessage { Kind = InnerKind.Presence, Flags = InnerMessage.RequestFlag, SenderKey = key, Session = session, Nickname = "Grace", Links = 3 },
                new InnerMessage
                {
                    Kind = InnerKind.Presence, SenderKey = key, Session = session, Nickname = "Ada", Links = 2,
                    Neighbours = new() { new Neighbour(0xA1B2C3D4, -67), new Neighbour(7, Distance.Unknown) },
                },
                new InnerMessage { Kind = InnerKind.Bye, SenderKey = key, Session = session, Nickname = "Linus" },
            };
            foreach (var m in msgs)
            {
                var body = m.Body();
                var sig = Enumerable.Repeat((byte)0xEE, 64).ToArray();
                var (back, b, s) = InnerMessage.Decode(B.Cat(body, sig));
                Check(back.Same(m), $"{m.Kind}");
                CheckBytes(b, body, "the signed part");
                CheckBytes(s, sig, "the signature");
            }
            // the first MeshChat 2 sent a presence without neighbours: still read, with none
            var old = new ByteWriter();
            old.U8((byte)InnerKind.Presence); old.U8(0); old.Bytes(key); old.Bytes(session); old.Str8("Old"); old.U8(1);
            var (oldOne, _, _) = InnerMessage.Decode(B.Cat(old.Data, new byte[64]));
            CheckEqual(oldOne.Links, (byte)1, "a presence of the first MeshChat 2 is read");
            Check(oldOne.Neighbours.Count == 0, "with no neighbours");
            old.U8(17);
            CheckThrows("more than 16 neighbours are refused", () => InnerMessage.Decode(B.Cat(old.Data, new byte[17 * 5], new byte[64])));
            var tooLong = new InnerMessage { Kind = InnerKind.Chat, SenderKey = key, Session = session, Nickname = "A", Text = new string('x', 1001) };
            CheckThrows("a message over 1000 bytes is not made", () => tooLong.Body());
            var empty = new InnerMessage { Kind = InnerKind.Chat, SenderKey = key, Session = session, Nickname = "A", Text = "\u001b\u0007" };
            CheckThrows("a message of control characters only is refused", () => InnerMessage.Decode(B.Cat(empty.Body(), new byte[64])));
            var noName = new InnerMessage { Kind = InnerKind.Chat, SenderKey = key, Session = session, Nickname = "‮", Text = "hi" };
            CheckThrows("a nickname of nothing visible is refused", () => InnerMessage.Decode(B.Cat(noName.Body(), new byte[64])));
        });

        Test("texts from other computers cannot change the terminal", () =>
        {
            CheckEqual(Sanitize.Text("hi\u001b[2J\u001b]0;pwned\u0007there"), "hi[2J]0;pwnedthere", "escape sequences lose their ESC and BEL");
            CheckEqual(Sanitize.Text("a\nb\r\nc\td"), "a b c d", "line breaks and tabs become spaces");
            CheckEqual(Sanitize.Text("  many    spaces  "), "many spaces", "spaces collapsed and trimmed");
            CheckEqual(Sanitize.Nickname("evil‮txt.exe"), "eviltxt.exe", "no direction overrides");
            CheckEqual(Sanitize.Nickname("zero​width﻿"), "zerowidth", "no invisible characters");
            CheckEqual(Sanitize.Nickname("\u009B31m"), "31m", "no 8-bit control characters (CSI)");
            CheckEqual(Cells.Graphemes(Sanitize.Nickname(string.Concat(Enumerable.Repeat("ab", 40)))).Count(), Proto.MaxNicknameCharacters, "nicknames are cut to 24 characters");
            CheckEqual(Sanitize.Nickname("👩‍👩‍👧‍👦 family"), "👩‍👩‍👧‍👦 family", "emoji with joiners stay whole");
            CheckEqual(Sanitize.Cut("äöü", 10, 5), "äö", "cut on characters, never inside one");
        });
    }

    private static bool Try(Action a)
    {
        try
        {
            a();
            return true;
        }
        catch (Exception) { return false; }
    }
}
