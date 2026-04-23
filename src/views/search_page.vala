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

    // Header controls now live inside SearchPage's own blueprint
    [GtkChild] private unowned Gtk.DropDown    mode_dropdown;
    [GtkChild] private unowned Gtk.DropDown    branch_dropdown;
    [GtkChild] private unowned Gtk.SearchEntry search_entry;

    // Empty-/error-state action buttons
    [GtkChild] private unowned Gtk.Button clear_btn;
    [GtkChild] private unowned Gtk.Button try_other_branch_btn;
    [GtkChild] private unowned Gtk.Button retry_btn;

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

    private const uint DEBOUNCE_MS = 250;

    private GLib.Cancellable? in_flight = null;
    private uint64            query_seq = 0;

    // Labels for the mode dropdown; index matches Data.SearchMode enum.
    private const string[] MODE_LABELS = {
        "Package", "Binary", "File", "Maintainer", "Task"
    };
    private const string[] MODE_PLACEHOLDERS = {
        "Type a package name…",
        "Type a binary package name…",
        "Type a file path…",
        "Type a maintainer nickname…",
        "Type a package name or task ID…"
    };

    public signal void open_details (Data.SourceGroup group, string branch);
    // Emitted after "Clear search" button is pressed and nothing is left
    public signal void wants_clear ();

    private static bool is_nonempty (string? s) {
        return s != null && s.strip ().length > 0;
    }

    private static bool is_reasonable_term (string? s, Data.SearchMode mode) {
        if (s == null) return false;
        string term = s.strip ();
        if (term.length < 2) return false;
        try {
            switch (mode) {
            case Data.SearchMode.FILE:
                return new Regex ("^[A-Za-z0-9._+\\-/]+$").match (term);
            case Data.SearchMode.TASK:
                return new Regex ("^[A-Za-z0-9._+\\-]+$").match (term);
            default:
                return new Regex ("^[A-Za-z0-9._+\\-]+$").match (term);
            }
        } catch (Error e) {
            return term.length >= 2;
        }
    }

    /* ===== Public control API ===== */

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

    // Focus the search entry (used by keyboard shortcut).
    public void focus_search_entry () {
        search_entry.grab_focus ();
    }

    private void clear_stores () {
        store.remove_all ();
        task_store.remove_all ();
    }

    construct {
        Style.ensure ();

        // Populate dropdowns
        var branches_model = new Gtk.StringList (null);
        string[] branch_names = { "sisyphus", "p11", "p10", "p9", "c10f2", "c9f2" };
        foreach (string b in branch_names) branches_model.append (b);
        branch_dropdown.model = branches_model;
        branch_dropdown.selected = 0;

        var modes_model = new Gtk.StringList (null);
        foreach (string m in MODE_LABELS) modes_model.append (_(m));
        mode_dropdown.model = modes_model;
        mode_dropdown.selected = 0;

        // Stores / factories
        store        = new GLib.ListStore (typeof (Data.SourceGroup));
        no_sel       = new Gtk.NoSelection (store);
        task_store   = new GLib.ListStore (typeof (Data.TaskResult));
        no_sel_tasks = new Gtk.NoSelection (task_store);

        pkg_factory  = build_package_factory ();
        task_factory = build_task_factory ();

        list_view.factory = pkg_factory;
        list_view.model   = no_sel;

        // Wire entry
        search_entry.search_changed.connect (() => {
            set_query ((search_entry.text ?? "").strip ());
            trigger_search_debounced ();
        });
        search_entry.activate.connect (() => {
            set_query ((search_entry.text ?? "").strip ());
            trigger_search_now ();
        });

        // Wire dropdowns
        mode_dropdown.notify["selected"].connect (() => {
            var mode = (Data.SearchMode) mode_dropdown.selected;
            set_mode (mode);
            search_entry.set_placeholder_text (_(MODE_PLACEHOLDERS[mode]));
            set_query ((search_entry.text ?? "").strip ());
            trigger_search_now ();
        });
        branch_dropdown.notify["selected"].connect (() => {
            set_branch (read_branch ());
            trigger_search_now ();
        });

        // Initial state
        set_branch (read_branch ());

        // Empty-/error-state buttons
        clear_btn.clicked.connect (() => {
            search_entry.text = "";
            search_entry.grab_focus ();
            wants_clear ();
        });
        try_other_branch_btn.clicked.connect (() => {
            // Cycle to the next branch in the list
            int n = (int) branches_model.get_n_items ();
            if (n <= 1) return;
            branch_dropdown.selected = (branch_dropdown.selected + 1) % (uint) n;
        });
        retry_btn.clicked.connect (() => {
            trigger_search_now ();
        });

        show_idle ();
    }

    private string read_branch () {
        int idx = (int) branch_dropdown.selected;
        var m = branch_dropdown.model as Gtk.StringList;
        if (m == null || idx < 0) return "sisyphus";
        return m.get_string ((uint) idx);
    }

    /* ===== Factories ===== */

    // Returns a leading icon widget appropriate for the current search mode.
    private Gtk.Widget make_leading_for_mode (Data.SearchMode mode, string title_text) {
        switch (mode) {
        case Data.SearchMode.MAINTAINER:
            var av = new Adw.Avatar (36, title_text, true);
            av.add_css_class ("pkg-avatar");
            av.valign = Gtk.Align.CENTER;
            return av;

        case Data.SearchMode.FILE:
            return new Gtk.Image.from_icon_name ("folder-symbolic") {
                pixel_size = 28,
                valign = Gtk.Align.CENTER,
                css_classes = { "result-icon" }
            };

        case Data.SearchMode.BINARY:
            return new Gtk.Image.from_icon_name ("application-x-executable-symbolic") {
                pixel_size = 28,
                valign = Gtk.Align.CENTER,
                css_classes = { "result-icon" }
            };

        default:
            return new Gtk.Image.from_icon_name ("package-x-generic-symbolic") {
                pixel_size = 28,
                valign = Gtk.Align.CENTER,
                css_classes = { "result-icon" }
            };
        }
    }

    private Gtk.SignalListItemFactory build_package_factory () {
        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((obj) => {
            var li = obj as Gtk.ListItem; if (li == null) return;
            li.set_activatable (false);
            li.set_selectable (false);

            var frame = make_card_frame ();

            var root = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            root.set_hexpand (true);

            var leading_host = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                valign = Gtk.Align.CENTER,
                width_request = 36
            };

            var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            text_box.set_hexpand (true);
            text_box.set_valign (Gtk.Align.CENTER);

            var title = new Gtk.Label ("") {
                xalign = 0.0f,
                halign = Gtk.Align.START,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
                single_line_mode = true,
                max_width_chars = 40
            };
            title.add_css_class ("title-4");

            var subtitle = new Gtk.Label ("") {
                xalign = 0.0f,
                halign = Gtk.Align.START,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
                single_line_mode = true,
                max_width_chars = 50
            };
            subtitle.add_css_class ("subtitle");

            text_box.append (title);
            text_box.append (subtitle);

            var right = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                halign = Gtk.Align.END, valign = Gtk.Align.CENTER
            };
            var chevron = new Gtk.Image.from_icon_name ("go-next-symbolic");
            chevron.set_opacity (0.55);
            right.append (chevron);

            root.append (leading_host);
            root.append (text_box);
            root.append (right);

            frame.set_child (root);
            li.set_child (frame);

            attach_hover (frame);

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
            li.set_data ("leading_host", leading_host);
        });

        factory.bind.connect ((obj) => {
            var li = obj as Gtk.ListItem; if (li == null) return;
            var sg = li.get_item () as Data.SourceGroup; if (sg == null) return;

            var title        = li.get_data<Gtk.Label> ("title");
            var subtitle     = li.get_data<Gtk.Label> ("subtitle");
            var leading_host = li.get_data<Gtk.Box> ("leading_host");

            if (title != null) title.set_text (sg.name ?? "");
            if (subtitle != null) {
                string vr = "";
                if (is_nonempty (sg.version)) vr = sg.version;
                if (is_nonempty (sg.release))  vr = (vr == "") ? sg.release : vr + "-" + sg.release;
                subtitle.set_text (vr);
            }

            // Swap leading icon to match current mode
            if (leading_host != null) {
                var child = leading_host.get_first_child ();
                if (child != null) leading_host.remove (child);
                leading_host.append (make_leading_for_mode (current_mode, sg.name ?? ""));
            }
        });
        return factory;
    }

    private Gtk.SignalListItemFactory build_task_factory () {
        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((obj) => {
            var li = obj as Gtk.ListItem; if (li == null) return;
            li.set_activatable (false);
            li.set_selectable (false);

            var frame = make_card_frame ();

            var root = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            root.set_hexpand (true);

            var lead = new Gtk.Image.from_icon_name ("emblem-system-symbolic") {
                pixel_size = 28,
                valign = Gtk.Align.CENTER,
                css_classes = { "result-icon" }
            };

            var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            text_box.set_hexpand (true);
            text_box.set_valign (Gtk.Align.CENTER);

            var title = new Gtk.Label ("") {
                xalign = 0.0f,
                halign = Gtk.Align.START,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
                single_line_mode = true
            };
            title.add_css_class ("title-4");

            var state_tag = Style.make_tag ("", "accent");
            state_tag.visible = false;

            var title_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            title_row.append (title);
            title_row.append (state_tag);

            var subtitle = new Gtk.Label ("") {
                xalign = 0.0f,
                halign = Gtk.Align.START,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
                single_line_mode = true
            };
            subtitle.add_css_class ("subtitle");

            var pkgs_lbl = new Gtk.Label ("") {
                xalign = 0.0f,
                halign = Gtk.Align.START,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
                single_line_mode = true
            };
            pkgs_lbl.add_css_class ("subtitle");

            text_box.append (title_row);
            text_box.append (subtitle);
            text_box.append (pkgs_lbl);

            root.append (lead);
            root.append (text_box);

            frame.set_child (root);
            li.set_child (frame);

            attach_hover (frame);

            li.set_data ("title", title);
            li.set_data ("subtitle", subtitle);
            li.set_data ("pkgs", pkgs_lbl);
            li.set_data ("state_tag", state_tag);
        });

        factory.bind.connect ((obj) => {
            var li = obj as Gtk.ListItem; if (li == null) return;
            var t = li.get_item () as Data.TaskResult; if (t == null) return;

            var title    = li.get_data<Gtk.Label> ("title");
            var subtitle = li.get_data<Gtk.Label> ("subtitle");
            var pkgs_lbl = li.get_data<Gtk.Label> ("pkgs");
            var tag      = li.get_data<Gtk.Label> ("state_tag");

            if (title != null)
                title.set_text (_("Task #%lld").printf (t.task_id));

            if (tag != null) {
                string st = (t.state ?? "").strip ();
                if (st.length > 0) {
                    tag.label = st;
                    // Remove previous modifiers, set per-state color
                    tag.remove_css_class ("success");
                    tag.remove_css_class ("warning");
                    tag.remove_css_class ("error");
                    tag.remove_css_class ("accent");
                    tag.remove_css_class ("neutral");
                    string lc = st.down ();
                    if (lc == "done")         tag.add_css_class ("success");
                    else if (lc == "failed")  tag.add_css_class ("error");
                    else if (lc == "new")     tag.add_css_class ("accent");
                    else if (lc == "awaiting") tag.add_css_class ("warning");
                    else                       tag.add_css_class ("neutral");
                    tag.visible = true;
                } else {
                    tag.visible = false;
                }
            }

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
        frame.margin_start  = 8;
        frame.margin_end    = 8;
        frame.margin_top    = 6;
        frame.margin_bottom = 6;
        return frame;
    }

    private static void attach_hover (Gtk.Widget frame) {
        var motion = new Gtk.EventControllerMotion ();
        motion.enter.connect ((x, y) => { frame.add_css_class ("hover"); });
        motion.leave.connect (() =>     { frame.remove_css_class ("hover"); });
        frame.add_controller (motion);
    }

    private void show_idle ()    { content_stack.set_visible_child_name ("idle"); }
    private void show_loading () { content_stack.set_visible_child_name ("loading"); }
    private void show_results () { content_stack.set_visible_child_name ("results"); }
    private void show_empty ()   { content_stack.set_visible_child_name ("empty"); }
    private void show_error ()   { content_stack.set_visible_child_name ("error"); }

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
