// MeshChat tests – what it keeps, how far someone is, and the screen. As lib/meshchat/Tests/StoreTests.swift,
// DistanceTests.swift and ViewTests.swift.

using System.Text.RegularExpressions;
using static MeshChat.TestRun;

namespace MeshChat;

public static class StoreTests
{
    private static Store Fresh()
    {
        var dir = Path.Combine(Path.GetTempPath(), "meshchat-test-" + Guid.NewGuid().ToString("N"));
        return new Store(dir);
    }

    public static void Run()
    {
        Test("settings: one key changed, the other lines kept, values checked", () =>
        {
            var s = Fresh();
            File.WriteAllText(s.PathOf("settings"), "# mine\nOTHER=keep me\nLINKS=5\n");
            s.Set("NICKNAME", "Ada");
            s.Set("LINKS", "3");
            var text = File.ReadAllText(s.PathOf("settings"));
            Check(text.Contains("OTHER=keep me") && text.Contains("# mine"), "other lines stay");
            CheckEqual(s.Nickname, "Ada", "the name");
            CheckEqual(s.MaxLinks, 3, "links");
            s.Set("LINKS", "99");
            CheckEqual(s.MaxLinks, 8, "links over 8 are taken as 8");
            s.Set("NICKNAME", "\u001b[31m");
            CheckEqual(s.Nickname, "[31m", "a name is made safe when read");
            Directory.Delete(s.Dir, true);
        });

        Test("identity: made once, kept; a damaged one is replaced", () =>
        {
            var s = Fresh();
            var a = s.Identity();
            CheckEqual(a.Length, 32, "32 bytes");
            CheckBytes(s.Identity(), a, "the same the second time");
            if (!OperatingSystem.IsWindows()) CheckEqual(File.GetUnixFileMode(s.PathOf("identity")) & (UnixFileMode)0x1FF, UnixFileMode.UserRead | UnixFileMode.UserWrite, "readable by you only");
            File.WriteAllText(s.PathOf("identity"), "broken");
            var b = s.Identity();
            Check(b.Length == 32 && !B.Eq(a, b), "a damaged identity is replaced by a new one");
            Directory.Delete(s.Dir, true);
        });

        Test("history: written as it comes, read back, damaged lines skipped, kept short", () =>
        {
            var s = Fresh();
            for (var i = 0; i < 5; i++) s.Append(new ChatMessage((ulong)(i + 1), "Ada", "k3f9", $"message {i}", 1_700_000_000 + i, 1_700_000_001 + i, i % 2, i == 0));
            File.AppendAllText(s.PathOf("history.jsonl"), "not json\n{\"id\":\"zz\"}\n");
            s.Append(new ChatMessage(3, "Ada", "k3f9", "message 2 again", 1_700_000_010, 1_700_000_010, 0, false));
            var (messages, skipped) = s.History(50);
            CheckList(messages.Select(m => m.Text), new[] { "message 0", "message 1", "message 2", "message 3", "message 4" }, "in order, the same message once");
            CheckEqual(skipped, 2, "two damaged lines skipped");
            Check(messages[0].Mine && !messages[1].Mine && messages[1].Hops == 1, "who wrote it and how far it came");
            CheckEqual(s.History(2).Messages.Count, 2, "the last ones only, when asked");
            var line = Store.Encode(new ChatMessage(0xAB, "Bob", "x1y2", "a \"quote\" and ü", 1.5, 2.5, 3, false));
            CheckEqual(line, "{\"fp\":\"x1y2\",\"hops\":3,\"id\":\"00000000000000ab\",\"me\":false,\"nick\":\"Bob\",\"rx\":2500,\"t\":1500,\"text\":\"a \\\"quote\\\" and ü\",\"v\":1}", "the keys in the Mac's order");
            var back = Store.Decode("{\"id\":\"00000000000000aa\",\"t\":1761570000000,\"rx\":1761570000000,\"nick\":\"Bob\",\"fp\":\"k3f9\",\"text\":\"see you at \\u001b[31mthe bridge\",\"hops\":2,\"me\":false,\"v\":1}");
            CheckEqual(back?.Text, "see you at [31mthe bridge", "a line a Mac wrote is read, and an escape code in it taken out");
            for (var i = 0; i < Store.HistoryKeep * 2; i++) s.Append(new ChatMessage((ulong)(100 + i), "A", "a", "x", 1, 1, 0, false));
            s.TrimHistory();
            CheckEqual(File.ReadAllLines(s.PathOf("history.jsonl")).Length, Store.HistoryKeep, "kept to the last 2000");
            Directory.Delete(s.Dir, true);
        });

        Test("one chat at a time on a computer", () =>
        {
            var s = Fresh();
            Check(s.Lock(), "the first chat gets the lock");
            Check(!new Store(s.Dir).Lock(), "a second one does not");
        });
    }
}

public static class DistanceTests
{
    public static void Run()
    {
        Test("how far: signal strength to metres, and said no more exactly than it is known", () =>
        {
            Check(Math.Abs(Distance.Metres(-59) - 1) < 0.01, "−59 dBm is about a metre");
            Check(Distance.Metres(-80) > Distance.Metres(-70), "weaker is further");
            CheckEqual(Distance.Metres(-10), 0.3, "never closer than 30 cm");
            CheckEqual(Distance.Metres(-120), 100.0, "nor further than 100 m");
            CheckEqual(Distance.Label(0.5), "< 1 m", "< 1 m");
            CheckEqual(Distance.Label(3.4), "≈ 3 m", "metres while near");
            CheckEqual(Distance.Label(23), "≈ 25 m", "fives further away");
            CheckEqual(Distance.Label(80), "> 50 m", "and beyond 50 m no number");
            CheckEqual(Distance.Rssi(1), -59, "the simulated radio: 1 m is −59 dBm");
            CheckEqual(Distance.Short(2.2), "2m", "short, for the line of who is here");
        });

        Test("the way through the mesh: the fewest relays, then the shortest", () =>
        {
            var links = new Dictionary<uint, Dictionary<uint, int>>
            {
                [1] = new() { [2] = -60, [3] = -80 },
                [2] = new() { [1] = -60, [4] = -60 },
                [3] = new() { [1] = -80, [4] = -50 },
                [4] = new() { [2] = -60, [3] = -50, [5] = Distance.Unknown },
                [5] = new() { [4] = Distance.Unknown },
            };
            var way = Distance.Route(1, 4, links)!;
            CheckList(way.Select(w => w.Mac), new uint[] { 2, 4 }, "two legs either way – the shorter through 2");
            CheckEqual(way[0].Rssi, -60, "with the signal of each leg");
            var far = Distance.Route(1, 5, links)!;
            CheckEqual(far[^1].Rssi, (int?)null, "a leg not measured says so");
            Check(Distance.Route(1, 9, links) == null, "no way to someone unknown");
            Check(Distance.Route(1, 1, links)!.Count == 0, "and none to yourself");
        });

        Test("how far on the simulated radio: a neighbour by its signal, someone further along the way", () =>
        {
            var m = new TestMesh();
            foreach (var n in new[] { "A", "B", "C" }) m.Add(n);
            m.Net.SetRange("A", "B", true);
            m.Net.SetRange("B", "C", true);
            m.Net.SetDistance("A", "B", 2);
            m.Net.SetDistance("B", "C", 8);
            m.RunFor(60);
            var b = m.Person("B", "A");
            Check(b?.Signal is int sig && Math.Abs(Distance.Metres(sig) - 2) < 0.6, $"B, a neighbour, is about 2 m away ({b?.Signal} dBm)");
            var c = m.Person("C", "A")!;
            var route = m.Node("A").Route(c.Key);
            CheckList(route?.Select(l => l.Name) ?? Enumerable.Empty<string>(), new[] { "B", "C" }, "the way to C goes through B");
            Check(route != null && route[1].Rssi is int r2 && Math.Abs(Distance.Metres(r2) - 8) < 2, "and its second leg is about 8 m");
        });
    }
}

public static class ViewTests
{
    public static void Run()
    {
        Test("the line you write in: editing, words, history, limits", () =>
        {
            var e = new LineEditor();
            e.Insert("hello world");
            e.WordLeft();
            e.Insert("big ");
            CheckEqual(e.Text, "hello big world", "a word put in before the last one");
            e.End();
            e.DeleteWordBack();
            CheckEqual(e.Text, "hello big ", "a word taken out");
            e.Insert("\u001b[31mred\u0007");
            CheckEqual(e.Text, "hello big [31mred", "nothing that could change the terminal goes in");
            e.Insert("\ttab\nline");
            CheckEqual(e.Text, "hello big [31mred tab line", "tabs and line breaks become spaces");
            var sent = e.Commit();
            CheckEqual(sent, "hello big [31mred tab line", "Enter gives the line");
            Check(e.IsEmpty, "and empties it");
            e.Insert("draft");
            e.Older();
            CheckEqual(e.Text, sent, "↑ brings the last line back");
            e.Newer();
            CheckEqual(e.Text, "draft", "↓ the draft");
            e.Clear();
            e.Insert(new string('x', 2000));
            CheckEqual(e.Bytes, Proto.MaxTextBytes, "at most 1000 bytes");
            e.Clear();
            e.Insert("👍🏽é");
            CheckEqual(e.Chars.Count, 2, "an emoji with its skin tone and an é are one character each");
            e.Backspace();
            e.Backspace();
            Check(e.IsEmpty, "and go with one backspace each");
        });

        Test("text wrapped and cut to the window, wide characters counted twice", () =>
        {
            CheckList(Cells.Wrap("one two three four", 9), new[] { "one two", "three", "four" }, "broken at spaces");
            CheckList(Cells.Wrap("abcdefghij", 4), new[] { "abcd", "efgh", "ij" }, "a long word is cut");
            CheckEqual(Cells.Width("日本"), 4, "CJK takes two cells");
            CheckEqual(Cells.Width("🌸x"), 3, "an emoji too");
            CheckEqual(Cells.Width("é"), 1, "an accent none");
            CheckEqual(Cells.Clip("Margaretha", 5), "Marg…", "a name cut with …");
            CheckEqual(Cells.Visible(Theme.Paint("1", "abc")), 3, "color codes take no room");
            CheckEqual(Cells.Fit("\u001b[1mabcdef\u001b[0m", 3), "\u001b[1mabc\u001b[0m", "cut to the window, the codes kept");
        });

        Test("every frame fits the window, whatever its size", () =>
        {
            var s = new ChatViewState { Nickname = "Ada", Fingerprint = "k3f9" };
            s.Snapshot = new MeshSnapshot
            {
                Radio = RadioState.On, Links = 1,
                Participants = new()
                {
                    new Participant { Nickname = "Bob", Fingerprint = "x1y2", Direct = true, Signal = -62, Session = new byte[8] },
                    new Participant { Nickname = "Gracefully long name", Fingerprint = "q7r8", Hops = 2, Session = new byte[8] },
                },
            };
            for (var i = 0; i < 40; i++)
                s.Add(new ViewItem.Message(new ChatMessage((ulong)i, i % 3 == 0 ? "Bob" : "Ada", "x1y2", $"message {i} " + new string('w', i * 3) + " 日本 🌸", 1_700_000_000 + i, 1_700_000_000 + i, i % 2, i % 3 != 0)), 1_700_000_000 + i);
            s.Add(new ViewItem.NoticeItem(new Notice(NoticeLevel.Warning, "a notice that is long enough to need a second line in a narrow window")), 1_700_000_100);
            s.Editor.Insert("typing something 🌸");
            foreach (var (rows, cols) in new[] { (6, 20), (8, 30), (12, 40), (24, 80), (30, 100), (40, 120), (50, 200), (24, 31) })
            {
                var frame = ChatRender.Frame(s, rows, cols);
                var lines = frame.Split("\u001b[").Where(p => p.Length > 0 && char.IsAsciiDigit(p[0]) && p.Contains(";1H")).Select(p => p[(p.IndexOf('H') + 1)..]).ToList();
                var widest = lines.Select(l => Cells.Visible("\u001b[" + "0m" + l)).DefaultIfEmpty(0).Max();
                Check(widest <= cols, $"{rows} × {cols}: no row wider than the window ({widest})");
                Check(frame.Contains($"\u001b[{rows};"), $"{rows} × {cols}: the input line is on the last row");
            }
        });

        Test("the days: a line before each – Today, Yesterday, 3 days ago, 1 week ago – in the language of Lotus or Windows", () =>
        {
            var de = new (long Ago, string Says)[]
            {
                (-1, "Heute"), (0, "Heute"), (1, "Gestern"), (2, "vor 2 Tagen"), (6, "vor 6 Tagen"), (7, "vor 1 Woche"), (13, "vor 1 Woche"),
                (14, "vor 2 Wochen"), (29, "vor 4 Wochen"), (30, "vor 1 Monat"), (60, "vor 2 Monaten"), (364, "vor 11 Monaten"),
                (365, "vor 1 Jahr"), (800, "vor 2 Jahren"),
            };
            CheckList(de.Select(x => Days.Label(x.Ago, "de")), de.Select(x => x.Says), "in German, from today to years ago");
            var en = new (long Ago, string Says)[]
            {
                (0, "Today"), (1, "Yesterday"), (3, "3 days ago"), (7, "1 week ago"), (21, "3 weeks ago"), (45, "1 month ago"),
                (100, "3 months ago"), (400, "1 year ago"), (1000, "2 years ago"),
            };
            CheckList(en.Select(x => Days.Label(x.Ago, "en")), en.Select(x => x.Says), "in English");
            CheckList(new[] { Days.Label(1, "fr"), Days.Label(8, "fr"), Days.Label(3, "es") }, new[] { "Hier", "il y a 1 semaine", "hace 3 días" },
                "in French and Spanish");
            CheckEqual(Days.Label(1, "it"), "Yesterday", "a language without words of its own: English");
            CheckList(new[] { Days.Pick("de"), Days.Pick("de_CH"), Days.Pick("FR-ch"), Days.Pick("it"), Days.Pick("d"), Days.Pick(null) },
                new string?[] { "de", "de", "fr", null, null, null }, "the language as LOTUS_LANG says it");

            // midnight in this computer's time zone divides the days
            var midnight = new DateTimeOffset(DateTime.Today).ToUnixTimeMilliseconds() / 1000.0;
            var noon = midnight + 12 * 3600;
            CheckEqual(Days.Index(noon) - Days.Index(midnight + 60), 0L, "a minute after midnight is today");
            CheckEqual(Days.Index(noon) - Days.Index(midnight - 60), 1L, "a minute before it is yesterday");

            // the rows: a line before each day – 8 and 9 days ago are both 1 week ago – and the history's own line kept
            var s = new ChatViewState { Language = "de" };
            var ago = new[] { 9, 8, 2, 1, 1 };
            for (var i = 0; i < ago.Length; i++)
            {
                var t = noon - ago[i] * 86400.0 + i;
                s.Add(new ViewItem.Message(new ChatMessage((ulong)i, "Bob", "ab1c", $"message {i}", t, t, 0, false)), t);
            }
            s.Add(new ViewItem.Divider("earlier messages above"), noon - 86400 + 10);
            s.Add(new ViewItem.Message(new ChatMessage(9, "Ada", "k3f9", "and now", noon, noon, 0, true)), noon);
            s.Add(new ViewItem.NoticeItem(new Notice(NoticeLevel.Info, "Bob is here")), noon + 1);
            List<string> Plain(double now) => ChatRender.MessageRows(s, 60, now).Select(r => Regex.Replace(r, "\u001b\\[[0-9;]*m", "")).ToList();
            List<string> Rules(double now) => Plain(now).Where(r => r.Contains("───")).Select(r => r.Trim(' ', '─')).ToList();
            CheckList(Rules(noon + 60), new[] { "vor 1 Woche", "vor 2 Tagen", "Gestern", "earlier messages above", "Heute" }, "a line before each day, in German");
            var shown = Plain(noon + 60);
            Check(shown.Count > 0 && shown[0].Contains(" vor 1 Woche "), "the first row says the day of the oldest message");
            var at = shown.FindIndex(r => r.Contains(" Heute "));
            Check(at >= 0 && at + 1 < shown.Count && shown[at + 1].Contains("and now"), "today's message right under it");
            Check(shown.All(r => Cells.Visible(r) <= 60), "every line fits the window");
            CheckList(Rules(noon + 86400), new[] { "vor 1 Woche", "vor 3 Tagen", "vor 2 Tagen", "earlier messages above", "Gestern" },
                "the next day: what was today is yesterday");
            s.Language = "en";
            CheckList(Rules(noon + 60), new[] { "1 week ago", "2 days ago", "Yesterday", "earlier messages above", "Today" }, "in English");
            s.Lines.Clear();
            CheckList(Rules(noon), Array.Empty<string>(), "nothing said: no line");
            s.Add(new ViewItem.NoticeItem(new Notice(NoticeLevel.Info, "This is a demo")), noon);
            CheckList(Rules(noon), new[] { "Today" }, "a chat of today: one line on top");
        });
    }
}
