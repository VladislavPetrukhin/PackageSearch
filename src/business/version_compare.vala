namespace Business {

    public class VersionCompare : GLib.Object {

        public static bool is_digit (char c) {
            return c >= '0' && c <= '9';
        }

        public static bool is_alpha (char c) {
            return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        }

        public static bool is_alnum (char c) {
            return is_digit (c) || is_alpha (c);
        }

        public static int rpmvercmp (string a, string b) {
            if (a == b) return 0;
            int i = 0, j = 0;
            int la = a.length, lb = b.length;

            while (i < la || j < lb) {

                while (i < la && !is_alnum (a[i]) && a[i] != '~' && a[i] != '^') i++;
                while (j < lb && !is_alnum (b[j]) && b[j] != '~' && b[j] != '^') j++;

                if ((i < la && a[i] == '~') || (j < lb && b[j] == '~')) {
                    if (i >= la || a[i] != '~') return 1;
                    if (j >= lb || b[j] != '~') return -1;
                    i++; j++; continue;
                }

                if ((i < la && a[i] == '^') || (j < lb && b[j] == '^')) {
                    if (i >= la) return -1;
                    if (j >= lb) return 1;
                    if (a[i] != '^') return 1;
                    if (b[j] != '^') return -1;
                    i++; j++; continue;
                }
                if (i >= la || j >= lb) break;

                int sa = i, sb = j;
                bool isnum = is_digit (a[i]);
                if (isnum) {
                    while (i < la && is_digit (a[i])) i++;
                    while (j < lb && is_digit (b[j])) j++;
                } else {
                    while (i < la && is_alpha (a[i])) i++;
                    while (j < lb && is_alpha (b[j])) j++;
                }

                if (sa == i) return -1;
                if (sb == j) return isnum ? 1 : -1;

                string seg_a = a.substring (sa, i - sa);
                string seg_b = b.substring (sb, j - sb);

                if (isnum) {

                    int za = 0, zb = 0;
                    while (za < seg_a.length && seg_a[za] == '0') za++;
                    while (zb < seg_b.length && seg_b[zb] == '0') zb++;
                    seg_a = seg_a.substring (za);
                    seg_b = seg_b.substring (zb);
                    if (seg_a.length != seg_b.length)
                        return seg_a.length > seg_b.length ? 1 : -1;
                }
                int rc = strcmp (seg_a, seg_b);
                if (rc != 0) return rc < 0 ? -1 : 1;
            }

            if (i >= la && j >= lb) return 0;
            if (i >= la) return -1;
            return 1;
        }

        public static void parse_evr (string s, out int epoch,
                                       out string ver, out string rel) {
            epoch = 0;
            string rest = s;
            int colon = s.index_of_char (':');
            if (colon >= 0) {
                epoch = int.parse (s.substring (0, colon));
                rest = s.substring (colon + 1);
            }
            int dash = rest.index_of_char ('-');
            if (dash >= 0) {
                ver = rest.substring (0, dash);
                rel = rest.substring (dash + 1);
            } else {
                ver = rest;
                rel = "";
            }
        }

        public static int compare_evr (string a, string b) {
            int ea, eb;
            string va, vb, ra, rb;
            parse_evr (a, out ea, out va, out ra);
            parse_evr (b, out eb, out vb, out rb);
            if (ea != eb) return ea < eb ? -1 : 1;
            int c = rpmvercmp (va, vb);
            if (c != 0) return c;
            return rpmvercmp (ra, rb);
        }
    }
}
