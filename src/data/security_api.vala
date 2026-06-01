using Gee;
using AltRepo;

namespace Data {

public class SecurityApi : RepoApiBase {

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
}

}
