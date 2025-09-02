using Gtk;
using Adw;
using GLib;
using Pango;
using Gdk;
using Intl;

[GtkTemplate (ui = "/org/example/PackageSearch/ui/search_page.ui")]
public class SearchPage : Adw.NavigationPage {
    [GtkChild] private unowned Adw.ToastOverlay    toast_overlay;
    [GtkChild] private unowned Adw.ViewStack       content_stack;
    [GtkChild] private unowned Gtk.ListView        list_view;
    [GtkChild] private unowned Gtk.ScrolledWindow  results_scroller;

    private GLib.ListStore   store;
    private Gtk.NoSelection  no_sel;
    private uint             debounce_id = 0;

    private string current_query = "";
    private string current_branch = "sisyphus";

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

    /* Публичные методы для управления извне (из MainWindow) */
    public void set_query (string q) {
        current_query = q.strip ();
        if (current_query.length == 0) {
            store.remove_all ();
            show_idle ();
        }
    }
    public void set_branch (string b) {
        if (b == null || b.strip ().length == 0) return;
        current_branch = b.strip ();
    }
    public void trigger_search_debounced () {
        if (debounce_id != 0) { Source.remove (debounce_id); debounce_id = 0; }
        if (current_query.length == 0) { store.remove_all (); show_idle (); return; }
        debounce_id = Timeout.add (250, () => { trigger_search_now (); debounce_id = 0; return Source.REMOVE; });
    }
    public void trigger_search_now () {
        if (debounce_id != 0) { Source.remove (debounce_id); debounce_id = 0; }
        do_search.begin ();
    }

    construct {
        /* CSS для карточек */
        var css = """
        .results-scroll,
        .results-scroll > .frame,
        .results-scroll > viewport,
        .results-scroll > viewport > listview,
        .results-scroll > listview,
        .results-scroll listview.view {
          background-color: transparent;
          background: transparent;
          box-shadow: none;
        }
        .big-card {
          border-radius: 12px;
          border: 1px solid @borders;
        }
        .big-card > box {
          padding: 10px 12px;
          min-height: 48px;
        }
        .big-card .subtitle { opacity: 0.8; }
        .big-card.hover { border-color: @accent_color; }
        """;
        var provider = new Gtk.CssProvider ();
        provider.load_from_string (css);
        var disp = Gdk.Display.get_default ();
        if (disp != null)
            Gtk.StyleContext.add_provider_for_display (disp, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        store  = new GLib.ListStore (typeof (Data.SourceGroup));
        no_sel = new Gtk.NoSelection (store);
        list_view.model = no_sel;

        // Фабрика карточек
        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect ((obj) => {
            var li = obj as Gtk.ListItem; if (li == null) return;

            li.set_activatable (false);
            li.set_selectable (false);

            var frame = new Gtk.Frame (null);
            frame.add_css_class ("card");
            frame.add_css_class ("big-card");
            frame.set_hexpand (true);

            frame.margin_start = 12;
            frame.margin_end   = 12;
            frame.margin_top   = 8;
            frame.margin_bottom= 8;

            var root = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            root.set_hexpand (true);

            var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            text_box.set_hexpand (true);

            var title = new Gtk.Label ("") { xalign = 0.0f, hexpand = true };
            title.add_css_class ("title-4");
            title.set_ellipsize (EllipsizeMode.END);

            var subtitle = new Gtk.Label ("") { xalign = 0.0f, hexpand = true };
            subtitle.add_css_class ("subtitle");
            subtitle.set_ellipsize (EllipsizeMode.END);

            text_box.append (title);
            text_box.append (subtitle);

            var right = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { halign = Align.END, valign = Align.CENTER };
            var chevron = new Gtk.Image.from_icon_name ("go-next-symbolic");
            chevron.set_opacity (0.6);
            right.append (chevron);

            root.append (text_box);
            root.append (right);

            frame.set_child (root);
            li.set_child (frame);

            var motion = new Gtk.EventControllerMotion ();
            motion.enter.connect ((x, y) => { frame.add_css_class ("hover"); });
            motion.leave.connect (() =>     { frame.remove_css_class ("hover"); });
            frame.add_controller (motion);

            var click = new Gtk.GestureClick ();
            click.released.connect ((n_press, x, y) => {
                if (n_press != 1) return;
                int pos = (int) li.get_position ();
                if (pos < 0 || pos >= (int) store.get_n_items ()) return;

                var obj_item = store.get_item (pos);
                var sg = obj_item as Data.SourceGroup; if (sg == null) return;

                var win = this.get_root () as MainWindow;
                if (win != null) win.show_details (sg, current_branch);
            });
            frame.add_controller (click);

            li.set_data ("title", title);
            li.set_data ("subtitle", subtitle);
        });

        factory.bind.connect ((obj) => {
            var li = obj as Gtk.ListItem; if (li == null) return;
            var sg = li.get_item () as Data.SourceGroup; if (sg == null) return;

            var title = li.get_data<Gtk.Label> ("title");
            var subtitle = li.get_data<Gtk.Label> ("subtitle");
            if (title != null)    title.set_text (sg.name ?? "");
            if (subtitle != null) {
                string vr = "";
                if (is_nonempty (sg.version)) vr = sg.version;
                if (is_nonempty (sg.release))  vr = (vr == "") ? sg.release : vr + "-" + sg.release;
                subtitle.set_text (vr);
            }
        });

        list_view.factory = factory;

        show_idle ();
    }

    private void show_idle ()    { content_stack.set_visible_child_name ("idle"); }
    private void show_loading () { content_stack.set_visible_child_name ("loading"); }
    private void show_results () { content_stack.set_visible_child_name ("results"); }
    private void show_empty ()   { content_stack.set_visible_child_name ("empty"); }
    private void show_error ()   { content_stack.set_visible_child_name ("error"); }

    private async void do_search () {
        var term = current_query;
        var branch = current_branch;
        if (term.length == 0) {
        store.remove_all ();
        show_idle ();
        return;
        }

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

