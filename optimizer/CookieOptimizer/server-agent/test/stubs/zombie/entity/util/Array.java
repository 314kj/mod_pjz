package zombie.entity.util;
/** Test stand-in with the behaviour the agent relies on (unordered: the last item fills a removed slot). */
@SuppressWarnings("unchecked")
public class Array<T> {
    public T[] items = (T[]) new Object[16];
    public int size;
    public boolean ordered;
    public Array() {}
    public Array(boolean ordered, int capacity) { this.ordered = ordered; items = (T[]) new Object[Math.max(1, capacity)]; }
    public void add(T value) {
        if (size == items.length) items = java.util.Arrays.copyOf(items, Math.max(8, size * 2));
        items[size++] = value;
    }
    public boolean removeValue(T value, boolean identity) {
        for (int i = 0; i < size; i++) {
            if (identity ? items[i] == value : java.util.Objects.equals(items[i], value)) { removeIndex(i); return true; }
        }
        return false;
    }
    public T removeIndex(int index) {
        if (index >= size) throw new IndexOutOfBoundsException(index + " >= " + size);
        T v = items[index];
        size--;
        if (ordered) System.arraycopy(items, index + 1, items, index, size - index);
        else items[index] = items[size];
        items[size] = null;
        return v;
    }
}
