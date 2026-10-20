// lotus – a tiny Paper plugin that tells the control center (lib/mc/control.zsh) what the server
// alone knows: each player's ping, world, health and game mode, and the TPS and tick time.
// Every two seconds it writes plugins/LotusBridge/status.tsv – nothing else, no network, no commands.
// Built on your Mac by lib/mc/bridge.zsh against the server's own API, so it fits every version;
// what only newer versions have is asked for by name.
package lotus.bridge;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Locale;
import org.bukkit.Bukkit;
import org.bukkit.entity.Player;
import org.bukkit.plugin.java.JavaPlugin;

public final class LotusBridge extends JavaPlugin {
  private Path out;
  private Path tmp;

  @Override
  public void onEnable() {
    getDataFolder().mkdirs();
    out = getDataFolder().toPath().resolve("status.tsv");
    tmp = getDataFolder().toPath().resolve("status.tsv.part");
    Bukkit.getScheduler().runTaskTimer(this, this::snapshot, 20L, 40L);
  }

  @Override
  public void onDisable() {
    try {
      Files.deleteIfExists(out);
    } catch (IOException ignored) {
    }
  }

  // On the server thread: read everything, then write it on another thread
  private void snapshot() {
    StringBuilder sb = new StringBuilder();
    sb.append("time\t").append(System.currentTimeMillis() / 1000).append('\n');
    sb.append("tps\t").append(num(tps())).append('\t').append(num(mspt())).append('\n');
    for (Player p : Bukkit.getOnlinePlayers()) {
      sb.append("player\t").append(clean(p.getName()))
        .append('\t').append(ping(p))
        .append('\t').append(clean(p.getWorld().getName()))
        .append('\t').append(Math.round(p.getHealth()))
        .append('\t').append(p.getGameMode().name().toLowerCase(Locale.ROOT))
        .append('\t').append(p.getLevel())
        .append('\n');
    }
    final String text = sb.toString();
    Bukkit.getScheduler().runTaskAsynchronously(this, () -> write(text));
  }

  private synchronized void write(String text) {
    try {
      Files.write(tmp, text.getBytes(StandardCharsets.UTF_8));
      Files.move(tmp, out, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
    } catch (IOException ignored) {
    }
  }

  // Player.getPing() since 1.17, player.spigot().getPing() before
  private static int ping(Player p) {
    try {
      return ((Number) p.getClass().getMethod("getPing").invoke(p)).intValue();
    } catch (Throwable e) {
      try {
        Object spigot = p.getClass().getMethod("spigot").invoke(p);
        return ((Number) spigot.getClass().getMethod("getPing").invoke(spigot)).intValue();
      } catch (Throwable e2) {
        return -1;
      }
    }
  }

  // Paper only: Bukkit.getTPS() and Bukkit.getAverageTickTime()
  private static double tps() {
    try {
      double[] t = (double[]) Bukkit.class.getMethod("getTPS").invoke(null);
      return Math.min(20.0, t[0]);
    } catch (Throwable e) {
      return -1;
    }
  }

  private static double mspt() {
    try {
      return ((Number) Bukkit.class.getMethod("getAverageTickTime").invoke(null)).doubleValue();
    } catch (Throwable e) {
      return -1;
    }
  }

  private static String num(double v) {
    return v < 0 ? "-" : String.format(Locale.ROOT, "%.1f", v);
  }

  private static String clean(String s) {
    return s.replace('\t', ' ').replace('\n', ' ');
  }
}
