using Gee;
using AltRepo;

namespace Data {

public class BinaryApi : RepoApiBase {

    public async BinaryInfo get_binary_info (
        string branch, int64 pkghash, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var info = new BinaryInfo ();
        try {
            yield throttle ();
            var resp = yield cli.get_site_package_info_pkghash_async (
                branch, pkghash, 0, "binary", Priority.DEFAULT, null
            );
            info.summary = resp.summary;
            info.license = resp.license;

            var seen = new Gee.HashSet<string> ();
            foreach (var el in resp.dependencies) {
                var nm = el.name ?? "";
                if (nm.length == 0) continue;
                var t = el.type_ ?? "";
                var key = t + "\t" + nm;
                if (seen.contains (key)) continue;
                seen.add (key);
                info.deps.add (new BinaryDep () {
                    name     = nm,
                    version  = el.version,
                    dep_type = t
                });
            }
        } catch (Error e) {
            if (Validation.is_no_data_error (e)) return info;
            throw e;
        }
        return info;
    }

    public async Gee.ArrayList<BinaryFile> get_binary_files (
        int64 pkghash, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var out_list = new Gee.ArrayList<BinaryFile> ();
        try {
            yield throttle ();
            var resp = yield cli.get_package_package_files_pkghash_async (
                pkghash, Priority.DEFAULT, null
            );
            foreach (var el in resp.files) {
                var nm = el.file_name ?? "";
                if (nm.length == 0) continue;
                out_list.add (new BinaryFile () {
                    name       = nm,
                    size       = int64.parse (el.file_size ?? "0"),
                    file_class = el.file_class,
                    symlink    = el.symlink
                });
            }
            out_list.sort ((a, b) => GLib.strcmp (a.name, b.name));
        } catch (Error e) {
            if (Validation.is_no_data_error (e)) return out_list;
            throw e;
        }
        return out_list;
    }
}

}
