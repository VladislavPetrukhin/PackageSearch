using Gee;
using AltRepo;

namespace Data {

public class AltRepoClient : GLib.Object {
    private AltRepo.Client cli;

    public AltRepoClient () {
        cli = new AltRepo.Client ();
    }

    // контейнер для сортировки
    private class Candidate : GLib.Object {
        public double score;
        public SourceGroup sg;
        public Candidate (double score, SourceGroup sg) {
            this.score = score;
            this.sg = sg;
        }
    }

    // ---------- helpers: нормализация имени ----------
    // Оставляем только [a-z0-9], всё в нижний регистр
    private static string norm (string s) {
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

    // ---------- helpers: расстояние Левенштейна ----------
    private static int lev (string a, string b) {
        int n = a.length;
        int m = b.length;
        if (n == 0) return m;
        if (m == 0) return n;

        var d = new int[(n + 1) * (m + 1)];
        for (int i = 0; i <= n; i++) d[i*(m+1) + 0] = i;
        for (int j = 0; j <= m; j++) d[0*(m+1) + j] = j;

        for (int i = 1; i <= n; i++) {
            unichar ca = a.get_char (a.index_of_nth_char (i - 1));
            for (int j = 1; j <= m; j++) {
                unichar cb = b.get_char (b.index_of_nth_char (j - 1));
                int cost = (ca == cb) ? 0 : 1;
                int del = d[(i-1)*(m+1) + j] + 1;
                int ins = d[i*(m+1) + (j-1)] + 1;
                int sub = d[(i-1)*(m+1) + (j-1)] + cost;
                int val = del < ins ? del : ins;
                if (sub < val) val = sub;
                d[i*(m+1) + j] = val;
            }
        }
        return d[n*(m+1) + m];
    }

    // Поиск префикса на границе слова: (^|[^a-z0-9])term
    private static int first_word_prefix_pos (string name, string term) {
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

    // ---------- скоринг имени ----------
    private static double score_name (string name, string term) {
        // Сначала жёсткие правила c большими весами
        if (name == term) return 1000.0;

        if (name.has_prefix (term)) {
            // чем меньше разница длин — тем лучше
            return 900.0 - (name.length - term.length);
        }

        int wb = first_word_prefix_pos (name, term);
        if (wb == 0) return 880.0;           // начало имени на границе слова
        if (wb > 0)  return 860.0 - wb;      // дальше — ниже

        int idx = name.index_of (term);
        if (idx >= 0) {
            // Подстрока: ранняя позиция и малая разница длин — лучше
            double pos_penalty = idx;
            double len_penalty = (name.length - term.length);
            return 800.0 - pos_penalty - 0.5*len_penalty;
        }

        int dist = lev (name, term);
        int L = (name.length > term.length) ? name.length : term.length;
        double sim = 1.0 - ((double) dist / (double) L); // 0..1
        if (sim < 0.0) sim = 0.0;

        double length_bias = 1.0 / (1.0 + (name.length - term.length));
        if (length_bias < 0.2) length_bias = 0.2;

        return 700.0 * sim * length_bias;
    }

    // ---------- Поиск source-пакетов ----------
    public async Gee.ArrayList<SourceGroup> search_source (
        string branch, string term, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var term_raw = term.strip ();
        var term_n = norm (term_raw);
        if (term_n.length < 2) return new Gee.ArrayList<SourceGroup> ();

        var groups = new Gee.ArrayList<SourceGroup> ();
        var resp = yield cli.get_site_find_packages_async(
            { term_raw },       // terms
            branch,             // branch
            null,               // arch
            Priority.DEFAULT,   // priority
            cancellable         // cancellable
        );

        var candidates = new Gee.ArrayList<Candidate> ();
        foreach (var pkg in resp.packages) {
            if (pkg.by_binary) continue;

            // Берём лучшую актуальную версию в этой ветке
            AltRepo.SitePackageVersionsElement? best = null;
            foreach (var v in pkg.versions) {
                if (v.branch == branch && !v.deleted) { best = v; break; }
            }
            if (best == null) continue;

            var g = new SourceGroup (pkg.name);
            g.version = best.version;
            g.release = best.release;

            var name_n = norm (pkg.name);
            double s = score_name (name_n, term_n);
            if (pkg.name.down () == term_raw.down ()) s += 5.0;

            candidates.add (new Candidate (s, g));
        }

        // сортировка
        candidates.sort ((a, b) => {
            if (a.score > b.score) return -1;
            if (a.score < b.score) return 1;

            int la = a.sg.name.length;
            int lb = b.sg.name.length;
            if (la != lb) return (la < lb) ? -1 : 1;

            return strcmp (a.sg.name, b.sg.name);
        });

        // Берём верхние 100 результата
        int cap = (candidates.size < 100) ? candidates.size : 100;
        for (int i = 0; i < cap; i++) groups.add (candidates[i].sg);

        return groups;
    }

    // ---------- Детали source-пакета + список бинарей ----------
    public async PackageDetails get_source_details (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var details = new PackageDetails ();

        var h = cli.get_site_pkghash_by_name (branch, src_name, cancellable);
        var pkghash = int64.parse (h.pkghash);

        var info = yield cli.get_site_package_info_pkghash_async (
            branch, pkghash, 50, "source", Priority.DEFAULT, cancellable
        );

        details.version     = info.version;
        details.release     = info.release;
        details.maintainer  = (info.maintainers.size > 0) ? info.maintainers[0] : null;
        details.license     = info.license;
        details.homepage    = info.url;
        details.summary     = info.summary;
        details.description = info.description;
        details.group       = info.category;

        foreach (var pa in info.package_archs) {
            if (pa.name == src_name) continue;
            foreach (var arch in pa.archs) {
                details.binaries.add (new BinaryPackage () {
                    name     = pa.name,
                    version  = info.version,
                    release  = info.release,
                    arch     = arch,
                    src_name = src_name
                });
            }
        }
        return details;
    }

    // ---------- Changelog ----------
    public async AltRepo.SiteChangelog get_changelog (
        string branch, string src_name, int64 last = 50, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var h = cli.get_site_pkghash_by_name (branch, src_name, cancellable);
        var pkghash = int64.parse (h.pkghash);
        return yield cli.get_site_package_changelog_pkghash_async (
            pkghash, last, Priority.DEFAULT, cancellable
        );
    }
}

}

