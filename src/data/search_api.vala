using Gee;
using AltRepo;

namespace Data {

public class SearchApi : RepoApiBase {

    public const int SEARCH_RESULT_LIMIT = 100;

    private class Candidate : GLib.Object {
        public double score;
        public SourceGroup sg;
        public Candidate (double score, SourceGroup sg) {
            this.score = score;
            this.sg = sg;
        }
    }

    private static int candidate_cmp (Candidate a, Candidate b) {
        if (a.score > b.score) return -1;
        if (a.score < b.score) return 1;
        int la = a.sg.name.length;
        int lb = b.sg.name.length;
        if (la != lb) return (la < lb) ? -1 : 1;
        return strcmp (a.sg.name, b.sg.name);
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

        candidates.sort (candidate_cmp);

        int cap = (candidates.size < SEARCH_RESULT_LIMIT) ? candidates.size : SEARCH_RESULT_LIMIT;
        for (int i = 0; i < cap; i++) groups.add (candidates[i].sg);

        cache_put_obj (key, groups);
        return groups;
    }

    private const int FUZZY_MIN_TERM   = 5;
    private const int FUZZY_MIN_PROBE  = 4;
    private const int FUZZY_ENOUGH     = 3;

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
}

}
