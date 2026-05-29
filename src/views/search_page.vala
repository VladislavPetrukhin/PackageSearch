using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/search_page.ui")]
public class SearchPage : Adw.NavigationPage {
    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
    [GtkChild] private unowned Adw.ViewStack    content_stack;
    [GtkChild] private unowned Gtk.ListBox      results_list;
    [GtkChild] private unowned Gtk.Label        results_header;

    [GtkChild] private unowned Gtk.DropDown    mode_dropdown;
    [GtkChild] private unowned Gtk.SearchEntry search_entry;

    [GtkChild] private unowned Gtk.Button    retry_btn;
    [GtkChild] private unowned Gtk.Box       suggestions_box;
    [GtkChild] private unowned Gtk.MenuButton history_btn;

    private GLib.Settings? settings = null;
    private const int    HISTORY_LIMIT   = 15;
    private const string SETTINGS_SCHEMA = "space.altlinux.PackageSearch";
    private const string KEY_RECENT      = "recent-queries";

    private uint   debounce_id    = 0;
    private string current_query  = "";
    private const string current_branch = "sisyphus";
    private Data.SearchMode current_mode = Data.SearchMode.PACKAGE;

    private const uint DEBOUNCE_MS = 250;

    private GLib.Cancellable? in_flight           = null;
    private GLib.Cancellable? suggestions_cancel   = null;
    private uint64            query_seq            = 0;

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
            default:
                return new Regex ("^[A-Za-z0-9._+\\-]+$").match (term);
            }
        } catch (Error e) {
            return term.length >= 2;
        }
    }

    construct {
        try {
            var src = GLib.SettingsSchemaSource.get_default ();
            if (src != null && src.lookup (SETTINGS_SCHEMA, true) != null) {
                settings = new GLib.Settings (SETTINGS_SCHEMA);
            }
        } catch (Error e) {
            warning ("[SearchPage] settings unavailable: %s", e.message);
        }
        rebuild_history_popover ();

        var mode_model = new Gtk.StringList (null);
        foreach (var m in MODE_LABELS) mode_model.append (_(m));
        mode_dropdown.model = mode_model;
        mode_dropdown.selected = 0;
        mode_dropdown.notify["selected"].connect (() => {
            current_mode = (Data.SearchMode) mode_dropdown.selected;
            search_entry.set_placeholder_text (_(MODE_PLACEHOLDERS[(int) current_mode]));
            reset_search ();
            trigger_search_now ();
        });

        search_entry.search_changed.connect (() => {
            set_query ((search_entry.text ?? "").strip ());
            trigger_search_debounced ();
        });
        search_entry.activate.connect (() => {
            set_query ((search_entry.text ?? "").strip ());
            trigger_search_now ();
        });

        results_list.row_activated.connect ((row) => {
            var sg = row.get_data<Data.SourceGroup> ("sg");
            if (sg != null) {
                if (is_nonempty (sg.name)) save_to_history (sg.name);
                open_details (sg, current_branch);
            }
        });

        retry_btn.clicked.connect (() => trigger_search_now ());

        show_idle ();
    }

    public void focus_search_entry () {
        search_entry.grab_focus ();
    }

    public void clear_history () {
        if (settings != null) settings.set_strv (KEY_RECENT, new string[0]);
        rebuild_history_popover ();
        toast_overlay.add_toast (new Adw.Toast (_("Search history cleared")));
    }

    public void set_query (string? q) {
        current_query = (q != null) ? q.strip () : "";
        if (current_query.length == 0) {
            reset_search ();
            show_idle ();
        }
    }

    private void reset_search () {
        if (in_flight != null) { in_flight.cancel (); in_flight = null; }
        if (debounce_id != 0) { Source.remove (debounce_id); debounce_id = 0; }
        cancel_suggestions ();
        clear_results ();
    }

    public void trigger_search_debounced () {
        if (debounce_id != 0) { Source.remove (debounce_id); debounce_id = 0; }
        if (current_query.length == 0) { reset_search (); show_idle (); return; }
        debounce_id = Timeout.add (DEBOUNCE_MS, () => {
            trigger_search_now ();
            debounce_id = 0;
            return Source.REMOVE;
        });
    }

    public void trigger_search_now () {
        if (debounce_id != 0) { Source.remove (debounce_id); debounce_id = 0; }
        if (current_query.length == 0) { reset_search (); show_idle (); return; }

        if (in_flight != null) { in_flight.cancel (); in_flight = null; }
        cancel_suggestions ();
        in_flight = new GLib.Cancellable ();
        query_seq++;
        do_search.begin (in_flight, query_seq);
    }

    private void clear_results () {
        Gtk.Widget? c;
        while ((c = results_list.get_first_child ()) != null)
            results_list.remove (c);
    }

    private void show_idle ()    { content_stack.set_visible_child_name ("idle"); }
    private void show_loading () { content_stack.set_visible_child_name ("loading"); }
    private void show_results () { content_stack.set_visible_child_name ("results"); }
    private void show_empty ()   { content_stack.set_visible_child_name ("empty"); }
    private void show_error ()   { content_stack.set_visible_child_name ("error"); }

    private async void do_search (GLib.Cancellable? cancellable, uint64 my_seq) {
        var term   = Data.AltRepoClient.normalize_layout (current_query);
        var branch = current_branch;
        var mode   = current_mode;

        if (term.length == 0 || !is_reasonable_term (term, mode)) {
            clear_results ();
            show_idle ();
            return;
        }

        show_loading ();

        var api = new Data.AltRepoClient ();
        try {
            switch (mode) {
            case Data.SearchMode.PACKAGE:
                var r = yield api.search_source (branch, term, cancellable);
                if (my_seq != query_seq) return;
                apply_results (r, branch, term);
                break;

            case Data.SearchMode.BINARY:
                var src_name = yield api.find_source_by_binary (branch, term, cancellable);
                if (my_seq != query_seq) return;
                var one = new Gee.ArrayList<Data.SourceGroup> ();
                if (src_name != null && src_name.length > 0)
                    one.add (new Data.SourceGroup (src_name));
                apply_results (one, branch, term);
                break;

            case Data.SearchMode.FILE:
                var r = yield api.search_by_file (branch, term, cancellable);
                if (my_seq != query_seq) return;
                apply_results (r, branch, term);
                break;

            case Data.SearchMode.MAINTAINER:
                var r = yield api.search_by_maintainer (branch, term, cancellable);
                if (my_seq != query_seq) return;
                apply_results (r, branch, term);
                break;

            case Data.SearchMode.TASK:
                var r = yield api.search_tasks (term, branch, cancellable);
                if (my_seq != query_seq) return;
                apply_task_results (r, branch, term);
                break;
            }
        } catch (Error e) {
            if ((cancellable != null && cancellable.is_cancelled ()) || my_seq != query_seq)
                return;
            warning ("[SearchPage] do_search: %s", e.message);
            clear_results ();
            show_error ();
        } finally {
            if (cancellable == in_flight) in_flight = null;
        }
    }

    private void apply_results (Gee.ArrayList<Data.SourceGroup>? results, string branch, string term) {
        clear_results ();
        int n = 0;
        if (results != null) {
            foreach (var g in results) {
                if (g == null) continue;
                results_list.append (make_source_row (g));
                n++;
            }
        }
        if (n == 0) {
            show_empty ();
            run_suggestions.begin (term, current_mode, branch, query_seq);
        } else {
            results_header.label = _("Found %d in repository %s").printf (n, branch);
            show_results ();
        }
    }

    private void apply_task_results (Gee.ArrayList<Data.TaskResult>? results, string branch, string term) {
        clear_results ();
        int n = 0;
        if (results != null) {
            foreach (var t in results) {
                if (t == null) continue;
                results_list.append (make_task_row (t));
                n++;
            }
        }
        if (n == 0) {
            show_empty ();
            run_suggestions.begin (term, current_mode, branch, query_seq);
        } else {
            results_header.label = _("Found %d in repository %s").printf (n, branch);
            show_results ();
        }
    }

    private static Gtk.Label trailing_label (string text) {
        var l = new Gtk.Label (text) { valign = Gtk.Align.CENTER };
        l.add_css_class ("dim-label");
        l.add_css_class ("numeric");
        return l;
    }

    private Adw.ActionRow make_source_row (Data.SourceGroup sg) {
        string vr = "";
        if (is_nonempty (sg.version)) vr = sg.version;
        if (is_nonempty (sg.release)) vr = (vr == "") ? sg.release : vr + "-" + sg.release;

        var row = new Adw.ActionRow () {
            title = sg.name ?? "",
            activatable = true
        };
        if (vr != "") row.add_suffix (trailing_label (vr));
        row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
        row.set_data ("sg", sg);
        return row;
    }

    private Adw.ActionRow make_task_row (Data.TaskResult t) {
        var row = new Adw.ActionRow () {
            title = _("Task #%lld").printf (t.task_id)
        };
        string sub = "";
        if (is_nonempty (t.state))   sub = t.state;
        if (is_nonempty (t.owner))   sub = (sub == "") ? t.owner : sub + " · " + t.owner;
        if (is_nonempty (t.repo))    sub = (sub == "") ? t.repo  : sub + " · " + t.repo;
        if (is_nonempty (t.changed)) sub = (sub == "") ? t.changed : sub + " · " + t.changed;
        if (sub != "") row.subtitle = sub;
        if (is_nonempty (t.packages)) {
            var l = new Gtk.Label (t.packages) { valign = Gtk.Align.CENTER, ellipsize = Pango.EllipsizeMode.END, max_width_chars = 24 };
            l.add_css_class ("dim-label");
            row.add_suffix (l);
        }
        return row;
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

        var outer = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
            margin_top = 6, margin_bottom = 6, margin_start = 6, margin_end = 6
        };

        if (items.length == 0) {
            var empty = new Gtk.Label (_("No recent searches yet")) {
                halign = Gtk.Align.CENTER, margin_top = 6, margin_bottom = 6
            };
            empty.add_css_class ("dim-label");
            outer.append (empty);
        } else {
            var list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE };
            list.add_css_class ("boxed-list");
            foreach (var q in items) {
                var row = new Adw.ActionRow () { title = q, activatable = true };
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
        }

        popover.set_child (outer);
        history_btn.set_popover (popover);
    }

    private void cancel_suggestions () {
        if (suggestions_cancel != null) {
            suggestions_cancel.cancel ();
            suggestions_cancel = null;
        }
        clear_suggestions ();
    }

    private void clear_suggestions () {
        Gtk.Widget? c;
        while ((c = suggestions_box.get_first_child ()) != null)
            suggestions_box.remove (c);
    }

    private async void run_suggestions (string term, Data.SearchMode original_mode,
                                        string branch, uint64 my_seq) {
        if (suggestions_cancel != null) suggestions_cancel.cancel ();
        suggestions_cancel = new GLib.Cancellable ();
        var cancel = suggestions_cancel;

        clear_suggestions ();
        if (term.length == 0) return;

        Data.SearchMode[] modes = {
            Data.SearchMode.PACKAGE, Data.SearchMode.BINARY, Data.SearchMode.FILE,
            Data.SearchMode.MAINTAINER, Data.SearchMode.TASK
        };

        var api = new Data.AltRepoClient ();
        foreach (var m in modes) {
            if (m == original_mode) continue;
            if (cancel.is_cancelled () || my_seq != query_seq) return;
            if (!is_reasonable_term (term, m)) continue;

            int count = yield probe_mode (api, m, term, branch, cancel);
            if (cancel.is_cancelled () || my_seq != query_seq) return;
            if (count > 0) add_suggestion_button (m, count);
        }
    }

    private async int probe_mode (Data.AltRepoClient api, Data.SearchMode mode,
                                  string term, string branch, GLib.Cancellable? cancel) {
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

    private void add_suggestion_button (Data.SearchMode mode, int count) {
        var btn = new Gtk.Button () {
            label = _("Search as %s (%d)").printf (_(MODE_LABELS[(int) mode]), count),
            halign = Gtk.Align.CENTER
        };
        btn.add_css_class ("pill");
        var captured = mode;
        btn.clicked.connect (() => {
            mode_dropdown.selected = (uint) captured;
        });
        suggestions_box.append (btn);
    }
}
