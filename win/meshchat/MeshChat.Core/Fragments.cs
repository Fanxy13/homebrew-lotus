// MeshChat – fragments and duplicates, as lib/meshchat/Sources/Fragments.swift and Dedup.swift.
// A mesh packet (up to 2048 bytes) is cut into DATA frames that fit one write or notification of a link (20–512 bytes),
// and put back together on the other side – in any order, each part once, with limits on how many packets may be half
// done, how large they get and how long they wait.

namespace MeshChat;

public static class Fragmenter
{
    public static List<byte[]> Frames(byte[] packet, ushort seq, int maxFrame)
    {
        var frame = Math.Min(maxFrame, Proto.MaxFrame);
        if (frame < Proto.MinFrame) throw WireError.Invalid($"a link with frames of {maxFrame} bytes");
        if (packet.Length == 0 || packet.Length > Proto.MaxPacket) throw WireError.TooLarge($"packet of {packet.Length} bytes");
        var chunk = frame - LinkFrame.DataHeader;
        var count = (packet.Length + chunk - 1) / chunk;
        if (count > Proto.MaxFragments) throw WireError.TooLarge($"{count} fragments");
        var frames = new List<byte[]>(count);
        for (var i = 0; i < count; i++)
        {
            var part = packet.AsSpan(i * chunk, Math.Min(packet.Length, (i + 1) * chunk) - i * chunk).ToArray();
            frames.Add(LinkFrame.Data(seq, (byte)i, (byte)count, part).Encode());
        }
        return frames;
    }
}

// One per link: the frames of a link arrive in order, but nothing here relies on it
public sealed class Reassembler
{
    public enum Outcome { Incomplete, Complete, Duplicate, Rejected }

    private sealed class Pending
    {
        public byte Count;
        public Dictionary<byte, byte[]> Parts = new();
        public int Bytes;
        public double Started;
    }

    private readonly int maxPending;
    private readonly double timeout;
    private readonly int maxPacket;
    private readonly Dictionary<ushort, Pending> pending = new();
    private readonly List<ushort> completed = new();    // the last packets put together: a late copy of a part is a duplicate

    public Reassembler(int maxPending = 8, double timeout = 15, int maxPacket = Proto.MaxPacket)
    {
        this.maxPending = maxPending;
        this.timeout = timeout;
        this.maxPacket = maxPacket;
    }

    public int Dropped { get; private set; }    // packets given up: too old, or pushed out by newer ones
    public string Reason { get; private set; } = "";      // why the last part was refused
    public int PendingCount => pending.Count;

    public Outcome Add(ushort seq, byte index, byte count, byte[] payload, double now, out byte[]? whole)
    {
        whole = null;
        Expire(now);
        if (count < 1 || index >= count) return Reject($"fragment {index} of {count}");
        if (payload.Length > maxPacket) return Reject("too large");
        if (!pending.ContainsKey(seq) && completed.Contains(seq)) return Outcome.Duplicate;
        if (count == 1)
        {
            pending.Remove(seq);
            Done(seq);
            whole = payload;
            return Outcome.Complete;
        }
        if (pending.TryGetValue(seq, out var p) && p.Count == count)
        {
            if (p.Parts.ContainsKey(index)) return Outcome.Duplicate;
            if (p.Bytes + payload.Length > maxPacket)
            {
                pending.Remove(seq);
                Dropped++;
                return Reject("too large");
            }
            p.Parts[index] = payload;
            p.Bytes += payload.Length;
            if (p.Parts.Count == count)
            {
                pending.Remove(seq);
                Done(seq);
                var all = new byte[p.Bytes];
                var at = 0;
                for (byte i = 0; i < count; i++)
                {
                    p.Parts[i].CopyTo(all, at);
                    at += p.Parts[i].Length;
                }
                whole = all;
                return Outcome.Complete;
            }
            return Outcome.Incomplete;
        }
        // a new packet – or the same sequence number with another count: the old one never finished
        if (pending.Remove(seq)) Dropped++;
        if (pending.Count >= maxPending)
        {
            var oldest = pending.MinBy(kv => kv.Value.Started);
            pending.Remove(oldest.Key);
            Dropped++;
        }
        var fresh = new Pending { Count = count, Bytes = payload.Length, Started = now };
        fresh.Parts[index] = payload;
        pending[seq] = fresh;
        return Outcome.Incomplete;
    }

    private Outcome Reject(string why)
    {
        Reason = why;
        return Outcome.Rejected;
    }

    private void Done(ushort seq)
    {
        completed.Add(seq);
        if (completed.Count > 32) completed.RemoveAt(0);
    }

    public void Expire(double now)
    {
        foreach (var seq in pending.Where(kv => now - kv.Value.Started > timeout).Select(kv => kv.Key).ToList())
        {
            pending.Remove(seq);
            Dropped++;
        }
    }
}

// Duplicate detection: the IDs of the messages seen in the last half hour, at most 4096 of them. A message that arrives
// twice – over two paths, or again when a computer reconnects – is shown and passed on once. Messages older than
// 15 minutes are refused anyway, so a copy can never come back after its ID was forgotten.
public sealed class DedupCache
{
    private readonly int capacity;
    private readonly double window;
    private readonly Dictionary<ulong, double> seen = new();
    private readonly List<(ulong Id, double Time)> order = new();      // oldest first
    private int head;

    public DedupCache(int capacity = 4096, double window = 30 * 60)
    {
        this.capacity = capacity;
        this.window = window;
    }

    public int Count => seen.Count;

    public bool Contains(ulong id, double now)
    {
        Purge(now);
        return seen.ContainsKey(id);
    }

    // true when it is new
    public bool Insert(ulong id, double now)
    {
        Purge(now);
        if (seen.ContainsKey(id)) return false;
        seen[id] = now;
        order.Add((id, now));
        while (seen.Count > capacity) DropOldest();
        return true;
    }

    private void Purge(double now)
    {
        while (head < order.Count && now - order[head].Time > window) DropOldest();
        if (head > 1024 && head * 2 > order.Count)
        {
            order.RemoveRange(0, head);
            head = 0;
        }
    }

    private void DropOldest()
    {
        if (head >= order.Count) return;
        var e = order[head];
        if (seen.TryGetValue(e.Id, out var t) && t == e.Time) seen.Remove(e.Id);
        head++;
    }
}
