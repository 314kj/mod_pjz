package zombie.debug;
public class DebugLogStream extends java.io.PrintStream {
    public DebugLogStream() { super(System.out); }
    public void printException(Throwable t, String a, String b, LogSeverity s) { throw new UnsupportedOperationException("stub"); }
}
