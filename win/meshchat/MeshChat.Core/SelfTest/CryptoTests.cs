// MeshChat tests – the cryptography: published test vectors (so this computer's Ed25519, SHA-256 and HKDF are checked
// against the standards – the Mac checks CryptoKit against the same ones), this computer's signing key, and packets
// that are refused when anything in them was changed. As lib/meshchat/Tests/CryptoTests.swift.

using System.Text;
using static MeshChat.TestRun;

namespace MeshChat;

public static class CryptoTests
{
    private static byte[] U(string s) => Encoding.UTF8.GetBytes(s);

    public static void Run()
    {
        Test("SHA-256 and HKDF-SHA256 (RFC 5869) give the published results", () =>
        {
            CheckEqual(Hex.Encode(CryptoBackend.Sha256(U("abc"))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 of abc");
            var okm = CryptoBackend.Hkdf(H("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), H("000102030405060708090a0b0c"), H("f0f1f2f3f4f5f6f7f8f9"), 42);
            CheckEqual(Hex.Encode(okm), "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865", "RFC 5869 test case 1");
        });

        Test("Ed25519 (RFC 8032): the published keys and signatures, and signatures of this computer", () =>
        {
            var seed = H("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60");
            var pub = CryptoBackend.SigningPublicKey(seed);
            CheckEqual(Hex.Encode(pub), "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "test 1 public key");
            var sig1 = H("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b");
            Check(CryptoBackend.Verify(sig1, Array.Empty<byte>(), pub), "test 1 signature verifies");
            CheckBytes(CryptoBackend.Sign(Array.Empty<byte>(), seed), sig1, "and is the one this computer makes (Ed25519 is deterministic here)");
            var pub2 = H("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c");
            var sig2 = H("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00");
            Check(CryptoBackend.Verify(sig2, new byte[] { 0x72 }, pub2), "test 2 signature verifies");
            Check(!CryptoBackend.Verify(sig2, new byte[] { 0x73 }, pub2), "not for another message");
            Check(!CryptoBackend.Verify(sig1, Array.Empty<byte>(), pub2), "not with another key");
            var mine = CryptoBackend.Sign(U("MeshChat"), seed);
            Check(CryptoBackend.Verify(mine, U("MeshChat"), pub), "a signature of this computer verifies");
            Check(!CryptoBackend.Verify(mine[..63], U("MeshChat"), pub), "a signature cut short does not");
            Check(!CryptoBackend.Verify(mine, U("MeshChat"), new byte[31]), "nor with a key of the wrong size");
            Check(!CryptoBackend.Verify(mine, U("MeshChat"), Enumerable.Repeat((byte)0xFF, 32).ToArray()), "nor with a key that is no point on the curve");
        });

        Test("this computer's key: the same identity gives the same key, another identity another", () =>
        {
            var identity = Enumerable.Repeat((byte)0x42, 32).ToArray();
            Signer a = Signer.FromIdentity(identity), b = Signer.FromIdentity(identity);
            CheckBytes(a.PublicKey, b.PublicKey, "the same identity, the same key");
            CheckEqual(a.Fingerprint, b.Fingerprint, "and the same fingerprint – the others recognize you");
            var c = Signer.FromIdentity(CryptoBackend.RandomBytes(32));
            Check(!B.Eq(c.PublicKey, a.PublicKey) && c.Fingerprint != a.Fingerprint, "another identity, another key");
            Check(!B.Eq(a.Seed, identity), "the identity file itself is not the key");
            CheckBytes(a.Seed, CryptoBackend.Hkdf(identity, U("MeshChat v2"), U("signing key"), 32), "the key is HKDF(identity, \"MeshChat v2\", \"signing key\")");
            CheckEqual(a.Fingerprint.Length, 4, "fingerprints have four characters");
            Check(a.Fingerprint.All(ch => Base32.Alphabet.Contains(char.ToUpperInvariant(ch))), "of base32");
        });

        Test("packets: signed, readable by everyone, refused when anything was changed", () =>
        {
            var alice = Signer.FromIdentity(CryptoBackend.RandomBytes(32));
            var inner = new InnerMessage { Kind = InnerKind.Chat, SenderKey = alice.PublicKey, Session = Enumerable.Repeat((byte)1, 8).ToArray(), Nickname = "Alice", Text = "Meet at the bridge" };
            var p = Signing.Make(inner, alice, 16, 42, 1_700_000_000_000);
            Check(Signing.Open(p).Same(inner), "opened – by anyone: the chat is public");
            var wire = Hex.Encode(p.Encode());
            Check(wire.Contains(Hex.Encode(U("Meet at the bridge"))) && wire.Contains(Hex.Encode(U("Alice"))), "the text and the name are on the wire as they are – nothing is encrypted");
            var relayed = p.Copy();
            relayed.Ttl = 2;
            relayed.Hops = 3;
            Check(Signing.Open(relayed).Same(inner), "relays may change ttl and hops");
            // where the name and the text are in the message: kind, flags, key, session, then str8 name and str16 text
            int nameAt = 1 + 1 + 32 + 8 + 1, textAt = nameAt + 5 + 2;
            CheckEqual(p.Payload[textAt], (byte)'M', "the text starts where it should");
            var bob = Signer.FromIdentity(CryptoBackend.RandomBytes(32));
            void Refused(string what, Action<MeshPacket> change)
            {
                var q = p.Copy();
                q.Payload = (byte[])p.Payload.Clone();
                change(q);
                try
                {
                    Signing.Open(q);
                    Check(false, what);
                }
                catch (Signing.OpenError e)
                {
                    Check(e.IsSignature, what);
                }
            }
            Refused("a changed letter in the text", q => q.Payload[textAt] ^= 0x01);
            Refused("a changed name", q => q.Payload[nameAt] ^= 0x01);
            Refused("someone else's key put in", q => bob.PublicKey.CopyTo(q.Payload, 2));
            Refused("a changed message ID (a copy passed off as new)", q => q.MessageId += 1);
            Refused("a changed time (an old message made new)", q => q.Timestamp += 60_000);
            Refused("a changed flag", q => q.Flags = 1);
            Refused("a changed signature", q => q.Payload[^1] ^= 1);
            var cut = p.Copy();
            cut.Payload = B.Cat(p.Payload[..30], p.Payload[^64..]);
            try
            {
                Signing.Open(cut);
                Check(false, "a message cut short is refused as broken");
            }
            catch (Signing.OpenError e)
            {
                Check(e.Malformed != null, "a message cut short is refused as broken");
            }
        });

        Test("signatures: no one can write in someone else's name", () =>
        {
            var alice = Signer.FromIdentity(CryptoBackend.RandomBytes(32));
            var mallory = Signer.FromIdentity(CryptoBackend.RandomBytes(32));
            // Mallory puts Alice's public key and name in, but can only sign with her own key
            var forged = new InnerMessage { Kind = InnerKind.Chat, SenderKey = alice.PublicKey, Session = new byte[8], Nickname = "Alice", Text = "Send me your password" };
            var p = Signing.Make(forged, mallory, 16, 7, 1);
            try
            {
                Signing.Open(p);
                Check(false, "a message signed with another key than the one it names is refused");
            }
            catch (Signing.OpenError e)
            {
                Check(e.IsSignature, "a message signed with another key than the one it names is refused");
            }
            Check(alice.Fingerprint != mallory.Fingerprint, "two people, two fingerprints");
        });
    }
}
