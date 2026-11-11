package cookie.slicer;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/** One line to the server console and to CookieSlicer.log next to the jar. */
final class Log {
    private static File file;

    static void init(File dir) {
        file = dir == null ? null : new File(dir, "CookieSlicer.log");
    }

    static synchronized void line(String s) {
        String text = "[CookieSlicer] " + s;
        System.out.println(text);
        if (file == null) return;
        try (Writer w = new OutputStreamWriter(new FileOutputStream(file, true), StandardCharsets.UTF_8)) {
            w.write(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT).format(new Date()) + " " + text + "\r\n");
        } catch (Exception ignored) {
            // the console line is enough
        }
    }

    private Log() {}
}
