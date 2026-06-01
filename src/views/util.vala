using GLib;

namespace Ui {

    public static bool is_nonempty (string? s) {
        return s != null && s.strip ().length > 0;
    }

    public static void open_uri (string url) {
        try { AppInfo.launch_default_for_uri (url, null); }
        catch (Error e) { warning ("open url failed: %s", e.message); }
    }

    public static string normalize_url (string raw) {
        string url = (raw ?? "").strip ();
        if (url.length == 0) return url;
        if (!(url.has_prefix ("http://") || url.has_prefix ("https://")))
            url = "https://" + url;
        return url;
    }

    public static string date_only (string? iso) {
        if (iso == null) return "";
        int t = iso.index_of ("T");
        return (t > 0) ? iso.substring (0, t) : iso;
    }

    public static string trim_toast (string s) {
        const int LIMIT = 80;
        var clean = s.replace ("\n", " ").strip ();
        if (clean.length <= LIMIT) return clean;
        return clean.substring (0, LIMIT) + "…";
    }

    public static string evr (string? version, string? release) {
        string vr = version ?? "";
        if (is_nonempty (release)) vr = (vr == "") ? release : vr + "-" + release;
        return vr;
    }

    public delegate void FindFunc (string query);

    public static void attach_find_bar (Gtk.SearchBar bar, Gtk.SearchEntry entry,
                                        Gtk.Widget? capture, owned FindFunc on_query) {
        bar.connect_entry (entry);
        if (capture != null) bar.set_key_capture_widget (capture);
        entry.search_changed.connect (() => on_query (entry.text));
        bar.notify["search-mode-enabled"].connect (() => {
            if (!bar.search_mode_enabled) on_query ("");
        });
    }
}
