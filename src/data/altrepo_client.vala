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
    var url = BASE + path;
    stdout.printf ("[AltRepoClient] get_json path='%s'\n", path);
    stdout.printf ("[AltRepoClient] GET %s\n", url);

    var msg = new Soup.Message ("GET", url);

    // (опционально) идентифицируемся — иногда прокси/серты капризничают
    msg.request_headers.append ("User-Agent", "PackageSearch/0.1 (libsoup3)");

    GLib.Bytes bytes;
    try {
        stdout.printf ("[AltRepoClient] sending request...\n");
        bytes = yield session.send_and_read_async (msg, GLib.Priority.DEFAULT, null);
    } catch (Error e) {
        stdout.printf ("[AltRepoClient] send_and_read_async ERROR: domain=%s code=%d msg=%s\n",
                       e.domain.to_string (), e.code, e.message);
        // пробрасываем вверх — пусть вызывающий решает
        throw e;
    }

    stdout.printf ("[AltRepoClient] HTTP %u %s\n",
                   msg.status_code,
                   (msg.reason_phrase != null) ? msg.reason_phrase : "");

    if (msg.status_code != 200) {
        // напечатаем немного ответа, если есть
        unowned uint8[] arr_err = bytes.get_data ();
        string body_err = (string) arr_err;
        if (body_err != null && body_err.length > 0) {
            if (body_err.length > 512)
                stdout.printf ("[AltRepoClient] error body (512b): %.512s ...\n", body_err);
            else
                stdout.printf ("[AltRepoClient] error body: %s\n", body_err);
        }
        throw new GLib.IOError.FAILED ("HTTP %u".printf (msg.status_code));
    }

    unowned uint8[] arr = bytes.get_data ();
    stdout.printf ("[AltRepoClient] body bytes: %zu\n", (size_t) arr.length);

    string body = (string) arr;
    if (body != null) {
        if (body.length > 512)
            stdout.printf ("[AltRepoClient] body preview: %.512s ...\n", body);
        else
            stdout.printf ("[AltRepoClient] body preview: %s\n", body);
    } else {
        stdout.printf ("[AltRepoClient] body is NULL string-view (unexpected)\n");
    }

    var parser = new Json.Parser ();
    try {
        parser.load_from_data (body, -1);
    } catch (Error pe) {
        stdout.printf ("[AltRepoClient] JSON parse ERROR: %s\n", pe.message);
        throw pe;
    }

    var root = parser.get_root ();
    return root;
}


    public async Gee.ArrayList<BinaryPackage> get_branch_binaries (string branch) throws GLib.Error {
        var root = yield get_json ("/api/export/branch_binary_packages/" + branch);
        var arr = root.get_array ();
        var list = new Gee.ArrayList<BinaryPackage> ();

        uint total = (arr != null) ? arr.get_length () : 0;
        stdout.printf ("[AltRepoClient] parsing %u entries\n", total);
        uint added = 0;
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
            added++;
            if (added <= 5) {
            stdout.printf ("  [+] %s %s-%s.%s (src=%s)\n",
                           name, version, release, arch, src_name);
        }
        }
        stdout.printf ("[AltRepoClient] parsed %u/%u BinaryPackage\n", added, total);
        return list;
    }

    public async Gee.ArrayList<BinaryPackage> search_source (string term, string branch) throws GLib.Error {
        stdout.printf ("[AltRepoClient] search_source query='%s', branch='%s'\n", term, branch);
        var all = yield get_branch_binaries (branch);
        stdout.printf ("[AltRepoClient] branch '%s' has %u binaries\n", branch, all.size);

        if (term == null || term.strip ().length == 0)
            return all;

        var out = new Gee.ArrayList<BinaryPackage> ();
        foreach (var bp in all) {
            if (bp.name != null && bp.name.index_of (term) >= 0)
                out.add (bp);
        }
        stdout.printf ("[AltRepoClient] matched binaries for '%s'\n", term);
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
