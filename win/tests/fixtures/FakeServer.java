// A stand-in for a Minecraft server in the tests of /minecraft on Windows (win/tests/Minecraft.Tests.ps1): the lines a
// server prints, and what it does with a few console commands – no world, no network. Built by the tests with javac
// into a server.jar of its own.
//   join <name> · leave <name>   a player comes or goes (as the log of a real server says it)
//   say <text>                   [Server] <text>
//   crash                        an error, exit code 1
//   stop                         saves and ends, exit code 0
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;

public class FakeServer {
  static final DateTimeFormatter TIME = DateTimeFormatter.ofPattern("HH:mm:ss");

  static void log(String level, String msg) {
    System.out.println("[" + LocalTime.now().format(TIME) + "] [Server thread/" + level + "]: " + msg);
    System.out.flush();
  }

  public static void main(String[] args) throws Exception {
    log("INFO", "Starting minecraft server version 1.21.4");
    Path eula = Path.of("eula.txt");
    if (!Files.exists(eula) || !Files.readString(eula).contains("eula=true")) {
      log("INFO", "You need to agree to the EULA in order to run the server. Go to eula.txt for more info.");
      System.exit(0);
    }
    for (int p = 0; p <= 100; p += 50) {
      log("INFO", "Preparing spawn area: " + p + "%");
      Thread.sleep(150);
    }
    log("INFO", "Done (0.321s)! For help, type \"help\"");
    BufferedReader in = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
    String line;
    while ((line = in.readLine()) != null) {
      line = line.trim();
      if (line.equals("stop")) {
        log("INFO", "Stopping the server");
        log("INFO", "Saving worlds");
        System.exit(0);
      } else if (line.startsWith("join ")) {
        log("INFO", line.substring(5) + " joined the game");
      } else if (line.startsWith("leave ")) {
        log("INFO", line.substring(6) + " left the game");
      } else if (line.startsWith("say ")) {
        log("INFO", "[Server] " + line.substring(4));
      } else if (line.equals("crash")) {
        log("ERROR", "Encountered an unexpected exception");
        System.exit(1);
      } else {
        log("INFO", "Unknown or incomplete command: " + line);
      }
    }
  }
}
