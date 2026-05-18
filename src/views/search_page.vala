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

    [GtkChild] private unowned Gtk.DropDown    mode_dropdown;
    [GtkChild] private unowned Gtk.Box         branch_group;
    [GtkChild] private unowned Gtk.SearchEntry search_entry;

    private Gee.ArrayList<Gtk.ToggleButton> branch_buttons;

    [GtkChild] private unowned Gtk.Button clear_btn;
    [GtkChild] private unowned Gtk.Button try_other_branch_btn;
    [GtkChild] private unowned Gtk.Button retry_btn;

    [GtkChild] private unowned Gtk.Box suggestions_wrap;
    [GtkChild] private unowned Gtk.Box suggestions_box;

    [GtkChild] private unowned Gtk.MenuButton history_btn;
    private GLib.Settings? settings = null;
    private const int HISTORY_LIMIT = 15;
    private const string SETTINGS_SCHEMA = "space.altlinux.PackageSearch";
    private const string KEY_RECENT     = "recent-queries";

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
    private GLib.Cancellable? suggestions_cancel = null;
    private uint64            query_seq = 0;

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

    public void set_query (string? q) {
        current_query = (q != null) ? q.strip () : "";
        if (current_query.length == 0) {
            if (in_flight != null) { in_flight.cancel (); in_flight = null; }
            if (debounce_id != 0) { Source.remove (debounce_id); debounce_id = 0; }
            cancel_suggestions ();
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
        cancel_suggestions ();
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
            cancel_suggestions ();
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
            cancel_suggestions ();
            clear_stores ();
            show_idle ();
            return;
        }

        if (in_flight != null) { in_flight.cancel (); in_flight = null; }
        cancel_suggestions ();
        in_flight = new GLib.Cancellable ();
        query_seq++;
        do_search.begin (in_flight, query_seq);
    }

    private string[] load_history () {
        if (settings == null) return new string[0];
        return settings.get_strv (KEY_RECENT);
    }

    private void save_to_history (string q) {
        if (settings == null) return;
        var trimmed = q.strip ();
        if (trimmed.length < 2) return;

        var current = load_history ();
        var dedup = new Gee.ArrayList<string> ();
        dedup.add (trimmed);
        foreach (var s in current) {
            if (s == trimmed) continue;
            dedup.add (s);
            if (dedup.size >= HISTORY_LIMIT) break;
        }
        var arr = new string[dedup.size];
        for (int i = 0; i < dedup.size; i++) arr[i] = dedup[i];
        settings.set_strv (KEY_RECENT, arr);
        rebuild_history_popover ();
    }

    private void rebuild_history_popover () {
        var items = load_history ();
        var popover = new Gtk.Popover ();
        popover.set_size_request (260, -1);
        popover.has_arrow = true;

        var outer = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
            margin_top    = 6,
            margin_bottom = 6,
            margin_start  = 6,
            margin_end    = 6
        };

        if (items.length == 0) {
            var empty = new Gtk.Label (_("No recent searches yet")) {
                halign = Gtk.Align.CENTER,
                margin_top = 6,
                margin_bottom = 6
            };
            empty.add_css_class ("dim-label");
            outer.append (empty);
        } else {
            var list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.NONE
            };
            list.add_css_class ("boxed-list");
            foreach (var q in items) {
                var row = new Adw.ActionRow () {
                    title = q,
                    activatable = true
                };
                row.add_prefix (new Gtk.Image.from_icon_name ("document-open-recent-symbolic"));
                string captured = q;
                row.activated.connect (() => {
                    search_entry.text = captured;
                    set_query (captured);
                    trigger_search_now ();
                    popover.popdown ();
                });
                list.append (row);
            }
            outer.append (list);

            var clear = new Gtk.Button.with_label (_("Clear history")) {
                halign = Gtk.Align.CENTER,
                margin_top = 4
            };
            clear.add_css_class ("flat");
            clear.clicked.connect (() => {
                if (settings != null)
                    settings.set_strv (KEY_RECENT, new string[0]);
                rebuild_history_popover ();
                popover.popdown ();
            });
            outer.append (clear);
        }

        popover.set_child (outer);
        history_btn.set_popover (popover);
    }

    private void cancel_suggestions () {
        if (suggestions_cancel != null) {
            suggestions_cancel.cancel ();
            suggestions_cancel = null;
        }
        suggestions_wrap.visible = false;
        clear_suggestions ();
    }

    private void clear_suggestions () {
        for (var c = suggestions_box.get_first_child (); c != null; ) {
            var next = c.get_next_sibling ();
            suggestions_box.remove (c);
            c = next;
        }
    }

    public void focus_search_entry () {
        search_entry.grab_focus ();
    }

    private void clear_stores () {
        store.remove_all ();
        task_store.remove_all ();
    }

    construct {
        Style.ensure ();

        try {
            var src = GLib.SettingsSchemaSource.get_default ();
            if (src != null && src.lookup (SETTINGS_SCHEMA, true) != null) {
                settings = new GLib.Settings (SETTINGS_SCHEMA);
            }
        } catch (Error e) {
            warning ("[SearchPage] settings unavailable: %s", e.message);
        }
        rebuild_history_popover ();

        branch_buttons = new Gee.ArrayList<Gtk.ToggleButton> ();
        string[] branch_names = { "sisyphus", "p11", "p10", "p9", "c10f2", "c9f2" };
        Gtk.ToggleButton? first = null;
        foreach (string bname in branch_names) {
            var btn = new Gtk.ToggleButton.with_label (bname);
            btn.valign = Gtk.Align.CENTER;
            if (first == null) {
                btn.active = true;
                first = btn;
            } else {
                btn.set_group (first);
            }
            string captured = bname;
            btn.toggled.connect (() => {
                if (!btn.active) return;
                set_branch (captured);
                trigger_search_debounced ();
            });
            branch_group.append (btn);
            branch_buttons.add (btn);
        }

        var modes_model = new Gtk.StringList (null);
        foreach (string m in MODE_LABELS) modes_model.append (_(m));
        mode_dropdown.model = modes_model;
        mode_dropdown.selected = 0;

        store        = new GLib.ListStore (typeof (Data.SourceGroup));
        no_sel       = new Gtk.NoSelection (store);
        task_store   = new GLib.ListStore (typeof (Data.TaskResult));
        no_sel_tasks = new Gtk.NoSelection (task_store);

        pkg_factory  = build_package_factory ();
        task_factory = build_task_factory ();

        list_view.factory = pkg_factory;
        list_view.model   = no_sel;

        search_entry.search_changed.connect (() => {
            set_query ((search_entry.text ?? "").strip ());
            trigger_search_debounced ();
        });
        search_entry.activate.connect (() => {
            set_query ((search_entry.text ?? "").strip ());
            trigger_search_now ();
        });

        mode_dropdown.notify["selected"].connect (() => {
            var mode = (Data.SearchMode) mode_dropdown.selected;
            set_mode (mode);
            search_entry.set_placeholder_text (_(MODE_PLACEHOLDERS[mode]));
            set_query ((search_entry.text ?? "").strip ());
            trigger_search_now ();
        });

        set_branch (read_branch ());

        clear_btn.clicked.connect (() => {
            search_entry.text = "";
            search_entry.grab_focus ();
            wants_clear ();
        });
        try_other_branch_btn.clicked.connect (() => {
            int n = branch_buttons.size;
            if (n <= 1) return;
            int current = 0;
            for (int i = 0; i < n; i++) {
                if (branch_buttons.get (i).active) { current = i; break; }
            }
            branch_buttons.get ((current + 1) % n).active = true;
        });
        retry_btn.clicked.connect (() => {
            trigger_search_now ();
        });

        show_idle ();
    }

    private string read_branch () {
        foreach (var btn in branch_buttons) {
            if (btn.active) return btn.get_label () ?? "sisyphus";
        }
        return "sisyphus";
    }

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
            if (store.get_n_items () == 0) {
                show_empty ();
                run_suggestions.begin (current_query, current_mode, current_branch, query_seq);
            } else {
                show_results ();
                save_to_history (current_query);
            }
            return Source.REMOVE;
        });
    }

    private void apply_task_results (Gee.ArrayList<Data.TaskResult>? results) {
        Idle.add (() => {
            clear_stores ();
            if (results != null) {
                foreach (var t in results) if (t != null) task_store.append (t);
            }
            if (task_store.get_n_items () == 0) {
                show_empty ();
                run_suggestions.begin (current_query, current_mode, current_branch, query_seq);
            } else {
                show_results ();
                save_to_history (current_query);
            }
            return Source.REMOVE;
        });
    }

    private async void run_suggestions (string term, Data.SearchMode original_mode,
                                        string branch, uint64 my_seq) {
        if (suggestions_cancel != null) suggestions_cancel.cancel ();
        suggestions_cancel = new GLib.Cancellable ();
        var cancel = suggestions_cancel;

        clear_suggestions ();
        suggestions_wrap.visible = false;

        if (term.length == 0) return;

        Data.SearchMode[] modes = {
            Data.SearchMode.PACKAGE,
            Data.SearchMode.BINARY,
            Data.SearchMode.FILE,
            Data.SearchMode.MAINTAINER,
            Data.SearchMode.TASK
        };

        var api = new Data.AltRepoClient ();
        bool any_added = false;

        foreach (var m in modes) {
            if (m == original_mode) continue;
            if (cancel.is_cancelled () || my_seq != query_seq) return;
            if (!is_reasonable_term (term, m)) continue;

            int count = yield probe_mode (api, m, term, branch, cancel);
            if (cancel.is_cancelled () || my_seq != query_seq) return;

            if (count > 0) {
                add_suggestion_button (m, count);
                any_added = true;
                suggestions_wrap.visible = true;
            }
        }

        if (!any_added) suggestions_wrap.visible = false;
    }

    private async int probe_mode (Data.AltRepoClient api, Data.SearchMode mode,
                                  string term, string branch,
                                  GLib.Cancellable? cancel) {
        try {
            switch (mode) {
            case Data.SearchMode.PACKAGE:
                var r = yield api.search_source (branch, term, cancel);
                return (r != null) ? r.size : 0;

            case Data.SearchMode.BINARY:
                var s = yield api.find_source_by_binary (branch, term, cancel);
                return (s != null && s.length > 0) ? 1 : 0;

            case Data.SearchMode.FILE:
                var r = yield api.search_by_file (branch, term, cancel);
                return (r != null) ? r.size : 0;

            case Data.SearchMode.MAINTAINER:
                var r = yield api.search_by_maintainer (branch, term, cancel);
                return (r != null) ? r.size : 0;

            case Data.SearchMode.TASK:
                var r = yield api.search_tasks (term, branch, cancel);
                return (r != null) ? r.size : 0;
            }
        } catch (Error e) {
            return 0;
        }
        return 0;
    }

    private string mode_icon_name (Data.SearchMode mode) {
        switch (mode) {
        case Data.SearchMode.MAINTAINER: return "avatar-default-symbolic";
        case Data.SearchMode.FILE:       return "folder-symbolic";
        case Data.SearchMode.BINARY:     return "application-x-executable-symbolic";
        case Data.SearchMode.TASK:       return "emblem-system-symbolic";
        default:                         return "package-x-generic-symbolic";
        }
    }

    private void add_suggestion_button (Data.SearchMode mode, int count) {
        string label = _(MODE_LABELS[(int) mode]);

        var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER
        };
        var icon = new Gtk.Image.from_icon_name (mode_icon_name (mode)) {
            pixel_size = 18
        };
        var name_lbl = new Gtk.Label (_("Search as %s").printf (label));
        name_lbl.add_css_class ("heading");
        var count_lbl = Style.make_tag (_("%d").printf (count), "accent");

        content.append (icon);
        content.append (name_lbl);
        content.append (count_lbl);

        var btn = new Gtk.Button () {
            child = content,
            halign = Gtk.Align.CENTER
        };
        btn.add_css_class ("pill");
        btn.add_css_class ("suggestion");

        var captured = mode;
        btn.clicked.connect (() => {
            mode_dropdown.selected = (uint) captured;
        });

        suggestions_box.append (btn);
    }
}
