using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/history_popover.ui")]
public class HistoryPopover : Gtk.Popover {
    [GtkChild] private unowned Gtk.Label   empty_label;
    [GtkChild] private unowned Gtk.ListBox list;

    public signal void query_chosen (string query);

    public void set_items (string[] items) {
        Gtk.Widget? c;
        while ((c = list.get_first_child ()) != null) list.remove (c);

        bool any = items.length > 0;
        empty_label.visible = !any;
        list.visible = any;

        foreach (var q in items) {
            var row = new Adw.ActionRow () { title = q, activatable = true };
            row.add_prefix (new Gtk.Image.from_icon_name ("document-open-recent-symbolic"));
            string captured = q;
            row.activated.connect (() => {
                query_chosen (captured);
                popdown ();
            });
            list.append (row);
        }
    }
}
