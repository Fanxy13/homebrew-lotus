// MeshChat – the protocol on the wire, version 2: the same bytes as lib/meshchat/Sources/Wire.swift on the Mac, so a
// Windows computer and a Mac are in the same chat. Numbers are big-endian; str8/str16 is UTF-8 after its length.
//
// Link frames – one GATT write or notification each, between two computers that are connected:
//   [1 link version = 1][1 kind] then
//   HELLO 1  [1 lowest][1 highest mesh version][8 session][2 largest packet][1 flags][str8 software]
//   DATA  2  [2 sequence][1 index][1 count][a part of one mesh packet]
//   PING 3 · PONG 4   nothing more
//   BYE   5  [1 reason]
// A newer version may add fields at the end of a HELLO; they are skipped.
//
// Mesh packets – put together from DATA frames, checked, and passed on whole by every computer on the way:
//   [1 version = 2][1 type = 1, a message to everyone][1 flags][1 ttl][1 hops][8 message ID][8 time, ms]
//   then the message and its signature
//   ttl: relays it may still take · hops: relays it took. Only these two change on the way, so the signature
//   covers the header with both set to 0.
//
// The message – in the clear: the chat is public, everyone nearby reads it:
//   [1 kind][1 flags][32 sender's public key][8 sender's session][str8 nickname] then
//   chat 1      [str16 text]
//   presence 2  [1 links][1 n][n × (4 token, 1 signal)]   flags bit 0: "who is here?" – answer with yours
//   bye 3       nothing more
//   [64 Ed25519 signature over "MeshChat v2", the header (ttl and hops 0) and everything before it]

using System.Globalization;
using System.Text;

namespace MeshChat;

public static class Proto
{
    public const byte Version = 2;                  // mesh packets
    public const byte LinkVersion = 1;              // link frames
    public const string Release = "2.1.0";
    public const string Software = "meshchat-windows/" + Release;
    public const int MaxFrame = 512;                // the most a GATT attribute value holds
    public const int MinFrame = 20;                 // the least BLE gives (ATT MTU 23 minus 3)
    public const int MaxPacket = 2048;
    public const int MaxFragments = 255;
    public const byte HopLimit = 16;                // ttl + hops is never more – every message is sent with all of it
    public const int SessionLength = 8;
    public const int KeyLength = 32;
    public const int SignatureLength = 64;
    public const int HeaderLength = 21;
    public const int MaxNicknameCharacters = 24;
    public const int MaxNicknameBytes = 64;
    public const int MaxTextBytes = 1000;
    public const int MaxSoftwareBytes = 32;
    public const int MaxNeighbours = 16;

    // A version byte that is not ours: a plausible other version (1–15) is named as such, anything else is noise
    public static WireError VersionError(byte v, byte ours) =>
        v >= 1 && v <= 15 && v != ours ? WireError.UnsupportedVersion(v) : WireError.Invalid($"version byte {v}");
}

// ── Link frames ───────────────────────────────────────────────

public enum LinkKind : byte { Hello = 1, Data = 2, Ping = 3, Pong = 4, Bye = 5 }

public static class ByeReason
{
    public const byte Leaving = 1;          // the chat was closed
    public const byte Incompatible = 2;     // no protocol version in common
    public const byte Redundant = 3;        // a second link to the same computer
    public const byte Full = 4;             // too many links already
}

public sealed record Hello(byte[] Session, byte MinVersion = Proto.Version, byte MaxVersion = Proto.Version,
                           ushort MaxPacket = Proto.MaxPacket, byte Flags = 0, string Software = Proto.Software);

public sealed class LinkFrame
{
    public const int DataHeader = 6;

    public LinkKind Kind { get; }
    public Hello? Hello { get; }
    public ushort Seq { get; }
    public byte Index { get; }
    public byte Count { get; }
    public byte[] Payload { get; } = Array.Empty<byte>();
    public byte Reason { get; }

    private LinkFrame(LinkKind kind, Hello? hello = null, ushort seq = 0, byte index = 0, byte count = 0, byte[]? payload = null, byte reason = 0)
    {
        Kind = kind;
        Hello = hello;
        Seq = seq;
        Index = index;
        Count = count;
        Payload = payload ?? Array.Empty<byte>();
        Reason = reason;
    }

    public static LinkFrame HelloFrame(Hello h) => new(LinkKind.Hello, hello: h);
    public static LinkFrame Data(ushort seq, byte index, byte count, byte[] payload) => new(LinkKind.Data, seq: seq, index: index, count: count, payload: payload);
    public static readonly LinkFrame Ping = new(LinkKind.Ping);
    public static readonly LinkFrame Pong = new(LinkKind.Pong);
    public static LinkFrame Bye(byte reason) => new(LinkKind.Bye, reason: reason);

    public byte[] Encode()
    {
        var w = new ByteWriter();
        w.U8(Proto.LinkVersion);
        w.U8((byte)Kind);
        switch (Kind)
        {
            case LinkKind.Hello:
                var h = Hello!;
                w.U8(h.MinVersion);
                w.U8(h.MaxVersion);
                w.Bytes(h.Session);
                w.U16(h.MaxPacket);
                w.U8(h.Flags);
                w.Str8(Sanitize.Cut(h.Software, Proto.MaxSoftwareBytes, Proto.MaxSoftwareBytes));
                break;
            case LinkKind.Data:
                w.U16(Seq);
                w.U8(Index);
                w.U8(Count);
                w.Bytes(Payload);
                break;
            case LinkKind.Bye:
                w.U8(Reason);
                break;
        }
        return w.Data;
    }

    public static LinkFrame Decode(byte[] d)
    {
        if (d.Length > Proto.MaxFrame) throw WireError.TooLarge($"frame of {d.Length} bytes");
        var r = new ByteReader(d);
        var version = r.U8();
        if (version != Proto.LinkVersion) throw Proto.VersionError(version, Proto.LinkVersion);
        var kind = r.U8();
        switch ((LinkKind)kind)
        {
            case LinkKind.Hello:
            {
                byte lo = r.U8(), hi = r.U8();
                if (lo < 1 || lo > hi) throw WireError.Invalid("version range");
                var session = r.Bytes(Proto.SessionLength);
                var maxPacket = r.U16();
                var flags = r.U8();
                var software = Sanitize.Line(r.Str8(Proto.MaxSoftwareBytes), Proto.MaxSoftwareBytes, Proto.MaxSoftwareBytes);
                return HelloFrame(new Hello(session, lo, hi, maxPacket, flags, software));
            }
            case LinkKind.Data:
            {
                var seq = r.U16();
                byte index = r.U8(), count = r.U8();
                if (count < 1 || index >= count) throw WireError.Invalid($"fragment {index} of {count}");
                var payload = r.Rest();
                if (payload.Length == 0) throw WireError.Truncated();
                return Data(seq, index, count, payload);
            }
            case LinkKind.Ping: return Ping;
            case LinkKind.Pong: return Pong;
            case LinkKind.Bye: return Bye(r.IsAtEnd ? (byte)0 : r.U8());
            default: throw WireError.Invalid("frame kind");
        }
    }
}

// ── Mesh packets ──────────────────────────────────────────────

public sealed class MeshPacket
{
    public const byte TypePublic = 1;

    public byte Version = Proto.Version;
    public byte Type = TypePublic;
    public byte Flags;
    public byte Ttl;
    public byte Hops;
    public ulong MessageId;
    public ulong Timestamp;              // milliseconds since 1970, the sender's clock
    public byte[] Payload = Array.Empty<byte>();     // the message and its signature

    public MeshPacket Copy() => (MeshPacket)MemberwiseClone();

    public byte[] Encode()
    {
        var w = new ByteWriter();
        Header(w, Ttl, Hops);
        w.Bytes(Payload);
        return w.Data;
    }

    // What the signature covers of the header: all of it, with what relays change set to 0
    public byte[] SignedHeader
    {
        get
        {
            var w = new ByteWriter();
            Header(w, 0, 0);
            return w.Data;
        }
    }

    // The same packet one relay further
    public MeshPacket? Relayed()
    {
        if (Ttl == 0) return null;
        var p = Copy();
        p.Ttl--;
        p.Hops++;
        return p;
    }

    private void Header(ByteWriter w, byte ttl, byte hops)
    {
        w.U8(Version);
        w.U8(Type);
        w.U8(Flags);
        w.U8(ttl);
        w.U8(hops);
        w.U64(MessageId);
        w.U64(Timestamp);
    }

    public static MeshPacket Decode(byte[] d)
    {
        if (d.Length > Proto.MaxPacket) throw WireError.TooLarge($"packet of {d.Length} bytes");
        var r = new ByteReader(d);
        var version = r.U8();
        if (version != Proto.Version) throw Proto.VersionError(version, Proto.Version);
        var type = r.U8();
        if (type != TypePublic) throw WireError.Invalid($"packet type {type}");
        byte flags = r.U8(), ttl = r.U8(), hops = r.U8();
        if (ttl + hops > Proto.HopLimit) throw WireError.Invalid($"ttl {ttl} and hops {hops}");
        var id = r.U64();
        var time = r.U64();
        var payload = r.Rest();
        if (payload.Length <= Proto.SignatureLength) throw WireError.Truncated();
        return new MeshPacket { Version = version, Type = type, Flags = flags, Ttl = ttl, Hops = hops, MessageId = id, Timestamp = time, Payload = payload };
    }
}

// ── The message in a packet ───────────────────────────────────

public enum InnerKind : byte { Chat = 1, Presence = 2, Bye = 3 }

// A computer someone has a link to, and how strong they hear it
public readonly record struct Neighbour(uint Token, int Rssi);      // the first 4 bytes of its session · dBm, or Distance.Unknown

public sealed class InnerMessage
{
    public const byte RequestFlag = 1;      // presence: please answer with yours

    public InnerKind Kind;
    public byte Flags;
    public byte[] SenderKey = Array.Empty<byte>();
    public byte[] Session = Array.Empty<byte>();
    public string Nickname = "";
    public string Text = "";                        // chat
    public byte Links;                              // presence: how many computers it is connected to
    public List<Neighbour> Neighbours = new();      // presence: which, and how strong it hears them

    public bool Same(InnerMessage o) =>
        Kind == o.Kind && Flags == o.Flags && B.Eq(SenderKey, o.SenderKey) && B.Eq(Session, o.Session) && Nickname == o.Nickname
        && Text == o.Text && Links == o.Links && Neighbours.SequenceEqual(o.Neighbours);

    // Everything but the signature
    public byte[] Body()
    {
        if (SenderKey.Length != Proto.KeyLength || Session.Length != Proto.SessionLength) throw WireError.Invalid("key or session");
        var w = new ByteWriter();
        w.U8((byte)Kind);
        w.U8(Flags);
        w.Bytes(SenderKey);
        w.Bytes(Session);
        if (Encoding.UTF8.GetByteCount(Nickname) > Proto.MaxNicknameBytes) throw WireError.TooLarge("nickname");
        w.Str8(Nickname);
        switch (Kind)
        {
            case InnerKind.Chat:
                if (Encoding.UTF8.GetByteCount(Text) > Proto.MaxTextBytes) throw WireError.TooLarge("message");
                w.Str16(Text);
                break;
            case InnerKind.Presence:
                w.U8(Links);
                var list = Neighbours.Take(Proto.MaxNeighbours).ToList();
                w.U8((byte)list.Count);
                foreach (var n in list)
                {
                    w.Bytes(new[] { (byte)(n.Token >> 24 & 0xFF), (byte)(n.Token >> 16 & 0xFF), (byte)(n.Token >> 8 & 0xFF), (byte)(n.Token & 0xFF) });
                    w.U8(unchecked((byte)(sbyte)Math.Clamp(n.Rssi, sbyte.MinValue, sbyte.MaxValue)));
                }
                break;
        }
        return w.Data;
    }

    // → the message (its texts made safe for the terminal), the signed bytes and the signature
    public static (InnerMessage Message, byte[] Body, byte[] Signature) Decode(byte[] payload)
    {
        if (payload.Length <= Proto.SignatureLength + 2) throw WireError.Truncated();
        var body = payload.AsSpan(0, payload.Length - Proto.SignatureLength).ToArray();
        var signature = payload.AsSpan(payload.Length - Proto.SignatureLength).ToArray();
        var r = new ByteReader(body);
        var kind = r.U8();
        if (kind < 1 || kind > 3) throw WireError.Invalid("message kind");
        var flags = r.U8();
        var key = r.Bytes(Proto.KeyLength);
        var session = r.Bytes(Proto.SessionLength);
        var nickname = Sanitize.Nickname(r.Str8(Proto.MaxNicknameBytes));
        if (nickname.Length == 0) throw WireError.Invalid("empty nickname");
        var m = new InnerMessage { Kind = (InnerKind)kind, Flags = flags, SenderKey = key, Session = session, Nickname = nickname };
        switch (m.Kind)
        {
            case InnerKind.Chat:
                m.Text = Sanitize.Text(r.Str16(Proto.MaxTextBytes));
                if (m.Text.Length == 0) throw WireError.Invalid("empty message");
                break;
            case InnerKind.Presence:
                m.Links = r.U8();
                if (!r.IsAtEnd)
                {
                    int n = r.U8();
                    if (n > Proto.MaxNeighbours) throw WireError.Invalid($"{n} neighbours");
                    for (var i = 0; i < n; i++)
                    {
                        var token = B.Token(r.Bytes(4));
                        m.Neighbours.Add(new Neighbour(token, unchecked((sbyte)r.U8())));
                    }
                }
                break;
        }
        // a newer version may add fields here – they are signed, and skipped
        return (m, body, signature);
    }
}

// ── Texts from other computers ────────────────────────────────
// Whatever arrives is shown in a terminal: control characters (ESC starts terminal commands), direction overrides
// and invisible characters are taken out, line breaks become spaces, and lengths are cut.

public static class Sanitize
{
    public static bool IsUnsafe(int v) =>
        v <= 0x1F || (v >= 0x7F && v <= 0x9F)                       // control characters, ESC among them
        || v == 0x200B || v == 0x200E || v == 0x200F                // zero width space, direction marks
        || (v >= 0x202A && v <= 0x202E) || (v >= 0x2066 && v <= 0x2069)    // direction overrides and isolates
        || (v >= 0x2060 && v <= 0x2064) || v == 0xFEFF              // invisible joiners and operators
        || (v >= 0xFFF9 && v <= 0xFFFB)                             // annotations
        || (v >= 0xE0000 && v <= 0xE007F);                          // tag characters (hidden text)

    // One line: spaces for line breaks and tabs, no unsafe characters, spaces collapsed and trimmed, then cut
    public static string Line(string s, int characters, int bytes)
    {
        var sb = new StringBuilder(s.Length);
        var space = false;
        foreach (var r in s.EnumerateRunes())
        {
            if (Rune.IsWhiteSpace(r))       // spaces of all kinds, tabs and line breaks (Unicode's White_Space)
            {
                space = true;
                continue;
            }
            if (IsUnsafe(r.Value)) continue;
            if (space && sb.Length > 0) sb.Append(' ');
            space = false;
            sb.Append(r.ToString());
        }
        return Cut(sb.ToString(), characters, bytes);
    }

    // At most so many characters (as a person counts them: é, 🌸 and 👍🏽 are one each) and UTF-8 bytes, never in
    // the middle of a character
    public static string Cut(string s, int characters, int bytes)
    {
        var sb = new StringBuilder();
        int n = 0, b = 0;
        var e = StringInfo.GetTextElementEnumerator(s);
        while (e.MoveNext())
        {
            var ch = e.GetTextElement();
            var size = Encoding.UTF8.GetByteCount(ch);
            if (n + 1 > characters || b + size > bytes) break;
            sb.Append(ch);
            n++;
            b += size;
        }
        return sb.ToString();
    }

    public static string Nickname(string s) => Line(s, Proto.MaxNicknameCharacters, Proto.MaxNicknameBytes);
    public static string Text(string s) => Line(s, int.MaxValue, Proto.MaxTextBytes);
}
