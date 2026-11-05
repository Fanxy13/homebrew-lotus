// MeshChat tests – private messages (/tell): the message and the box key on the wire, the sealing (X25519 and
// ChaCha20-Poly1305 with their published test vectors, and that only the recipient opens it), a private message through
// the mesh – passed on by everyone, read by one – one that waits for the recipient's key, who /tell finds by name, and
// how it is kept and shown. As lib/meshchat/Tests/TellTests.swift.

using System.Text;
using System.Text.RegularExpressions;
using static MeshChat.TestRun;

namespace MeshChat;

public static class TellTests
{
    private static byte[] R(int n) => CryptoBackend.RandomBytes(n);

    // The packets a neighbour sent to a rogue, put together again and opened
    private static List<InnerMessage> Opened(Rogue rogue)
    {
        var r = new Reassembler();
        var out_ = new List<InnerMessage>();
        foreach (var f in rogue.ReceivedFrames)
        {
            LinkFrame frame;
            try { frame = LinkFrame.Decode(f); } catch (WireError) { continue; }
            if (frame.Kind != LinkKind.Data) continue;
            if (r.Add(frame.Seq, frame.Index, frame.Count, frame.Payload, 0, out var whole) != Reassembler.Outcome.Complete || whole == null) continue;
            try { out_.Add(Signing.Open(MeshPacket.Decode(whole))); } catch (Exception) { }
        }
        return out_;
    }

    public static void Run()
    {
        Test("private messages on the wire: the message and the box key round trip, older ones are still read", () =>
        {
            byte[] Fill(byte b, int n) => Enumerable.Repeat(b, n).ToArray();
            var key = Fill(3, 32);
            var session = Fill(4, 8);
            var tell = new InnerMessage
            {
                Kind = InnerKind.Tell, SenderKey = key, Session = session, Nickname = "Ada",
                Recipient = Fill(5, 32), OneTimeKey = Fill(6, 32), Nonce = Fill(7, 12), Sealed = Fill(8, 40),
            };
            var presence = new InnerMessage
            {
                Kind = InnerKind.Presence, SenderKey = key, Session = session, Nickname = "Ada", Links = 1,
                Neighbours = new() { new Neighbour(9, -60) }, BoxKey = Fill(10, 32),
            };
            foreach (var m in new[] { tell, presence })
            {
                var body = m.Body();
                var (back, signed, _) = InnerMessage.Decode(B.Cat(body, new byte[64]));
                Check(back.Same(m), $"{m.Kind} round trips");
                CheckBytes(signed, body, $"{m.Kind}: the signed part");
            }
            var old = new InnerMessage { Kind = InnerKind.Presence, SenderKey = key, Session = session, Nickname = "Old", Links = 1 };
            Check(InnerMessage.Decode(B.Cat(old.Body(), new byte[64])).Message.BoxKey == null, "a presence without a box key (before 2.2) is read, without one");
            CheckEqual(presence.Body().Length - old.Body().Length, 5 + 32, "the box key is 32 bytes at the end");
            Check(InnerMessage.Decode(B.Cat(old.Body(), new byte[10], new byte[64])).Message.BoxKey == null, "a shorter field there is skipped, as a newer one may be");
            var tooLong = new InnerMessage
            {
                Kind = InnerKind.Tell, SenderKey = key, Session = session, Nickname = "Ada", Recipient = Fill(5, 32), OneTimeKey = Fill(6, 32),
                Nonce = Fill(7, 12), Sealed = new byte[Proto.MaxTextBytes + Proto.TagLength + 1],
            };
            CheckThrows("a sealed text over 1000 bytes is not made", () => tooLong.Body());
            tooLong.Sealed = new byte[Proto.TagLength];
            CheckThrows("nor one with no room for its tag", () => tooLong.Body());
            CheckThrows("a private message cut short is refused", () => InnerMessage.Decode(B.Cat(tell.Body()[..^5], new byte[64])));
        });

        Test("X25519 (RFC 7748) and ChaCha20-Poly1305 (RFC 8439) give the published results", () =>
        {
            var alice = H("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");
            var bob = H("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb");
            CheckEqual(Hex.Encode(CryptoBackend.BoxPublicKey(alice)), "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a", "Alice's public key");
            CheckEqual(Hex.Encode(CryptoBackend.BoxPublicKey(bob)), "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f", "Bob's public key");
            const string shared = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742";
            CheckEqual(Hex.Encode(CryptoBackend.SharedSecret(alice, CryptoBackend.BoxPublicKey(bob))), shared, "the secret they share");
            CheckEqual(Hex.Encode(CryptoBackend.SharedSecret(bob, CryptoBackend.BoxPublicKey(alice))), shared, "the same from Bob's side");
            CheckThrows("a public key of low order gives no secret", () => CryptoBackend.SharedSecret(alice, new byte[32]));
            var key = H("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f");
            var nonce = H("070000004041424344454647");
            var aad = H("50515253c0c1c2c3c4c5c6c7");
            var text = Encoding.ASCII.GetBytes("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.");
            const string sealedHex = "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116"
                                     + "1ae10b594f09e26a7e902ecbd0600691";
            CheckEqual(Hex.Encode(CryptoBackend.Seal(text, key, nonce, aad)), sealedHex, "the sealed text and its tag");
            CheckBytes(CryptoBackend.Open(H(sealedHex), key, nonce, aad), text, "opened again");
            var changed = H(sealedHex);
            changed[3] ^= 1;
            CheckThrows("one byte changed: it does not open", () => CryptoBackend.Open(changed, key, nonce, aad));
            CheckThrows("other associated data: neither", () => CryptoBackend.Open(H(sealedHex), key, nonce, H("00")));
        });

        Test("a private message is sealed for one: the recipient opens it, no one else – and nothing changed opens", () =>
        {
            var ada = Signer.FromIdentity(R(32));
            var bob = Signer.FromIdentity(R(32));
            var eve = Signer.FromIdentity(R(32));
            const string text = "Meet at the bridge 🌉";
            var s = Sealing.Seal(text, ada.PublicKey, bob.PublicKey, bob.BoxKey);
            InnerMessage M(byte[] sender, byte[] recipient, byte[] sealedText) => new()
            {
                Kind = InnerKind.Tell, SenderKey = sender, Session = R(8), Nickname = "Ada",
                Recipient = recipient, OneTimeKey = s.OneTimeKey, Nonce = s.Nonce, Sealed = sealedText,
            };
            CheckEqual(Sealing.Open(M(ada.PublicKey, bob.PublicKey, s.Sealed), bob), text, "Bob reads it");
            CheckEqual(Sealing.Open(M(ada.PublicKey, bob.PublicKey, s.Sealed), eve), null, "Eve, who passes it on, cannot");
            CheckEqual(Sealing.Open(M(ada.PublicKey, eve.PublicKey, s.Sealed), eve), null, "not even when she makes it one to herself");
            CheckEqual(Sealing.Open(M(eve.PublicKey, bob.PublicKey, s.Sealed), bob), null, "nor can she pass it off as her own");
            var changed = (byte[])s.Sealed.Clone();
            changed[2] ^= 0x40;
            CheckEqual(Sealing.Open(M(ada.PublicKey, bob.PublicKey, changed), bob), null, "a changed byte: it does not open");
            Check(!Encoding.UTF8.GetString(s.Sealed).Contains("bridge"), "the text is not in it");
            var again = Sealing.Seal(text, ada.PublicKey, bob.PublicKey, bob.BoxKey);
            Check(!B.Eq(again.Sealed, s.Sealed) && !B.Eq(again.OneTimeKey, s.OneTimeKey), "the same text twice: two different messages");
            var packet = Signing.Make(M(ada.PublicKey, bob.PublicKey, s.Sealed), ada, 16, 99, 1_761_570_000_000);
            var opened = Signing.Open(MeshPacket.Decode(packet.Encode()));
            CheckEqual(opened.Kind, InnerKind.Tell, "signed and checked like every packet");
            CheckEqual(Sealing.Open(opened, bob), text, "and it still opens for Bob");
            var id = R(32);
            CheckBytes(Signer.FromIdentity(id).BoxKey, Signer.FromIdentity(id).BoxKey, "the same identity gives the same box key");
            Check(!B.Eq(bob.BoxKey, bob.PublicKey) && !B.Eq(bob.BoxSeed, bob.Seed), "a key of its own, not the signing key");
        });

        Test("a private message through the mesh: everyone on the way passes it on, only the recipient reads it", () =>
        {
            var m = new TestMesh();
            foreach (var n in new[] { "A", "B", "C" }) m.Add(n);
            m.Net.SetRange("A", "B", true);
            m.Net.SetRange("B", "C", true);
            m.RunFor(40);
            var c = m.Person("C", "A");
            Check(c?.BoxKey != null, "A has C's box key – it came with C's presence");
            m.Node("A").SendPrivately("only for you, C", c!.Key);
            m.Net.Pump();
            m.RunFor(1);
            var got = m.Received("C").Where(x => x.Privately).ToList();
            CheckList(got.Select(x => x.Text), new[] { "only for you, C" }, "C reads it");
            Check(got.Count == 1 && got[0].Hops == 1 && got[0].Nickname == "A", "from A, through one relay");
            Check(!m.Received("B").Any(x => x.Privately || x.Text.Contains("only for you")), "B shows nothing of it");
            Check(m.Stats("B").Relayed >= 1, "but passed it on");
            var mine = m.Events["A"].OfType<MeshEvent.Message>().Select(e => e.M).FirstOrDefault(x => x.Mine && x.Privately);
            Check(mine != null && mine.To == "C" && mine.Text == "only for you, C", "A shows it as its own, to C");
            m.Node("C").SendPrivately("got it", m.Person("A", "C")!.Key);
            m.Net.Pump();
            m.RunFor(1);
            CheckList(m.Received("A").Where(x => x.Privately).Select(x => x.Text), new[] { "got it" }, "and the answer comes back, privately");
            CheckThrows("to someone who is not there: it says so", () => m.Node("A").SendPrivately("hello?", R(32)));
        });

        Test("a private message waits for the recipient's key – and is given up after a minute", () =>
        {
            var m = new TestMesh();
            m.Add("A");
            var rogue = new Rogue(m.Net, "old");
            m.Net.AllInRange("A", "old");
            m.RunFor(3);
            rogue.ConnectTo("A", m.Net);
            Check(rogue.Link != null, "an older MeshChat linked to A");
            var old = Signer.FromIdentity(R(32));
            var session = R(8);
            MeshPacket Presence(bool withBox, ulong id) => Signing.Make(new InnerMessage
            {
                Kind = InnerKind.Presence, SenderKey = old.PublicKey, Session = session, Nickname = "Old", Links = 1,
                BoxKey = withBox ? old.BoxKey : null,
            }, old, 16, id, (ulong)(m.Net.Now * 1000));
            rogue.SendPacket(Presence(false, 501));
            m.Net.Pump();
            var who = m.Person("Old", "A");
            Check(who != null && who.BoxKey == null, "A knows Old – an older MeshChat, without a box key");
            m.Node("A").SendPrivately("are you there?", who!.Key);
            m.Net.Pump();
            Check(m.Notices("A").Any(n => n.Contains("has not come yet")), "the message waits, and A says so");
            Check(!m.Events["A"].OfType<MeshEvent.Message>().Any(e => e.M.Privately), "nothing is sent yet");
            Check(Opened(rogue).Any(i => i.Kind == InnerKind.Presence && (i.Flags & InnerMessage.RequestFlag) != 0), "A asks who is here – for the key");
            rogue.SendPacket(Presence(true, 502));
            m.Net.Pump();
            var sent = m.Events["A"].OfType<MeshEvent.Message>().Select(e => e.M).FirstOrDefault(x => x.Privately && x.Mine);
            Check(sent?.Text == "are you there?" && sent.To == "Old", "once the key comes, it is sent");
            var tells = Opened(rogue).Where(i => i.Kind == InnerKind.Tell).ToList();
            Check(tells.Count == 1 && Sealing.Open(tells[0], old) == "are you there?", "sealed for Old – who opens it");
            var older = Signer.FromIdentity(R(32));
            rogue.SendPacket(Signing.Make(new InnerMessage
            {
                Kind = InnerKind.Presence, SenderKey = older.PublicKey, Session = R(8), Nickname = "Older", Links = 1,
            }, older, 16, 503, (ulong)(m.Net.Now * 1000)));
            m.Net.Pump();
            m.Node("A").SendPrivately("hello?", m.Person("Older", "A")!.Key);
            m.RunFor(62);
            Check(m.Notices("A").Any(n => n.Contains("was not sent") && n.Contains("Older")), "a key that never comes: after a minute it says the message was not sent");
            CheckEqual(m.Events["A"].OfType<MeshEvent.Message>().Count(e => e.M.Privately && e.M.Mine), 1, "and it never went out");
        });

        Test("/tell finds who it is for: a name in any case, its beginning, the four letters or both – or says why not", () =>
        {
            Participant P(string nick, string fp) => new() { Nickname = nick, Fingerprint = fp, Key = R(32), Session = R(8) };
            var bob = P("Bob", "k3f9");
            var bob2 = P("Bob", "m2x1");
            var ada = P("Ada Lovelace", "a1b2");
            var grace = P("Grace", "g7h8");
            var people = new List<Participant> { bob, ada, grace };
            Check(ChatApp.AddresseeOf("bob hi there", people) is ChatApp.Addressee.Found f1 && f1.P == bob && f1.Text == "hi there", "a name, in any case");
            Check(ChatApp.AddresseeOf("Ada Lovelace see you", people) is ChatApp.Addressee.Found f2 && f2.P == ada && f2.Text == "see you", "a name with a space in it");
            Check(ChatApp.AddresseeOf("gr hello", people) is ChatApp.Addressee.Found f3 && f3.P == grace && f3.Text == "hello", "the beginning of a name");
            Check(ChatApp.AddresseeOf("g7h8 hello", people) is ChatApp.Addressee.Found f4 && f4.P == grace, "the four letters");
            var two = new List<Participant> { bob, bob2, ada };
            Check(ChatApp.AddresseeOf("bob hi", two) is ChatApp.Addressee.Several s && s.People.Count == 2, "two called Bob: it says so");
            Check(ChatApp.AddresseeOf("bob.m2x1 hi", two) is ChatApp.Addressee.Found f5 && f5.P == bob2, "Bob.m2x1: that one");
            Check(ChatApp.AddresseeOf("Bob·k3f9 hi", two) is ChatApp.Addressee.Found f6 && f6.P == bob, "Bob·k3f9 too");
            Check(ChatApp.AddresseeOf("zed hi", people) is ChatApp.Addressee.Nobody { Name: "zed" }, "no one called that");
            Check(ChatApp.AddresseeOf("bob", people) is ChatApp.Addressee.Nothing n7 && n7.P == bob, "a name, and nothing to say");
            Check(ChatApp.AddresseeOf("", people) is ChatApp.Addressee.Nobody { Name: "" }, "nothing at all");
        });

        Test("a private message is kept as it was read, and shown with who it is for", () =>
        {
            var m = new ChatMessage(42, "Ada", "a1b2", "only for you", 1_700_000_000, 1_700_000_001, 1, true, Privately: true, To: "Bob");
            var line = Store.Encode(m);
            Check(line.Contains("\"pv\":true") && line.Contains("\"to\":\"Bob\""), "the history says it was private, and to whom");
            var back = Store.Decode(line)!.Message;
            Check(back.Privately && back.To == "Bob" && back.Text == "only for you" && back.Mine, "and reads it back");
            var plain = Store.Encode(m with { Privately = false, To = "" });
            Check(!plain.Contains("\"pv\"") && !plain.Contains("\"to\""), "a public message is kept as before");
            var s = new ChatViewState { Nickname = "Ada", Fingerprint = "a1b2" };
            s.Add(new ViewItem.Message(m), m.Sent);
            s.Add(new ViewItem.Message(new ChatMessage(43, "Bob", "k3f9", "and only for you", 1_700_000_002, 1_700_000_002, 0, false, Privately: true)), 1_700_000_002);
            var rows = ChatRender.MessageRows(s, 80, 1_700_000_100).Select(r => Regex.Replace(r, "\u001b\\[[0-9;]*m", "")).ToList();
            Check(rows.Any(r => r.Contains("Ada") && r.Contains("→ Bob: only for you")), "mine: → Bob, first");
            Check(rows.Any(r => r.Contains("Bob") && r.Contains("→ you: and only for you")), "theirs: → you");
        });
    }
}
