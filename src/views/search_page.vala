using Gtk;
using Adw;
using GLib;
using Pango;

[GtkTemplate (ui = "/org/example/PackageSearch/ui/search_page.ui")]
public class SearchPage : Adw.NavigationPage {
    [GtkChild] private unowned Gtk.SearchEntry  search_entry;
    [GtkChild] private unowned Gtk.DropDown     branch_dropdown;
    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
    [GtkChild] private unowned Gtk.Stack        content_stack;
    [GtkChild] private unowned Gtk.ListView     list_view;
    [GtkChild] private unowned Gtk.ScrolledWindow results_scroller;


    private GLib.ListStore store;
    private Gtk.SingleSelection sel;

    private uint debounce_id = 0;

    // utils
    private static bool is_nonempty (string? s) {
        return s != null && s.strip ().length > 0;
    }
    private static bool is_reasonable_term (string? s) {
        if (s == null) return false;
        string term = s.strip ();
        if (term.length < 2) return false;
        try { var re = new Regex ("^[A-Za-z0-9._+-]+$"); return re.match (term); }
        catch (Error e) { return term.length >= 2; }
    }

    construct {
        // --- pretty cards CSS ---
        var css = """
        .results-scroll,
        .results-scroll > .frame {
          background-color: transparent;
          background: transparent;
          box-shadow: none;
        }

        .results-scroll > viewport,
        .results-scroll > viewport > listview {
          background-color: transparent;
          background: transparent;
        }

        .results-scroll > listview,
        .results-scroll listview.view {
          background-color: transparent;
          background: transparent;
        }
        .pkg-card {
            border-radius: 14px;
            }
        .pkg-card > * { padding: 10px; }
        .pkg-card:hover { box-shadow: 0 0 0 1px alpha(@accent_color, 0.35); }
        .pkg-row { }

        .pkg-badge {
          border-radius: 9999px;
          padding: 2px 10px;
          background: alpha(@accent_color, 0.15);
          color: @accent_color;
          font-size: 0.85em;
        }
        """;
        var provider = new Gtk.CssProvider ();
        provider.load_from_string (css);
        var disp = Gdk.Display.get_default ();
        if (disp != null)
            Gtk.StyleContext.add_provider_for_display (disp, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);


        // model
        store = new GLib.ListStore (typeof (Data.SourceGroup));
        sel = new Gtk.SingleSelection (store) { autoselect = false, can_unselect = true };
        list_view.model = sel;

        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((obj) => {
            var li = obj as Gtk.ListItem; if (li == null) return;

            var frame = new Gtk.Frame (null);
            frame.add_css_class ("card");
            frame.add_css_class ("pkg-card");
            frame.margin_top = 6; frame.margin_bottom = 6;

            var row = new Adw.ActionRow () { activatable = true };
            row.add_css_class ("pkg-row");

            // suffix: branch badge + chevron
            var suffix = new Gtk.Box (Orientation.HORIZONTAL, 8);

            var branch_lbl = new Gtk.Label ("") { halign = Align.END };
            branch_lbl.add_css_class ("pkg-badge");

            var chevron = new Gtk.Image.from_icon_name ("go-next-symbolic");
            chevron.opacity = 0.6;

            suffix.append (branch_lbl);
            suffix.append (chevron);
            row.add_suffix (suffix);

            row.subtitle = "";

            frame.set_child (row);
            li.set_child (frame);

            li.set_data ("branch_lbl", branch_lbl);
        });

        // BIND: заполняем заголовок/подзаголовок и бейдж ветки
        factory.bind.connect ((obj) => {
            var li = obj as Gtk.ListItem; if (li == null) return;

            var frame = li.get_child () as Gtk.Frame; if (frame == null) return;
            var row = frame.get_child () as Adw.ActionRow; if (row == null) return;

            var sg = li.get_item () as Data.SourceGroup; if (sg == null) return;

            // title
            row.title = sg.name ?? "";

            // subtitle: version-release
            string vr = "";
            if (is_nonempty (sg.version)) vr = sg.version;
            if (is_nonempty (sg.release))  vr = (vr == "") ? sg.release : vr + "-" + sg.release;
            row.subtitle = vr;

            // branch badge
            var branch_lbl = li.get_data<Gtk.Label> ("branch_lbl");
            if (branch_lbl != null) branch_lbl.label = current_branch ();
        });

        list_view.factory = factory;

        // single-click activate
        var click = new Gtk.GestureClick ();
        click.released.connect ((n_press, x, y) => {
            if (n_press == 1) {
                int idx = (int) sel.selected;
                if (idx >= 0) list_view.activate ((uint) idx);
            }
        });
        list_view.add_controller (click);

        // activate handler → open details
        list_view.activate.connect ((pos) => {
            var obj = store.get_item ((int) pos);
            var sg = obj as Data.SourceGroup; if (sg == null) return;

            var branch = current_branch ();
            var win = this.get_root () as MainWindow;
            if (win != null) win.show_details (sg, branch);

            sel.unselect_all ();
        });

        // branches
        try {
            var branches_model = new Gtk.StringList (null);
            string[] branch_names = { "sisyphus", "p11" };
            foreach (string b in branch_names) branches_model.append (b);
            branch_dropdown.model = branches_model;
            branch_dropdown.selected = 0;
        } catch (Error e) {
            warning ("[SearchPage] failed to init branches: %s", e.message);
        }

        // initial state
        show_idle ();

        // events
        search_entry.search_changed.connect (() => debounce_search ());
        search_entry.activate.connect (() => trigger_search_now ());
        branch_dropdown.notify["selected"].connect (() => trigger_search_now ());
    }

    // stack helpers
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

    // debounce
    private void debounce_search () {
        if (debounce_id != 0) { Source.remove (debounce_id); debounce_id = 0; }
        var term = (search_entry.text ?? "").strip ();
        if (term.length == 0) {
            store.remove_all ();
            show_idle ();
            return;
        }
        debounce_id = Timeout.add (250, () => { trigger_search_now (); debounce_id = 0; return Source.REMOVE; });
    }
    private void trigger_search_now () {
        if (debounce_id != 0) { Source.remove (debounce_id); debounce_id = 0; }
        do_search.begin ();
    }

    // async search
    private async void do_search () {
        var term = (search_entry.text ?? "").strip ();
        var branch = current_branch ();
        if (!is_reasonable_term (term)) {
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
                if (results != null) foreach (var g in results) if (g != null) store.append (g);
                if (store.get_n_items () == 0) show_empty (); else show_results ();
                return Source.REMOVE;
            });
        } catch (Error e) {
            warning ("[SearchPage] do_search(): %s", e.message);
            store.remove_all (); show_error ();
        }
    }
}

