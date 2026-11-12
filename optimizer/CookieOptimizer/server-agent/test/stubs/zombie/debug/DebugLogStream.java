package zombie.debug;
/** test stand-in: printed exceptions are recorded */
public class DebugLogStream extends java.io.PrintStream {
    public final java.util.List<String> printed = new java.util.ArrayList<>();
    public DebugLogStream() { super(System.out); }
    public void printException(Throwable t, String a, String b, LogSeverity s) { printed.add(t + " | " + a + " | " + b); }
}
