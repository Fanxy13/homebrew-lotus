// MeshChat – what the chat looks like: who you are on top, what is said with its time, who is here and how the mesh is
// doing below, and the line you write in. Drawn whole into the terminal's alternate screen, so the terminal is as it
// was when the chat ends. As lib/meshchat/Sources/ChatView.swift.
//
//   lotus / MeshChat  everyone nearby  public                                you: Ada·k3f9
//   ─────────────────────────────────────────────────────────────────────────────────────
//   ─────────────────────────────────────── Today ───────────────────────────────────────
//   14:02  Bob    Hi everyone
//   14:03  Carol  Hello from the other end of the field ⇢1
//   ── here: Bob ● · Carol ⇢1 ───────────────────────────────────────────────────────────
//   ● Bluetooth on · 1 link · 4 relayed                                /help · ctrl-c quits
//   › _

using System.Globalization;
using System.Text;

namespace MeshChat;

public sealed class LineEditor
{
    private readonly List<string> chars = new();
    private readonly List<string> history = new();
    private int? browsing;
    private List<string> draft = new();

    public IReadOnlyList<string> Chars => chars;
    public int Cursor { get; private set; }
    public string Text => string.Concat(chars);
    public bool IsEmpty => chars.Count == 0;
    public int Bytes => Encoding.UTF8.GetByteCount(Text);

    // Typed or pasted text: one line, nothing that could change the terminal, at most 1000 bytes
    public void Insert(string s)
    {
        foreach (var ch in Cells.Graphemes(s))
        {
            var runes = ch.EnumerateRunes().ToList();
            if (runes.Any(r => Sanitize.IsUnsafe(r.Value) && !Rune.IsWhiteSpace(r))) continue;
            var c = runes.Any(Rune.IsWhiteSpace) ? " " : ch;
            if (Bytes + Encoding.UTF8.GetByteCount(c) > Proto.MaxTextBytes) return;
            chars.Insert(Cursor, c);
            Cursor++;
        }
    }

    public void Backspace()
    {
        if (Cursor == 0) return;
        chars.RemoveAt(Cursor - 1);
        Cursor--;
    }

    public void Delete()
    {
        if (Cursor < chars.Count) chars.RemoveAt(Cursor);
    }

    public void Left() => Cursor = Math.Max(0, Cursor - 1);
    public void Right() => Cursor = Math.Min(chars.Count, Cursor + 1);
    public void Home() => Cursor = 0;
    public void End() => Cursor = chars.Count;

    public void Clear()
    {
        chars.Clear();
        Cursor = 0;
        browsing = null;
    }

    public void KillToEnd() => chars.RemoveRange(Cursor, chars.Count - Cursor);

    public void KillToStart()
    {
        chars.RemoveRange(0, Cursor);
        Cursor = 0;
    }

    public void WordLeft()
    {
        while (Cursor > 0 && chars[Cursor - 1] == " ") Cursor--;
        while (Cursor > 0 && chars[Cursor - 1] != " ") Cursor--;
    }

    public void WordRight()
    {
        while (Cursor < chars.Count && chars[Cursor] == " ") Cursor++;
        while (Cursor < chars.Count && chars[Cursor] != " ") Cursor++;
    }

    public void DeleteWordBack()
    {
        var end = Cursor;
        WordLeft();
        chars.RemoveRange(Cursor, end - Cursor);
    }

    // Enter: the line, kept for ↑
    public string Commit()
    {
        var t = Text;
        if (t.Trim().Length > 0 && (history.Count == 0 || history[^1] != t)) history.Add(t);
        if (history.Count > 100) history.RemoveAt(0);
        Clear();
        return t;
    }

    public void Older()
    {
        if (history.Count == 0) return;
        if (browsing == null)
        {
            draft = new List<string>(chars);
            browsing = history.Count;
        }
        if (browsing is not int b || b <= 0) return;
        browsing = b - 1;
        Replace(Cells.Graphemes(history[b - 1]));
    }

    public void Newer()
    {
        if (browsing is not int b) return;
        if (b + 1 >= history.Count)
        {
            browsing = null;
            Replace(draft);
        }
        else
        {
            browsing = b + 1;
            Replace(Cells.Graphemes(history[b + 1]));
        }
    }

    private void Replace(IEnumerable<string> with)
    {
        var list = with.ToList();
        chars.Clear();
        chars.AddRange(list);
        Cursor = chars.Count;
    }
}

public abstract record ViewItem
{
    public sealed record Message(ChatMessage M) : ViewItem;
    public sealed record NoticeItem(Notice N) : ViewItem;
    public sealed record Divider(string Text) : ViewItem;
}

public sealed record ViewLine(ViewItem Item, double Order);      // where it goes: a message by when it was written

// The days the chat's lines were written on, said in the language of Lotus or of Windows: a line across the window before
// each one – ── Today ──, ── Yesterday ──, ── 3 days ago ──, ── 1 week ago ── – drawn anew every time, so that at midnight
// Today becomes Yesterday. Within a week each day has its own line; further back the days go together by weeks, months and
// years, as their names do. As Days in lib/meshchat/Sources/ChatView.swift.
public static class Days
{
    //                  today, yesterday, days, 1 week, weeks, 1 month, months, 1 year, years – % is the number
    private static readonly Dictionary<string, string[]> Words = new()
    {
        ["en"] = new[] { "Today", "Yesterday", "% days ago", "1 week ago", "% weeks ago", "1 month ago", "% months ago", "1 year ago", "% years ago" },
        ["de"] = new[] { "Heute", "Gestern", "vor % Tagen", "vor 1 Woche", "vor % Wochen", "vor 1 Monat", "vor % Monaten", "vor 1 Jahr", "vor % Jahren" },
        ["fr"] = new[] { "Aujourd’hui", "Hier", "il y a % jours", "il y a 1 semaine", "il y a % semaines", "il y a 1 mois", "il y a % mois", "il y a 1 an", "il y a % ans" },
        ["es"] = new[] { "Hoy", "Ayer", "hace % días", "hace 1 semana", "hace % semanas", "hace 1 mes", "hace % meses", "hace 1 año", "hace % años" },
    };

    // en, de, fr or es: the language Lotus speaks (LOTUS_LANG), else the one the platform names (WindowsPlatform: the
    // language Windows is shown in), else English
    public static string Language { get; set; } = Pick(Environment.GetEnvironmentVariable("LOTUS_LANG")) ?? "en";

    // "de", "de_CH", "de-DE" → "de"; a language without words here → null
    public static string? Pick(string? code)
    {
        if (code == null || code.Length < 2) return null;
        var two = code[..2].ToLowerInvariant();
        return Words.ContainsKey(two) ? two : null;
    }

    // The day t is on in this computer's time zone: the days since 1 January 1970 there
    public static long Index(double t)
    {
        var offset = TimeZoneInfo.Local.GetUtcOffset(DateTimeOffset.FromUnixTimeMilliseconds((long)Math.Floor(t * 1000)));
        return (long)Math.Floor((t + offset.TotalSeconds) / 86400);
    }

    // What the line before a day says, d days before today – a clock that went back counts as today
    public static string Label(long d, string language)
    {
        var w = Words.TryGetValue(language, out var found) ? found : Words["en"];
        string Count(int i, long n) => w[i].Replace("%", n.ToString(CultureInfo.InvariantCulture));
        return d switch
        {
            <= 0 => w[0],
            1 => w[1],
            < 7 => Count(2, d),
            < 30 => d < 14 ? w[3] : Count(4, d / 7),
            < 365 => d < 60 ? w[5] : Count(6, Math.Min(11, d / 30)),
            _ => d < 730 ? w[7] : Count(8, d / 365),
        };
    }
}

// Everything the screen shows, as plain values – ChatApp fills it, ChatRender draws it
public sealed class ChatViewState
{
    public List<ViewLine> Lines = new();
    public string Nickname = "";
    public string Fingerprint = "";
    public bool Demo;
    public MeshSnapshot Snapshot = new();
    public HashSet<ulong> Pending = new();      // messages of ours that no other computer has yet
    public LineEditor Editor = new();
    public int Scroll;                          // rows scrolled up from the newest
    public string Language = Days.Language;     // the words of the lines between the days

    // A line in its place, by time; the oldest go when there are too many
    public void Add(ViewItem item, double order)
    {
        var i = Lines.Count;
        while (i > 0 && Lines[i - 1].Order > order) i--;
        Lines.Insert(i, new ViewLine(item, order));
        if (Lines.Count > 1500) Lines.RemoveRange(0, Lines.Count - 1500);
    }

    public List<Participant> OthersHere => Snapshot.Participants.Where(p => !p.Left).ToList();
}

public static class ChatRender
{
    public static string Time(double t) => DateTimeOffset.FromUnixTimeMilliseconds((long)(t * 1000)).ToLocalTime().ToString("HH:mm");

    // ──── a few words in the middle of a line across the window ────
    public static string Rule(string text, int width, Func<string, string>? paint = null)
    {
        var words = $" {text} ";
        var side = new string('─', Math.Max(2, (width - 2 - Cells.Width(words)) / 2));
        return " " + Theme.Dim(side) + (paint ?? Theme.Dim)(words) + Theme.Dim(side);
    }

    // All rows of the message area, oldest first, and before each day a line that says which: ── Yesterday ── – at the
    // time now (null: the clock's)
    public static List<string> MessageRows(ChatViewState s, int width, double? now = null)
    {
        var names = s.Lines.Select(l => l.Item).OfType<ViewItem.Message>().Select(m => m.M.Nickname).ToList();
        // " 14:02  " + the name + "  " + the text; narrow windows give the name less room
        var nameWidth = Math.Min(12, Math.Min(Math.Max(4, width / 5), Math.Max(4, names.Count == 0 ? 4 : names.Max(Cells.Width))));
        var indent = 8 + nameWidth + 2;
        var textWidth = Math.Max(4, width - indent - 1);
        var rows = new List<string>();
        var today = Days.Index(now ?? DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0);
        long? lastDay = null;           // the day of the line before, and what the line above it says
        string? lastLabel = null;
        foreach (var line in s.Lines)
        {
            // a line of another day: the line that says which, unless it says the same (8 and 9 days ago: 1 week ago);
            // the line between the history and now is on no day
            if (line.Item is not ViewItem.Divider)
            {
                var day = Days.Index(line.Order);
                if (day != lastDay)
                {
                    lastDay = day;
                    var label = Days.Label(today - day, s.Language);
                    if (label != lastLabel)
                    {
                        rows.Add(Rule(label, width, text => text));
                        lastLabel = label;
                    }
                }
            }
            switch (line.Item)
            {
                case ViewItem.Message { M: var m }:
                {
                    // after the text, dim: the relays it took, a late arrival, or that nobody has it yet
                    var extra = "";
                    if (m.Hops > 0) extra += $" ⇢{m.Hops}";
                    if (m.Received - m.Sent > 90 && !m.Mine) extra += $" (arrived {Time(m.Received)})";
                    if (m.Mine && s.Pending.Contains(m.Id)) extra += " · waiting for someone nearby";
                    var chunks = Cells.Wrap(m.Text, textWidth);
                    if (extra.Length > 0)
                    {
                        var last = chunks[^1];
                        chunks.RemoveAt(chunks.Count - 1);
                        if (Cells.Width(last) + Cells.Width(extra) <= textWidth)
                        {
                            chunks.Add(last + Theme.Dim(extra));
                        }
                        else
                        {
                            chunks.Add(last);
                            chunks.Add(Theme.Dim(extra[1..]));
                        }
                    }
                    var name = Cells.Clip(m.Nickname, nameWidth);
                    var pad = new string(' ', Math.Max(0, nameWidth - Cells.Width(name)));
                    var who = m.Mine ? Theme.Bold(Theme.Accent(name)) : Theme.Person(m.Fingerprint, name);
                    for (var i = 0; i < chunks.Count; i++)
                        rows.Add(i == 0 ? " " + Theme.Dim(Time(m.Sent)) + "  " + who + pad + "  " + chunks[i] : new string(' ', indent) + chunks[i]);
                    break;
                }
                case ViewItem.NoticeItem { N: var n }:
                {
                    Func<string, string> paint = n.Level == NoticeLevel.Error ? Theme.Red : n.Level == NoticeLevel.Warning ? Theme.Yellow : Theme.Dim;
                    var chunks = Cells.Wrap(n.Text, Math.Max(2, width - 10));
                    for (var i = 0; i < chunks.Count; i++)
                        rows.Add(i == 0 ? " " + Theme.Dim(Time(line.Order)) + "  " + paint("· " + chunks[i]) : new string(' ', 10) + paint(chunks[i]));
                    break;
                }
                case ViewItem.Divider { Text: var text }:
                    rows.Add(Rule(text, width));
                    break;
            }
        }
        return rows;
    }

    // What to do when nobody is there yet
    public static List<string> LonelyRows(ChatViewState s)
    {
        if (s.Demo) return new();
        var rows = new List<string> { "", "   " + Theme.Bold("No one else is here yet.") };
        switch (s.Snapshot.Radio)
        {
            case RadioState.On:
                rows.Add("   · On the other computers: " + Theme.Key("meshchat") + Theme.Dim(" on Windows, ") + Theme.Key("lotus meshchat") + Theme.Dim(" on a Mac – everyone nearby is in this chat"));
                rows.Add("   · Bluetooth on there too, within about 10 m – walls and bodies shorten that");
                rows.Add("   · Every computer with MeshChat passes messages on: one in between reaches further");
                rows.Add("   · Not working? Close the chat (ctrl-c) and run " + Theme.Key("meshchat doctor"));
                break;
            case RadioState.Off:
                rows.Add("   · Bluetooth is off – turn it on in Settings › Bluetooth & devices");
                break;
            case RadioState.Unauthorized:
                rows.Add("   · Windows does not let apps use Bluetooth – Settings › Privacy & security › Radios");
                break;
            case RadioState.Starting:
                rows.Add("   · Starting Bluetooth …");
                break;
            case RadioState.Unsupported:
                rows.Add("   · This computer has no Bluetooth Low Energy");
                break;
            case RadioState.Resetting:
                rows.Add("   · Bluetooth is restarting …");
                break;
        }
        return rows.Select(Theme.Dim).ToList();
    }

    public static string Header(ChatViewState s, int width)
    {
        var title = " " + Theme.Bold(Theme.Accent("lotus")) + Theme.Dim(" / ") + Theme.Bold("MeshChat");
        var place = "  " + Theme.Bold("everyone nearby");
        var note = Theme.Dim("  public");
        var demoLong = s.Demo ? "  " + Theme.Yellow("DEMO – simulated") : "";
        var demoShort = s.Demo ? "  " + Theme.Yellow("DEMO") : "";
        var you = Theme.Dim("you: ") + Theme.Accent(s.Nickname) + Theme.Dim($"·{s.Fingerprint}") + " ";
        var candidates = new (string Left, string Right)[]
        {
            (title + place + note + demoLong, you),
            (title + place + demoLong, you),
            (title + demoLong, you),
            (title + place + demoShort, you),
            (title + demoShort, you),
            (title + demoShort, Theme.Accent(s.Nickname) + " "),
            (title + demoShort, ""),
        };
        foreach (var (left, right) in candidates)
        {
            var gap = width - Cells.Visible(left) - Cells.Visible(right);
            if (gap >= 1) return left + new string(' ', gap) + right;
        }
        return title;
    }

    public static string PeopleRule(ChatViewState s, int width)
    {
        var people = s.OthersHere;
        string text;
        if (people.Count == 0)
        {
            text = Theme.Dim(" no one else here yet ");
        }
        else
        {
            var parts = new List<string>();
            var used = 10;
            for (var i = 0; i < people.Count; i++)
            {
                var p = people[i];
                var distance = p.Direct && p.Signal is int sig ? Theme.Dim(" " + Distance.Short(Distance.Metres(sig))) : "";
                var mark = p.Away ? Theme.Dim(" ○") : p.Direct ? Theme.Green(" ●") + distance : Theme.Dim($" ⇢{p.Hops}");
                var part = Theme.Person(p.Fingerprint, Cells.Clip(p.Nickname, 16)) + mark;
                var w = Cells.Visible(part) + 3;
                if (used + w > width - 16)
                {
                    parts.Add(Theme.Dim($"+{people.Count - i} more · /who"));
                    break;
                }
                parts.Add(part);
                used += w;
            }
            text = Theme.Dim(" here: ") + string.Join(Theme.Dim(" · "), parts) + " ";
        }
        var fill = Math.Max(0, width - 3 - Cells.Visible(text));
        return Theme.Dim(" ──") + text + Theme.Dim(new string('─', fill));
    }

    public static string Status(ChatViewState s, int width)
    {
        var snap = s.Snapshot;
        var left = snap.Radio switch
        {
            RadioState.On => Theme.Green(" ●") + " Bluetooth on",
            RadioState.Off => Theme.Red(" ●") + " Bluetooth is off – Settings › Bluetooth & devices",
            RadioState.Unauthorized => Theme.Red(" ●") + " Bluetooth not allowed – Settings › Privacy & security › Radios",
            RadioState.Unsupported => Theme.Red(" ●") + " No Bluetooth LE on this computer",
            RadioState.Starting => Theme.Yellow(" ●") + " Starting Bluetooth …",
            _ => Theme.Yellow(" ●") + " Bluetooth is restarting …",
        };
        if (s.Demo) left = Theme.Yellow(" ●") + " Simulated";
        if (snap.Radio == RadioState.On || s.Demo)
        {
            left += Theme.Dim($" · {snap.Links} link{(snap.Links == 1 ? "" : "s")}");
            if (snap.Connecting > 0) left += Theme.Dim(" · connecting");
            else if (snap.Scanning && snap.Links == 0) left += Theme.Dim(" · looking for computers nearby");
            if (snap.Stats.Relayed > 0) left += Theme.Dim($" · {snap.Stats.Relayed} relayed");
        }
        var right = Theme.Dim(s.Scroll > 0 ? "↓ PgDn · /help " : "/help · ctrl-c quits ");
        var gap = width - Cells.Visible(left) - Cells.Visible(right);
        return gap >= 1 ? left + new string(' ', gap) + right : left;
    }

    // The input line and where the cursor goes in it
    public static (string Line, int Column) Input(ChatViewState s, int width)
    {
        const string prompt = " › ";
        var room = Math.Max(4, width - 4 - (s.Editor.Bytes > 800 ? 6 : 0));
        var chars = s.Editor.Chars;
        // the part of the line around the cursor that fits
        var start = 0;
        while (Cells.Width(string.Concat(chars.Skip(start).Take(s.Editor.Cursor - start))) > room - 1) start++;
        var shown = new StringBuilder();
        var w = 0;
        foreach (var ch in chars.Skip(start))
        {
            var cw = Cells.Width(ch, true);
            if (w + cw > room) break;
            shown.Append(ch);
            w += cw;
        }
        var line = Theme.Accent(prompt) + shown;
        if (s.Editor.Bytes > 800) line += Theme.Dim($" {Proto.MaxTextBytes - s.Editor.Bytes}");
        var column = Cells.Width(prompt) + Cells.Width(string.Concat(chars.Skip(start).Take(s.Editor.Cursor - start))) + 1;
        return (line, column);
    }

    // The whole screen: rows × cols – at the time now (null: the clock's), for the lines between the days
    public static string Frame(ChatViewState s, int rows, int cols, double? now = null)
    {
        var out_ = new StringBuilder("\u001b[?2026h\u001b[?25l");
        // every row cut to the window: a row too wide would wrap and push the screen out of place
        void Put(int r, string text) => out_.Append($"\u001b[{r};1H").Append(Cells.Fit(text, cols)).Append("\u001b[0m\u001b[K");
        var tiny = rows < 8 || cols < 30;
        var top = tiny ? 1 : 3;
        var bottom = tiny ? rows - 1 : rows - 3;
        if (!tiny)
        {
            Put(1, Header(s, cols));
            Put(2, Theme.Dim(" " + new string('─', Math.Max(0, cols - 2))));
        }
        var height = Math.Max(1, bottom - top + 1);
        var content = MessageRows(s, cols, now);
        if (s.OthersHere.Count == 0) content.AddRange(LonelyRows(s));
        var scroll = Math.Min(s.Scroll, Math.Max(0, content.Count - height));
        var end = content.Count - scroll;
        var from = Math.Max(0, end - height);
        var visible = content.Skip(from).Take(Math.Max(0, end) - from).ToList();
        for (var i = 0; i < height; i++) Put(top + i, i < visible.Count ? visible[i] : "");
        if (!tiny)
        {
            Put(rows - 2, PeopleRule(s, cols));
            Put(rows - 1, Status(s, cols));
        }
        var (input, column) = Input(s, cols);
        Put(rows, input);
        out_.Append($"\u001b[{rows};{Math.Min(cols, column)}H\u001b[?25h\u001b[?2026l");
        return out_.ToString();
    }
}
