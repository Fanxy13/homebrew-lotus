// MeshChat's tests where there is no Bluetooth to speak of:
//   meshchat-tests                          the protocol tests (the same as meshchat selftest on Windows)
//   meshchat-tests --write-vectors <file>   the test vectors this implementation makes (lib/meshchat/Tests/vectors.txt)
//   meshchat-tests --verify-foreign <file>  packets a Mac signed: they must open here (the CI, after the Mac's tests)
//   meshchat-tests demo | history | …       the chat's commands, without a radio

using MeshChat;

switch (args.FirstOrDefault())
{
    case null:
        return SelfTest.Run();
    case "--write-vectors" when args.Length == 2:
        File.WriteAllText(args[1], VectorTests.Generate());
        Console.WriteLine($"  wrote {args[1]}");
        return 0;
    case "--verify-foreign" when args.Length == 2:
        return VectorTests.VerifyForeign(args[1]);
    default:
        return Cli.Run(args, new NoRadio());
}

// No Bluetooth here: the chat's commands work, the chat itself says where it runs
sealed class NoRadio : IPlatform
{
    public string Name => "tests (no Bluetooth)";

    public ILinkTransport? Radio(SerialQueue queue, Store store, out string why)
    {
        why = "This build has no Bluetooth – the chat runs in meshchat.exe on Windows, and with lotus meshchat on a Mac";
        return null;
    }

    public int Doctor(Store store)
    {
        Cli.Header("doctor");
        Console.WriteLine("    This build has no Bluetooth: it runs the tests and the demo. On Windows: meshchat.exe doctor");
        Console.WriteLine();
        return 1;
    }

    public void PrepareConsole() { }
}
