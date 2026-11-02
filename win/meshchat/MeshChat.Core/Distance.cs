// MeshChat – how far someone is, as lib/meshchat/Sources/Distance.swift. Bluetooth says how strong a computer's signal
// arrives (RSSI, in dBm): the weaker, the further. From it comes a rough distance, by the log-distance model: about
// −59 dBm at one metre, fading with the 2.5th power of the distance indoors. Walls, bodies and the Bluetooth chip
// easily make a computer seem twice or half as far – an estimate, and said as one.

namespace MeshChat;

public static class Distance
{
    public const double AtOneMetre = -59.0;
    public const double Fading = 2.5;
    public const int Unknown = 127;             // "no signal measured"

    public static double Metres(int rssi) => Math.Min(100, Math.Max(0.3, Math.Pow(10, (AtOneMetre - rssi) / (10 * Fading))));

    // The signal a computer so far away arrives with – for the simulated radio
    public static int Rssi(double metres) => (int)Math.Round(AtOneMetre - 10 * Fading * Math.Log10(Math.Max(0.1, metres)), MidpointRounding.AwayFromZero);

    public static string Label(double m)
    {
        if (m < 1) return "< 1 m";
        if (m < 10) return $"≈ {(int)Math.Round(m, MidpointRounding.AwayFromZero)} m";
        if (m <= 50) return $"≈ {(int)Math.Round(m / 5, MidpointRounding.AwayFromZero) * 5} m";
        return "> 50 m";
    }

    public static string Short(double m)
    {
        if (m < 1) return "<1m";
        if (m < 10) return $"{(int)Math.Round(m, MidpointRounding.AwayFromZero)}m";
        if (m <= 50) return $"{(int)Math.Round(m / 5, MidpointRounding.AwayFromZero) * 5}m";
        return ">50m";
    }

    public static string Closeness(double m) => m switch
    {
        < 1.5 => "right next to you",
        < 4 => "close",
        < 10 => "in the same room or near it",
        _ => "further away – or behind a wall",
    };

    // The way from one computer to another through links known to exist: the fewest relays first, then the shortest
    // estimated distance (a leg without a measured signal counts as 10 m). → the computers on the way, each with the
    // signal of the leg that reaches it; null when no way is known.
    public static List<(uint Mac, int? Rssi)>? Route(uint start, uint goal, Dictionary<uint, Dictionary<uint, int>> links)
    {
        if (start == goal) return new();
        static double Cost(int rssi) => rssi == Unknown ? 10 : Metres(rssi);
        var best = new Dictionary<uint, (int Hops, double Metres)> { [start] = (0, 0) };
        var previous = new Dictionary<uint, uint>();
        var open = new HashSet<uint> { start };
        var done = new HashSet<uint>();
        while (open.Count > 0)
        {
            var here = open.Aggregate((a, b) =>
            {
                var x = best[a];
                var y = best[b];
                return (x.Hops != y.Hops ? x.Hops < y.Hops : x.Metres < y.Metres) ? a : b;
            });
            open.Remove(here);
            done.Add(here);
            if (here == goal) break;
            var base_ = best[here];
            if (!links.TryGetValue(here, out var next)) continue;
            foreach (var (n, rssi) in next)
            {
                if (done.Contains(n)) continue;
                var candidate = (Hops: base_.Hops + 1, Metres: base_.Metres + Cost(rssi));
                if (best.TryGetValue(n, out var known) && (known.Hops < candidate.Hops || (known.Hops == candidate.Hops && known.Metres <= candidate.Metres))) continue;
                best[n] = candidate;
                previous[n] = here;
                open.Add(n);
            }
        }
        if (!best.ContainsKey(goal)) return null;
        var way = new List<(uint, int?)>();
        var at = goal;
        while (at != start && previous.TryGetValue(at, out var from))
        {
            var r = links.TryGetValue(from, out var l) && l.TryGetValue(at, out var v) ? v : Unknown;
            way.Insert(0, (at, r == Unknown ? null : r));
            at = from;
        }
        return way;
    }
}
