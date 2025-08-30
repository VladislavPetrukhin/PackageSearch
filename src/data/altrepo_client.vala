// src/data/altrepo_client.vala
using Gee;
using AltRepo;

namespace Data {

public class AltRepoClient : GLib.Object {
    private AltRepo.Client cli;

    public AltRepoClient () {
        cli = new AltRepo.Client ();
    }

    // Поиск source-пакетов по имени в ветке
    public async Gee.ArrayList<SourceGroup> search_source (
        string branch, string term, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        stdout.printf ("[AltRepoClient] search_source term='%s', branch='%s'\n", term, branch);

        var groups = new Gee.ArrayList<SourceGroup> ();
        var resp = yield cli.get_site_find_packages_async ({ term }, branch, null, Priority.DEFAULT, cancellable);

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
            groups.add (g);
        }
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
            branch, pkghash, 20, "source", Priority.DEFAULT, cancellable
        );

        details.version     = info.version;
        details.release     = info.release;
        details.maintainer  = (info.maintainers.size > 0) ? info.maintainers[0] : null;
        details.license     = info.license;
        details.homepage    = info.url;
        details.summary     = info.summary;
        details.description = info.description;
        // details.group = info.group; // если в твоей .vapi это свойство появится — раскомментируй

        foreach (var pa in info.package_archs) {
            if (pa.name == src_name) continue; // это сам source
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

    // Ченджлог (для раскрывающегося списка)
    public async AltRepo.SiteChangelog get_changelog (
        string branch, string src_name, int64 last = 50, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var h = cli.get_site_pkghash_by_name (branch, src_name, cancellable);
        var pkghash = int64.parse (h.pkghash);
        return yield cli.get_site_package_changelog_pkghash_async (pkghash, last, Priority.DEFAULT, cancellable);
    }
}

}

