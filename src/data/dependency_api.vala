using Gee;
using AltRepo;

namespace Data {

public class DependencyApi : RepoApiBase {

    public async Gee.ArrayList<DependencyPackage> get_direct_build_depends (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var out_list = new Gee.ArrayList<DependencyPackage> ();
        var seen = new Gee.HashSet<string> ();
        try {
            yield throttle ();
            var h = yield cli.get_site_pkghash_by_name_async (
                branch, src_name, Priority.DEFAULT, null
            );
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
            var src = yield new SearchApi ().find_source_by_binary (branch, bin, null);
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
}

}
