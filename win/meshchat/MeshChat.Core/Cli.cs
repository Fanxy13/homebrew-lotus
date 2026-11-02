// MeshChat – the command: meshchat [history|nick|set|relay|doctor|demo|selftest|version|help]. Without a word: the
// chat. As lib/meshchat/Sources/App.swift; on Windows it is a program of its own, meshchat.exe.

namespace MeshChat;

public static class Cli
{
    public static int Run(string[] args, IPlatform platform)
    {
        var words = new List<string>();
        var flags = new HashSet<string>();
        var values = new Dictionary<string, string>();
        for (var i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if ((a == "--links" || a == "-n") && i + 1 < args.Length)
            {
                values[a] = args[++i];
                continue;
            }
            if (a.StartsWith("--")) flags.Add(a);
            else words.Add(a);
        }
        var rest = string.Join(" ", words.Skip(1));
        var store = Store.Standard();
        platform.PrepareConsole();
        switch ((words.FirstOrDefault() ?? "chat").ToLowerInvariant())
        {
            case "chat": case "open": return Chat(store, values, platform);
            case "history": return History(store, values);
            case "nick": case "name": return Nick(store, rest);
            case "set": return Set(store, words);
            case "doctor": return platform.Doctor(store);
            case "demo":
                if (!Term.IsTTY)
                {
                    Fail("The demo needs a terminal window");
                    return 1;
                }
                return ChatApp.Demo(store.Nickname ?? "You", platform);
            case "relay": return ChatApp.Relay(store, Config(store, values), platform);
            case "selftest": case "test": case "tests": return SelfTest.Run();
            case "version": case "--version": case "-v":
                Term.Line($"MeshChat {Proto.Release} for {platform.Name} – protocol {Proto.Version}, crypto {CryptoBackend.Name}");
                return 0;
            case "help": case "-h": case "--help": case "/?":
                Help();
                return 0;
            case "create": case "new": case "join": case "rooms": case "list": case "ls": case "invite": case "code": case "leave": case "forget":
                Fail("MeshChat has no rooms", "Everyone nearby with MeshChat is in one chat, and it is public: meshchat");
                return 2;
            default:
                Fail($"There is no \"meshchat {words[0]}\"", "meshchat help lists what it can do");
                return 2;
        }
    }

    // ── Saying things ─────────────────────────────────────────

    public static void Fail(string text, string hint = "")
    {
        Term.Line();
        Term.Line("  " + Theme.Red("✗ " + text));
        if (hint.Length > 0) Term.Line("    " + Theme.Dim(hint));
        Term.Line();
    }

    private static void Ok(string text) => Term.Line("  " + Theme.Bold(Theme.Key("✓")) + " " + text);

    public static void Header(string subtitle)
    {
        Term.Line();
        Term.Line("  " + Theme.Bold(Theme.Accent("lotus")) + Theme.Dim(" / ") + Theme.Bold("MeshChat") + Theme.Dim("  " + subtitle));
        Term.Line();
    }

    private static void Help()
    {
        Header("one chat with everyone nearby, over Bluetooth – no internet, no server");
        foreach (var (c, d) in new[]
        {
            ("meshchat", "the chat – everything in it goes to every computer with MeshChat nearby"),
            ("meshchat history", "what was said while your chat was open (-n 50: the last 50)"),
            ("meshchat nick <name>", "your name in the chat"),
            ("meshchat set links 1–8", "Bluetooth links at most (8)"),
            ("meshchat relay", "only pass on what computers nearby send – one in between, for range"),
            ("meshchat doctor", "why Bluetooth does not work, and what Windows says about it"),
            ("meshchat demo", "try the chat with two simulated people – no Bluetooth"),
            ("meshchat selftest", "the protocol tests, on this computer"),
        })
        {
            Term.Line("    " + Theme.Key(c.PadRight(26)) + Theme.Dim(d));
        }
        Term.Line();
        Term.Line("  " + Theme.Dim("In the chat: /who /where /nick /status /clear /quit /help"));
        Term.Line("  " + Theme.Dim($"Every computer passes each message on, up to {Proto.HopLimit} relays far. It is public: anyone nearby can read it."));
        Term.Line("  " + Theme.Dim("Signed, so no one can write in your name. Windows and Macs chat together – MeshChat on each (lotus meshchat on a Mac)."));
        Term.Line();
    }

    // ── The chat ──────────────────────────────────────────────

    private static MeshConfig Config(Store store, Dictionary<string, string> values) => new()
    {
        MaxLinks = values.TryGetValue("--links", out var l) && int.TryParse(l, out var n) ? Math.Clamp(n, 1, 8) : store.MaxLinks,
    };

    // The first time: what MeshChat is, and a name
    private static bool EnsureNickname(Store store)
    {
        if (store.Nickname != null) return true;
        Header("one chat with everyone nearby");
        Term.Line("  What you write goes to every computer with MeshChat around you – Macs and Windows – and each one passes it on:");
        Term.Line("  no internet, no server. It is public: anyone nearby can read it. Signed, so no one can write in your name.");
        Term.Line();
        var user = Environment.UserName;
        var suggestion = Sanitize.Nickname(user.Length > 0 ? char.ToUpperInvariant(user[0]) + user[1..] : "");
        Term.Write($"  Your name in the chat{(suggestion.Length == 0 ? "" : $" [{suggestion}]")}: ");
        var answer = Console.ReadLine();
        if (answer == null) return false;
        var name = Sanitize.Nickname(answer.Trim().Length == 0 ? suggestion : answer);
        if (name.Length == 0) return false;
        store.Set("NICKNAME", name);
        return true;
    }

    private static int Chat(Store store, Dictionary<string, string> values, IPlatform platform)
    {
        if (!Term.IsTTY)
        {
            Fail("The chat needs a terminal window", "Without one: meshchat history – or meshchat help");
            return 1;
        }
        if (!store.Lock())
        {
            Fail("MeshChat is open already in another window", "One chat at a time on a computer – close the other one first");
            return 1;
        }
        if (!EnsureNickname(store)) return 1;
        return ChatApp.Bluetooth(store, Config(store, values), platform);
    }

    // ── History, settings ─────────────────────────────────────

    private static int History(Store store, Dictionary<string, string> values)
    {
        var n = values.TryGetValue("-n", out var v) && int.TryParse(v, out var k) ? k : 50;
        var (messages, skipped) = store.History(Math.Max(1, n));
        Header(messages.Count == 0 ? "history" : $"the last {messages.Count} message{(messages.Count == 1 ? "" : "s")}");
        foreach (var m in messages)
        {
            var when = DateTimeOffset.FromUnixTimeMilliseconds((long)(m.Sent * 1000)).ToLocalTime().ToString("yyyy-MM-dd HH:mm");
            var who = m.Mine ? Theme.Accent(m.Nickname) : Theme.Person(m.Fingerprint, m.Nickname);
            Term.Line("  " + Theme.Dim(when) + "  " + who + Theme.Dim($"·{m.Fingerprint}") + "  " + m.Text + (m.Hops > 0 ? Theme.Dim($" ⇢{m.Hops}") : ""));
        }
        if (messages.Count == 0) Term.Line("  " + Theme.Dim("Nothing said yet."));
        if (skipped > 0) Term.Line("  " + Theme.Yellow("! ") + $"{skipped} damaged line{(skipped == 1 ? "" : "s")} skipped");
        Term.Line();
        return 0;
    }

    private static int Nick(Store store, string name)
    {
        if (name.Length == 0)
        {
            Term.Line("  " + (store.Nickname is string n ? $"You are {Theme.Accent(n)} in the chat." : "No name yet – meshchat nick <name>"));
            return 0;
        }
        var clean = Sanitize.Nickname(name);
        if (clean.Length == 0)
        {
            Fail("That name has nothing visible in it");
            return 2;
        }
        store.Set("NICKNAME", clean);
        Ok($"You are {clean} in the chat" + (clean != name.Trim() ? Theme.Dim("  (made fit: at most 24 characters, no control characters)") : ""));
        return 0;
    }

    private static int Set(Store store, List<string> words)
    {
        if (words.Count < 3)
        {
            Term.Line($"  links {store.MaxLinks}" + Theme.Dim("  – meshchat set links <1–8>"));
            return words.Count == 1 ? 0 : 2;
        }
        var value = words[2].ToLowerInvariant();
        switch (words[1].ToLowerInvariant())
        {
            case "links":
                if (!int.TryParse(value, out var n) || n < 1 || n > 8)
                {
                    Fail("links is a number from 1 to 8");
                    return 2;
                }
                store.Set("LINKS", n.ToString());
                Ok($"At most {n} Bluetooth link{(n == 1 ? "" : "s")}");
                return 0;
            case "hops": case "relay":
                Fail($"{words[1].ToLowerInvariant()} is no setting",
                     $"Every computer with MeshChat passes every message on, as far as the mesh reaches (up to {Proto.HopLimit} relays)");
                return 2;
            default:
                Fail($"There is no setting \"{words[1]}\"", "links");
                return 2;
        }
    }
}
