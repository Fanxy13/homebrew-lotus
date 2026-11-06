// MeshChat – what it keeps on this computer, all of it in its data folder: %LOCALAPPDATA%\lotus\data\meshchat on
// Windows ($LOTUS_MESHCHAT_DATA when set), the same files as on the Mac (lib/meshchat/Sources/Store.swift):
//   settings          NICKNAME=…, LINKS=8  (one KEY=value per line – other lines in it are left alone)
//   identity          this computer's secret its signing key comes from: 32 random bytes, hex
//   history.jsonl     what was said while the chat was open, one message per line (the last 2000)
//   events.log        links and errors, for meshchat doctor – never keys, names or messages
// On Windows the folder is in your profile, which only you can read; elsewhere folders are 0700 and files 0600.

using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace MeshChat;

public sealed class StoredMessage
{
    public ulong Id;
    public double Sent, Received;
    public string Nickname = "", Fingerprint = "", Text = "";
    public int Hops;
    public bool Mine;
    public bool Privately;          // a private message (/tell) – to this computer, or from it to To
    public string To = "";

    public ChatMessage Message => new(Id, Nickname, Fingerprint, Text, Sent, Received, Hops, Mine, Privately, To);
}

public sealed class Store
{
    public const int HistoryKeep = 2000;
    private static readonly UTF8Encoding Utf8 = new(false);
    private readonly object logLock = new();
    private FileStream? lockFile;

    public string Dir { get; }

    public Store(string dir)
    {
        Dir = dir;
        try
        {
            Directory.CreateDirectory(dir);
            if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(dir, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }
        catch (Exception) { }
    }

    // Lotus says where: LOTUS_MESHCHAT_DATA. Else Lotus' data folder of this system.
    public static Store Standard()
    {
        var d = Environment.GetEnvironmentVariable("LOTUS_MESHCHAT_DATA");
        if (!string.IsNullOrEmpty(d)) return new Store(d);
        if (OperatingSystem.IsWindows())
        {
            var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return new Store(Path.Combine(local, "lotus", "data", "meshchat"));
        }
        var xdg = Environment.GetEnvironmentVariable("XDG_DATA_HOME");
        var basePath = string.IsNullOrEmpty(xdg) ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "share") : xdg;
        return new Store(Path.Combine(basePath, "lotus", "meshchat"));
    }

    public string PathOf(string name) => Path.Combine(Dir, name);

    // Written whole or not at all, readable only by this user
    private void Write(string name, string text)
    {
        var path = PathOf(name);
        Directory.CreateDirectory(Dir);
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, text, Utf8);
        Private(tmp);
        File.Move(tmp, path, overwrite: true);
    }

    private static void Private(string path)
    {
        if (OperatingSystem.IsWindows()) return;
        try { File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite); } catch (Exception) { }
    }

    private string? Read(string name)
    {
        try { return File.ReadAllText(PathOf(name), Utf8); }
        catch (Exception) { return null; }
    }

    // ── Settings ──────────────────────────────────────────────
    // One KEY=value per line. Read line by line, never run.

    public Dictionary<string, string> Settings()
    {
        var out_ = new Dictionary<string, string>();
        var text = Read("settings");
        if (text == null) return out_;
        foreach (var line in text.Split('\n'))
        {
            var eq = line.IndexOf('=');
            if (eq < 0 || line.StartsWith('#')) continue;
            var k = line[..eq].Trim();
            if (k.Length == 0) continue;
            out_[k] = line[(eq + 1)..].TrimEnd('\r');
        }
        return out_;
    }

    // One key changed (null: removed), the other lines kept as they are
    public void Set(string key, string? value)
    {
        var lines = (Read("settings") ?? "").Split('\n', StringSplitOptions.RemoveEmptyEntries).ToList();
        lines.RemoveAll(l => l.StartsWith(key + "="));
        if (value != null) lines.Add($"{key}={value.Replace('\n', ' ')}");
        try { Write("settings", string.Join("\n", lines) + "\n"); } catch (Exception) { }
    }

    public string? Nickname
    {
        get
        {
            var n = Sanitize.Nickname(Settings().GetValueOrDefault("NICKNAME", ""));
            return n.Length == 0 ? null : n;
        }
    }

    public int MaxLinks => int.TryParse(Settings().GetValueOrDefault("LINKS", ""), out var n) ? Math.Clamp(n, 1, 8) : 8;

    // ── This computer's identity ──────────────────────────────
    // The secret the signing key comes from. Made once; a damaged file is replaced, and then the others see a new
    // fingerprint for you.

    public byte[] Identity()
    {
        var text = Read("identity");
        if (text != null && Hex.Decode(text.Trim()) is byte[] d && d.Length == 32) return d;
        var fresh = CryptoBackend.RandomBytes(32);
        try { Write("identity", Hex.Encode(fresh) + "\n"); } catch (Exception) { }
        return fresh;
    }

    // ── History ───────────────────────────────────────────────

    // The last messages, oldest first; damaged lines are skipped
    public (List<StoredMessage> Messages, int Skipped) History(int last = 500)
    {
        var text = Read("history.jsonl");
        if (text == null) return (new(), 0);
        var lines = text.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        var keep = Math.Max(last * 2, last + 100);
        var out_ = new List<StoredMessage>();
        var skipped = 0;
        foreach (var line in lines.Skip(Math.Max(0, lines.Length - keep)))
        {
            var m = Decode(line);
            if (m == null)
            {
                skipped++;
                continue;
            }
            out_.Add(m);
        }
        // in the order they were written, the same message once
        var seen = new HashSet<ulong>();
        out_ = out_.Where(m => seen.Add(m.Id)).ToList();
        return (out_.Skip(Math.Max(0, out_.Count - last)).ToList(), skipped);
    }

    public void Append(ChatMessage m)
    {
        try
        {
            Directory.CreateDirectory(Dir);
            var path = PathOf("history.jsonl");
            var created = !File.Exists(path);
            File.AppendAllText(path, Encode(m) + "\n", Utf8);
            if (created) Private(path);
        }
        catch (Exception) { }
    }

    // Keeps the last 2000 when there are many more
    public void TrimHistory()
    {
        var text = Read("history.jsonl");
        if (text == null) return;
        var lines = text.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        if (lines.Length <= HistoryKeep + HistoryKeep / 5) return;
        try { Write("history.jsonl", string.Join("\n", lines.Skip(lines.Length - HistoryKeep)) + "\n"); } catch (Exception) { }
    }

    private static readonly JsonWriterOptions JsonOptions = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    // The keys in the order the Mac writes them (sorted)
    public static string Encode(ChatMessage m)
    {
        using var ms = new MemoryStream();
        using (var w = new Utf8JsonWriter(ms, JsonOptions))
        {
            w.WriteStartObject();
            w.WriteString("fp", m.Fingerprint);
            w.WriteNumber("hops", m.Hops);
            w.WriteString("id", Hex.U64(m.Id));
            w.WriteBoolean("me", m.Mine);
            w.WriteString("nick", m.Nickname);
            // a private message: kept here as it was read – in the clear, in your data folder only
            if (m.Privately) w.WriteBoolean("pv", true);
            w.WriteNumber("rx", (long)(m.Received * 1000));
            w.WriteNumber("t", (long)(m.Sent * 1000));
            w.WriteString("text", m.Text);
            if (m.Privately && m.To.Length > 0) w.WriteString("to", m.To);
            w.WriteNumber("v", 1);
            w.WriteEndObject();
        }
        return Encoding.UTF8.GetString(ms.ToArray());
    }

    public static StoredMessage? Decode(string line)
    {
        try
        {
            using var doc = JsonDocument.Parse(line);
            var o = doc.RootElement;
            if (o.ValueKind != JsonValueKind.Object) return null;
            if (!o.TryGetProperty("id", out var idEl) || idEl.ValueKind != JsonValueKind.String) return null;
            if (Hex.Decode(idEl.GetString()!) is not byte[] idData || idData.Length != 8) return null;
            if (!o.TryGetProperty("t", out var tEl) || tEl.ValueKind != JsonValueKind.Number) return null;
            if (!o.TryGetProperty("text", out var textEl) || textEl.ValueKind != JsonValueKind.String) return null;
            var clean = Sanitize.Text(textEl.GetString()!);
            if (clean.Length == 0) return null;
            var t = tEl.GetDouble();
            var rx = o.TryGetProperty("rx", out var rxEl) && rxEl.ValueKind == JsonValueKind.Number ? rxEl.GetDouble() : t;
            string Str(string k, string fallback) => o.TryGetProperty(k, out var e) && e.ValueKind == JsonValueKind.String ? e.GetString()! : fallback;
            return new StoredMessage
            {
                Id = idData.Aggregate(0UL, (acc, b) => acc << 8 | b),
                Nickname = Sanitize.Nickname(Str("nick", "?")),
                Fingerprint = Sanitize.Nickname(Str("fp", "")),
                Text = clean,
                Sent = t / 1000,
                Received = rx / 1000,
                Hops = o.TryGetProperty("hops", out var h) && h.ValueKind == JsonValueKind.Number ? (int)h.GetDouble() : 0,
                Mine = o.TryGetProperty("me", out var me) && me.ValueKind == JsonValueKind.True,
                Privately = o.TryGetProperty("pv", out var pv) && pv.ValueKind == JsonValueKind.True,
                To = Sanitize.Nickname(Str("to", "")),
            };
        }
        catch (Exception) { return null; }
    }

    // ── One chat at a time ────────────────────────────────────
    // Two MeshChats on one computer would advertise the same service twice. The lock goes with the process.

    public bool Lock()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            lockFile = new FileStream(PathOf("chat.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            return true;
        }
        catch (IOException) { return false; }
        catch (Exception) { return true; }          // no lock file: do not stand in the way
    }

    // ── Diagnostics ───────────────────────────────────────────

    public void Log(string text)
    {
        var stamp = DateTimeOffset.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'");
        lock (logLock)
        {
            try
            {
                Directory.CreateDirectory(Dir);
                File.AppendAllText(PathOf("events.log"), $"{stamp} {text}\n", Utf8);
            }
            catch (Exception) { }
        }
    }

    public void TrimLog()
    {
        var text = Read("events.log");
        if (text == null) return;
        var lines = text.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        if (lines.Length > 600)
        {
            try { Write("events.log", string.Join("\n", lines.Skip(lines.Length - 400)) + "\n"); } catch (Exception) { }
        }
    }

    public List<string> RecentLog(int n)
    {
        var text = Read("events.log");
        if (text == null) return new();
        var lines = text.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        return lines.Skip(Math.Max(0, lines.Length - n)).ToList();
    }
}
