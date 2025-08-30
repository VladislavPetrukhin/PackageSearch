using Soup;
using Gee;

namespace Data {

public class AltRepoClient : GLib.Object {
    private const string BASE = "https://rdb.altlinux.org";
    private Soup.Session session;

    public AltRepoClient () {
        session = new Soup.Session ();
    }

    private async Json.Node get_json (string path) throws GLib.Error {
        stdout.printf ("[AltRepoClient] get_json path='%s'\n", path);
        var msg = new Soup.Message ("GET", BASE + path);

        GLib.Bytes bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, null);

        if (msg.status_code != 200)
            throw new GLib.IOError.FAILED ("HTTP %u".printf (msg.status_code));

        unowned uint8[] arr = bytes.get_data ();
        string body = (string) arr;

        var parser = new Json.Parser ();
        parser.load_from_data (body, -1);
        return parser.get_root ();
    }

    public async Gee.ArrayList<BinaryPackage> get_branch_binaries (string branch) throws GLib.Error {
        var root = yield get_json ("/api/export/branch_binary_packages/" + branch);
        var arr = root.get_array ();
        var list = new Gee.ArrayList<BinaryPackage> ();

        foreach (var node in arr.get_elements ()) {
            if (node.get_node_type () != Json.NodeType.OBJECT) continue;
            var obj = node.get_object ();

            string  name     = json_get_string_or (obj, "name", "");
            string  version  = json_get_string_or (obj, "version", "");
            string  release  = json_get_string_or (obj, "release", "");
            string  arch     = json_get_string_or (obj, "arch", "");
            string  src_name = json_get_string_or (obj, "srcname",
                                   json_get_string_or (obj, "src_name", ""));
            string? pkghash  = null;
            if (obj.has_member ("pkghash"))
                pkghash = json_get_string_or (obj, "pkghash", null);

            if (name == "" || src_name == "") continue;

            var bp = new BinaryPackage () {
                name     = name,
                version  = version,
                release  = release,
                arch     = arch,
                src_name = src_name,
                pkghash  = pkghash
            };
            list.add (bp);
        }
        return list;
    }

    public async Gee.ArrayList<BinaryPackage> search_source (string term, string branch) throws GLib.Error {
        stdout.printf ("[AltRepoClient] search_source called query='%s', branch='%s'\n", term, branch);
        var all = yield get_branch_binaries (branch);
        if (term == null || term.strip ().length == 0)
            return all;

        var out = new Gee.ArrayList<BinaryPackage> ();
        foreach (var bp in all) {
            if (bp.name != null && bp.name.index_of (term) >= 0)
                out.add (bp);
        }
        return out;
    }

    private static string? json_get_string_or (Json.Object o, string key, string? fallback) {
        if (!o.has_member (key))
            return fallback;

        var n = o.get_member (key);

        if (n.get_node_type () == Json.NodeType.VALUE && n.get_value_type () == typeof (string))
            return n.get_string ();

        if (n.get_node_type () == Json.NodeType.VALUE) {
            var t = n.get_value_type ();
            if (t == typeof (int64))   return ((int64) n.get_int ()).to_string ();
            if (t == typeof (int))     return n.get_int ().to_string ();
            if (t == typeof (double))  return n.get_double ().to_string ();
            if (t == typeof (bool))    return n.get_boolean ().to_string ();
        }
        return fallback;
    }
}

}

