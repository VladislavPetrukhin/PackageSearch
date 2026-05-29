namespace Business {

    public class TextDiff : GLib.Object {

        public static string only_differences (string a, string b) {
            string[] la = a.split ("\n");
            string[] lb = b.split ("\n");
            int n = la.length;
            int m = lb.length;

            var dp = new int[(n + 1) * (m + 1)];
            for (int i = n - 1; i >= 0; i--) {
                for (int j = m - 1; j >= 0; j--) {
                    if (la[i] == lb[j])
                        dp[i * (m + 1) + j] = dp[(i + 1) * (m + 1) + (j + 1)] + 1;
                    else
                        dp[i * (m + 1) + j] =
                            int.max (dp[(i + 1) * (m + 1) + j], dp[i * (m + 1) + (j + 1)]);
                }
            }

            var sb = new StringBuilder ();
            bool skipped = false;
            int x = 0, y = 0;

            while (x < n && y < m) {
                if (la[x] == lb[y]) {
                    skipped = true;
                    x++; y++;
                } else if (dp[(x + 1) * (m + 1) + y] >= dp[x * (m + 1) + (y + 1)]) {
                    emit_separator (sb, ref skipped);
                    sb.append ("- ").append (la[x]).append_c ('\n');
                    x++;
                } else {
                    emit_separator (sb, ref skipped);
                    sb.append ("+ ").append (lb[y]).append_c ('\n');
                    y++;
                }
            }
            while (x < n) {
                emit_separator (sb, ref skipped);
                sb.append ("- ").append (la[x]).append_c ('\n');
                x++;
            }
            while (y < m) {
                emit_separator (sb, ref skipped);
                sb.append ("+ ").append (lb[y]).append_c ('\n');
                y++;
            }

            return sb.str;
        }

        private static void emit_separator (StringBuilder sb, ref bool skipped) {
            if (skipped && sb.len > 0)
                sb.append ("  ⋯\n");
            skipped = false;
        }
    }
}
