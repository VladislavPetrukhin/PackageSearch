using Gee;
using AltRepo;

namespace Data {

public class ImageApi : RepoApiBase {

    public async Gee.ArrayList<ImageEdition> get_images_for_source (
        string branch, string src_name, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var out_list = new Gee.ArrayList<ImageEdition> ();
        try {
            yield throttle ();
            var resp = yield cli.get_image_find_images_by_package_name_async (
                src_name, branch, null, "source", "active", Priority.DEFAULT, null
            );

            var by_edition = new Gee.HashMap<string, ImageEdition> ();
            var arches     = new Gee.HashMap<string, Gee.HashSet<string>> ();

            foreach (var el in resp.images) {
                var ed = (el.edition ?? "").strip ();
                if (ed.length == 0) continue;

                var agg = by_edition.get (ed);
                if (agg == null) {
                    agg = new ImageEdition ();
                    agg.edition = ed;
                    by_edition.set (ed, agg);
                    arches.set (ed, new Gee.HashSet<string> ());
                }

                if (el.arch != null && el.arch.length > 0)
                    arches.get (ed).add (el.arch);

                string d = el.date ?? "";
                if (d.length >= 10) d = d.substring (0, 10);
                if (agg.date == null || d > agg.date) {
                    agg.date    = d;
                    agg.version = el.version;
                }
            }

            foreach (var e in by_edition.entries) {
                var list = new Gee.ArrayList<string> ();
                list.add_all (arches.get (e.key));
                list.sort ((a, b) => GLib.strcmp (a, b));
                string astr = "";
                foreach (var a in list) astr = (astr == "") ? a : astr + ", " + a;
                e.value.arches = astr;
                out_list.add (e.value);
            }
            out_list.sort ((a, b) => GLib.strcmp (a.edition, b.edition));
        } catch (Error e) {
            if (Validation.is_no_data_error (e)) return out_list;
            throw e;
        }
        return out_list;
    }
}

}
