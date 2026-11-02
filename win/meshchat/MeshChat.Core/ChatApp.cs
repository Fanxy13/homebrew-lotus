// MeshChat – the chat itself: the mesh on a queue of its own, the screen and the keys on the main thread, and the
// commands (/who, /nick, /status, /quit …). There is one chat – everyone nearby – and what is said in it goes into this
// computer's history. Closing the chat says goodbye, stops Bluetooth and gives the terminal back – nothing keeps
// running. As lib/meshchat/Sources/ChatApp.swift.

namespace MeshChat;

// What the system gives the chat: its radio, its doctor, its console
public interface IPlatform
{
    string Name { get; }                                            // "Windows"
    ILinkTransport? Radio(SerialQueue queue, Store store, out string why);     // null, and why, when there is none
    int Doctor(Store store);
    void PrepareConsole();                                          // escape codes on, UTF-8
}

public sealed class ChatApp
{
    private readonly Store? store;                  // null: the demo keeps nothing
    private readonly IPlatform platform;
    private readonly SerialQueue meshQueue = new("meshchat mesh");
    private readonly SerialQueue ui = new("meshchat screen", started: false);
    private MeshNode node = null!;
    private DemoWorld? demo;
    private readonly ChatViewState view = new();
    private readonly HashSet<ulong> seen = new();
    private bool drawQueued;
    private bool screenOn;
    private bool quitting;
    private (int Rows, int Cols) lastSize;
    private Timer? timer;

    private ChatApp(Store? store, IPlatform platform)
    {
        this.store = store;
        this.platform = platform;
        SerialQueue.Unhandled = e => store?.Log($"error: {e.GetType().Name}: {e.Message}");
    }

    private void SetUp(ILinkTransport transport, MeshConfig config, string nickname, Signer signer)
    {
        var world = demo;
        node = new MeshNode(transport, nickname, signer, e => ui.Post(() => Handle(e)), config,
                            clock: world != null ? () => world.Net.Now : null);
        view.Nickname = node.Nickname;
        view.Fingerprint = signer.Fingerprint;
    }

    // ── Starting ──────────────────────────────────────────────

    // The chat over Bluetooth. Bluetooth starts before the screen changes: what goes wrong is said in the terminal.
    public static int Bluetooth(Store store, MeshConfig config, IPlatform platform)
    {
        var app = new ChatApp(store, platform);
        var signer = Signer.FromIdentity(store.Identity());
        var radio = platform.Radio(app.meshQueue, store, out var why);
        if (radio == null)
        {
            Cli.Fail(why, "Try the chat without Bluetooth: meshchat demo");
            return 1;
        }
        app.SetUp(radio, config, store.Nickname ?? "anon", signer);
        store.TrimLog();
        store.Log($"chat started – MeshChat {Proto.Software}, {config.MaxLinks} links");
        app.OpenChat();
        app.meshQueue.Send(app.node.Start);
        var state = RadioState.Starting;
        var deadline = DateTime.UtcNow.AddSeconds(4);
        do
        {
            Thread.Sleep(100);
            state = app.meshQueue.Send(() => radio.State);
        } while (state == RadioState.Starting && DateTime.UtcNow < deadline);
        switch (state)
        {
            case RadioState.Unauthorized:
                Cli.Fail("Windows does not let MeshChat use Bluetooth", "Turn it on: Settings › Privacy & security › Radios (\"Let apps control device radios\"), then start MeshChat again. More: meshchat doctor");
                return 1;
            case RadioState.Unsupported:
                Cli.Fail("This computer has no Bluetooth Low Energy – MeshChat cannot run on it", "meshchat doctor says what Windows reports");
                return 1;
        }
        return app.Run();
    }

    // The demo: two simulated people, nothing over Bluetooth, nothing saved
    public static int Demo(string nickname, IPlatform platform)
    {
        var app = new ChatApp(null, platform);
        var world = new DemoWorld(app.meshQueue);
        app.demo = world;
        app.view.Demo = true;
        var config = new MeshConfig { PresenceInterval = 20 };
        // the simulated people must not have your name
        var name = DemoWorld.BotNames.Contains(nickname) ? $"{nickname} (you)" : nickname;
        // a random identity: the demo is not you, and keeps nothing
        app.SetUp(world.UserRadio(), config, name, Signer.FromIdentity(CryptoBackend.RandomBytes(32)));
        app.meshQueue.Send(() =>
        {
            app.node.Start();
            world.Start();
        });
        app.Notice("This is a demo: Ada and Grace are simulated on this computer, nothing goes over Bluetooth. Write something!");
        return app.Run();
    }

    private int Run()
    {
        platform.PrepareConsole();
        Screen.Enter();
        screenOn = true;
        new KeyReader(ui, Key).Start();
        timer = meshQueue.Every(1, () =>
        {
            if (demo != null) demo.Tick();
            else node.Tick();
            ui.Post(CheckSize);
        });
        lastSize = Term.Size();
        Draw();
        ui.Run();
        return 0;
    }

    // The history on the screen; messages in it that come again are not shown twice
    private void OpenChat()
    {
        if (store == null) return;
        store.TrimHistory();
        var (history, skipped) = store.History(300);
        foreach (var m in history)
        {
            view.Add(new ViewItem.Message(m.Message), Math.Min(m.Sent, m.Received));
            seen.Add(m.Id);
        }
        if (history.Count > 0) view.Add(new ViewItem.Divider("earlier messages above"), (view.Lines.Count > 0 ? view.Lines[^1].Order : 0) + 0.001);
        if (skipped > 0) Notice($"{skipped} damaged line{(skipped == 1 ? "" : "s")} in the history skipped.", NoticeLevel.Warning);
        var now = Now();
        var recent = history.Where(m => now - m.Sent < 1800).Select(m => m.Id).ToList();
        meshQueue.Send(() => node.MarkSeen(recent));
    }

    private static double Now() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;

    // ── Events of the mesh ────────────────────────────────────

    private void Handle(MeshEvent e)
    {
        switch (e)
        {
            case MeshEvent.Message { M: var m }:
                if (!seen.Add(m.Id)) return;
                view.Add(new ViewItem.Message(m), Math.Min(m.Sent, m.Received));
                store?.Append(m);
                break;
            case MeshEvent.Sent { Id: var id, Links: var links }:
                if (links == 0) view.Pending.Add(id);
                else view.Pending.Remove(id);
                break;
            case MeshEvent.NoticeEvent { N: var n }:
                view.Add(new ViewItem.NoticeItem(n), Now());
                break;
            case MeshEvent.Snapshot { S: var s }:
                view.Snapshot = s;
                break;
            case MeshEvent.Log { Text: var text }:
                store?.Log(text);
                break;
        }
        ScheduleDraw();
    }

    private void Notice(string text, NoticeLevel level = NoticeLevel.Info)
    {
        view.Add(new ViewItem.NoticeItem(new Notice(level, text)), Now());
        ScheduleDraw();
    }

    // ── Drawing ───────────────────────────────────────────────

    private void ScheduleDraw()
    {
        if (drawQueued) return;
        drawQueued = true;
        ui.Post(() =>
        {
            drawQueued = false;
            Draw();
        });
    }

    private void CheckSize()
    {
        var size = Term.Size();
        if (size == lastSize) return;
        lastSize = size;
        Term.Write("\u001b[2J");
        Draw();
    }

    private void Draw()
    {
        if (!screenOn) return;
        var (rows, cols) = Term.Size();
        Term.Write(ChatRender.Frame(view, rows, cols));
    }

    // ── Keys ──────────────────────────────────────────────────

    private void Key(Key k)
    {
        if (quitting) return;
        var page = Math.Max(1, Term.Size().Rows - 7);
        switch (k.Kind)
        {
            case KeyKind.Char: view.Editor.Insert(k.Text); break;
            case KeyKind.Enter: Submit(); break;
            case KeyKind.Backspace: view.Editor.Backspace(); break;
            case KeyKind.Delete: view.Editor.Delete(); break;
            case KeyKind.Left: view.Editor.Left(); break;
            case KeyKind.Right: view.Editor.Right(); break;
            case KeyKind.Home: case KeyKind.CtrlA: view.Editor.Home(); break;
            case KeyKind.End: case KeyKind.CtrlE: view.Editor.End(); break;
            case KeyKind.WordLeft: view.Editor.WordLeft(); break;
            case KeyKind.WordRight: view.Editor.WordRight(); break;
            case KeyKind.WordBackspace: case KeyKind.CtrlW: view.Editor.DeleteWordBack(); break;
            case KeyKind.CtrlU: view.Editor.KillToStart(); break;
            case KeyKind.CtrlK: view.Editor.KillToEnd(); break;
            case KeyKind.Up: view.Editor.Older(); break;
            case KeyKind.Down: view.Editor.Newer(); break;
            case KeyKind.PageUp: view.Scroll += page; break;
            case KeyKind.PageDown: view.Scroll = Math.Max(0, view.Scroll - page); break;
            case KeyKind.CtrlL: Term.Write("\u001b[2J"); break;
            case KeyKind.Esc:
                if (view.Editor.IsEmpty) view.Scroll = 0;
                else view.Editor.Clear();
                break;
            case KeyKind.CtrlC:
                if (view.Editor.IsEmpty) { Quit(); return; }
                view.Editor.Clear();
                break;
            case KeyKind.CtrlD:
                if (view.Editor.IsEmpty) { Quit(); return; }
                view.Editor.Delete();
                break;
            case KeyKind.Eof: Quit(); return;
            case KeyKind.Tab: Complete(); break;
        }
        Draw();
    }

    public static readonly string[] Commands = { "/help", "/who", "/where", "/nick", "/status", "/clear", "/quit" };

    private void Complete()
    {
        var t = view.Editor.Text;
        if (!t.StartsWith('/') || t.Contains(' ')) return;
        var fits = Commands.Where(c => c.StartsWith(t.ToLowerInvariant())).ToList();
        if (fits.Count == 1)
        {
            view.Editor.Clear();
            view.Editor.Insert(fits[0] + " ");
        }
        else if (fits.Count > 1)
        {
            Notice(string.Join("  ", fits));
        }
    }

    private void Submit()
    {
        var text = view.Editor.Commit().Trim(' ');
        if (text.Length == 0) return;
        view.Scroll = 0;
        if (text.StartsWith('/') && !text.StartsWith("//"))
        {
            Command(text);
            return;
        }
        var message = text.StartsWith("//") ? text[1..] : text;      // //like this sends "/like this"
        meshQueue.Post(() =>
        {
            try { node.Send(message); }
            catch (Exception e) when (e is MeshNode.SendError || e is WireError) { ui.Post(() => Notice(e.Message, NoticeLevel.Warning)); }
        });
    }

    // ── Commands ──────────────────────────────────────────────

    private void Command(string line)
    {
        var parts = line.Split(' ', 2);
        var cmd = parts[0].ToLowerInvariant();
        var arg = parts.Length > 1 ? parts[1].Trim(' ') : "";
        switch (cmd)
        {
            case "/help": case "/h": case "/?": Help(); break;
            case "/who": case "/people": case "/here": Who(); break;
            case "/where": case "/far": case "/distance": WhereIs(arg); break;
            case "/status": case "/mesh": case "/info": Status(); break;
            case "/nick": case "/name": Rename(arg); break;
            case "/clear": view.Lines.Clear(); break;
            case "/quit": case "/exit": case "/q": case "/bye": Quit(); break;
            case "/join": case "/create": case "/new": case "/invite": case "/code": case "/leave": case "/rooms": case "/room": case "/open":
                Notice("There are no rooms: everyone nearby with MeshChat is in this one chat, and everything in it is public.", NoticeLevel.Warning);
                break;
            default:
                Notice($"There is no {cmd} – /help lists the commands. To send a line starting with /, write //.", NoticeLevel.Warning);
                break;
        }
    }

    private void Help()
    {
        foreach (var line in new[]
        {
            "Everything you write goes to every computer nearby with MeshChat – Macs and Windows alike – and each one passes it on, as far as the mesh reaches. It is public.",
            "/who – who is here, and how: ● a direct Bluetooth link, ⇢2 two relays away, ○ not heard for a while",
            "/where <name> – how far someone is: from the signal strength, and the way through the mesh (/where alone: everyone)",
            "/nick <name> – your name · /status – Bluetooth and the mesh · /clear – an empty screen",
            "/quit (ctrl-c, ctrl-d) – close the chat · PgUp/PgDn scroll · ↑ your last lines · //text sends a line that starts with /",
        }) Notice(line);
    }

    private static string Ago(double t)
    {
        var s = (int)Math.Max(0, Now() - t);
        return s < 90 ? $"{s} s ago" : s < 5400 ? $"{s / 60} min ago" : $"{s / 3600} h ago";
    }

    private void Who()
    {
        var people = view.Snapshot.Participants;
        var here = people.Count(p => !p.Left);
        Notice($"Nearby: you and {here} other{(here == 1 ? "" : "s")} – you are {view.Nickname}·{view.Fingerprint}, with {view.Snapshot.Links} link{(view.Snapshot.Links == 1 ? "" : "s")}");
        foreach (var p in people)
        {
            string how;
            if (p.Left) how = "left the chat";
            else if (p.Away) how = $"away – last heard {Ago(p.LastSeen)}";
            else if (p.Direct) how = "a neighbour: a direct Bluetooth link" + (p.Signal is int sig ? ", " + Distance.Label(Distance.Metres(sig)) : "");
            else how = $"{p.Hops} relay{(p.Hops == 1 ? "" : "s")} away{(p.Via.Length == 0 ? "" : $" through {p.Via}")}, heard {Ago(p.LastSeen)}";
            Notice($"  {p.Nickname}·{p.Fingerprint} – {how}{(p.Links > 0 && !p.Left ? $" · {p.Links} link{(p.Links == 1 ? "" : "s")}" : "")}");
        }
        if (people.Count == 0) Notice("  No one else yet. On the other computers: meshchat (Windows) or lotus meshchat (Mac)");
        if (people.Select(p => p.Nickname).Distinct().Count() < people.Count)
            Notice("  Two people have the same name – the four letters after the dot tell them apart.", NoticeLevel.Warning);
    }

    // How far someone is: a neighbour from its signal, anyone else along the way through the mesh
    private void WhereIs(string query)
    {
        var people = view.Snapshot.Participants.Where(p => !p.Left).ToList();
        if (people.Count == 0)
        {
            Notice("No one else is here yet – nobody to measure.");
            return;
        }
        var q = query.ToLowerInvariant();
        var fits = q.Length == 0 ? people : people.Where(p => p.Nickname.ToLowerInvariant().StartsWith(q) || p.Fingerprint == q).ToList();
        if (fits.Count == 0)
        {
            Notice($"No one called {query} is here – /who lists who is.", NoticeLevel.Warning);
            return;
        }
        foreach (var p in fits)
        {
            var route = meshQueue.Send(() => node.Route(p.Key));
            Notice($"{p.Nickname}·{p.Fingerprint} – " + Describe(p, route));
            if (q.Length == 0) continue;
            if (route != null && route.Count > 1)
            {
                var way = "  you";
                foreach (var leg in route) way += $" → {leg.Name} " + (leg.Rssi is int r ? Distance.Label(Distance.Metres(r)) : "(not measured)");
                Notice(way);
            }
        }
        Notice("Estimated from Bluetooth signal strength – walls, bodies and how a computer is turned make it twice or half as far.");
    }

    public static string Describe(Participant p, List<RouteLeg>? route)
    {
        if ((p.Direct || p.Hops == 0) && (p.Signal ?? route?.FirstOrDefault().Rssi) is int rssi)
        {
            var m = Distance.Metres(rssi);
            return $"{Distance.Label(m)} from you, {Distance.Closeness(m)} (signal {rssi} dBm)";
        }
        if (p.Direct) return "a neighbour – its signal is not measured yet";
        var hops = $"{p.Hops} relay{(p.Hops == 1 ? "" : "s")} away";
        if (route == null || route.Count == 0) return hops + (p.Via.Length == 0 ? "" : $", through {p.Via}") + " – the way further is not known yet";
        var measured = route.Where(l => l.Rssi != null).Select(l => l.Rssi!.Value).ToList();
        var through = string.Join(", ", route.Take(route.Count - 1).Select(l => l.Name));
        if (measured.Count == route.Count)
        {
            var total = measured.Sum(Distance.Metres);
            return hops + (through.Length == 0 ? "" : $" through {through}") + $" – about {Distance.Label(total).Replace("≈ ", "")} along the way";
        }
        return hops + (through.Length == 0 ? "" : $" through {through}") + " – not every leg is measured yet";
    }

    private void Status()
    {
        var s = view.Snapshot;
        var st = s.Stats;
        Notice($"Bluetooth {s.Radio.Label()} · {s.Links} link{(s.Links == 1 ? "" : "s")}{(s.Connecting > 0 ? $" · connecting to {s.Connecting}" : "")} · {(s.Scanning ? "scanning" : "not scanning")} · {(s.Advertising ? "advertising" : "not advertising")}");
        Notice($"Messages shown {st.Delivered} · passed on {st.Relayed} · copies dropped {st.Duplicates} · caught up {st.CaughtUp}");
        Notice($"Refused: {st.Forged} forged or damaged · {st.Expired} too old or from the future · {st.Malformed} broken · {st.RateLimited} too many · {st.Incompatible} another version");
        Notice($"Your messages go up to {Proto.HopLimit} relays far – as far as there are computers to pass them on. You are {view.Nickname}·{view.Fingerprint}.");
        if (st.ConnectFailures > 0) Notice($"Connections that failed: {st.ConnectFailures} – meshchat doctor shows the last ones");
        if (store != null) Notice($"History: {Path.Combine(store.Dir, "history.jsonl")}");
    }

    private void Rename(string name)
    {
        var clean = Sanitize.Nickname(name);
        if (clean.Length == 0)
        {
            Notice($"You are {view.Nickname}. A new name: /nick <name> (up to 24 characters)");
            return;
        }
        store?.Set("NICKNAME", clean);
        view.Nickname = clean;
        meshQueue.Post(() => node.Rename(clean));
        Notice($"You are now {clean}.");
    }

    // ── Closing ───────────────────────────────────────────────

    // Goodbye to everyone and the neighbours, a moment for it to go out, then Bluetooth off and the terminal back
    private void Quit()
    {
        if (quitting) return;
        quitting = true;
        meshQueue.Send(node.Goodbye);
        ui.PostAfter(0.4, () =>
        {
            timer?.Dispose();
            meshQueue.Send(node.Stop);
            screenOn = false;
            Screen.Leave();
            Term.Line(demo != null ? "  That was the demo. The real chat: " + Theme.Key("meshchat") : "  MeshChat closed – " + Theme.Key("meshchat") + " opens it again.");
            store?.Log("chat closed");
            ui.Complete();
        });
    }

    // ── Relay mode ────────────────────────────────────────────

    // No chat on the screen: this computer only passes on what computers nearby send, so that it reaches further. It
    // says nothing itself, shows nothing and keeps nothing.
    public static int Relay(Store store, MeshConfig config, IPlatform platform)
    {
        config.Silent = true;
        var queue = new SerialQueue("meshchat relay");
        var radio = platform.Radio(queue, store, out var why);
        if (radio == null)
        {
            Cli.Fail(why);
            return 1;
        }
        var latest = new MeshSnapshot();
        // a relay never signs anything, so it needs no lasting identity
        var node = new MeshNode(radio, "relay", Signer.FromIdentity(CryptoBackend.RandomBytes(32)), e =>
        {
            if (e is MeshEvent.Snapshot s) latest = s.S;
            if (e is MeshEvent.Log l) store.Log(l.Text);
        }, config);
        platform.PrepareConsole();
        Term.Line();
        Term.Line("  " + Theme.Bold(Theme.Accent("lotus")) + Theme.Dim(" / ") + Theme.Bold("MeshChat relay") + Theme.Dim("  passes on what MeshChat computers nearby send"));
        Term.Line(Theme.Dim("  It shows nothing and keeps nothing. Ctrl-C stops it."));
        Term.Line();
        queue.Send(node.Start);
        using var timer = queue.Every(1, () =>
        {
            node.Tick();
            var s = latest;
            var line = $"  {(s.Radio == RadioState.On ? Theme.Green("●") : Theme.Yellow("●"))} Bluetooth {s.Radio.Label()} · {s.Links} link{(s.Links == 1 ? "" : "s")} · {s.Stats.Relayed} passed on · {s.Stats.Duplicates} copies dropped";
            Term.Write("\r\u001b[K" + line);
        });
        using var stop = new ManualResetEventSlim();
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            stop.Set();
        };
        stop.Wait();
        var relayed = queue.Send(() =>
        {
            node.Stop();
            return latest.Stats.Relayed;
        });
        Term.Line($"\n  Relay stopped – {relayed} messages passed on.");
        return 0;
    }
}
