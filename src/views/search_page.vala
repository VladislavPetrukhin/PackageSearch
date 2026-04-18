using Gtk;
using Adw;
using GLib;
using Pango;
using Gdk;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/search_page.ui")]
public class SearchPage : Adw.NavigationPage {
    [GtkChild] private unowned Adw.ToastOverlay   toast_overlay;
    [GtkChild] private unowned Adw.ViewStack      content_stack;
    [GtkChild] private unowned Gtk.ListView       list_view;
    [GtkChild] private unowned Gtk.ScrolledWindow results_scroller;

    // Separate stores — one for package-like results, one for tasks.
    private GLib.ListStore  store;
    private GLib.ListStore  task_store;
    private Gtk.NoSelection no_sel;
    private Gtk.NoSelection no_sel_tasks;

    private Gtk.SignalListItemFactory pkg_factory;
    private Gtk.SignalListItemFactory task_factory;

    private uint   debounce_id = 0;
    private string current_query  = "";
    private string current_branch = "sisyphus";
    private Data.SearchMode current_mode = Data.SearchMode.PACKAGE;

    // Settings
    private const uint DEBOUNCE_MS = 250;

    // --- race protection ---
    private GLib.Cancellable? in_flight = null;
    private uint64            query_seq = 0;

    public signal void open_details (Data.SourceGroup group, string branch);

    // Returns true if s is non-null and has non-whitespace content
    private static bool is_nonempty (string? s) {
        return s != null && s.strip ().length > 0;
    }

    // Validate the term depending on the active search mode.
    // Package/Maintainer — restricted alnum+separators. File — allow paths.
    // Task — allow digits (task ID) and package-like tokens.
    private static bool is_reasonable_term (string? s, Data.SearchMode mode) {
        if (s == null) return false;
        string term = s.strip ();
        if (term.length < 2) return false;
        try {
            switch (mode) {
            case Data.SearchMode.FILE:
                // Allow file paths: letters, digits, ._+-/
                return new Regex ("^[A-Za-z0-9._+\\-/]+$").match (term);
            case Data.SearchMode.TASK:
                // Digits (task id) or package-like token
                return new Regex ("^[A-Za-z0-9._+\\-]+$").match (term);
            default:
                return new Regex ("^[A-Za-z0-9._+\\-]+$").match (term);
            }
        } catch (Error e) {
            return term.length >= 2;
        }
    }

    /* Public control API (used by MainWindow) */

    public void set_query (string? q) {
        current_query = (q != null) ? q.strip () : "";
        if (current_query.length == 0) {
            if (in_flight != null) { in_flight.cancel (); in_flight = null; }
            if (debounce_id != 0) { Source.remove (debounce_id); debounce_id = 0; }
            clear_stores ();
            show_idle ();
        }
    }

    public void set_branch (string? b) {
        if (b == null || b.strip ().length == 0) return;
        current_branch = b.strip ();
    }

    public void set_mode (Data.SearchMode mode) {
        if (current_mode == mode) return;
        current_mode = mode;

        // Cancel pending work and swap the list view's model/factory.
        if (in_flight != null) { in_flight.cancel (); in_flight = null; }
        if (debounce_id != 0) { Source.remove (debounce_id); debounce_id = 0; }
        clear_stores ();

        if (mode == Data.SearchMode.TASK) {
            list_view.factory = task_factory;
            list_view.model   = no_sel_tasks;
        } else {
            list_view.factory = pkg_factory;
            list_view.model   = no_sel;
        }
        show_idle ();
    }

    // Schedule search with debounce. Cancels previous timer if any.
    public void trigger_search_debounced () {
        if (debounce_id != 0) { Source.remove (debounce_id); debounce_id = 0; }

        if (current_query.length == 0) {
            if (in_flight != null) { in_flight.cancel (); in_flight = null; }
            clear_stores ();
            show_idle ();
            return;
        }

        debounce_id = Timeout.add (DEBOUNCE_MS, () => {
            trigger_search_now ();
            debounce_id = 0;
            return Source.REMOVE;
        });
    }

    // Launch search immediately
    public void trigger_search_now () {
        if (debounce_id != 0) { Source.remove (debounce_id); debounce_id = 0; }

        if (current_query.length == 0) {
            if (in_flight != null) { in_flight.cancel (); in_flight = null; }
            clear_stores ();
            show_idle ();
            return;
        }

        if (in_flight != null) { in_flight.cancel (); in_flight = null; }
        in_flight = new GLib.Cancellable ();
        query_seq++;

        do_search.begin (in_flight, query_seq);
    }

    private void clear_stores () {
        store.remove_all ();
        task_store.remove_all ();
    }

    construct {
        /* Lightweight CSS for result cards */
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
          padding: 12px 12px;
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

        // Package-like model (SourceGroup) — default
        store        = new GLib.ListStore (typeof (Data.SourceGroup));
        no_sel       = new Gtk.NoSelection (store);
        // Task model
        task_store   = new GLib.ListStore (typeof (Data.TaskResult));
        no_sel_tasks = new Gtk.NoSelection (task_store);

        pkg_factory  = build_package_factory ();
        task_factory = build_task_factory ();

        list_view.factory = pkg_factory;
        list_view.model   = no_sel;

        show_idle ();
    }

    // Factory for SourceGroup cards (package/file/maintainer modes)
    private Gtk.SignalListItemFactory build_package_factory () {
        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((obj) => {
            var li = obj as Gtk.ListItem; if (li == null) return;
            li.set_activatable (false);
            li.set_selectable (false);

            var frame = make_card_frame ();

            var root = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            root.set_hexpand (true);

            var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            text_box.set_hexpand (true);
            text_box.set_valign (Gtk.Align.CENTER);

            var title = new Gtk.Label ("") { xalign = 0.0f, hexpand = true, valign = Align.CENTER };
            title.add_css_class ("title-4");
            title.set_ellipsize (EllipsizeMode.END);

            var subtitle = new Gtk.Label ("") { xalign = 0.0f, hexpand = true, valign = Align.CENTER };
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

            attach_hover (frame);

            // Open details on single click
            var click = new Gtk.GestureClick ();
            click.released.connect ((n_press, x, y) => {
                if (n_press != 1) return;
                int pos = (int) li.get_position ();
                if (pos < 0 || pos >= (int) store.get_n_items ()) return;

                var sg = store.get_item (pos) as Data.SourceGroup;
                if (sg == null) return;
                open_details (sg, current_branch);
            });
            frame.add_controller (click);

            li.set_data ("title", title);
            li.set_data ("subtitle", subtitle);
        });

        factory.bind.connect ((obj) => {
            var li = obj as Gtk.ListItem; if (li == null) return;
            var sg = li.get_item () as Data.SourceGroup; if (sg == null) return;

            var title    = li.get_data<Gtk.Label> ("title");
            var subtitle = li.get_data<Gtk.Label> ("subtitle");

            if (title != null) title.set_text (sg.name ?? "");
            if (subtitle != null) {
                string vr = "";
                if (is_nonempty (sg.version)) vr = sg.version;
                if (is_nonempty (sg.release))  vr = (vr == "") ? sg.release : vr + "-" + sg.release;
                subtitle.set_text (vr);
            }
        });
        return factory;
    }

    // Factory for TaskResult cards (task mode)
    private Gtk.SignalListItemFactory build_task_factory () {
        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((obj) => {
            var li = obj as Gtk.ListItem; if (li == null) return;
            li.set_activatable (false);
            li.set_selectable (false);

            var frame = make_card_frame ();

            var root = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            root.set_hexpand (true);

            var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            text_box.set_hexpand (true);
            text_box.set_valign (Gtk.Align.CENTER);

            var title = new Gtk.Label ("") { xalign = 0.0f, hexpand = true, valign = Align.CENTER };
            title.add_css_class ("title-4");
            title.set_ellipsize (EllipsizeMode.END);

            var subtitle = new Gtk.Label ("") { xalign = 0.0f, hexpand = true, valign = Align.CENTER };
            subtitle.add_css_class ("subtitle");
            subtitle.set_ellipsize (EllipsizeMode.END);

            var pkgs_lbl = new Gtk.Label ("") { xalign = 0.0f, hexpand = true, valign = Align.CENTER };
            pkgs_lbl.add_css_class ("subtitle");
            pkgs_lbl.set_ellipsize (EllipsizeMode.END);

            text_box.append (title);
            text_box.append (subtitle);
            text_box.append (pkgs_lbl);

            root.append (text_box);

            frame.set_child (root);
            li.set_child (frame);

            attach_hover (frame);

            li.set_data ("title", title);
            li.set_data ("subtitle", subtitle);
            li.set_data ("pkgs", pkgs_lbl);
        });

        factory.bind.connect ((obj) => {
            var li = obj as Gtk.ListItem; if (li == null) return;
            var t = li.get_item () as Data.TaskResult; if (t == null) return;

            var title    = li.get_data<Gtk.Label> ("title");
            var subtitle = li.get_data<Gtk.Label> ("subtitle");
            var pkgs_lbl = li.get_data<Gtk.Label> ("pkgs");

            if (title != null)
                title.set_text (_("Task #%lld  —  %s").printf (t.task_id, t.state ?? ""));

            if (subtitle != null) {
                string parts = "";
                if (is_nonempty (t.owner))   parts = t.owner;
                if (is_nonempty (t.repo))    parts = (parts == "") ? t.repo : parts + " · " + t.repo;
                if (is_nonempty (t.changed)) parts = (parts == "") ? t.changed : parts + " · " + t.changed;
                subtitle.set_text (parts);
            }

            if (pkgs_lbl != null)
                pkgs_lbl.set_text (t.packages ?? "");
        });
        return factory;
    }

    private Gtk.Frame make_card_frame () {
        var frame = new Gtk.Frame (null);
        frame.add_css_class ("card");
        frame.add_css_class ("big-card");
        frame.set_hexpand (true);
        frame.margin_start  = 12;
        frame.margin_end    = 12;
        frame.margin_top    = 8;
        frame.margin_bottom = 8;
        return frame;
    }

    private static void attach_hover (Gtk.Widget frame) {
        var motion = new Gtk.EventControllerMotion ();
        motion.enter.connect ((x, y) => { frame.add_css_class ("hover"); });
        motion.leave.connect (() =>     { frame.remove_css_class ("hover"); });
        frame.add_controller (motion);
    }

    // View state helpers
    private void show_idle ()    { content_stack.set_visible_child_name ("idle"); }
    private void show_loading () { content_stack.set_visible_child_name ("loading"); }
    private void show_results () { content_stack.set_visible_child_name ("results"); }
    private void show_empty ()   { content_stack.set_visible_child_name ("empty"); }
    private void show_error ()   { content_stack.set_visible_child_name ("error"); }

    // Main async search — dispatches to the right API method per mode.
    private async void do_search (GLib.Cancellable? cancellable, uint64 my_seq) {
        var term   = current_query;
        var branch = current_branch;
        var mode   = current_mode;

        if (term.length == 0 || !is_reasonable_term (term, mode)) {
            clear_stores ();
            show_idle ();
            return;
        }

        show_loading ();

        var api = new Data.AltRepoClient ();
        try {
            switch (mode) {
            case Data.SearchMode.PACKAGE:
                var results = yield api.search_source (branch, term, cancellable);
                if (my_seq != query_seq) return;
                apply_package_results (results);
                break;

            case Data.SearchMode.BINARY:
                var src_name = yield api.find_source_by_binary (branch, term, cancellable);
                if (my_seq != query_seq) return;
                var one = new Gee.ArrayList<Data.SourceGroup> ();
                if (src_name != null && src_name.length > 0)
                    one.add (new Data.SourceGroup (src_name));
                apply_package_results (one);
                break;

            case Data.SearchMode.FILE:
                var results = yield api.search_by_file (branch, term, cancellable);
                if (my_seq != query_seq) return;
                apply_package_results (results);
                break;

            case Data.SearchMode.MAINTAINER:
                var results = yield api.search_by_maintainer (branch, term, cancellable);
                if (my_seq != query_seq) return;
                apply_package_results (results);
                break;

            case Data.SearchMode.TASK:
                var results = yield api.search_tasks (term, branch, cancellable);
                if (my_seq != query_seq) return;
                apply_task_results (results);
                break;
            }
        } catch (Error e) {
            if ((cancellable != null && cancellable.is_cancelled ()) || my_seq != query_seq)
                return;
            warning ("[SearchPage] do_search(): %s", e.message);
            clear_stores ();
            show_error ();
        } finally {
            if (cancellable == in_flight) in_flight = null;
        }
    }

    private void apply_package_results (Gee.ArrayList<Data.SourceGroup>? results) {
        Idle.add (() => {
            clear_stores ();
            if (results != null) {
                foreach (var g in results) if (g != null) store.append (g);
            }
            if (store.get_n_items () == 0) show_empty (); else show_results ();
            return Source.REMOVE;
        });
    }

    private void apply_task_results (Gee.ArrayList<Data.TaskResult>? results) {
        Idle.add (() => {
            clear_stores ();
            if (results != null) {
                foreach (var t in results) if (t != null) task_store.append (t);
            }
            if (task_store.get_n_items () == 0) show_empty (); else show_results ();
            return Source.REMOVE;
        });
    }
}
