// MeshChat – the cryptography, and who you are in the chat. SHA-256 and HKDF-SHA256 (RFC 5869) come with .NET,
// Ed25519 (RFC 8032) from BouncyCastle – nothing self-made. Nothing is encrypted: the chat is public, signatures keep
// it honest. The same derivations as lib/meshchat on the Mac (CryptoKitBackend.swift, Identity.swift, Signing.swift):
// the same identity gives the same key there and here.

using System.Security.Cryptography;
using System.Text;
using Org.BouncyCastle.Math.EC.Rfc8032;

namespace MeshChat;

public static class CryptoBackend
{
    public const string Name = "BouncyCastle";

    public static byte[] RandomBytes(int count) => RandomNumberGenerator.GetBytes(count);

    public static byte[] Sha256(byte[] data) => SHA256.HashData(data);

    public static byte[] Hkdf(byte[] ikm, byte[] salt, byte[] info, int count) =>
        HKDF.DeriveKey(HashAlgorithmName.SHA256, ikm, count, salt, info);

    // Ed25519: a 32-byte private key (seed) → its 32-byte public key
    public static byte[] SigningPublicKey(byte[] seed)
    {
        if (seed.Length != 32) throw new ArgumentException("an Ed25519 key has 32 bytes");
        var pk = new byte[Ed25519.PublicKeySize];
        Ed25519.GeneratePublicKey(seed, 0, pk, 0);
        return pk;
    }

    public static byte[] Sign(byte[] message, byte[] seed)
    {
        if (seed.Length != 32) throw new ArgumentException("an Ed25519 key has 32 bytes");
        var sig = new byte[Ed25519.SignatureSize];
        Ed25519.Sign(seed, 0, message, 0, message.Length, sig, 0);
        return sig;
    }

    public static bool Verify(byte[] signature, byte[] message, byte[] publicKey)
    {
        if (signature.Length != 64 || publicKey.Length != 32) return false;
        try { return Ed25519.Verify(signature, 0, publicKey, 0, message, 0, message.Length); }
        catch (Exception) { return false; }      // a public key that is no point on the curve
    }
}

// Who you are in the chat: a signing key made from this computer's identity (32 random bytes in the data folder).
// Everything you write is signed with it, and the others see four letters of it after your name (Ada·k3f9).
public sealed class Signer
{
    public byte[] Seed { get; }
    public byte[] PublicKey { get; }
    public string Fingerprint { get; }

    private Signer(byte[] seed)
    {
        Seed = seed;
        PublicKey = CryptoBackend.SigningPublicKey(seed);
        Fingerprint = FingerprintOf(PublicKey);
    }

    public static Signer FromSeed(byte[] seed) => new(seed);

    // The Ed25519 key of this computer: HKDF-SHA256 of its identity – the file itself is never the key
    public static Signer FromIdentity(byte[] identity) =>
        new(CryptoBackend.Hkdf(identity, Encoding.UTF8.GetBytes("MeshChat v2"), Encoding.UTF8.GetBytes("signing key"), 32));

    public byte[] Sign(byte[] message) => CryptoBackend.Sign(message, Seed);

    // Four characters of the key's SHA-256 – enough to tell two people with the same name apart
    public static string FingerprintOf(byte[] publicKey) =>
        Base32.Encode(CryptoBackend.Sha256(publicKey))[..4].ToLowerInvariant();
}

// What someone says, made into a signed packet for everyone nearby, and packets checked again: the message read, the
// sender's signature verified. A packet that fails is never shown and never passed on.
public static class Signing
{
    public static readonly byte[] Context = Encoding.UTF8.GetBytes("MeshChat v2");

    public sealed class OpenError : Exception
    {
        public WireError? Malformed { get; }       // not a message of this protocol – else: not signed by the key it names
        public bool IsSignature => Malformed == null;

        public OpenError(WireError? malformed) : base(malformed?.Message ?? "the signature does not fit") => Malformed = malformed;
    }

    public static MeshPacket Make(InnerMessage inner, Signer signer, byte ttl, ulong messageId, ulong timestamp)
    {
        var packet = new MeshPacket { Ttl = ttl, Hops = 0, MessageId = messageId, Timestamp = timestamp };
        var body = inner.Body();
        packet.Payload = B.Cat(body, signer.Sign(B.Cat(Context, packet.SignedHeader, body)));
        if (packet.Encode().Length > Proto.MaxPacket) throw WireError.TooLarge("message");
        return packet;
    }

    public static InnerMessage Open(MeshPacket packet)
    {
        (InnerMessage Message, byte[] Body, byte[] Signature) decoded;
        try { decoded = InnerMessage.Decode(packet.Payload); }
        catch (WireError e) { throw new OpenError(e); }
        if (!CryptoBackend.Verify(decoded.Signature, B.Cat(Context, packet.SignedHeader, decoded.Body), decoded.Message.SenderKey))
            throw new OpenError(null);
        return decoded.Message;
    }
}
