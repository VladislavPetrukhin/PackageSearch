using Gtk;
using Adw;
using GLib;
using Pango;

[GtkTemplate (ui = "/org/example/PackageSearch/ui/search_page.ui")]
public class SearchPage : Adw.NavigationPage {
    [GtkChild] private unowned Gtk.SearchEntry search_entry;
    [GtkChild] private unowned Gtk.DropDown    branch_dropdown;

    // From the .blp
    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
    [GtkChild] private unowned Gtk.Stack        content_stack;
    [GtkChild] private unowned Gtk.ListView     list_view;

    private GLib.ListStore store;
    private Gtk.SingleSelection sel;

    private uint debounce_id = 0;

    //utils
    private static bool is_nonempty (string? s) {
        return s != null && s.strip ().length > 0;
    }

    private static bool is_reasonable_term (string? s) {
        if (s == null) return false;
        string term = s.strip ();
        if (term.length < 2) return false;
        try {
            var re = new Regex ("^[A-Za-z0-9._+-]+$");
            return re.match (term);
        } catch (Error e) {
            return term.length >= 2;
        }
    }

    construct {
        // list model
        store = new GLib.ListStore (typeof (Data.SourceGroup));
        sel = new Gtk.SingleSelection (store);
        sel.autoselect = false;
        sel.can_unselect = true;
        list_view.model = sel;

        // click-to-activate (single click)
        var click = new Gtk.GestureClick ();
        click.released.connect ((n_press, x, y) => {
            if (n_press == 1) {
                int idx = (int) sel.selected;
                if (idx >= 0) {
                    list_view.activate ((uint) idx);
                }
            }
        });
        list_view.add_controller (click);

        // branches
        try {
            var branches_model = new Gtk.StringList (null);
            string[] branch_names = { "sisyphus", "p11" };
            foreach (string b in branch_names) {
                branches_model.append (b);
            }
            branch_dropdown.model = branches_model;
            branch_dropdown.selected = 0;
        } catch (Error e) {
            warning ("[SearchPage] failed to init branches: %s", e.message);
        }

        // factory
        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((obj) => {
            var item = obj as Gtk.ListItem;
            if (item == null) { warning ("[SearchPage] setup: obj is not Gtk.ListItem"); return; }

            var row = new Gtk.Box (Orientation.VERTICAL, 0);
            row.margin_top = 8; row.margin_bottom = 8; row.margin_start = 12; row.margin_end = 12;

            var title = new Gtk.Label ("");
            title.halign = Align.START;
            title.ellipsize = Pango.EllipsizeMode.END;
            title.add_css_class ("title-3");

            var subtitle = new Gtk.Label ("");
            subtitle.halign = Align.START;
            subtitle.ellipsize = Pango.EllipsizeMode.END;
            subtitle.add_css_class ("dim-label");

            row.append (title);
            row.append (subtitle);
            item.set_child (row);
        });

        factory.bind.connect ((obj) => {
            var item = obj as Gtk.ListItem;
            if (item == null) { warning ("[SearchPage] bind: obj is not Gtk.ListItem"); return; }

            var row = item.get_child () as Gtk.Box;
            if (row == null) return;

            var title = row.get_first_child () as Gtk.Label;
            var subtitle = (title != null) ? (title.get_next_sibling () as Gtk.Label) : null;

            var sg = item.get_item () as Data.SourceGroup;
            if (sg == null) { warning ("[SearchPage] bind: item.get_item() null/invalid"); return; }

            if (title != null) title.label = sg.name;

            string vr = "";
            if (is_nonempty (sg.version)) vr = sg.version;
            if (is_nonempty (sg.release))
                vr = (vr == "") ? sg.release : vr + "-" + sg.release;

            if (subtitle != null) subtitle.label = vr;
        });

        list_view.factory = factory;

        // row activation -> open details
        list_view.activate.connect ((pos) => {
            uint position = (uint) pos;
            var obj = store.get_item ((int) position);
            var sg = obj as Data.SourceGroup;
            if (sg == null) { warning ("[SearchPage] activate: selected item null/invalid"); return; }
            var branch = current_branch ();
            var win = this.get_root () as MainWindow;
            if (win != null) win.show_details (sg, branch);
            else warning ("[SearchPage] MainWindow not found — can't open details");
        });

        // initial state
        show_idle ();

        // events
        search_entry.search_changed.connect (() => debounce_search ());
        search_entry.activate.connect (() => trigger_search_now ());
        branch_dropdown.notify["selected"].connect (() => trigger_search_now ());
    }

    //stack state helpers
    private void show_idle ()    { content_stack.set_visible_child_name ("idle"); }
    private void show_loading () { content_stack.set_visible_child_name ("loading"); }
    private void show_results () { content_stack.set_visible_child_name ("results"); }
    private void show_empty ()   { content_stack.set_visible_child_name ("empty"); }
    private void show_error ()   { content_stack.set_visible_child_name ("error"); }

    private string current_branch () {
        int idx = (int) branch_dropdown.selected;
        var m = branch_dropdown.model as Gtk.StringList;
        if (m == null || idx < 0) return "sisyphus";
        return m.get_string ((uint) idx);
    }

    // search triggering with debounce
    private void debounce_search () {
        if (debounce_id != 0) {
            Source.remove (debounce_id);
            debounce_id = 0;
        }
        var term = (search_entry.text ?? "").strip ();
        if (term.length == 0) {
            // clear and go idle
            store.remove_all ();
            show_idle ();
            return;
        }
        // 250ms debounce
        debounce_id = Timeout.add (250, () => {
            trigger_search_now ();
            debounce_id = 0;
            return Source.REMOVE;
        });
    }

    private void trigger_search_now () {
        if (debounce_id != 0) {
            Source.remove (debounce_id);
            debounce_id = 0;
        }
        do_search.begin ();
    }

    /* ---------- async search ---------- */
    private async void do_search () {
        var term = (search_entry.text ?? "").strip ();
        var branch = current_branch ();
        debug ("[SearchPage] do_search(): term='%s', branch='%s'", term, branch);

        if (!is_reasonable_term (term)) {
            debug ("[SearchPage] term too short/invalid -> clear list + idle");
            store.remove_all ();
            show_idle ();
            return;
        }

        show_loading ();

        var api = new Data.AltRepoClient ();
        try {
            var results = yield api.search_source (branch, term);

            Idle.add (() => {
                store.remove_all ();
                if (results != null) {
                    foreach (var g in results) if (g != null) store.append (g);
                }
                if (store.get_n_items () == 0)
                    show_empty ();
                else
                    show_results ();
                return Source.REMOVE;
            });
        } catch (Error e) {
            warning ("[SearchPage] do_search(): error: %s", e.message);
            store.remove_all ();
            show_error ();
           // toast_overlay.add_toast (new Adw.Toast ("Failed to fetch search results"));
        }
    }
}

