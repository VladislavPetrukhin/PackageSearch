using Gee;
using AltRepo;

namespace Data {

public class DownloadApi : RepoApiBase {

    public async Gee.ArrayList<DownloadLink> get_source_downloads (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
        var out_list = new Gee.ArrayList<DownloadLink> ();
        var h = yield cli.get_site_pkghash_by_name_async (
            branch, src_name, Priority.DEFAULT, null
        );
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
        var h = yield cli.get_site_pkghash_by_name_async (
            branch, src_name, Priority.DEFAULT, null
        );
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
}

}
