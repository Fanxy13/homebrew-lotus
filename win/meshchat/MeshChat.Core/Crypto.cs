// MeshChat – the cryptography, and who you are in the chat. SHA-256 and HKDF-SHA256 (RFC 5869) come with .NET,
// Ed25519 (RFC 8032), X25519 (RFC 7748) and ChaCha20-Poly1305 (RFC 8439) from BouncyCastle – nothing self-made. The chat
// is public, signatures keep it honest; only a private message (/tell) is encrypted, sealed for its recipient. The same
// derivations as lib/meshchat on the Mac (CryptoKitBackend.swift, Identity.swift, Signing.swift): the same identity
// gives the same keys there and here.

using System.Security.Cryptography;
using System.Text;
using Org.BouncyCastle.Crypto.Agreement;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Math.EC.Rfc8032;
// BouncyCastle's, not .NET's own: that one is missing on macOS, where these tests run too
using BcChaCha20Poly1305 = Org.BouncyCastle.Crypto.Modes.ChaCha20Poly1305;

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

    // X25519: a 32-byte private key → its 32-byte public key
    public static byte[] BoxPublicKey(byte[] privateKey)
    {
        if (privateKey.Length != 32) throw new ArgumentException("an X25519 key has 32 bytes");
        return new X25519PrivateKeyParameters(privateKey, 0).GeneratePublicKey().GetEncoded();
    }

    // The secret a private key and someone's public key share – the same from either side. Throws for a public key of
    // low order (no secret at all)
    public static byte[] SharedSecret(byte[] privateKey, byte[] publicKey)
    {
        if (privateKey.Length != 32 || publicKey.Length != 32) throw new ArgumentException("an X25519 key has 32 bytes");
        var agreement = new X25519Agreement();
        agreement.Init(new X25519PrivateKeyParameters(privateKey, 0));
        var secret = new byte[agreement.AgreementSize];
        agreement.CalculateAgreement(new X25519PublicKeyParameters(publicKey, 0), secret, 0);
        return secret;
    }

    // ChaCha20-Poly1305: the ciphertext with its 16-byte tag after it
    public static byte[] Seal(byte[] plaintext, byte[] key, byte[] nonce, byte[] aad)
    {
        var aead = new BcChaCha20Poly1305();
        aead.Init(true, new AeadParameters(new KeyParameter(key), 128, nonce, aad));
        var output = new byte[aead.GetOutputSize(plaintext.Length)];
        var n = aead.ProcessBytes(plaintext, 0, plaintext.Length, output, 0);
        aead.DoFinal(output, n);
        return output;
    }

    // … and opened again – it throws when anything was changed, or it was sealed with another key
    public static byte[] Open(byte[] sealedText, byte[] key, byte[] nonce, byte[] aad)
    {
        if (sealedText.Length <= 16) throw new CryptographicException("too short to be sealed");
        var aead = new BcChaCha20Poly1305();
        aead.Init(false, new AeadParameters(new KeyParameter(key), 128, nonce, aad));
        var output = new byte[aead.GetOutputSize(sealedText.Length)];
        var n = aead.ProcessBytes(sealedText, 0, sealedText.Length, output, 0);
        n += aead.DoFinal(output, n);
        return output.AsSpan(0, n).ToArray();
    }
}

// Who you are in the chat: a signing key made from this computer's identity (32 random bytes in the data folder).
// Everything you write is signed with it, and the others see four letters of it after your name (Ada·k3f9). A second
// key made from it, the box key, opens private messages (/tell).
public sealed class Signer
{
    public byte[] Seed { get; }
    public byte[] PublicKey { get; }
    public string Fingerprint { get; }
    public byte[] BoxSeed { get; }      // X25519: private messages to this computer are sealed for its public key …
    public byte[] BoxKey { get; }       // … which every presence of it carries

    // boxSeed null: made from the seed (a Signer for a test, the demo or a relay)
    private Signer(byte[] seed, byte[]? boxSeed)
    {
        Seed = seed;
        PublicKey = CryptoBackend.SigningPublicKey(seed);
        Fingerprint = FingerprintOf(PublicKey);
        BoxSeed = boxSeed ?? CryptoBackend.Hkdf(seed, Signing.Context, Encoding.UTF8.GetBytes("box key"), 32);
        BoxKey = CryptoBackend.BoxPublicKey(BoxSeed);
    }

    public static Signer FromSeed(byte[] seed) => new(seed, null);

    // The Ed25519 key and the box key of this computer: HKDF-SHA256 of its identity – the file itself is never a key
    public static Signer FromIdentity(byte[] identity) =>
        new(CryptoBackend.Hkdf(identity, Encoding.UTF8.GetBytes("MeshChat v2"), Encoding.UTF8.GetBytes("signing key"), 32),
            CryptoBackend.Hkdf(identity, Encoding.UTF8.GetBytes("MeshChat v2"), Encoding.UTF8.GetBytes("box key"), 32));

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

// A private message (/tell): only the recipient can read it, every computer on the way passes it on. As Sealing in
// lib/meshchat/Sources/Signing.swift:
//   secret = X25519(a one-time key, the recipient's box key)        – the one-time key is used for this message only
//   key    = HKDF-SHA256(secret, salt "MeshChat v2", info "tell" + the one-time public key + the box key), 32 bytes
//   sealed = ChaCha20-Poly1305(key, a random 12-byte nonce, the text, associated data: the sender's and the recipient's
//            public keys) – so it cannot be passed off as someone else's, or as one to someone else
// The recipient makes the same secret from its box seed and the one-time public key. The packet around it is signed as
// every packet is: who wrote it, and to whom, is in the clear – what it says is not.
public static class Sealing
{
    public sealed record Result(byte[] OneTimeKey, byte[] Nonce, byte[] Sealed);     // the one-time public key, the nonce, ciphertext and tag

    private static byte[] Key(byte[] secret, byte[] oneTime, byte[] box) =>
        CryptoBackend.Hkdf(secret, Signing.Context, B.Cat(Encoding.UTF8.GetBytes("tell"), oneTime, box), 32);

    // oneTime and nonce are random – the tests give fixed ones for the test vectors
    public static Result Seal(string text, byte[] sender, byte[] recipient, byte[] box, byte[]? oneTime = null, byte[]? nonce = null)
    {
        var secret = oneTime ?? CryptoBackend.RandomBytes(32);
        var pub = CryptoBackend.BoxPublicKey(secret);
        var n = nonce ?? CryptoBackend.RandomBytes(Proto.NonceLength);
        var shared = CryptoBackend.SharedSecret(secret, box);
        var sealedText = CryptoBackend.Seal(Encoding.UTF8.GetBytes(text), Key(shared, pub, box), n, B.Cat(sender, recipient));
        return new Result(pub, n, sealedText);
    }

    // The text of a private message to this computer (made safe for the terminal) – null when it does not open: changed
    // on the way, or sealed for another key
    public static string? Open(InnerMessage m, Signer signer)
    {
        if (m.Kind != InnerKind.Tell || !B.Eq(m.Recipient, signer.PublicKey)) return null;
        try
        {
            var shared = CryptoBackend.SharedSecret(signer.BoxSeed, m.OneTimeKey);
            var plain = CryptoBackend.Open(m.Sealed, Key(shared, m.OneTimeKey, signer.BoxKey), m.Nonce, B.Cat(m.SenderKey, m.Recipient));
            var text = Sanitize.Text(new UTF8Encoding(false, true).GetString(plain));
            return text.Length == 0 ? null : text;
        }
        catch (Exception) { return null; }
    }
}
