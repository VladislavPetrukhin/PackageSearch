using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/task_details_page.ui")]
public class TaskDetailsPage : Adw.NavigationPage, Ui.Findable {
    private MainWindow win;
    private int64  task_id;
    private string branch;

    [GtkChild] private unowned Adw.WindowTitle       title_widget;
    [GtkChild] private unowned Adw.ViewStack         stack;
    [GtkChild] private unowned Adw.PreferencesGroup  info_group;
    [GtkChild] private unowned Adw.PreferencesGroup  subtasks_group;
    [GtkChild] private unowned Adw.PreferencesGroup  deps_group;
    [GtkChild] private unowned Adw.StatusPage        error_status;
    [GtkChild] private unowned Gtk.SearchBar         find_bar;
    [GtkChild] private unowned Gtk.SearchEntry       find_entry;

    private GLib.Cancellable cancel = new GLib.Cancellable ();

    public TaskDetailsPage (MainWindow win, int64 task_id, string branch) {
        this.win     = win;
        this.task_id = task_id;
        this.branch  = branch;

        string label = _("Task #%lld").printf (task_id);
        this.title = label;
        title_widget.title = label;
        title_widget.subtitle = branch;
        error_status.description = _("Could not load task #%lld.").printf (task_id);

        find_bar.connect_entry (find_entry);
        find_bar.set_key_capture_widget (this);
        find_entry.search_changed.connect (() => run_find (find_entry.text));
        find_bar.notify["search-mode-enabled"].connect (() => {
            if (!find_bar.search_mode_enabled) run_find ("");
        });

        this.hidden.connect (() => {
            if (!cancel.is_cancelled ()) cancel.cancel ();
        });
        load.begin ();
    }

    public void begin_find () {
        find_bar.search_mode_enabled = true;
        find_entry.grab_focus ();
    }

    private void run_find (string q) {
        Ui.filter_group (info_group, q);
        Ui.filter_group (subtasks_group, q);
        Ui.filter_group (deps_group, q);
    }

    private async void load () {
        var api = new Data.AltRepoClient ();
        try {
            var d = yield api.get_task_details (task_id, cancel);
            if (cancel.is_cancelled ()) return;
            populate (d);
            stack.set_visible_child_name ("content");
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[TaskDetailsPage] load failed: %s", e.message);
            stack.set_visible_child_name ("error");
        }
    }

    private void populate (Data.TaskDetails d) {
        if (Ui.is_nonempty (d.state)) title_widget.subtitle = "%s · %s".printf (branch, d.state);

        add_info (_("State"), d.state);
        add_info (_("Owner"), d.owner);
        add_info (_("Repository"), d.repo);
        add_info (_("Changed"), d.changed);
        if (d.try_num > 0 || d.iteration > 0)
            add_info (_("Try / iteration"), "%lld / %lld".printf (d.try_num, d.iteration));
        if (d.testonly)
            add_info (_("Test only"), _("Yes"));
        add_message (d.message);
        add_browser_row ();

        if (d.subtasks.size == 0) {
            subtasks_group.visible = false;
        } else {
            foreach (var st in d.subtasks) {
                if (st == null) continue;
                subtasks_group.add (make_subtask_row (st));
            }
        }

        if (d.dependencies.size == 0) {
            deps_group.visible = false;
        } else {
            foreach (var dep in d.dependencies) {
                if (dep == null) continue;
                deps_group.add (make_dep_row (dep));
            }
        }
    }

    private void add_info (string label, string? value) {
        if (!Ui.is_nonempty (value)) return;
        var row = new Adw.ActionRow () { title = label };
        var l = new Gtk.Label (value) { valign = Gtk.Align.CENTER, selectable = true };
        l.add_css_class ("dim-label");
        row.add_suffix (l);
        info_group.add (row);
    }

    private void add_message (string? message) {
        if (!Ui.is_nonempty (message)) return;
        var row = new Adw.ActionRow () {
            title = _("Message"),
            subtitle = message,
            subtitle_lines = 0
        };
        row.add_css_class ("property");
        info_group.add (row);
    }

    private void add_browser_row () {
        var row = new Adw.ActionRow () {
            title = _("Open on rdb.altlinux.org"),
            activatable = true
        };
        row.add_suffix (new Gtk.Image.from_icon_name ("adw-external-link-symbolic"));
        string uri = "https://rdb.altlinux.org/tasks/%lld/".printf (task_id);
        row.activated.connect (() => Ui.open_uri (uri));
        info_group.add (row);
    }

    private Adw.ActionRow make_subtask_row (Data.TaskSubtask st) {
        var row = new Adw.ActionRow () { title = st.name };

        string sub = "";
        if (Ui.is_nonempty (st.kind))     sub = st.kind;
        if (Ui.is_nonempty (st.pkg_from)) sub = (sub == "") ? st.pkg_from : sub + " · " + st.pkg_from;
        if (Ui.is_nonempty (sub)) row.subtitle = sub;

        if (Ui.is_nonempty (st.evr)) {
            var l = new Gtk.Label (st.evr) { valign = Gtk.Align.CENTER };
            l.add_css_class ("dim-label");
            l.add_css_class ("numeric");
            row.add_suffix (l);
        }

        if (Ui.is_nonempty (st.name)) {
            row.activatable = true;
            row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
            string captured = st.name;
            row.activated.connect (() => {
                win.show_details (new Data.SourceGroup (captured), branch);
            });
        }
        return row;
    }

    private Adw.ActionRow make_dep_row (int64 dep_id) {
        var row = new Adw.ActionRow () {
            title = _("Task #%lld").printf (dep_id),
            activatable = true
        };
        row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
        int64 captured = dep_id;
        row.activated.connect (() => {
            win.show_task_details (captured, branch);
        });
        return row;
    }
}
