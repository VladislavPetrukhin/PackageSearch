using Gee;
using AltRepo;

namespace Data {

public class AltRepoClient : GLib.Object {
    private AltRepo.Client cli;
    private Soup.Session   soup;

    private const string RAW_API_BASE = "https://rdb.altlinux.org/api";

    public const int SEARCH_RESULT_LIMIT = 100;

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

    private static string? jval_str (Json.Object? obj, string key) {
        if (obj == null || !obj.has_member (key)) return null;
        var m = obj.get_member (key);
        if (m == null || m.get_node_type () != Json.NodeType.VALUE) return null;
        var t = m.get_value_type ();
        if (t == typeof (string)) return m.get_string ();
        if (t == typeof (int64))  return m.get_int ().to_string ();
        if (t == typeof (double)) return ((int64) m.get_double ()).to_string ();
        return null;
    }

    private class Candidate : GLib.Object {
        public double score;
        public SourceGroup sg;
        public Candidate (double score, SourceGroup sg) {
            this.score = score;
            this.sg = sg;
        }
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

    public async Gee.ArrayList<SourceGroup> search_source (
        string branch, string term, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var term_raw = term.strip ();
        var key = "src|%s|%s".printf (branch, term_raw);
        var cached = cache_get (key);
        if (cached != null && cached.obj is Gee.ArrayList)
            return (Gee.ArrayList<SourceGroup>) cached.obj;

        yield throttle ();
        var term_n = SearchText.norm (term_raw);
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
            if (Validation.is_no_data_error (e)) { cache_put_obj (key, groups); return groups; }
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

            var name_n = SearchText.norm (pkg.name);
            double s = SearchText.score_name (name_n, term_n);
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

        int cap = (candidates.size < SEARCH_RESULT_LIMIT) ? candidates.size : SEARCH_RESULT_LIMIT;
        for (int i = 0; i < cap; i++) groups.add (candidates[i].sg);

        cache_put_obj (key, groups);
        return groups;
    }

    private const int FUZZY_MIN_TERM   = 5;
    private const int FUZZY_MIN_PROBE  = 4;
    private const int FUZZY_ENOUGH     = 3;

    private static int candidate_cmp (Candidate a, Candidate b) {
        if (a.score > b.score) return -1;
        if (a.score < b.score) return 1;
        int la = a.sg.name.length;
        int lb = b.sg.name.length;
        if (la != lb) return (la < lb) ? -1 : 1;
        return strcmp (a.sg.name, b.sg.name);
    }

    public async Gee.ArrayList<SourceGroup> search_source_fuzzy (
        string branch, string term, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var term_raw = term.strip ();
        var key = "fuzz|%s|%s".printf (branch, term_raw);
        var cached = cache_get (key);
        if (cached != null && cached.obj is Gee.ArrayList)
            return (Gee.ArrayList<SourceGroup>) cached.obj;

        var term_n = SearchText.norm (term_raw);
        var groups = new Gee.ArrayList<SourceGroup> ();
        if (term_n.length < FUZZY_MIN_TERM) { cache_put_obj (key, groups); return groups; }

        int rlen = term_raw.char_count ();
        string prefix = term_raw.substring (0, term_raw.index_of_nth_char (rlen - 1));
        string suffix = term_raw.substring (term_raw.index_of_nth_char (1));
        string[] probes = { prefix, suffix };

        int maxd = (term_n.length <= 5) ? 1 : 2;
        var cand = new Gee.ArrayList<Candidate> ();
        var seen = new Gee.HashSet<string> ();

        foreach (var probe in probes) {
            if (cancellable != null && cancellable.is_cancelled ()) break;
            if (probe.char_count () < FUZZY_MIN_PROBE) continue;
            if (cand.size >= FUZZY_ENOUGH) break;

            yield throttle ();
            AltRepo.SiteFingPackages resp;
            try {
                resp = yield cli.get_site_find_packages_async (
                    { probe }, branch, null, Priority.DEFAULT, null
                );
            } catch (Error e) {
                if (Validation.is_no_data_error (e)) continue;
                throw e;
            }

            foreach (var pkg in resp.packages) {
                if (pkg.by_binary) continue;
                if (seen.contains (pkg.name)) continue;

                AltRepo.SitePackageVersionsElement? best = null;
                foreach (var v in pkg.versions) {
                    if (v.branch == branch && !v.deleted) { best = v; break; }
                }
                if (best == null) continue;

                var name_n = SearchText.norm (pkg.name);
                int dist = SearchText.lev (name_n, term_n);
                if (dist == 0 || dist > maxd) continue;

                seen.add (pkg.name);
                var g = new SourceGroup (pkg.name);
                g.version = best.version;
                g.release = best.release;
                cand.add (new Candidate (SearchText.score_name (name_n, term_n), g));
            }
        }

        cand.sort (candidate_cmp);
        int cap = (cand.size < SEARCH_RESULT_LIMIT) ? cand.size : SEARCH_RESULT_LIMIT;
        for (int i = 0; i < cap; i++) groups.add (cand[i].sg);

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

    private const int FILE_SEARCH_LIMIT = 60;
    private const int FILE_PATHS_MAX    = 40;

    public async Gee.ArrayList<SourceGroup> search_by_file (
        string branch, string file_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var term = file_name.strip ();
        var key = "file|%s|%s".printf (branch, term);
        var cached = cache_get (key);
        if (cached != null && cached.obj is Gee.ArrayList)
            return (Gee.ArrayList<SourceGroup>) cached.obj;

        var groups = new Gee.ArrayList<SourceGroup> ();

        yield throttle ();
        AltRepo.Files fres;
        try {
            fres = yield cli.get_file_search_async (
                branch, term, FILE_SEARCH_LIMIT, Priority.DEFAULT, null
            );
        } catch (Error e) {
            if (Validation.is_no_data_error (e)) { cache_put_obj (key, groups); return groups; }
            throw e;
        }

        var paths = new Gee.ArrayList<string> ();
        var pseen = new Gee.HashSet<string> ();
        foreach (var f in fres.files) {
            if (f.file_name == null || f.file_name.length == 0) continue;
            if (pseen.contains (f.file_name)) continue;
            pseen.add (f.file_name);
            paths.add (f.file_name);
            if (paths.size >= FILE_PATHS_MAX) break;
        }
        if (paths.size == 0) { cache_put_obj (key, groups); return groups; }

        yield throttle ();
        var payload = new AltRepo.PackagesByFileNamesJson ();
        payload.branch = branch;
        payload.arch   = "x86_64";
        payload.files  = paths;

        AltRepo.PackageByFileName pres;
        try {
            pres = yield cli.post_package_packages_by_file_names_async (
                payload, Priority.DEFAULT, null
            );
        } catch (Error e) {
            if (Validation.is_no_data_error (e)) { cache_put_obj (key, groups); return groups; }
            throw e;
        }

        var nseen = new Gee.HashSet<string> ();
        foreach (var p in pres.packages) {
            if (p.name == null || p.name.length == 0 || nseen.contains (p.name)) continue;
            nseen.add (p.name);
            var g = new SourceGroup (p.name);
            g.version  = p.version;
            g.release  = p.release;
            g.bin_name = p.name;
            if (p.files != null && p.files.size > 0) g.subtitle = p.files[0];
            groups.add (g);
        }
        groups.sort ((a, b) => strcmp (a.name, b.name));
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
        bool by_package = !Validation.is_all_digits (term.strip ());
        AltRepo.TasksList resp;
        try {
            resp = yield cli.get_task_progress_find_tasks_async (
                { term }, null, branch, null, 50, by_package,
                Priority.DEFAULT, null
            );
        } catch (Error e) {
            if (Validation.is_no_data_error (e)) { cache_put_obj (key, results); return results; }
            throw e;
        }
        foreach (var t in resp.tasks) {
            var tr = new TaskResult ();
            tr.task_id = t.task_id;
            tr.state   = t.task_state ?? "";
            tr.owner   = t.task_owner ?? "";
            tr.repo    = t.task_repo ?? "";
            tr.changed = t.task_changed ?? "";
            tr.message = t.task_message ?? "";
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

    private static string subtask_display_name (AltRepo.SubTaskInfoElement st) {
        if (st.src_pkg_name != null && st.src_pkg_name.length > 0) return st.src_pkg_name;
        if (st.subtask_srpm_name != null && st.subtask_srpm_name.length > 0) return st.subtask_srpm_name;
        if (st.subtask_package != null && st.subtask_package.length > 0) return st.subtask_package;
        if (st.subtask_dir != null && st.subtask_dir.length > 0) {
            var b = GLib.Path.get_basename (st.subtask_dir);
            if (b.has_suffix (".git")) b = b.substring (0, b.length - 4);
            return b;
        }
        return "";
    }

    public async TaskDetails get_task_details (
        int64 task_id, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var key = "taskinfo|%lld".printf (task_id);
        var cached = cache_get (key);
        if (cached != null && cached.obj is TaskDetails)
            return (TaskDetails) cached.obj;

        yield throttle ();
        var d = new TaskDetails ();
        var info = yield cli.get_task_progress_task_info_id_async (
            task_id, Priority.DEFAULT, null
        );

        d.task_id   = info.task_id;
        d.state     = info.task_state ?? "";
        d.owner     = info.task_owner ?? "";
        d.repo      = info.task_repo ?? "";
        d.changed   = info.task_changed ?? "";
        d.message   = info.task_message ?? "";
        d.stage     = info.task_stage ?? "";
        d.try_num   = info.task_try;
        d.iteration = info.task_iter;
        d.testonly  = info.task_testonly != 0;

        foreach (var st in info.subtasks) {
            var ts = new TaskSubtask ();
            ts.id       = st.subtask_id;
            ts.name     = subtask_display_name (st);
            ts.kind     = st.subtask_type ?? "";
            ts.pkg_from = st.subtask_pkg_from ?? "";
            if (st.subtask_srpm_evr != null && st.subtask_srpm_evr.length > 0)
                ts.evr = st.subtask_srpm_evr;
            else if (st.subtask_tag_name != null)
                ts.evr = st.subtask_tag_name;
            d.subtasks.add (ts);
        }
        foreach (var dep in info.dependencies) d.dependencies.add (dep);

        cache_put_obj (key, d);
        return d;
    }

    public async bool is_source_deleted (
        string branch, string name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var key = "del|%s|%s".printf (branch, name.strip ());
        var cached = cache_get (key);
        if (cached != null && cached.has_str) return cached.str == "1";

        yield throttle ();
        try {
            var resp = yield cli.get_site_deleted_package_info_async (
                branch, name, "source", null, Priority.DEFAULT, cancellable
            );
            bool deleted = resp != null && resp.package != null && resp.package.length > 0;
            cache_put_str (key, deleted ? "1" : "0");
            return deleted;
        } catch (Error e) {
            string m = (e.message ?? "").down ();
            if (Validation.is_no_data_error (e) || m.contains ("no information about deleting")) {
                cache_put_str (key, "0");
                return false;
            }
            throw e;
        }
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
            if (Validation.is_no_data_error (e)) { cache_put_str (key, null); return null; }
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
            if (Validation.is_no_data_error (e)) return out_list;
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
            if (Validation.is_no_data_error (e)) return out_list;
            throw e;
        }
        return out_list;
    }

    public async string? resolve_capability_source (
        string branch, string dp_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        if (Validation.is_valid_package_name (dp_name)) return dp_name;
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
            if (Validation.is_no_data_error (e)) return null;
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
            if (Validation.is_no_data_error (e)) return out_list;
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
        var out_list = new Gee.ArrayList<BugItem> ();
        var url = "%s/bug/bugzilla_by_package?package_name=%s&package_type=source".printf (
            RAW_API_BASE,
            GLib.Uri.escape_string (src_name, null, false)
        );

        var root = yield http_get_json (url, cancellable);
        if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return out_list;

        var obj = root.get_object ();
        if (!obj.has_member ("bugs")) return out_list;

        var bugs_node = obj.get_member ("bugs");
        if (bugs_node == null || bugs_node.get_node_type () != Json.NodeType.ARRAY) return out_list;

        var arr = bugs_node.get_array ();
        for (uint i = 0; i < arr.get_length (); i++) {
            var e = arr.get_element (i);
            if (e.get_node_type () != Json.NodeType.OBJECT) continue;
            var bo = e.get_object ();

            var item = new BugItem ();
            item.id           = jval_str (bo, "id") ?? "";
            if (item.id.length == 0) continue;
            item.status       = jstr (bo, "status");
            item.resolution   = jstr (bo, "resolution");
            item.severity     = jstr (bo, "severity");
            item.component    = jstr (bo, "component");
            item.summary      = jstr (bo, "summary");
            item.assignee     = jstr (bo, "assignee");
            item.reporter     = jstr (bo, "reporter");
            item.last_changed = jstr (bo, "last_changed");
            out_list.add (item);
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
            if (!Validation.branch_allowed (v.branch)) continue;
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
