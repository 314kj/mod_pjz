package cookie.test;

import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.LocalDateTime;

/**
 * Test-only Java agent for Cookie Optimizer.
 * It does ONE thing: when the game starts, write a small text report
 * (Java version, max heap, GC, JVM args) to the path given after '='.
 * It does not patch, read or change anything in the game. No network.
 */
public final class CookieAgentTest {
    public static void premain(String args) {
        try {
            Path out = Paths.get(args != null && !args.isBlank() ? args : "cookie_agent_report.txt");
            StringBuilder sb = new StringBuilder();
            sb.append("agent=loaded\n");
            sb.append("time=").append(LocalDateTime.now()).append('\n');
            sb.append("java.version=").append(System.getProperty("java.version")).append('\n');
            sb.append("java.home=").append(System.getProperty("java.home")).append('\n');
            sb.append("cwd=").append(Paths.get("").toAbsolutePath()).append('\n');
            sb.append("maxHeapMB=").append(Runtime.getRuntime().maxMemory() / (1024 * 1024)).append('\n');
            for (GarbageCollectorMXBean gc : ManagementFactory.getGarbageCollectorMXBeans()) {
                sb.append("gc=").append(gc.getName()).append('\n');
            }
            sb.append("env.JAVA_TOOL_OPTIONS=").append(System.getenv("JAVA_TOOL_OPTIONS")).append('\n');
            sb.append("env._JAVA_OPTIONS=").append(System.getenv("_JAVA_OPTIONS")).append('\n');
            for (String a : ManagementFactory.getRuntimeMXBean().getInputArguments()) {
                sb.append("arg=").append(a).append('\n');
            }
            Files.write(out, sb.toString().getBytes(StandardCharsets.UTF_8));
        } catch (Throwable t) {
            // Never break the game because of a test report.
        }
    }
}
