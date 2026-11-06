// MeshChat tests – a small runner, like lib/meshchat/Tests/TestKit.swift: prints ✓/✗ per check like Lotus' own tests,
// status 1 on a failure. `meshchat selftest` runs them on this computer; win/meshchat/MeshChat.Tests runs them anywhere
// .NET runs (the CI). The mesh tests run on a simulated radio (Sim.cs): they test the protocol, not Bluetooth.

using System.Runtime.CompilerServices;

namespace MeshChat;

public static class TestRun
{
    public static int Passed;
    public static int Failed;
    public static string Current = "";
    public static readonly List<string> Failures = new();

    public static void Check(bool ok, string what, [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
    {
        if (ok)
        {
            Passed++;
            return;
        }
        Failed++;
        var place = $"{Path.GetFileName(file)}:{line}";
        Failures.Add($"{Current}: {what} ({place})");
        Term.Line($"    ✗ {what}  [{place}]");
    }

    public static void CheckEqual<T>(T got, T want, string what, [CallerFilePath] string file = "", [CallerLineNumber] int line = 0) =>
        Check(EqualityComparer<T>.Default.Equals(got, want), $"{what} – got {Show(got)}, want {Show(want)}", file, line);

    public static void CheckBytes(byte[]? got, byte[]? want, string what, [CallerFilePath] string file = "", [CallerLineNumber] int line = 0) =>
        Check(B.Eq(got, want), $"{what} – got {(got == null ? "nothing" : Hex.Encode(got))}, want {(want == null ? "nothing" : Hex.Encode(want))}", file, line);

    public static void CheckList<T>(IEnumerable<T> got, IEnumerable<T> want, string what, [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
    {
        var g = got.ToList();
        var w = want.ToList();
        Check(g.SequenceEqual(w), $"{what} – got [{string.Join(", ", g)}], want [{string.Join(", ", w)}]", file, line);
    }

    public static void CheckThrows(string what, Action body, [CallerFilePath] string file = "", [CallerLineNumber] int line = 0)
    {
        try
        {
            body();
            Check(false, $"{what} – it did not fail", file, line);
        }
        catch (Exception)
        {
            Check(true, what, file, line);
        }
    }

    private static string Show<T>(T v) => v switch
    {
        null => "null",
        byte[] b => Hex.Encode(b),
        string s => $"\"{s}\"",
        _ => v.ToString() ?? "",
    };

    public static void Test(string name, Action body)
    {
        Current = name;
        var before = Failed;
        try
        {
            body();
        }
        catch (Exception e)
        {
            Failed++;
            Failures.Add($"{name}: {e}");
            Term.Line($"    ✗ stopped by an error: {e.GetType().Name}: {e.Message}");
        }
        Term.Line($"  {(Failed == before ? "✓" : "✗")} {name}");
    }

    public static byte[] H(string s) => Hex.Decode(new string(s.Where(c => !char.IsWhiteSpace(c) && c != ':').ToArray()))!;
}

// SplitMix64: the same "random" bytes on every run and every system
public sealed class SeededGenerator
{
    private ulong state;

    public SeededGenerator(ulong seed) => state = seed;

    public ulong Next()
    {
        unchecked
        {
            state += 0x9E3779B97F4A7C15;
            var z = state;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EB;
            return z ^ (z >> 31);
        }
    }

    public int Int(int lo, int hi) => lo + (int)(Next() % (ulong)(hi - lo + 1));
    public byte Byte() => (byte)(Next() & 0xFF);
}

public static class SelfTest
{
    // → the exit status: 0 when every check passed
    public static int Run()
    {
        Term.Line();
        Term.Line($"  MeshChat {Proto.Release} – the protocol tests (crypto: {CryptoBackend.Name}, .NET {Environment.Version})");
        Term.Line();
        TestRun.Passed = 0;
        TestRun.Failed = 0;
        TestRun.Failures.Clear();
        CodecTests.Run();
        CryptoTests.Run();
        FragmentTests.Run();
        VectorTests.Run();
        StoreTests.Run();
        DistanceTests.Run();
        ViewTests.Run();
        MeshTests.Run();
        TellTests.Run();
        Term.Line();
        Term.Line($"  {TestRun.Passed} passed, {TestRun.Failed} failed");
        Term.Line();
        return TestRun.Failed == 0 ? 0 : 1;
    }
}
