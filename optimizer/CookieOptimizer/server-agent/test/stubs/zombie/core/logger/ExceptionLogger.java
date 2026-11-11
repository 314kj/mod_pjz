package zombie.core.logger;
public class ExceptionLogger {
    public static void logException(Throwable t) { zombie.TestWorld.log.add("EXC " + t.getMessage()); }
}
