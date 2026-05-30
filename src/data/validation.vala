namespace Data {

    public class Validation : GLib.Object {

        private const string[] ALLOWED_BRANCHES = {
            "sisyphus", "p11", "p10", "p9", "c10f2", "c9f2"
        };

        public static bool branch_allowed (string? b) {
            if (b == null) return false;
            var lc = b.down ();
            foreach (var a in ALLOWED_BRANCHES) if (a == lc) return true;
            return false;
        }

        public static bool is_all_digits (string s) {
            if (s.length == 0) return false;
            for (int i = 0; i < s.length; i++)
                if (s[i] < '0' || s[i] > '9') return false;
            return true;
        }

        public static bool is_valid_package_name (string? s) {
            if (s == null) return false;
            var t = s.strip ();
            if (t.length == 0) return false;
            if (!t.get_char (0).isalnum ()) return false;
            int idx = 0;
            unichar c;
            while (t.get_next_char (ref idx, out c)) {
                if (c.isalnum () || c == '.' || c == '_' || c == '+' || c == '-') continue;
                return false;
            }
            return true;
        }

        public static bool is_no_data_error (GLib.Error e) {
            if (e == null) return false;
            string m = (e.message ?? "").down ();
            return m.contains ("no data not found in database")
                || m.contains ("no data found in database")
                || m.contains ("no data found in db")
                || m.contains ("no information found")
                || m.contains ("no errata data found")
                || m.contains ("nothing found")
                || m.contains ("not found in database")
                || m.contains ("no packages found")
                || m.contains ("not found in the database")
                || m.contains ("http 404")
                || m.contains (" 404 ")
                || m.contains ("wrong type: expected json_node_array");
        }

        public static bool is_rate_limited_error (GLib.Error e) {
            if (e == null) return false;
            string m = (e.message ?? "").down ();
            return m.contains ("too many requests")
                || m.contains ("429");
        }
    }
}
