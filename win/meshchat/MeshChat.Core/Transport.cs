// MeshChat – what the mesh needs from a radio: find computers with MeshChat nearby, connect, and move frames over the
// links. On Windows that is Bluetooth LE (MeshChat/BleTransport.cs); the tests and `meshchat demo` use a simulated one
// (Sim.cs). The mesh works the same on both and never learns which one it has. A radio calls its delegate on the
// mesh's queue, and is only called there. As lib/meshchat/Sources/Transport.swift.

namespace MeshChat;

public enum RadioState { Starting, On, Off, Unauthorized, Unsupported, Resetting }

public static class RadioStates
{
    public static string Label(this RadioState s) => s switch
    {
        RadioState.Starting => "starting",
        RadioState.On => "on",
        RadioState.Off => "off",
        RadioState.Unauthorized => "not allowed",
        RadioState.Unsupported => "not available",
        RadioState.Resetting => "restarting",
        _ => "unknown",
    };
}

// outbound: true – we connected to them (central) · false – they connected to us (peripheral)
// endpoint: the other computer as the radio knows it (a Bluetooth address or device ID – it changes now and then)
public readonly record struct LinkInfo(int Id, bool Outbound, string Endpoint, int MaxFrame);

// A computer with MeshChat that the radio heard advertising. token: from its advertised name, the first 4 bytes of
// its session (null when not heard – Windows cannot put it in its own advertisement)
public readonly record struct Sighting(string Endpoint, uint? Token, int Rssi);

public interface ILinkTransportDelegate
{
    void RadioStateChanged(RadioState state);
    void RadioSighted(Sighting s);
    void RadioOpened(LinkInfo link);
    void RadioClosed(int link, string reason);
    void RadioReceived(byte[] frame, int link);
    void RadioConnectFailed(string endpoint, string reason);
    void RadioSignal(int rssi, int link);       // how strong the other computer of a link arrives
}

public interface ILinkTransport
{
    ILinkTransportDelegate? Delegate { get; set; }
    RadioState State { get; }
    void Start(uint token);                 // advertise (with this token where the radio can), once the radio is on
    void Stop();                            // everything off: no advertising, no scanning, every link closed
    void SetScanning(bool on);              // on again: a fresh scan, so computers already seen are reported again
    void SetAdvertising(bool on);
    void Connect(string endpoint);
    void CancelConnect(string endpoint);
    void Send(byte[] frame, int link);      // in order; the radio waits while the link is busy
    void Close(int link);                   // the radio answers with RadioClosed
    int MaxFrame(int link);
    void MeasureSignal(int link);           // answered with RadioSignal – where the radio can measure it
}
