using Gee;
using AltRepo;

namespace Data {

public class AltRepoClient : GLib.Object {
    private AltRepo.Client cli;
    private Soup.Session   soup;

    private const string RAW_API_BASE = "https://rdb.altlinux.org/api";

    private const string[] ALLOWED_BRANCHES = {
        "sisyphus", "p11", "p10", "p9", "c10f2", "c9f2"
    };

    public static bool branch_allowed (string? b) {
        if (b == null) return false;
        var lc = b.down ();
        foreach (var a in ALLOWED_BRANCHES) if (a == lc) return true;
        return false;
    }

    public AltRepoClient () {
        cli  = new AltRepo.Client ();
        soup = new Soup.Session ();
        soup.timeout = 30;
    }

    private async Json.Node? http_get_json (
        string url, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var msg = new Soup.Message ("GET", url);
        var bytes = yield soup.send_and_read_async (
            msg, GLib.Priority.DEFAULT, cancellable
        );
        if (msg.status_code < 200 || msg.status_code >= 300) return null;

        unowned uint8[] raw = bytes.get_data ();
        var parser = new Json.Parser ();
        parser.load_from_data ((string) raw, (ssize_t) raw.length);
        return parser.get_root ();
    }

    private static string? jstr (Json.Object? obj, string key) {
        if (obj == null || !obj.has_member (key)) return null;
        var m = obj.get_member (key);
        if (m == null || m.get_node_type () != Json.NodeType.VALUE) return null;
        return m.get_string ();
    }

    private class Candidate : GLib.Object {
        public double score;
        public SourceGroup sg;
        public Candidate (double score, SourceGroup sg) {
            this.score = score;
            this.sg = sg;
        }
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

    private static bool is_no_data_error (GLib.Error e) {
        if (e == null) return false;
        string m = (e.message ?? "").down ();
        return m.contains ("no data not found in database")
            || m.contains ("no data found in database")
            || m.contains ("no data found in db")
            || m.contains ("no information found")
            || m.contains ("no errata data found")
            || m.contains ("node isn't array")
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

    private static int64 last_req_ms = 0;
    private const int    MIN_INTERVAL_MS = 450;

    private static async void throttle () {
        var now = GLib.get_monotonic_time () / 1000;
        var wait = MIN_INTERVAL_MS - (int) (now - last_req_ms);
        if (wait > 0) {
            var src = new GLib.TimeoutSource ((uint) wait);
            src.set_callback (() => {
                throttle.callback ();
                return GLib.Source.REMOVE;
            });
            src.attach (GLib.MainContext.default ());
            yield;
        }
        last_req_ms = GLib.get_monotonic_time () / 1000;
    }

    private class CacheBox : GLib.Object {
        public int64       ts;
        public GLib.Object? obj;
        public string?     str;
        public bool        has_str;
    }

    private const int64 CACHE_TTL_MS = 90000;
    private const int   CACHE_MAX    = 200;
    private static Gee.HashMap<string, CacheBox>? search_cache = null;

    private static CacheBox? cache_get (string key) {
        if (search_cache == null) return null;
        var box = search_cache.get (key);
        if (box == null) return null;
        if (GLib.get_monotonic_time () / 1000 - box.ts > CACHE_TTL_MS) {
            search_cache.unset (key);
            return null;
        }
        return box;
    }

    private static void cache_put_obj (string key, GLib.Object? o) {
        if (search_cache == null) search_cache = new Gee.HashMap<string, CacheBox> ();
        if (search_cache.size >= CACHE_MAX) search_cache.clear ();
        var box = new CacheBox ();
        box.ts = GLib.get_monotonic_time () / 1000;
        box.obj = o;
        search_cache.set (key, box);
    }

    private static void cache_put_str (string key, string? s) {
        if (search_cache == null) search_cache = new Gee.HashMap<string, CacheBox> ();
        if (search_cache.size >= CACHE_MAX) search_cache.clear ();
        var box = new CacheBox ();
        box.ts = GLib.get_monotonic_time () / 1000;
        box.str = s;
        box.has_str = true;
        search_cache.set (key, box);
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

    private static double score_name (string name, string term) {
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

    public async Gee.ArrayList<SourceGroup> search_source (
        string branch, string term, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var term_raw = term.strip ();
        var key = "src|%s|%s".printf (branch, term_raw);
        var cached = cache_get (key);
        if (cached != null && cached.obj is Gee.ArrayList)
            return (Gee.ArrayList<SourceGroup>) cached.obj;

        yield throttle ();
        var term_n = norm (term_raw);
        if (term_n.length < 2) return new Gee.ArrayList<SourceGroup> ();

        var groups = new Gee.ArrayList<SourceGroup> ();
        AltRepo.SiteFingPackages resp;
        try {
            resp = yield cli.get_site_find_packages_async (
                { term_raw },
                branch,
                null,
                Priority.DEFAULT,
                null
            );
        } catch (Error e) {
            if (is_no_data_error (e)) { cache_put_obj (key, groups); return groups; }
            throw e;
        }

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

            int la = a.sg.name.length;
            int lb = b.sg.name.length;
            if (la != lb) return (la < lb) ? -1 : 1;

            return strcmp (a.sg.name, b.sg.name);
        });

        int cap = (candidates.size < 100) ? candidates.size : 100;
        for (int i = 0; i < cap; i++) groups.add (candidates[i].sg);

        cache_put_obj (key, groups);
        return groups;
    }

    public async PackageDetails get_source_details (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var details = new PackageDetails ();

        var h = cli.get_site_pkghash_by_name (branch, src_name, null);
        var pkghash = int64.parse (h.pkghash);

        yield throttle ();
        var info = yield cli.get_site_package_info_pkghash_async (
            branch, pkghash, 50, "source", Priority.DEFAULT, null
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
            var non_src_arches = new Gee.ArrayList<string> ();
            foreach (var arch in pa.archs) {
                if (arch != null && arch.down () != "src")
                    non_src_arches.add (arch);
            }

            if (non_src_arches.size == 0)
                continue;
            foreach (var arch in non_src_arches) {
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

    public async Gee.ArrayList<SourceGroup> search_by_file (
        string branch, string file_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var key = "file|%s|%s".printf (branch, file_name.strip ());
        var cached = cache_get (key);
        if (cached != null && cached.obj is Gee.ArrayList)
            return (Gee.ArrayList<SourceGroup>) cached.obj;

        yield throttle ();
        var groups = new Gee.ArrayList<SourceGroup> ();
        AltRepo.FilePackagesByFile resp;
        try {
            resp = yield cli.get_file_packages_by_file_async (
                branch, file_name, Priority.DEFAULT, null
            );
        } catch (Error e) {
            if (is_no_data_error (e)) { cache_put_obj (key, groups); return groups; }
            throw e;
        }
        var seen = new Gee.HashSet<string> ();
        foreach (var pkg in resp.packages) {
            if (pkg.name == null || seen.contains (pkg.name)) continue;
            seen.add (pkg.name);
            var g = new SourceGroup (pkg.name);
            g.version = pkg.version;
            g.release = pkg.release;
            groups.add (g);
        }
        cache_put_obj (key, groups);
        return groups;
    }

    public async Gee.ArrayList<SourceGroup> search_by_maintainer (
        string branch, string maintainer, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var key = "maint|%s|%s".printf (branch, maintainer.strip ());
        var cached = cache_get (key);
        if (cached != null && cached.obj is Gee.ArrayList)
            return (Gee.ArrayList<SourceGroup>) cached.obj;

        yield throttle ();
        var groups = new Gee.ArrayList<SourceGroup> ();

        var url = "%s/site/maintainer_packages?branch=%s&maintainer_nickname=%s".printf (
            RAW_API_BASE,
            GLib.Uri.escape_string (branch, null, false),
            GLib.Uri.escape_string (maintainer, null, false)
        );

        var root = yield http_get_json (url, cancellable);
        if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return groups;

        var obj = root.get_object ();
        if (!obj.has_member ("packages")) return groups;

        var pkgs_node = obj.get_member ("packages");
        if (pkgs_node == null || pkgs_node.get_node_type () != Json.NodeType.ARRAY) return groups;

        var arr = pkgs_node.get_array ();
        for (uint i = 0; i < arr.get_length (); i++) {
            var e = arr.get_element (i);
            if (e.get_node_type () != Json.NodeType.OBJECT) continue;
            var po = e.get_object ();
            var name = jstr (po, "name");
            if (name == null || name.length == 0) continue;

            var g = new SourceGroup (name);
            g.version = jstr (po, "version");
            g.release = jstr (po, "release");
            groups.add (g);
        }
        groups.sort ((a, b) => strcmp (a.name, b.name));
        cache_put_obj (key, groups);
        return groups;
    }

    public async Gee.ArrayList<TaskResult> search_tasks (
        string term, string? branch = null, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var key = "task|%s|%s".printf (branch ?? "", term.strip ());
        var cached = cache_get (key);
        if (cached != null && cached.obj is Gee.ArrayList)
            return (Gee.ArrayList<TaskResult>) cached.obj;

        yield throttle ();
        var results = new Gee.ArrayList<TaskResult> ();
        AltRepo.TasksList resp;
        try {
            resp = yield cli.get_task_progress_find_tasks_async (
                { term }, null, branch, null, 50, true,
                Priority.DEFAULT, null
            );
        } catch (Error e) {
            if (is_no_data_error (e)) { cache_put_obj (key, results); return results; }
            throw e;
        }
        foreach (var t in resp.tasks) {
            var tr = new TaskResult ();
            tr.task_id = t.task_id;
            tr.state   = t.task_state ?? "";
            tr.owner   = t.task_owner ?? "";
            tr.repo    = t.task_repo ?? "";
            tr.changed = t.task_changed ?? "";
            var pkg_names = new Gee.ArrayList<string> ();
            foreach (var st in t.subtasks) {
                if (st.subtask_srpm_name != null && st.subtask_srpm_name.length > 0)
                    pkg_names.add (st.subtask_srpm_name);
            }
            tr.packages = string.joinv (", ", (string[]) pkg_names.to_array ());
            results.add (tr);
        }
        cache_put_obj (key, results);
        return results;
    }

    public async string? find_source_by_binary (
        string branch, string binary_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var key = "bin|%s|%s".printf (branch, binary_name.strip ());
        var cached = cache_get (key);
        if (cached != null && cached.has_str) return cached.str;

        yield throttle ();
        AltRepo.FindSourcePackageInBranch resp;
        try {
            resp = yield cli.get_site_find_source_package_async (
                branch, binary_name, Priority.DEFAULT, null
            );
        } catch (Error e) {
            if (is_no_data_error (e)) { cache_put_str (key, null); return null; }
            throw e;
        }
        if (resp.source_package != null && resp.source_package.length > 0) {
            cache_put_str (key, resp.source_package);
            return resp.source_package;
        }
        cache_put_str (key, null);
        return null;
    }

    public async AltRepo.SiteChangelog get_changelog (
        string branch, string src_name, int64 last = 50, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var h = cli.get_site_pkghash_by_name (branch, src_name, null);
        var pkghash = int64.parse (h.pkghash);
        yield throttle ();
        return yield cli.get_site_package_changelog_pkghash_async (
            pkghash, last, Priority.DEFAULT, null
        );
    }

    public async Gee.ArrayList<DependencyPackage> get_direct_build_depends (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var out_list = new Gee.ArrayList<DependencyPackage> ();
        var seen = new Gee.HashSet<string> ();
        try {
            yield throttle ();
            var h = cli.get_site_pkghash_by_name (branch, src_name, null);
            var pkghash = int64.parse (h.pkghash);
            yield throttle ();
            var resp = yield cli.get_dependencies_source_package_dependencies_pkghash_async (
                branch, pkghash, 1, Priority.DEFAULT, null
            );
            foreach (var el in resp.dependencies) {
                var nm = el.name ?? "";
                if (nm.length == 0 || seen.contains (nm)) continue;
                if (nm.has_prefix ("/") || nm.has_prefix ("rpmlib(") || nm.has_prefix ("rtld("))
                    continue;
                seen.add (nm);
                var dp = new DependencyPackage ();
                dp.name    = nm;
                dp.version = el.version;
                dp.branch  = branch;
                out_list.add (dp);
            }
        } catch (Error e) {
            if (is_no_data_error (e)) return out_list;
            throw e;
        }
        return out_list;
    }

    public async Gee.ArrayList<DependencyPackage> get_reverse_depends (
        string branch, string src_name, string? dp_type = "both",
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var out_list = new Gee.ArrayList<DependencyPackage> ();
        try {
            yield throttle ();
            var resp = yield cli.get_dependencies_what_depends_src_async (
                src_name, branch, dp_type, Priority.DEFAULT, null
            );
            foreach (var el in resp.dependencies) {
                var dp = new DependencyPackage ();
                dp.name   = el.name ?? "";
                dp.branch = el.branch;
                out_list.add (dp);
            }
        } catch (Error e) {
            if (is_no_data_error (e)) return out_list;
            throw e;
        }
        return out_list;
    }

    public async string? resolve_capability_source (
        string branch, string dp_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        if (is_valid_package_name (dp_name)) return dp_name;
        try {
            yield throttle ();
            var resp = yield cli.get_dependencies_packages_by_dependency_async (
                branch, dp_name, "all", Priority.DEFAULT, null
            );
            if (resp.packages == null || resp.packages.size == 0) return null;
            string? bin = null;
            foreach (var el in resp.packages) {
                if (el.name != null && el.name.length > 0) { bin = el.name; break; }
            }
            if (bin == null) return null;
            var src = yield find_source_by_binary (branch, bin);
            return (src != null) ? src : bin;
        } catch (Error e) {
            if (is_no_data_error (e)) return null;
            throw e;
        }
    }

    public async Gee.ArrayList<DependencyPackage> get_dependents_of_binary (
        string branch, string bin_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var out_list = new Gee.ArrayList<DependencyPackage> ();
        var resp = yield cli.get_dependencies_packages_by_dependency_async (
            branch, bin_name, "all", Priority.DEFAULT, null
        );
        foreach (var el in resp.packages) {
            var dp = new DependencyPackage ();
            dp.name    = el.name ?? "";
            dp.version = el.version;
            dp.release = el.release;
            dp.arch    = el.arch;
            dp.summary = el.summary;
            out_list.add (dp);
        }
        return out_list;
    }

    public async VulnerabilityItem? get_cve_info (
        string cve_id, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var resp = yield cli.get_vuln_cve_async (cve_id, true, Priority.DEFAULT, null);
        if (resp == null || resp.vuln_info == null) return null;
        var v = resp.vuln_info;
        var item = new VulnerabilityItem ();
        item.id        = v.id ?? cve_id;
        item.summary   = v.summary;
        item.severity  = v.severity;
        item.score     = v.score;
        item.url       = v.url;
        item.published = v.published;
        item.modified  = v.modified;
        return item;
    }

    public async Gee.ArrayList<VulnFixPackage> get_cve_fixes (
        string cve_id, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var out_list = new Gee.ArrayList<VulnFixPackage> ();
        var resp = yield cli.get_vuln_cve_fixes_async (cve_id, true, Priority.DEFAULT, null);
        foreach (var el in resp.packages) {
            var p = new VulnFixPackage ();
            p.name       = el.name ?? "";
            p.version    = el.version;
            p.release    = el.release;
            p.branch     = el.branch;
            p.errata_id  = el.errata_id;
            p.task_id    = el.task_id;
            p.task_state = el.task_state;
            out_list.add (p);
        }
        return out_list;
    }

    public async Gee.ArrayList<ErrataInfo> get_errata_for_package (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var out_list = new Gee.ArrayList<ErrataInfo> ();
        AltRepo.Erratas? resp = null;
        try {
            resp = yield cli.get_errata_search_async (
                branch, src_name, null, null, Priority.DEFAULT, null
            );
        } catch (Error e) {
            if (is_no_data_error (e)) return out_list;
            throw e;
        }
        if (resp == null) return out_list;
        foreach (var er in resp.erratas) {
            var item = new ErrataInfo ();
            item.id          = er.id ?? "";
            item.errata_type = er.type_ ?? "";
            item.created     = er.created;
            item.updated     = er.updated;
            item.pkgset_name = er.pkgset_name;
            item.pkg_version = er.pkg_version;
            item.pkg_release = er.pkg_release;
            foreach (var r in er.references) {
                var rr = new ErrataRef ();
                rr.id       = r.id ?? "";
                rr.ref_type = r.type_ ?? "";
                item.references.add (rr);
            }
            out_list.add (item);
        }
        return out_list;
    }

    public async Gee.ArrayList<BugItem> get_bugs_by_package (
        string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var out_list = new Gee.ArrayList<BugItem> ();
        Gee.List<AltRepo.BugzillaInfo>? resp_list = null;
        try {
            resp_list = yield cli.get_bug_bugzilla_by_package_async (
                src_name, "source", Priority.DEFAULT, null
            );
        } catch (Error e) {
            if (is_no_data_error (e)) return out_list;
            throw e;
        }
        if (resp_list == null) return out_list;
        foreach (var resp in resp_list) {
            foreach (var b in resp.bugs) {
                var item = new BugItem ();
                item.id           = b.id ?? "";
                item.status       = b.status;
                item.resolution   = b.resolution;
                item.severity     = b.severity;
                item.component    = b.component;
                item.summary      = b.summary;
                item.assignee     = b.assignee;
                item.reporter     = b.reporter;
                item.last_changed = b.last_changed;
                out_list.add (item);
            }
        }
        return out_list;
    }

    public async Gee.ArrayList<BranchVersion> get_package_versions_all (
        string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var out_list = new Gee.ArrayList<BranchVersion> ();
        var resp = yield cli.get_site_package_versions_async (
            src_name, "source", null, Priority.DEFAULT, null
        );
        foreach (var v in resp.versions) {
            if (!branch_allowed (v.branch)) continue;
            var bv = new BranchVersion ();
            bv.branch  = v.branch ?? "";
            bv.version = v.version;
            bv.release = v.release;
            bv.pkghash = v.pkghash;
            out_list.add (bv);
        }
        return out_list;
    }

    public async AltRepo.PackagesetCompare compare_packagesets (
        string pkgset1, string pkgset2, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        return yield cli.get_packageset_compare_packagesets_async (
            pkgset1, pkgset2, Priority.DEFAULT, null
        );
    }

    public async Gee.ArrayList<DownloadLink> get_source_downloads (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var out_list = new Gee.ArrayList<DownloadLink> ();
        var h = cli.get_site_pkghash_by_name (branch, src_name, null);
        var pkghash = int64.parse (h.pkghash);
        yield throttle ();
        var resp = yield cli.get_site_package_downloads_src_pkghash_async (
            branch, pkghash, Priority.DEFAULT, null
        );
        foreach (var el in resp.downloads) {
            foreach (var pkg in el.packages) {
                var d = new DownloadLink ();
                d.name = pkg.name ?? "";
                d.arch = el.arch ?? "src";
                d.url  = pkg.url;
                d.size = pkg.size;
                d.md5  = pkg.md5;
                out_list.add (d);
            }
        }
        return out_list;
    }

    public async Gee.ArrayList<DownloadLink> get_binary_downloads (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var out_list = new Gee.ArrayList<DownloadLink> ();
        var h = cli.get_site_pkghash_by_name (branch, src_name, null);
        var pkghash = int64.parse (h.pkghash);
        yield throttle ();
        var resp = yield cli.get_site_package_downloads_pkghash_async (
            branch, pkghash, Priority.DEFAULT, null
        );
        foreach (var el in resp.downloads) {
            foreach (var pkg in el.packages) {
                var d = new DownloadLink ();
                d.name = pkg.name ?? "";
                d.arch = el.arch;
                d.url  = pkg.url;
                d.size = pkg.size;
                d.md5  = pkg.md5;
                out_list.add (d);
            }
        }
        return out_list;
    }

    public async SpecFileInfo get_specfile (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var spec = new SpecFileInfo ();
        var resp = yield cli.get_package_specfile_by_name_async (
            branch, src_name, Priority.DEFAULT, null
        );
        spec.name = resp.specfile_name;
        spec.date = resp.specfile_date;
        if (resp.specfile_content != null && resp.specfile_content.length > 0) {
            var raw = GLib.Base64.decode (resp.specfile_content);
            var buf = new uint8[raw.length + 1];
            Memory.copy (buf, raw, raw.length);
            buf[raw.length] = 0;
            spec.content = (string) buf;
        }
        return spec;
    }
}

}
