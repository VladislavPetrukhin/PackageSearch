using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/lazy_expander_row.ui")]
public class LazyExpanderRow : Adw.ExpanderRow {
    [GtkChild] private unowned Adw.ActionRow placeholder;

    private bool started = false;
    private bool placeholder_cleared = false;

    public signal void load_requested ();

    construct {
        notify["expanded"].connect (() => {
            if (started || !expanded) return;
            started = true;
            load_requested ();
        });
    }

    public void clear_placeholder () {
        if (!placeholder_cleared) {
            remove (placeholder);
            placeholder_cleared = true;
        }
    }

    public void show_message (string title_text, string? subtitle_text = null) {
        clear_placeholder ();
        var row = new Adw.ActionRow () { title = title_text };
        if (subtitle_text != null)
            row.subtitle = GLib.Markup.escape_text (subtitle_text, -1);
        add_row (row);
    }
}
