using Gee;
using AltRepo;

namespace Data {

public class AltRepoClient : GLib.Object {
    private AltRepo.Client cli;

    public AltRepoClient () {
        cli = new AltRepo.Client ();
    }

    private class Candidate : GLib.Object {
        public double score;
        public SourceGroup sg;
        public Candidate (double score, SourceGroup sg) {
            this.score = score;
            this.sg = sg;
        }
    }

    // --- helpers ---
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

    private static double score_name (string name, string term) {
        if (name == term) return 100.0;
        if (name.has_prefix (term)) return 90.0;
        if (name.index_of (term) >= 0) return 80.0;

        int dist = lev (name, term);
        int L = (name.length > term.length) ? name.length : term.length;
        double sim = 1.0 - ((double) dist / (double) L); // 0..1
        if (sim < 0.0) sim = 0.0;
        return 70.0 * sim; // 0..70
    }

    // Поиск source-пакетов по имени в ветке
    public async Gee.ArrayList<SourceGroup> search_source (
        string branch, string term, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        // Расширяем лимит, иначе «firefox» может не попасть в сырой ответ
        const int LIMIT = 500;

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



        // Соберём кандидатов (только источники)
        var candidates = new Gee.ArrayList<Candidate> ();
        foreach (var pkg in resp.packages) {
            if (pkg.by_binary) continue;

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

       candidates.sort ((a, b) => {
            if (a.score > b.score) return -1;
            if (a.score < b.score) return 1;
            return strcmp (a.sg.name, b.sg.name);
        });

        int cap = (candidates.size < 100) ? candidates.size : 100;
        for (int i = 0; i < cap; i++) groups.add (candidates[i].sg);

        return groups;
    }

    // Детали source-пакета + список бинарей
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

    public async AltRepo.SiteChangelog get_changelog (
        string branch, string src_name, int64 last = 50, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var h = cli.get_site_pkghash_by_name (branch, src_name, cancellable);
        var pkghash = int64.parse (h.pkghash);
        return yield cli.get_site_package_changelog_pkghash_async (pkghash, last, Priority.DEFAULT, cancellable);
    }
}

}

