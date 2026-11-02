// meshchat.exe – MeshChat for Windows: one chat with everyone nearby over Bluetooth, the same as `lotus meshchat` on a
// Mac – Windows computers and Macs are in the same chat. `meshchat help` lists what it can do.

using MeshChat;
using MeshChat.Windows;

var code = Cli.Run(args, new WindowsPlatform());
// started with a double click: the window closes with the program – keep what it said readable
if (code != 0 && WindowsPlatform.OwnsConsole() && !Console.IsInputRedirected)
{
    Term.Write("  Press any key to close this window.");
    try { Console.ReadKey(intercept: true); } catch (Exception) { }
}
return code;
