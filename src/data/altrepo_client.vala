using Gee;
using AltRepo;

namespace Data {

public class AltRepoClient : GLib.Object {
    private AltRepo.Client cli;
    private Soup.Session   soup;

    // Direct HTTP base, bypassing libalt-repo for endpoints where the library
    // has mis-declared response shapes.
    private const string RAW_API_BASE = "https://rdb.altlinux.org/api";

    public AltRepoClient () {
        cli  = new AltRepo.Client ();
        soup = new Soup.Session ();
        soup.timeout = 30;
    }

    // Fetch URL, return root JSON node, or null if status is non-2xx.
    // Throws only on network/parse errors.
    private async Json.Node? http_get_json (
        string url, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
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

    // Helper: get string property from a JSON object, null-safe
    private static string? jstr (Json.Object? obj, string key) {
        if (obj == null || !obj.has_member (key)) return null;
        var m = obj.get_member (key);
        if (m == null || m.get_node_type () != Json.NodeType.VALUE) return null;
        return m.get_string ();
    }

    // Lightweight holder used for sorting search matches
    private class Candidate : GLib.Object {
        public double score;
        public SourceGroup sg;
        public Candidate (double score, SourceGroup sg) {
            this.score = score;
            this.sg = sg;
        }
    }

    // Detect "no results" responses from the API. The backend commonly
    // replies with HTTP 404 body `{"details":{},"message":"..."}`, and for
    // array-shaped endpoints the JSON layer reports "Node isn't array" when
    // it receives that error object.
    private static bool is_no_data_error (GLib.Error e) {
        if (e == null) return false;
        string m = (e.message ?? "").down ();
        return m.contains ("no data not found in database")
            || m.contains ("no information found")
            || m.contains ("node isn't array")
            || m.contains ("nothing found")
            || m.contains ("not found in database")
            || m.contains ("no packages found")
            || m.contains ("not found in the database")
            || m.contains ("http 404")
            || m.contains (" 404 ");
    }

    /* ===== Helpers: name normalization ===== */

    // Keep only [a-z0-9], lowercase. Simplifies matching/scoring.
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

    /* ===== Helpers: Levenshtein distance (byte-safe with UTF-8 indexing) ===== */

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

    /* ===== Helpers: word-boundary prefix search ===== */

    // Find term at a word boundary in name: (^|[^a-z0-9])term ; returns byte index or -1
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

    /* ===== Scoring ===== */
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

    /* ===== Search sources ===== */
    public async Gee.ArrayList<SourceGroup> search_source (
        string branch, string term, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var term_raw = term.strip ();
        var term_n = norm (term_raw);
        if (term_n.length < 2) return new Gee.ArrayList<SourceGroup> ();

        var groups = new Gee.ArrayList<SourceGroup> ();
        // NB: library mis-types this as `SiteFingPackages` (typo in upstream).
        AltRepo.SiteFingPackages resp;
        try {
            resp = yield cli.get_site_find_packages_async (
                { term_raw },       // terms (original, not normalized)
                branch,             // branch
                null,               // arch
                Priority.DEFAULT,   // priority
                null                // was: cancellable
            );
        } catch (Error e) {
            // "No data" / "No information found" → treat as empty result so
            // the UI can show the empty state (and suggest other modes).
            if (is_no_data_error (e)) return groups;
            throw e;
        }

        var candidates = new Gee.ArrayList<Candidate> ();
        foreach (var pkg in resp.packages) {
            if (pkg.by_binary) continue; // only source packages

            // Take best non-deleted version in this branch
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
            if (pkg.name.down () == term_raw.down ()) s += 5.0; // tiny boost

            candidates.add (new Candidate (s, g));
        }

        // Sort by score desc, then shorter name, then lexicographically
        candidates.sort ((a, b) => {
            if (a.score > b.score) return -1;
            if (a.score < b.score) return 1;

            int la = a.sg.name.length;
            int lb = b.sg.name.length;
            if (la != lb) return (la < lb) ? -1 : 1;

            return strcmp (a.sg.name, b.sg.name);
        });

        // Cap to top 100 items
        int cap = (candidates.size < 100) ? candidates.size : 100;
        for (int i = 0; i < cap; i++) groups.add (candidates[i].sg);

        return groups;
    }

    /* ===== Source details + binaries ===== */
    public async PackageDetails get_source_details (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var details = new PackageDetails ();

        // Resolve src_name to pkghash first
        var h = cli.get_site_pkghash_by_name (branch, src_name, null);
        var pkghash = int64.parse (h.pkghash);

        // Fetch package info by hash; we request "source" view here
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


        // Expand binary packages, skip pure source entries ("src" arch only)
        foreach (var pa in info.package_archs) {
            var non_src_arches = new Gee.ArrayList<string> ();
            foreach (var arch in pa.archs) {
                if (arch != null && arch.down () != "src")
                    non_src_arches.add (arch);
            }

            // if this is a source-only record then skip
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

    /* ===== Search by file ===== */
    public async Gee.ArrayList<SourceGroup> search_by_file (
        string branch, string file_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var groups = new Gee.ArrayList<SourceGroup> ();
        AltRepo.FilePackagesByFile resp;
        try {
            resp = yield cli.get_file_packages_by_file_async (
                branch, file_name, Priority.DEFAULT, null
            );
        } catch (Error e) {
            if (is_no_data_error (e)) return groups;
            throw e;
        }
        // Deduplicate by package name, keep first occurrence
        var seen = new Gee.HashSet<string> ();
        foreach (var pkg in resp.packages) {
            if (pkg.name == null || seen.contains (pkg.name)) continue;
            seen.add (pkg.name);
            var g = new SourceGroup (pkg.name);
            g.version = pkg.version;
            g.release = pkg.release;
            groups.add (g);
        }
        return groups;
    }

    /* ===== Search by maintainer =====
     *
     * Direct HTTP call: the libalt-repo binding mis-declares the response
     * shape for this endpoint (ArrayList<MaintainerPackages> vs. the single
     * object that the API actually returns), so we parse the JSON ourselves.
     */
    public async Gee.ArrayList<SourceGroup> search_by_maintainer (
        string branch, string maintainer, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
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
        return groups;
    }

    /* ===== Search tasks ===== */
    public async Gee.ArrayList<TaskResult> search_tasks (
        string term, string? branch = null, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var results = new Gee.ArrayList<TaskResult> ();
        AltRepo.TasksList resp;
        try {
            resp = yield cli.get_task_progress_find_tasks_async (
                { term }, null, branch, null, 50, true,
                Priority.DEFAULT, null
            );
        } catch (Error e) {
            if (is_no_data_error (e)) return results;
            throw e;
        }
        foreach (var t in resp.tasks) {
            var tr = new TaskResult ();
            tr.task_id = t.task_id;
            tr.state   = t.task_state ?? "";
            tr.owner   = t.task_owner ?? "";
            tr.repo    = t.task_repo ?? "";
            tr.changed = t.task_changed ?? "";
            // Collect package names from subtasks
            var pkg_names = new Gee.ArrayList<string> ();
            foreach (var st in t.subtasks) {
                if (st.subtask_srpm_name != null && st.subtask_srpm_name.length > 0)
                    pkg_names.add (st.subtask_srpm_name);
            }
            tr.packages = string.joinv (", ", (string[]) pkg_names.to_array ());
            results.add (tr);
        }
        return results;
    }

    /* ===== Find source package by binary name ===== */
    public async string? find_source_by_binary (
        string branch, string binary_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        AltRepo.FindSourcePackageInBranch resp;
        try {
            resp = yield cli.get_site_find_source_package_async (
                branch, binary_name, Priority.DEFAULT, null
            );
        } catch (Error e) {
            if (is_no_data_error (e)) return null;
            throw e;
        }
        if (resp.source_package != null && resp.source_package.length > 0)
            return resp.source_package;
        return null;
    }

    /* ===== Changelog ===== */
    public async AltRepo.SiteChangelog get_changelog (
        string branch, string src_name, int64 last = 50, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var h = cli.get_site_pkghash_by_name (branch, src_name, null);
        var pkghash = int64.parse (h.pkghash);
        return yield cli.get_site_package_changelog_pkghash_async (
            pkghash, last, Priority.DEFAULT, null
        );
    }

    /* ===== Build-time dependencies (what this source needs to build) ===== */
    public async Gee.ArrayList<DependencyPackage> get_build_depends (
        string branch, string src_name, string? arch = "x86_64",
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var out_list = new Gee.ArrayList<DependencyPackage> ();
        var resp = yield cli.get_package_build_dependency_set_async (
            branch, { src_name }, arch, Priority.DEFAULT, null
        );
        foreach (var grp in resp.packages) {
            foreach (var d in grp.depends) {
                var dp = new DependencyPackage ();
                dp.name    = d.name ?? "";
                dp.version = d.version;
                dp.release = d.release;
                dp.branch  = branch;
                dp.arch    = (d.archs.size > 0) ? string.joinv (", ", (string[]) d.archs.to_array ()) : null;
                out_list.add (dp);
            }
        }
        return out_list;
    }

    /* ===== Reverse dependencies (what depends on this source) ===== */
    public async Gee.ArrayList<DependencyPackage> get_reverse_depends (
        string branch, string src_name, string? dp_type = "both",
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var out_list = new Gee.ArrayList<DependencyPackage> ();
        var resp = yield cli.get_dependencies_what_depends_src_async (
            src_name, branch, dp_type, Priority.DEFAULT, null
        );
        foreach (var el in resp.dependencies) {
            var dp = new DependencyPackage ();
            dp.name   = el.name ?? "";
            dp.branch = el.branch;
            out_list.add (dp);
        }
        return out_list;
    }

    /* ===== Who depends on this binary package ===== */
    public async Gee.ArrayList<DependencyPackage> get_dependents_of_binary (
        string branch, string bin_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
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

    /* ===== CVE info ===== */
    public async VulnerabilityItem? get_cve_info (
        string cve_id, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
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

    /* ===== CVE fixes (packages closing a CVE) ===== */
    public async Gee.ArrayList<VulnFixPackage> get_cve_fixes (
        string cve_id, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
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

    /* ===== Bugzilla issues for a source package ===== */
    public async Gee.ArrayList<BugItem> get_bugs_by_package (
        string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var out_list = new Gee.ArrayList<BugItem> ();
        Gee.List<AltRepo.BugzillaInfo>? resp_list = null;
        try {
            resp_list = yield cli.get_bug_bugzilla_by_package_async (
                src_name, "source", Priority.DEFAULT, null
            );
        } catch (Error e) {
            // The API returns a 404-like error when the package has no bugs.
            // Treat that as "no results", not as an error.
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

    /* ===== Package versions across all branches ===== */
    public async Gee.ArrayList<BranchVersion> get_package_versions_all (
        string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var out_list = new Gee.ArrayList<BranchVersion> ();
        var resp = yield cli.get_site_package_versions_async (
            src_name, "source", null, Priority.DEFAULT, null
        );
        foreach (var v in resp.versions) {
            var bv = new BranchVersion ();
            bv.branch  = v.branch ?? "";
            bv.version = v.version;
            bv.release = v.release;
            bv.pkghash = v.pkghash;
            out_list.add (bv);
        }
        return out_list;
    }

    /* ===== Compare two package sets ===== */
    public async AltRepo.PackagesetCompare compare_packagesets (
        string pkgset1, string pkgset2, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        return yield cli.get_packageset_compare_packagesets_async (
            pkgset1, pkgset2, Priority.DEFAULT, null
        );
    }

    /* ===== Download links for source package (.src.rpm) ===== */
    public async Gee.ArrayList<DownloadLink> get_source_downloads (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var out_list = new Gee.ArrayList<DownloadLink> ();
        var h = cli.get_site_pkghash_by_name (branch, src_name, null);
        var pkghash = int64.parse (h.pkghash);
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

    /* ===== Download links for binaries (.rpm) produced by source ===== */
    public async Gee.ArrayList<DownloadLink> get_binary_downloads (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var out_list = new Gee.ArrayList<DownloadLink> ();
        var h = cli.get_site_pkghash_by_name (branch, src_name, null);
        var pkghash = int64.parse (h.pkghash);
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

    /* ===== Spec file (base64 -> plain text) ===== */
    public async SpecFileInfo get_specfile (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var spec = new SpecFileInfo ();
        var resp = yield cli.get_package_specfile_by_name_async (
            branch, src_name, Priority.DEFAULT, null
        );
        spec.name = resp.specfile_name;
        spec.date = resp.specfile_date;
        if (resp.specfile_content != null && resp.specfile_content.length > 0) {
            var raw = GLib.Base64.decode (resp.specfile_content);
            // Ensure null-termination before casting to a Vala string
            var buf = new uint8[raw.length + 1];
            Memory.copy (buf, raw, raw.length);
            buf[raw.length] = 0;
            spec.content = (string) buf;
        }
        return spec;
    }
}

}

