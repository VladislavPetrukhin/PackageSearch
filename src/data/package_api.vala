using Gee;
using AltRepo;

namespace Data {

public class PackageApi : RepoApiBase {

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
