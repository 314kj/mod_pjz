package zombie.debug;
/** test stand-in: error() prints are recorded */
public enum DebugType {
    General;
    public static final java.util.List<String> PRINTED = new java.util.ArrayList<>();
    public void error(Object o) { PRINTED.add(String.valueOf(o)); }
}
