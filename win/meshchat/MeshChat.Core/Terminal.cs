// MeshChat – the terminal: Lotus' colors, keys, the window's size, and the terminal given back as it was whatever
// ends the chat – /quit, Ctrl-C, a closed window. Windows Terminal and the console of Windows 10 and 11 understand the
// same escape codes as a Mac's terminal once they are switched on (the Windows app does that before the chat starts).
// As lib/meshchat/Sources/Terminal.swift.

using System.Globalization;
using System.Text;

namespace MeshChat;

// The theme's colors as Lotus gives them to its programs (LOTUS_COLOR_KEY=38;5;150 …); only digits and ;
public static class Theme
{
    public static bool Enabled = !Console.IsOutputRedirected && Environment.GetEnvironmentVariable("NO_COLOR") == null;

    private static string Sgr(string name, string fallback)
    {
        var v = Environment.GetEnvironmentVariable(name) ?? "";
        var ok = v.Length > 0 && v.Length < 40 && v.All(c => char.IsAsciiDigit(c) || c == ';');
        return ok ? v : fallback;
    }

    public static readonly string KeyCode = Sgr("LOTUS_COLOR_KEY", "38;5;150");
    public static readonly string AccentCode = Sgr("LOTUS_COLOR_ACCENT", "38;5;218");
    public static readonly string DimCode = Sgr("LOTUS_COLOR_DIM", "38;5;245");

    public static string Paint(string code, string s) => Enabled ? $"\u001b[{code}m{s}\u001b[0m" : s;
    public static string Key(string s) => Paint(KeyCode, s);
    public static string Accent(string s) => Paint(AccentCode, s);
    public static string Dim(string s) => Paint(DimCode, s);
    public static string Bold(string s) => Paint("1", s);
    public static string Red(string s) => Paint("38;5;203", s);
    public static string Green(string s) => Paint("38;5;114", s);
    public static string Yellow(string s) => Paint("38;5;179", s);

    // A color per person, from their fingerprint – the same for them on every computer, Mac or Windows
    private static readonly string[] People = { "38;5;117", "38;5;180", "38;5;151", "38;5;218", "38;5;222", "38;5;147", "38;5;174", "38;5;116" };

    public static string Person(string fingerprint, string s)
    {
        var n = 0;
        foreach (var r in fingerprint.EnumerateRunes()) n = unchecked(n * 31 + r.Value) & 0xFFFF;
        return Paint(People[n % People.Length], s);
    }
}

public static class Term
{
    private static Stream? stdout;
    private static readonly object writeLock = new();

    public static bool IsTTY => !Console.IsInputRedirected && !Console.IsOutputRedirected;

    public static (int Rows, int Cols) Size()
    {
        try
        {
            int rows = Console.WindowHeight, cols = Console.WindowWidth;
            if (rows > 0 && cols > 0) return (rows, cols);
        }
        catch (Exception) { }
        int.TryParse(Environment.GetEnvironmentVariable("LINES"), out var r);
        int.TryParse(Environment.GetEnvironmentVariable("COLUMNS"), out var c);
        return (r > 0 ? r : 24, c > 0 ? c : 80);
    }

    // Everything, as UTF-8, in one piece
    public static void Write(string s)
    {
        lock (writeLock)
        {
            stdout ??= Console.OpenStandardOutput();
            var bytes = Encoding.UTF8.GetBytes(s);
            try
            {
                stdout.Write(bytes, 0, bytes.Length);
                stdout.Flush();
            }
            catch (IOException) { }
        }
    }

    public static void Line(string s = "") => Write(s + "\n");
}

// The chat's screen: the alternate screen, keys without echo, Ctrl-C as a key
public static class Screen
{
    private const string LeaveSequence = "\u001b[?25h\u001b[0m\u001b[?1049l";
    private static bool active;
    private static bool installed;

    public static void Enter()
    {
        if (active || Console.IsInputRedirected) return;
        active = true;
        try { Console.TreatControlCAsInput = true; } catch (Exception) { }
        Term.Write("\u001b[?1049h\u001b[H\u001b[2J");
        if (installed) return;
        installed = true;
        AppDomain.CurrentDomain.ProcessExit += (_, _) => Leave();
    }

    public static void Leave()
    {
        if (!active) return;
        active = false;
        try { Console.TreatControlCAsInput = false; } catch (Exception) { }
        Term.Write(LeaveSequence);
    }
}

// ── Keys ──────────────────────────────────────────────────────

public enum KeyKind
{
    Char, Enter, Backspace, Delete, Tab, Esc,
    Left, Right, Up, Down, Home, End, PageUp, PageDown, WordLeft, WordRight, WordBackspace,
    CtrlA, CtrlC, CtrlD, CtrlE, CtrlK, CtrlL, CtrlU, CtrlW,
    Unknown, Eof,
}

public readonly record struct Key(KeyKind Kind, string Text = "");

// Reads the keyboard on a thread of its own and hands each key to `handler` on the screen's queue
public sealed class KeyReader
{
    private readonly SerialQueue queue;
    private readonly Action<Key> handler;

    public KeyReader(SerialQueue queue, Action<Key> handler)
    {
        this.queue = queue;
        this.handler = handler;
    }

    public void Start()
    {
        var t = new Thread(Loop) { IsBackground = true, Name = "meshchat keys" };
        t.Start();
    }

    private void Loop()
    {
        while (true)
        {
            Key key;
            try
            {
                var k = Console.ReadKey(intercept: true);
                key = Decode(k);
                if (key.Kind == KeyKind.Char && key.Text.Length == 1 && char.IsHighSurrogate(key.Text[0]))
                {
                    // an emoji comes in two halves
                    var low = Console.ReadKey(intercept: true);
                    key = char.IsLowSurrogate(low.KeyChar) ? new Key(KeyKind.Char, key.Text + low.KeyChar) : new Key(KeyKind.Unknown);
                }
            }
            catch (Exception)
            {
                queue.Post(() => handler(new Key(KeyKind.Eof)));
                return;
            }
            var k2 = key;
            queue.Post(() => handler(k2));
        }
    }

    public static Key Decode(ConsoleKeyInfo k)
    {
        var ctrl = (k.Modifiers & ConsoleModifiers.Control) != 0;
        var alt = (k.Modifiers & ConsoleModifiers.Alt) != 0;
        switch (k.Key)
        {
            case ConsoleKey.Enter: return new Key(KeyKind.Enter);
            case ConsoleKey.Backspace: return new Key(ctrl || alt ? KeyKind.WordBackspace : KeyKind.Backspace);
            case ConsoleKey.Delete: return new Key(KeyKind.Delete);
            case ConsoleKey.Tab: return new Key(KeyKind.Tab);
            case ConsoleKey.Escape: return new Key(KeyKind.Esc);
            case ConsoleKey.LeftArrow: return new Key(ctrl || alt ? KeyKind.WordLeft : KeyKind.Left);
            case ConsoleKey.RightArrow: return new Key(ctrl || alt ? KeyKind.WordRight : KeyKind.Right);
            case ConsoleKey.UpArrow: return new Key(KeyKind.Up);
            case ConsoleKey.DownArrow: return new Key(KeyKind.Down);
            case ConsoleKey.Home: return new Key(KeyKind.Home);
            case ConsoleKey.End: return new Key(KeyKind.End);
            case ConsoleKey.PageUp: return new Key(KeyKind.PageUp);
            case ConsoleKey.PageDown: return new Key(KeyKind.PageDown);
        }
        if (ctrl || (k.KeyChar >= '\u0001' && k.KeyChar <= '\u001a'))
        {
            var letter = k.KeyChar >= '\u0001' && k.KeyChar <= '\u001a' ? (char)('a' + k.KeyChar - 1) : char.ToLowerInvariant((char)k.Key);
            switch (letter)
            {
                case 'a': return new Key(KeyKind.CtrlA);
                case 'c': return new Key(KeyKind.CtrlC);
                case 'd': return new Key(KeyKind.CtrlD);
                case 'e': return new Key(KeyKind.CtrlE);
                case 'h': return new Key(KeyKind.Backspace);
                case 'i': return new Key(KeyKind.Tab);
                case 'j': case 'm': return new Key(KeyKind.Enter);
                case 'k': return new Key(KeyKind.CtrlK);
                case 'l': return new Key(KeyKind.CtrlL);
                case 'u': return new Key(KeyKind.CtrlU);
                case 'w': return new Key(KeyKind.CtrlW);
            }
            return new Key(KeyKind.Unknown);
        }
        if (k.KeyChar == '\0' || char.IsControl(k.KeyChar)) return new Key(KeyKind.Unknown);
        return new Key(KeyKind.Char, k.KeyChar.ToString());
    }
}

// ── Widths ────────────────────────────────────────────────────

public static class Cells
{
    // The characters of a string as a person counts them (é, 🌸 and 👍🏽 are one each)
    public static IEnumerable<string> Graphemes(string s)
    {
        var e = StringInfo.GetTextElementEnumerator(s);
        while (e.MoveNext()) yield return e.GetTextElement();
    }

    // Cells a character takes in the terminal: wide CJK and emoji take two, combining marks none
    public static int Width(string ch, bool grapheme)
    {
        if (ch.Length == 0) return 0;
        var v = char.IsSurrogatePair(ch, 0) ? char.ConvertToUtf32(ch, 0) : ch[0];
        if (v == 0 || (v >= 0x300 && v <= 0x36F) || v == 0x200D || (v >= 0xFE00 && v <= 0xFE0F)) return 0;
        if (v < 0x1100) return 1;
        if ((v >= 0x1100 && v <= 0x115F) || (v >= 0x2E80 && v <= 0xA4CF) || (v >= 0xAC00 && v <= 0xD7A3)
            || (v >= 0xF900 && v <= 0xFAFF) || (v >= 0xFE30 && v <= 0xFE4F) || (v >= 0xFF00 && v <= 0xFF60)
            || (v >= 0xFFE0 && v <= 0xFFE6) || (v >= 0x1F300 && v <= 0x1FAFF) || (v >= 0x20000 && v <= 0x3FFFD))
            return 2;
        return 1;
    }

    public static int Width(string s) => Graphemes(s).Sum(g => Width(g, true));

    // Width of a string with color codes in it
    public static int Visible(string s)
    {
        var w = 0;
        var inEscape = false;
        foreach (var ch in Graphemes(s))
        {
            if (inEscape)
            {
                if (ch.Length == 1 && ch[0] >= 0x40 && ch[0] <= 0x7E && ch != "[") inEscape = false;
                continue;
            }
            if (ch == "\u001b")
            {
                inEscape = true;
                continue;
            }
            w += Width(ch, true);
        }
        return w;
    }

    // A plain string cut to so many cells, with … when it was longer
    public static string Clip(string s, int cells)
    {
        if (cells <= 0) return "";
        if (Width(s) <= cells) return s;
        var sb = new StringBuilder();
        var w = 0;
        foreach (var ch in Graphemes(s))
        {
            var cw = Width(ch, true);
            if (w + cw > cells - 1) break;
            sb.Append(ch);
            w += cw;
        }
        return sb + "…";
    }

    // A string with color codes cut to so many cells; the codes stay, and the color is reset at the end
    public static string Fit(string s, int cells)
    {
        if (Visible(s) <= cells) return s;
        var sb = new StringBuilder();
        var w = 0;
        var inEscape = false;
        foreach (var ch in Graphemes(s))
        {
            if (inEscape)
            {
                sb.Append(ch);
                if (ch.Length == 1 && ch[0] >= 0x40 && ch[0] <= 0x7E && ch != "[") inEscape = false;
                continue;
            }
            if (ch == "\u001b")
            {
                inEscape = true;
                sb.Append(ch);
                continue;
            }
            var cw = Width(ch, true);
            if (w + cw > cells) break;
            sb.Append(ch);
            w += cw;
        }
        return sb + "\u001b[0m";
    }

    // Plain text in lines of at most `width` cells, broken at spaces where it can
    public static List<string> Wrap(string s, int width)
    {
        width = Math.Max(2, width);
        var lines = new List<string>();
        var line = new StringBuilder();
        var lineW = 0;
        foreach (var word in s.Split(' '))
        {
            var ww = Width(word);
            if (lineW > 0 && lineW + 1 + ww > width)
            {
                lines.Add(line.ToString());
                line.Clear();
                lineW = 0;
            }
            if (ww > width)
            {
                // a word longer than the line: cut it
                foreach (var ch in Graphemes(word))
                {
                    var cw = Width(ch, true);
                    if (lineW + cw > width)
                    {
                        lines.Add(line.ToString());
                        line.Clear();
                        lineW = 0;
                    }
                    line.Append(ch);
                    lineW += cw;
                }
                continue;
            }
            if (lineW > 0)
            {
                line.Append(' ');
                lineW += 1;
            }
            line.Append(word);
            lineW += ww;
        }
        lines.Add(line.ToString());
        return lines;
    }
}
