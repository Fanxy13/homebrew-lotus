// MeshChat – one thread that does one thing after the other, as a DispatchQueue does on the Mac: the mesh runs on one,
// the screen and the keys on another. What the radio hears is put on the mesh's queue, so the mesh never needs a lock.

using System.Collections.Concurrent;

namespace MeshChat;

public sealed class SerialQueue
{
    private readonly BlockingCollection<Action> items = new();
    private readonly ConcurrentDictionary<Timer, byte> timers = new();
    private int threadId = -1;

    public static Action<Exception>? Unhandled;     // the app logs what went wrong; the queue goes on

    // started: a thread of its own · not: Run() on the calling thread (the main one)
    public SerialQueue(string name, bool started = true)
    {
        if (!started) return;
        var t = new Thread(Run) { IsBackground = true, Name = name };
        t.Start();
    }

    public bool IsCurrent => Environment.CurrentManagedThreadId == threadId;

    public void Run()
    {
        threadId = Environment.CurrentManagedThreadId;
        foreach (var a in items.GetConsumingEnumerable())
        {
            try { a(); }
            catch (Exception e) { Unhandled?.Invoke(e); }
        }
    }

    public void Post(Action a)
    {
        try { items.Add(a); }
        catch (InvalidOperationException) { }       // the queue was closed: the app is ending
    }

    public void PostAfter(double seconds, Action a)
    {
        var holder = new Timer[1];
        holder[0] = new Timer(_ =>
        {
            if (timers.TryRemove(holder[0], out byte _)) holder[0].Dispose();
            Post(a);
        }, null, Timeout.Infinite, Timeout.Infinite);
        timers[holder[0]] = 0;                      // held until it fired: a timer nobody holds may never fire
        holder[0].Change((int)Math.Max(0, seconds * 1000), Timeout.Infinite);
    }

    // Runs it on the queue and waits for it (right away when already on the queue)
    public T Send<T>(Func<T> f)
    {
        if (IsCurrent) return f();
        T result = default!;
        Exception? error = null;
        using var done = new ManualResetEventSlim();
        Post(() =>
        {
            try { result = f(); }
            catch (Exception e) { error = e; }
            finally { done.Set(); }
        });
        if (!done.Wait(TimeSpan.FromSeconds(30))) throw new TimeoutException("the queue did not answer");
        if (error != null) throw error;
        return result;
    }

    public void Send(Action a) => Send(() => { a(); return 0; });

    // Every second, until the app ends
    public Timer Every(double seconds, Action a)
    {
        var t = new Timer(_ => Post(a), null, TimeSpan.FromSeconds(seconds), TimeSpan.FromSeconds(seconds));
        timers[t] = 0;
        return t;
    }

    public void Complete() => items.CompleteAdding();
}
