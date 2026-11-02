// MeshChat for Windows – what Windows gives the chat: Bluetooth (BleTransport.cs), the doctor (Doctor.cs), and a
// console that understands escape codes and UTF-8 – Windows Terminal does by itself, the classic console once it is
// told to (ENABLE_VIRTUAL_TERMINAL_PROCESSING, Windows 10 and newer).

using System.Runtime.InteropServices;
using System.Text;

namespace MeshChat.Windows;

public sealed partial class WindowsPlatform : IPlatform
{
    public WindowsPlatform()
    {
        MeshTexts.Update = "get the newest meshchat.exe (github.com/Fanxy13/homebrew-lotus/releases)";
        MeshTexts.CheckClock = "Settings › Time & language › Date & time, \"Set time automatically\"";
    }

    public string Name => "Windows";

    public ILinkTransport? Radio(SerialQueue queue, Store store, out string why)
    {
        why = "";
        return new BleTransport(queue, store.Log);
    }

    public int Doctor(Store store) => MeshChat.Windows.Doctor.Run(store);

    private bool prepared;

    public void PrepareConsole()
    {
        if (prepared) return;
        prepared = true;
        try
        {
            Console.OutputEncoding = new UTF8Encoding(false);
            Console.InputEncoding = new UTF8Encoding(false);
        }
        catch (Exception) { }
        var handle = GetStdHandle(StdOutputHandle);
        if (GetConsoleMode(handle, out var mode)) SetConsoleMode(handle, mode | EnableVirtualTerminalProcessing);
    }

    // Started from Explorer (a double click), the window is this program's alone and closes with it: what it said must
    // stay readable. In cmd or Windows Terminal there is a shell in the window too.
    public static bool OwnsConsole()
    {
        try
        {
            var list = new uint[4];
            return GetConsoleProcessList(list, (uint)list.Length) == 1;
        }
        catch (Exception) { return false; }
    }

    private const int StdOutputHandle = -11;
    private const uint EnableVirtualTerminalProcessing = 0x0004;

    [LibraryImport("kernel32.dll")]
    private static partial IntPtr GetStdHandle(int handle);

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetConsoleMode(IntPtr handle, out uint mode);

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetConsoleMode(IntPtr handle, uint mode);

    [LibraryImport("kernel32.dll")]
    private static partial uint GetConsoleProcessList([Out] uint[] list, uint count);
}
