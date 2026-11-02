// MeshChat – `meshchat demo`: the chat with two simulated people, to try it without a second computer. Nothing goes over
// Bluetooth and nothing is saved; the screen says DEMO. Ada is your neighbour; Grace is out of your range and reaches
// you through Ada, so her messages arrive relayed (⇢1). The mesh, the signatures and the screen are the real ones –
// only the radio is simulated (Sim.cs). As lib/meshchat/Sources/Demo.swift.

namespace MeshChat;

public sealed class DemoWorld
{
    public SimNetwork Net { get; }
    private readonly List<DemoBot> bots = new();
    private readonly SerialQueue queue;

    public DemoWorld(SerialQueue queue)
    {
        this.queue = queue;
        Net = new SimNetwork(live: queue);
    }

    public SimRadio UserRadio() => Net.Radio("you");

    // On the mesh's queue
    public void Start()
    {
        bots.Add(new DemoBot("Ada", this, queue,
            "Hi! I'm right next to you – a direct Bluetooth link (● in the list below).",
            new[]
            {
                "Got it 👍",
                "Grace is out of your range – what she writes reaches you through my computer.",
                "Try /where Grace – how far she is, and the way your messages take to her.",
                "There are no rooms: every computer with MeshChat nearby reads this – Macs and Windows alike – and passes it on.",
                "Ctrl-C closes the chat; in a real chat your history stays on this computer.",
            }, 1));
        bots.Add(new DemoBot("Grace", this, queue,
            "Hello from further away! I can't reach you directly – Ada passes this on, hence the mark after it.",
            new[]
            {
                "I read you through Ada 👋",
                "If Ada left, we could not hear each other any more – a mesh needs someone in between.",
                "Each computer passes a message on once; the copies that come back are dropped.",
            }, 2));
        Net.SetRange("you", "Ada", true);
        Net.SetRange("Ada", "Grace", true);
        Net.SetDistance("you", "Ada", 2);
        Net.SetDistance("Ada", "Grace", 8);
    }

    public void Tick() => Net.SecondPassed();

    public static readonly string[] BotNames = { "Ada", "Grace" };
}

public sealed class DemoBot
{
    private readonly MeshNode node;
    private readonly string name;
    private readonly string greeting;
    private readonly string[] replies;
    private readonly int replyEvery;
    private readonly SerialQueue queue;
    private bool greeted;
    private int heard;
    private int next;

    public DemoBot(string name, DemoWorld world, SerialQueue queue, string greeting, string[] replies, int replyEvery)
    {
        this.name = name;
        this.queue = queue;
        this.greeting = greeting;
        this.replies = replies;
        this.replyEvery = replyEvery;
        var net = world.Net;
        node = new MeshNode(net.Radio(name), name, Signer.FromIdentity(CryptoBackend.RandomBytes(32)), Handle, clock: () => net.Now);
        net.Tickers.Add(node.Tick);
        node.Start();
    }

    private void Say(string text, double after) => queue.PostAfter(after, () =>
    {
        try { node.Send(text); } catch (Exception) { }
    });

    private void Handle(MeshEvent e)
    {
        switch (e)
        {
            case MeshEvent.Snapshot s:
                // greet once the person trying the demo is known
                if (!greeted && s.S.Participants.Any(p => !DemoWorld.BotNames.Contains(p.Nickname)))
                {
                    greeted = true;
                    Say(greeting, name == "Ada" ? 1.0 : 2.5);
                }
                break;
            case MeshEvent.Message m when !m.M.Mine && !DemoWorld.BotNames.Contains(m.M.Nickname):
                heard++;
                if (heard % replyEvery != 0 && !m.M.Text.ToLowerInvariant().Contains(name.ToLowerInvariant())) return;
                Say(replies[next % replies.Length], 1.2 + Random.Shared.NextDouble() * 1.2);
                next++;
                break;
        }
    }
}
