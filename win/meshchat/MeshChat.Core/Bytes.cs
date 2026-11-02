// MeshChat – bytes on the wire: a writer, a strict reader that never reads past the end, hex and base32.
// The same as lib/meshchat/Sources/Bytes.swift: what one writes, the other reads.

using System.Text;

namespace MeshChat;

// What can be wrong with bytes that came from another computer. Never crashes, never reads past the end.
public sealed class WireError : Exception
{
    public enum Kinds { Truncated, TooLarge, Invalid, UnsupportedVersion }

    public Kinds Kind { get; }
    public string What { get; }
    public int Version { get; }

    private WireError(Kinds kind, string what, int version, string message) : base(message)
    {
        Kind = kind;
        What = what;
        Version = version;
    }

    public static WireError Truncated() => new(Kinds.Truncated, "", 0, "cut short");
    public static WireError TooLarge(string what) => new(Kinds.TooLarge, what, 0, $"too large: {what}");
    public static WireError Invalid(string what) => new(Kinds.Invalid, what, 0, $"invalid: {what}");
    public static WireError UnsupportedVersion(int v) => new(Kinds.UnsupportedVersion, "", v, $"protocol version {v} is not supported");
}

// Big-endian fields, one after the other
public sealed class ByteWriter
{
    private readonly List<byte> data = new();

    public byte[] Data => data.ToArray();

    public void U8(byte v) => data.Add(v);

    public void U16(ushort v)
    {
        data.Add((byte)(v >> 8));
        data.Add((byte)(v & 0xFF));
    }

    public void U64(ulong v)
    {
        for (var shift = 56; shift >= 0; shift -= 8) data.Add((byte)((v >> shift) & 0xFF));
    }

    public void Bytes(byte[] d) => data.AddRange(d);

    // A string with its length in one byte (at most 255 bytes of UTF-8)
    public void Str8(string s)
    {
        var b = Encoding.UTF8.GetBytes(s);
        if (b.Length > 255) throw WireError.TooLarge("text field");
        U8((byte)b.Length);
        Bytes(b);
    }

    // A string with its length in two bytes
    public void Str16(string s)
    {
        var b = Encoding.UTF8.GetBytes(s);
        if (b.Length > 65535) throw WireError.TooLarge("text field");
        U16((ushort)b.Length);
        Bytes(b);
    }
}

// Reads what ByteWriter wrote. Every read checks the length first; text must be valid UTF-8.
public sealed class ByteReader
{
    private static readonly UTF8Encoding Strict = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);
    private readonly byte[] buf;

    public ByteReader(byte[] data) => buf = data;

    public int Offset { get; private set; }
    public int Remaining => buf.Length - Offset;
    public bool IsAtEnd => Offset == buf.Length;

    public byte U8()
    {
        if (Remaining < 1) throw WireError.Truncated();
        return buf[Offset++];
    }

    public ushort U16()
    {
        if (Remaining < 2) throw WireError.Truncated();
        var v = (ushort)(buf[Offset] << 8 | buf[Offset + 1]);
        Offset += 2;
        return v;
    }

    public ulong U64()
    {
        if (Remaining < 8) throw WireError.Truncated();
        ulong v = 0;
        for (var i = 0; i < 8; i++) v = v << 8 | buf[Offset + i];
        Offset += 8;
        return v;
    }

    public byte[] Bytes(int n)
    {
        if (n < 0 || Remaining < n) throw WireError.Truncated();
        var d = buf.AsSpan(Offset, n).ToArray();
        Offset += n;
        return d;
    }

    public byte[] Rest()
    {
        var d = buf.AsSpan(Offset).ToArray();
        Offset = buf.Length;
        return d;
    }

    public string Str8(int max)
    {
        int n = U8();
        if (n > max) throw WireError.TooLarge("text field");
        return Utf8(Bytes(n));
    }

    public string Str16(int max)
    {
        int n = U16();
        if (n > max) throw WireError.TooLarge("text field");
        return Utf8(Bytes(n));
    }

    private static string Utf8(byte[] d)
    {
        try { return Strict.GetString(d); }
        catch (DecoderFallbackException) { throw WireError.Invalid("text is not UTF-8"); }
    }
}

public static class Hex
{
    private const string Digits = "0123456789abcdef";

    public static string Encode(byte[] d)
    {
        var sb = new StringBuilder(d.Length * 2);
        foreach (var b in d)
        {
            sb.Append(Digits[b >> 4]);
            sb.Append(Digits[b & 0x0F]);
        }
        return sb.ToString();
    }

    public static byte[]? Decode(string s)
    {
        s = s.ToLowerInvariant();
        if (s.Length % 2 != 0) return null;
        var out_ = new byte[s.Length / 2];
        for (var i = 0; i < s.Length; i += 2)
        {
            int hi = Digits.IndexOf(s[i]), lo = Digits.IndexOf(s[i + 1]);
            if (hi < 0 || lo < 0) return null;
            out_[i / 2] = (byte)(hi << 4 | lo);
        }
        return out_;
    }

    public static string U64(ulong v) => v.ToString("x16");
}

// Crockford's base32: no I, L, O or U, so the four letters of a fingerprint are not mistaken for others
public static class Base32
{
    public const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

    public static string Encode(byte[] d)
    {
        var sb = new StringBuilder();
        uint acc = 0;
        var bits = 0;
        foreach (var b in d)
        {
            acc = acc << 8 | b;
            bits += 8;
            while (bits >= 5)
            {
                bits -= 5;
                sb.Append(Alphabet[(int)((acc >> bits) & 0x1F)]);
            }
            acc &= (1u << bits) - 1;
        }
        if (bits > 0) sb.Append(Alphabet[(int)((acc << (5 - bits)) & 0x1F)]);
        return sb.ToString();
    }
}

// byte[] compared by what is in it – for sessions and keys
public static class B
{
    public static readonly IEqualityComparer<byte[]> Comparer = new ContentComparer();

    public static bool Eq(byte[]? a, byte[]? b) => a == null || b == null ? a == b : a.AsSpan().SequenceEqual(b);

    // a before b, byte by byte (a shorter one that is the start of the other comes first)
    public static bool Less(byte[] a, byte[] b) => a.AsSpan().SequenceCompareTo(b) < 0;

    public static byte[] Cat(params byte[][] parts)
    {
        var out_ = new byte[parts.Sum(p => p.Length)];
        var i = 0;
        foreach (var p in parts)
        {
            p.CopyTo(out_, i);
            i += p.Length;
        }
        return out_;
    }

    // the first four bytes as a number – a session's token
    public static uint Token(byte[] session) => session.Take(4).Aggregate(0u, (acc, b) => acc << 8 | b);

    private sealed class ContentComparer : IEqualityComparer<byte[]>
    {
        public bool Equals(byte[]? x, byte[]? y) => Eq(x, y);

        public int GetHashCode(byte[] obj)
        {
            var h = new HashCode();
            h.AddBytes(obj);
            return h.ToHashCode();
        }
    }
}
