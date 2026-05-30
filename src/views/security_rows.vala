using Gtk;
using Adw;
using GLib;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/bug_row.ui")]
public class BugRow : Adw.ActionRow {
    [GtkChild] private unowned Gtk.Label status_badge;

    public string status_value { get; private set; default = ""; }

    public BugRow (Data.BugItem b) {
        Object ();
        title = "#" + b.id;
        subtitle = GLib.Markup.escape_text (b.summary ?? "", -1);

        status_value = (b.status ?? "").strip ();
        if (status_value != "") {
            status_badge.label = status_value;
            status_badge.visible = true;
        }

        string id = b.id;
        activated.connect (() => open_uri ("https://bugzilla.altlinux.org/" + id));
    }

    private static void open_uri (string url) {
        try { AppInfo.launch_default_for_uri (url, null); }
        catch (Error e) { warning ("open url failed: %s", e.message); }
    }
}

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/bug_filter_row.ui")]
public class BugFilterRow : Adw.ActionRow {
    [GtkChild] private unowned Gtk.DropDown status_dropdown;

    public signal void status_changed (uint selected);

    public BugFilterRow (string[] options) {
        Object ();
        status_dropdown.model = new Gtk.StringList (options);
        status_dropdown.notify["selected"].connect (
            () => status_changed (status_dropdown.selected)
        );
    }
}

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/errata_row.ui")]
public class ErrataRow : Adw.ExpanderRow {
    public ErrataRow (string title_text, string? subtitle_text) {
        Object ();
        title = GLib.Markup.escape_text (title_text, -1);
        if (subtitle_text != null && subtitle_text.strip () != "")
            subtitle = GLib.Markup.escape_text (subtitle_text, -1);
    }
}

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/link_row.ui")]
public class LinkRow : Adw.ActionRow {
    [GtkChild] private unowned Gtk.Image arrow;

    public LinkRow (string title_text, string? url) {
        Object ();
        title = GLib.Markup.escape_text (title_text, -1);
        if (url != null && url.strip () != "") {
            activatable = true;
            arrow.visible = true;
            string u = url;
            activated.connect (() => open_uri (u));
        }
    }

    private static void open_uri (string url) {
        try { AppInfo.launch_default_for_uri (url, null); }
        catch (Error e) { warning ("open url failed: %s", e.message); }
    }
}
