namespace Data {

    public class SearchText : GLib.Object {

        public static string norm (string s) {
            var out = new StringBuilder ();
            string d = s.down ();

            int n = d.char_count ();
            for (int i = 0; i < n; i++) {
                int byte_idx = d.index_of_nth_char (i);
                unichar c = d.get_char (byte_idx);

                if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
                    out.append_unichar (c);
            }
            return out.str;
        }

        public static int lev (string a, string b) {
            int n = a.length;
            int m = b.length;
            if (n == 0) return m;
            if (m == 0) return n;

            var d = new int[(n + 1) * (m + 1)];
            for (int i = 0; i <= n; i++) d[i * (m + 1) + 0] = i;
            for (int j = 0; j <= m; j++) d[0 * (m + 1) + j] = j;

            for (int i = 1; i <= n; i++) {
                unichar ca = a.get_char (a.index_of_nth_char (i - 1));
                for (int j = 1; j <= m; j++) {
                    unichar cb = b.get_char (b.index_of_nth_char (j - 1));
                    int cost = (ca == cb) ? 0 : 1;
                    int del  = d[(i - 1) * (m + 1) + j] + 1;
                    int ins  = d[i * (m + 1) + (j - 1)] + 1;
                    int sub  = d[(i - 1) * (m + 1) + (j - 1)] + cost;
                    int val  = (del < ins) ? del : ins;
                    if (sub < val) val = sub;
                    d[i * (m + 1) + j] = val;
                }
            }
            return d[n * (m + 1) + m];
        }

        public static int first_word_prefix_pos (string name, string term) {
            int n = name.length;
            int tlen = term.length;
            for (int i = 0; i <= n - tlen; i++) {
                bool boundary = (i == 0);
                if (!boundary) {
                    unichar p = name.get_char (name.index_of_nth_char (i - 1));
                    boundary = !((p >= 'a' && p <= 'z') || (p >= '0' && p <= '9'));
                }
                if (!boundary) continue;

                bool match = true;
                for (int k = 0; k < tlen; k++) {
                    unichar a = name.get_char (name.index_of_nth_char (i + k));
                    unichar b = term.get_char (term.index_of_nth_char (k));
                    if (a != b) { match = false; break; }
                }
                if (match) return i;
            }
            return -1;
        }

        public static double score_name (string name, string term) {
            if (name == term) return 1000.0;

            if (name.has_prefix (term)) {
                return 900.0 - (name.length - term.length);
            }

            int wb = first_word_prefix_pos (name, term);
            if (wb == 0) return 880.0;
            if (wb > 0)  return 860.0 - wb;

            int idx = name.index_of (term);
            if (idx >= 0) {
                double pos_penalty = idx;
                double len_penalty = (name.length - term.length);
                return 800.0 - pos_penalty - 0.5 * len_penalty;
            }

            int dist = lev (name, term);
            int L = (name.length > term.length) ? name.length : term.length;
            double sim = 1.0 - ((double) dist / (double) L);
            if (sim < 0.0) sim = 0.0;

            double length_bias = 1.0 / (1.0 + (name.length - term.length));
            if (length_bias < 0.2) length_bias = 0.2;

            return 700.0 * sim * length_bias;
        }

        private static string? layout_char (unichar c) {
            switch (c) {
            case 'й': return "q"; case 'ц': return "w"; case 'у': return "e";
            case 'к': return "r"; case 'е': return "t"; case 'н': return "y";
            case 'г': return "u"; case 'ш': return "i"; case 'щ': return "o";
            case 'з': return "p"; case 'х': return "["; case 'ъ': return "]";
            case 'ф': return "a"; case 'ы': return "s"; case 'в': return "d";
            case 'а': return "f"; case 'п': return "g"; case 'р': return "h";
            case 'о': return "j"; case 'л': return "k"; case 'д': return "l";
            case 'ж': return ";"; case 'э': return "'";
            case 'я': return "z"; case 'ч': return "x"; case 'с': return "c";
            case 'м': return "v"; case 'и': return "b"; case 'т': return "n";
            case 'ь': return "m"; case 'б': return ","; case 'ю': return ".";
            case 'ё': return "`";
            default:  return null;
            }
        }

        public static string normalize_layout (string s) {
            if (s == null || s.length == 0) return s;

            int n = s.char_count ();
            bool has_cyr = false;
            for (int i = 0; i < n; i++) {
                unichar c = s.get_char (s.index_of_nth_char (i));
                if ((c >= 0x0410 && c <= 0x044F) || c == 0x0401 || c == 0x0451) {
                    has_cyr = true;
                    break;
                }
            }
            if (!has_cyr) return s;

            var sb = new StringBuilder ();
            for (int i = 0; i < n; i++) {
                unichar c = s.get_char (s.index_of_nth_char (i));
                string? rep = layout_char (c.tolower ());
                if (rep != null) sb.append (rep);
                else sb.append_unichar (c);
            }
            return sb.str;
        }
    }
}
