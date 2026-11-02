// MeshChat tests – fragments and duplicates: packets cut for small and large links and put back together in any
// order, with limits that hold against a hostile neighbour; message IDs remembered for a while.
// As lib/meshchat/Tests/FragmentTests.swift.

using static MeshChat.TestRun;

namespace MeshChat;

public static class FragmentTests
{
    private static List<(ushort Seq, byte Index, byte Count, byte[] Payload)> Parts(IEnumerable<byte[]> frames) =>
        frames.Select(LinkFrame.Decode).Where(f => f.Kind == LinkKind.Data).Select(f => (f.Seq, f.Index, f.Count, f.Payload)).ToList();

    public static void Run()
    {
        Test("fragments: cut to fit every link size, and put back together", () =>
        {
            var packet = CryptoBackend.RandomBytes(Proto.MaxPacket);
            foreach (var size in new[] { 20, 23, 64, 182, 185, 512, 600 })
            {
                var frames = Fragmenter.Frames(packet, 9, size);
                Check(frames.All(f => f.Length <= Math.Min(size, Proto.MaxFrame)), $"every frame fits {size} bytes");
                var r = new Reassembler();
                byte[]? whole = null;
                var result = Reassembler.Outcome.Incomplete;
                foreach (var (seq, index, count, payload) in Parts(frames)) result = r.Add(seq, index, count, payload, 0, out whole);
                Check(result == Reassembler.Outcome.Complete && B.Eq(whole, packet), $"{frames.Count} frames of up to {size} bytes back to 2048");
            }
            var small = "hi"u8.ToArray();
            CheckEqual(Fragmenter.Frames(small, 1, 182).Count, 1, "a small packet is one frame");
            CheckThrows("a link with frames under 20 bytes", () => Fragmenter.Frames(small, 1, 12));
            CheckThrows("a packet over 2048 bytes", () => Fragmenter.Frames(new byte[2049], 1, 512));
            CheckThrows("an empty packet", () => Fragmenter.Frames(Array.Empty<byte>(), 1, 512));
        });

        Test("fragments: out of order, twice, and two packets mixed", () =>
        {
            byte[] a = CryptoBackend.RandomBytes(900), b = CryptoBackend.RandomBytes(700);
            var fa = Parts(Fragmenter.Frames(a, 1, 100));
            var fb = Parts(Fragmenter.Frames(b, 2, 100));
            var r = new Reassembler();
            var done = new List<byte[]>();
            var duplicates = 0;
            // b backwards, mixed with a forwards, and every part of a twice
            var mixed = new List<(ushort, byte, byte, byte[])>();
            for (var i = 0; i < Math.Max(fa.Count, fb.Count); i++)
            {
                if (i < fa.Count)
                {
                    mixed.Add(fa[i]);
                    mixed.Add(fa[i]);
                }
                if (i < fb.Count) mixed.Add(fb[fb.Count - 1 - i]);
            }
            foreach (var (seq, index, count, payload) in mixed)
            {
                switch (r.Add(seq, index, count, payload, 0, out var whole))
                {
                    case Reassembler.Outcome.Complete: done.Add(whole!); break;
                    case Reassembler.Outcome.Duplicate: duplicates++; break;
                }
            }
            CheckEqual(done.Count, 2, "both packets whole");
            Check(done.Any(d => B.Eq(d, a)) && done.Any(d => B.Eq(d, b)), "and right");
            CheckEqual(duplicates, fa.Count, "parts that came twice are recognized – also after the packet was complete");
            CheckEqual(r.PendingCount, 0, "nothing left half done");
        });

        Test("fragments: limits against a hostile or broken neighbour", () =>
        {
            var r = new Reassembler(4, 15, Proto.MaxPacket);
            // a part that never gets its other parts is dropped after 15 seconds
            CheckEqual(r.Add(1, 0, 3, new byte[10], 0, out _), Reassembler.Outcome.Incomplete, "first of three");
            r.Add(1, 1, 3, new byte[10], 1, out _);
            r.Expire(20);
            CheckEqual(r.PendingCount, 0, "a packet missing a part is given up after its time");
            CheckEqual(r.Add(1, 2, 3, new byte[10], 21, out _), Reassembler.Outcome.Incomplete, "its last part alone does not complete anything");
            // many half packets: only the newest four are kept
            for (ushort s = 10; s < 30; s++) r.Add(s, 0, 2, new byte[10], 22, out _);
            Check(r.PendingCount <= 4, "at most 4 packets half done");
            // a packet that grows over 2048 bytes is refused
            var big = new Reassembler();
            var result = Reassembler.Outcome.Incomplete;
            for (byte i = 0; i < 5; i++) result = big.Add(7, i, 6, new byte[500], 0, out _);
            Check(result == Reassembler.Outcome.Rejected && big.Reason == "too large", "parts adding up to more than 2048 bytes");
            Check(big.Add(8, 0, 1, new byte[3000], 0, out _) == Reassembler.Outcome.Rejected && big.Reason == "too large", "a single part over 2048 bytes");
            // the same sequence number with another count: the old one is dropped, the new one starts
            var again = new Reassembler();
            again.Add(5, 0, 3, new byte[] { 1 }, 0, out _);
            again.Add(5, 0, 2, new byte[] { 2 }, 0, out _);
            Check(again.Add(5, 1, 2, new byte[] { 3 }, 0, out var w) == Reassembler.Outcome.Complete && B.Eq(w, new byte[] { 2, 3 }), "a reused sequence number");
            Check(again.Add(6, 3, 2, new byte[] { 3 }, 0, out _) == Reassembler.Outcome.Rejected && again.Reason == "fragment 3 of 2", "an index outside the count");
        });

        Test("duplicates: remembered for 30 minutes, 4096 at most", () =>
        {
            var d = new DedupCache(4, 1800);
            Check(d.Insert(1, 0), "new");
            Check(!d.Insert(1, 10), "the second time it is a duplicate");
            Check(d.Contains(1, 1799), "still known after 29 minutes");
            Check(!d.Contains(1, 1801), "forgotten after 30");
            for (ulong i = 10; i < 20; i++) d.Insert(i, 2000);
            CheckEqual(d.Count, 4, "the oldest go first when it is full");
            Check(d.Contains(19, 2000) && !d.Contains(10, 2000), "the newest stay");
            var bigCache = new DedupCache();
            for (var i = 0; i < 10_000; i++) bigCache.Insert((ulong)i, i / 10.0);
            Check(bigCache.Count <= 4096, "never more than 4096 IDs");
        });
    }
}
