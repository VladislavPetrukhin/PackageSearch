using Gtk;
using Adw;

namespace Ui {

    public interface Findable : GLib.Object {
        public abstract void begin_find ();
    }

    public static Gtk.ListBox? listbox_in (Gtk.Widget w) {
        for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
            if (c is Gtk.ListBox) return (Gtk.ListBox) c;
            var r = listbox_in (c);
            if (r != null) return r;
        }
        return null;
    }

    private static string haystack (Gtk.Widget w) {
        string hay = "";
        var pr = w as Adw.PreferencesRow;
        if (pr != null) hay = pr.title ?? "";
        var ar = w as Adw.ActionRow;
        if (ar != null) hay += " " + (ar.subtitle ?? "");
        var er = w as Adw.ExpanderRow;
        if (er != null) hay += " " + (er.subtitle ?? "");
        return hay.down ();
    }

    public static void filter_listbox (Gtk.ListBox lb, string raw) {
        string q = raw.strip ().down ();
        for (var c = lb.get_first_child (); c != null; c = c.get_next_sibling ()) {
            if (!(c is Gtk.ListBoxRow)) continue;
            c.visible = (q.length == 0) || haystack (c).contains (q);
        }
    }

    public static void filter_group (Adw.PreferencesGroup grp, string raw) {
        string q = raw.strip ().down ();
        var lb = listbox_in (grp);
        if (lb == null) return;
        bool any = false;
        bool has_rows = false;
        for (var c = lb.get_first_child (); c != null; c = c.get_next_sibling ()) {
            if (!(c is Gtk.ListBoxRow)) continue;
            has_rows = true;
            bool m = (q.length == 0) || haystack (c).contains (q);
            c.visible = m;
            if (m) any = true;
        }
        grp.visible = (q.length == 0) ? has_rows : any;
    }
}
