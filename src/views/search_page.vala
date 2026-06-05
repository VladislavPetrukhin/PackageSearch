using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/search_page.ui")]
public class SearchPage : Adw.NavigationPage, Ui.Findable {
    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
    [GtkChild] private unowned Gtk.Stack        content_stack;
    [GtkChild] private unowned Gtk.ListBox      results_list;
    [GtkChild] private unowned Gtk.Label        results_header;
    [GtkChild] private unowned Gtk.SearchBar    find_bar;
    [GtkChild] private unowned Gtk.SearchEntry  find_entry;

    [GtkChild] private unowned Gtk.DropDown    mode_dropdown;
    [GtkChild] private unowned Gtk.DropDown    repo_dropdown;
    [GtkChild] private unowned Gtk.SearchEntry search_entry;

    [GtkChild] private unowned Gtk.Button    retry_btn;
    [GtkChild] private unowned Gtk.Box       suggestions_box;
    [GtkChild] private unowned Gtk.Button history_btn;
    [GtkChild] private unowned Adw.StatusPage idle_status;

    private HistoryPopover history_popover;

    private GLib.Settings? settings = null;
    private const int    HISTORY_LIMIT   = 15;
    private const string SETTINGS_SCHEMA = "space.altlinux.PackageSearch";
    private const string KEY_RECENT      = "recent-queries";

    private uint   debounce_id    = 0;
    private string current_query  = "";
    private const string[] REPOS  = { "sisyphus", "p11", "p10", "p9", "c10f2", "c9f2" };
    private string current_repo   = "all";
    private string result_branch  = "sisyphus";
    private Data.SearchMode current_mode = Data.SearchMode.PACKAGE;

    private const uint DEBOUNCE_MS = 250;

    private GLib.Cancellable? in_flight           = null;
    private GLib.Cancellable? suggestions_cancel   = null;
    private uint64            query_seq            = 0;

    private const string[] MODE_LABELS = {
        N_("Package"), N_("Binary"), N_("File"), N_("Maintainer"), N_("Task")
    };
    private const string[] MODE_PLACEHOLDERS = {
        N_("Type a package name…"),
        N_("Type a binary package name…"),
        N_("Type a file name or path…"),
        N_("Type a maintainer nickname…"),
        N_("Type a package name or task ID…")
    };
    private const string[] MODE_IDLE_HINTS = {
        N_("Start typing a source package name, then pick it from the results."),
        N_("Start typing a binary package name, then pick it from the results."),
        N_("Start typing a file name or path to find the packages that contain it."),
        N_("Start typing a maintainer nickname to see the packages they maintain."),
        N_("Enter a task ID or a package name to open a build task.")
    };

    public signal void open_details (Data.SourceGroup group, string branch);
    public signal void open_task (int64 task_id, string branch);

    private static bool is_reasonable_term (string? s, Data.SearchMode mode) {
        if (s == null) return false;
        string term = s.strip ();
        if (term.length < 2) return false;
        try {
            switch (mode) {
            case Data.SearchMode.FILE:
                return new Regex ("^[A-Za-z0-9._+/\\-]*[A-Za-z0-9]{2,}[A-Za-z0-9._+/\\-]*$").match (term);
            default:
                return new Regex ("^[A-Za-z0-9._+\\-]+$").match (term);
            }
        } catch (Error e) {
            return term.length >= 2;
        }
    }

    private static bool is_all_digits (string s) {
        if (s.length == 0) return false;
        for (int i = 0; i < s.length; i++)
            if (s[i] < '0' || s[i] > '9') return false;
        return true;
    }

    private static Data.SearchMode[] probe_order (string term) {
        if (is_all_digits (term))
            return { Data.SearchMode.TASK, Data.SearchMode.PACKAGE,
                     Data.SearchMode.BINARY, Data.SearchMode.MAINTAINER, Data.SearchMode.FILE };
        if (term.contains ("/"))
            return { Data.SearchMode.FILE, Data.SearchMode.PACKAGE,
                     Data.SearchMode.BINARY, Data.SearchMode.MAINTAINER, Data.SearchMode.TASK };
        return { Data.SearchMode.MAINTAINER, Data.SearchMode.BINARY,
                 Data.SearchMode.PACKAGE, Data.SearchMode.FILE, Data.SearchMode.TASK };
    }

    private static string repo_display (string r) {
        return (r == "all") ? _("All") : r;
    }

    private Gtk.SignalListItemFactory make_repo_factory (bool compact) {
        var f = new Gtk.SignalListItemFactory ();
        f.setup.connect ((o) => {
            var l = new Gtk.Label ("") { xalign = 0 };
            if (compact) {
                l.ellipsize = Pango.EllipsizeMode.END;
                l.max_width_chars = 8;
            }
            ((Gtk.ListItem) o).child = l;
        });
        f.bind.connect ((o) => {
            var li = (Gtk.ListItem) o;
            var s = ((Gtk.StringObject) li.item).string;
            ((Gtk.Label) li.child).label = repo_display (s);
        });
        return f;
    }

    private Gtk.Widget make_probe_status (string text) {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
            halign = Gtk.Align.CENTER
        };
        box.append (new Gtk.Spinner () { spinning = true, valign = Gtk.Align.CENTER });
        var l = new Gtk.Label (text) {
            valign = Gtk.Align.CENTER
        };
        l.add_css_class ("dim-label");
        box.append (l);
        return box;
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
        history_popover = new HistoryPopover ();
        history_popover.query_chosen.connect ((q) => {
            search_entry.text = q;
            set_query (q);
            trigger_search_now ();
        });
        history_popover.set_parent (history_btn);
        history_btn.clicked.connect (() => history_popover.popup ());
        rebuild_history_popover ();

        var mode_model = new Gtk.StringList (null);
        foreach (var m in MODE_LABELS) mode_model.append (_(m));
        mode_dropdown.model = mode_model;
        mode_dropdown.selected = 0;
        mode_dropdown.notify["selected"].connect (() => {
            current_mode = (Data.SearchMode) mode_dropdown.selected;
            search_entry.set_placeholder_text (_(MODE_PLACEHOLDERS[(int) current_mode]));
            idle_status.description = _(MODE_IDLE_HINTS[(int) current_mode]);
            reset_search ();
            trigger_search_now ();
        });

        var repo_model = new Gtk.StringList (null);
        repo_model.append ("all");
        foreach (var r in REPOS) repo_model.append (r);
        repo_dropdown.model = repo_model;
        repo_dropdown.factory = make_repo_factory (true);
        repo_dropdown.list_factory = make_repo_factory (false);
        repo_dropdown.selected = 0;
        repo_dropdown.notify["selected"].connect (() => {
            var sel = repo_dropdown.selected;
            current_repo = (sel == 0) ? "all" : REPOS[sel - 1];
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
            if (row is SourceResultRow) {
                var sg = ((SourceResultRow) row).group;
                if (sg.bin_name != null) {
                    resolve_and_open.begin (sg, result_branch);
                } else {
                    if (Ui.is_nonempty (sg.name)) save_to_history (sg.name);
                    open_details (sg, result_branch);
                }
            } else if (row is TaskResultRow) {
                var tr = (TaskResultRow) row;
                open_task (tr.task_id, tr.target_branch);
            }
        });

        retry_btn.clicked.connect (() => trigger_search_now ());

        Ui.attach_find_bar (find_bar, find_entry, null, (q) => Ui.filter_listbox (results_list, q));

        show_idle ();
    }

    public void focus_search_entry () {
        search_entry.grab_focus ();
    }

    public void begin_find () {
        if (content_stack.get_visible_child_name () == "results") {
            find_bar.search_mode_enabled = true;
            find_entry.grab_focus ();
        } else {
            focus_search_entry ();
        }
    }

    private void close_find () {
        if (find_bar.search_mode_enabled) find_bar.search_mode_enabled = false;
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

    private void show_idle ()    { close_find (); content_stack.set_visible_child_name ("idle"); }
    private void show_loading () { close_find (); content_stack.set_visible_child_name ("loading"); }
    private void show_results () { content_stack.set_visible_child_name ("results"); }
    private void show_empty ()   { close_find (); content_stack.set_visible_child_name ("empty"); }
    private void show_error ()   { close_find (); content_stack.set_visible_child_name ("error"); }

    private async void do_search (GLib.Cancellable? cancellable, uint64 my_seq) {
        var term = Data.SearchText.normalize_layout (current_query);
        var mode = current_mode;

        if (term.length == 0 || !is_reasonable_term (term, mode)) {
            clear_results ();
            show_idle ();
            return;
        }

        show_loading ();

        string[] branches;
        if (current_repo == "all") branches = REPOS;
        else branches = { current_repo };

        var api = new Data.SearchApi ();
        try {
            if (mode == Data.SearchMode.TASK) {
                string? tb = (current_repo == "all") ? null : current_repo;
                var r = yield api.search_tasks (term, tb, cancellable);
                if (my_seq != query_seq) return;
                result_branch = (current_repo == "all") ? REPOS[0] : current_repo;
                apply_task_results (r, result_branch, term);
                return;
            }

            foreach (var b in branches) {
                var r = yield search_one (api, mode, b, term, cancellable);
                if (my_seq != query_seq) return;
                if (r.size > 0) {
                    result_branch = b;
                    apply_results (r, b, term);
                    return;
                }
            }

            if (mode == Data.SearchMode.PACKAGE) {
                var fuzzy = yield api.search_source_fuzzy (branches[0], term, cancellable);
                if (my_seq != query_seq) return;
                if (fuzzy.size > 0) {
                    result_branch = branches[0];
                    apply_results (fuzzy, branches[0], term);
                    return;
                }
            }

            result_branch = branches[0];
            apply_results (new Gee.ArrayList<Data.SourceGroup> (), branches[0], term);
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

    private async Gee.ArrayList<Data.SourceGroup> search_one (
        Data.SearchApi api, Data.SearchMode mode, string branch,
        string term, GLib.Cancellable? cancellable
    ) throws GLib.Error {
        switch (mode) {
        case Data.SearchMode.BINARY:
            var s = yield api.find_source_by_binary (branch, term, cancellable);
            var one = new Gee.ArrayList<Data.SourceGroup> ();
            if (s != null && s.length > 0) one.add (new Data.SourceGroup (s));
            return one;
        case Data.SearchMode.FILE:
            return yield api.search_by_file (branch, term, cancellable);
        case Data.SearchMode.MAINTAINER:
            return yield api.search_by_maintainer (branch, term, cancellable);
        default:
            return yield api.search_source (branch, term, cancellable);
        }
    }

    private void apply_results (Gee.ArrayList<Data.SourceGroup>? results, string branch, string term) {
        clear_results ();
        int n = 0;
        if (results != null) {
            foreach (var g in results) {
                if (g == null) continue;
                results_list.append (new SourceResultRow (g));
                n++;
            }
        }
        if (n == 0) {
            show_empty ();
            run_suggestions.begin (term, current_mode, branch, query_seq);
        } else {
            if (current_mode == Data.SearchMode.PACKAGE && n >= Data.SearchApi.SEARCH_RESULT_LIMIT)
                results_header.label = _("More than %d found in repository %s").printf (n, branch);
            else
                results_header.label = _("Found %d in repository %s").printf (n, branch);
            show_results ();
            reapply_find ();
        }
    }

    private void reapply_find () {
        if (find_bar.search_mode_enabled && find_entry.text.strip () != "")
            Ui.filter_listbox (results_list, find_entry.text);
    }

    private void apply_task_results (Gee.ArrayList<Data.TaskResult>? results, string branch, string term) {
        clear_results ();
        int n = 0;
        if (results != null) {
            foreach (var t in results) {
                if (t == null) continue;
                results_list.append (new TaskResultRow (t, result_branch));
                n++;
            }
        }
        if (n == 0) {
            show_empty ();
            run_suggestions.begin (term, current_mode, branch, query_seq);
        } else {
            results_header.label = _("Found %d in repository %s").printf (n, branch);
            show_results ();
            reapply_find ();
        }
    }

    private async void resolve_and_open (Data.SourceGroup sg, string branch) {
        var api = new Data.SearchApi ();
        string name = sg.bin_name;
        try {
            var src = yield api.find_source_by_binary (branch, sg.bin_name, null);
            if (src != null && src.length > 0) name = src;
        } catch (Error e) {
            warning ("[SearchPage] resolve_and_open: %s", e.message);
        }
        if (Ui.is_nonempty (name)) save_to_history (name);
        open_details (new Data.SourceGroup (name), branch);
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
        history_popover.set_items (load_history ());
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

        var status = make_probe_status (_("Looking in other search sections…"));
        suggestions_box.append (status);

        var api = new Data.SearchApi ();
        int found_modes = 0;
        foreach (var m in probe_order (term)) {
            if (m == original_mode) continue;
            if (cancel.is_cancelled () || my_seq != query_seq) return;
            if (!is_reasonable_term (term, m)) continue;

            int count = yield probe_mode (api, m, term, branch, cancel);
            if (cancel.is_cancelled () || my_seq != query_seq) return;
            if (count > 0) { add_suggestion_button (m, count); found_modes++; }
        }

        if (status.parent == suggestions_box) suggestions_box.remove (status);

        if (found_modes > 0 || current_repo == "all" || original_mode == Data.SearchMode.TASK)
            return;

        var repo_status = make_probe_status (_("Looking in other repositories…"));
        suggestions_box.append (repo_status);

        foreach (var repo in REPOS) {
            if (repo == current_repo) continue;
            if (cancel.is_cancelled () || my_seq != query_seq) return;

            Gee.ArrayList<Data.SourceGroup> r;
            try {
                r = yield search_one (api, original_mode, repo, term, cancel);
            } catch (Error e) {
                continue;
            }
            if (cancel.is_cancelled () || my_seq != query_seq) return;
            if (r.size > 0) add_repo_suggestion_button (repo, r.size);
        }

        if (repo_status.parent == suggestions_box) suggestions_box.remove (repo_status);
    }

    private async int probe_mode (Data.SearchApi api, Data.SearchMode mode,
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

    private void add_repo_suggestion_button (string repo, int count) {
        var btn = new Gtk.Button () {
            label = _("Search in %s (%d)").printf (repo, count),
            halign = Gtk.Align.CENTER
        };
        btn.add_css_class ("pill");
        var captured = repo;
        btn.clicked.connect (() => {
            for (uint i = 0; i < REPOS.length; i++) {
                if (REPOS[i] == captured) { repo_dropdown.selected = i + 1; break; }
            }
        });
        suggestions_box.append (btn);
    }
}
