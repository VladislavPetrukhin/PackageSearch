using Gee;
using AltRepo;

namespace Data {

public abstract class RepoApiBase : GLib.Object {
    protected AltRepo.Client cli;
    protected Soup.Session   soup;

    protected const string RAW_API_BASE = "https://rdb.altlinux.org/api";

    construct {
        cli  = new AltRepo.Client ();
        soup = new Soup.Session ();
        soup.timeout = 30;
    }

    protected async Json.Node? http_get_json (
        string url, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        yield throttle ();
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

    protected static string? jstr (Json.Object? obj, string key) {
        if (obj == null || !obj.has_member (key)) return null;
        var m = obj.get_member (key);
        if (m == null || m.get_node_type () != Json.NodeType.VALUE) return null;
        return m.get_string ();
    }

    protected static string? jval_str (Json.Object? obj, string key) {
        if (obj == null || !obj.has_member (key)) return null;
        var m = obj.get_member (key);
        if (m == null || m.get_node_type () != Json.NodeType.VALUE) return null;
        var t = m.get_value_type ();
        if (t == typeof (string)) return m.get_string ();
        if (t == typeof (int64))  return m.get_int ().to_string ();
        if (t == typeof (double)) return ((int64) m.get_double ()).to_string ();
        return null;
    }

    private static int64 last_req_ms = 0;
    private const int    MIN_INTERVAL_MS = 450;

    protected static async void throttle () {
        var now = GLib.get_monotonic_time () / 1000;
        var wait = MIN_INTERVAL_MS - (int) (now - last_req_ms);
        if (wait > 0) {
            var src = new GLib.TimeoutSource ((uint) wait);
            src.set_callback (() => {
                throttle.callback ();
                return GLib.Source.REMOVE;
            });
            src.attach (GLib.MainContext.default ());
            yield;
        }
        last_req_ms = GLib.get_monotonic_time () / 1000;
    }

    protected class CacheBox : GLib.Object {
        public int64       ts;
        public GLib.Object? obj;
        public string?     str;
        public bool        has_str;
    }

    private const int64 CACHE_TTL_MS = 90000;
    private const int   CACHE_MAX    = 200;
    private static Gee.HashMap<string, CacheBox>? search_cache = null;

    protected static CacheBox? cache_get (string key) {
        if (search_cache == null) return null;
        var box = search_cache.get (key);
        if (box == null) return null;
        if (GLib.get_monotonic_time () / 1000 - box.ts > CACHE_TTL_MS) {
            search_cache.unset (key);
            return null;
        }
        return box;
    }

    protected static void cache_put_obj (string key, GLib.Object? o) {
        if (search_cache == null) search_cache = new Gee.HashMap<string, CacheBox> ();
        if (search_cache.size >= CACHE_MAX) search_cache.clear ();
        var box = new CacheBox ();
        box.ts = GLib.get_monotonic_time () / 1000;
        box.obj = o;
        search_cache.set (key, box);
    }

    protected static void cache_put_str (string key, string? s) {
        if (search_cache == null) search_cache = new Gee.HashMap<string, CacheBox> ();
        if (search_cache.size >= CACHE_MAX) search_cache.clear ();
        var box = new CacheBox ();
        box.ts = GLib.get_monotonic_time () / 1000;
        box.str = s;
        box.has_str = true;
        search_cache.set (key, box);
    }
}

}
