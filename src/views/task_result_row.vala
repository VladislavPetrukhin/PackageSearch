using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/task_result_row.ui")]
public class TaskResultRow : Adw.ActionRow {
    [GtkChild] private unowned Gtk.Label packages_label;

    public int64  task_id       { get; private set; }
    public string target_branch { get; private set; }

    public TaskResultRow (Data.TaskResult t, string fallback_branch) {
        Object ();
        task_id = t.task_id;
        target_branch = Ui.is_nonempty (t.repo) ? t.repo : fallback_branch;

        string head = _("Task #%lld").printf (t.task_id);
        if (Ui.is_nonempty (t.state)) head += " · " + t.state;
        title = head;

        string sub = "";
        if (Ui.is_nonempty (t.owner))   sub = t.owner;
        if (Ui.is_nonempty (t.repo))    sub = (sub == "") ? t.repo  : sub + " · " + t.repo;
        if (Ui.is_nonempty (t.changed)) sub = (sub == "") ? t.changed : sub + " · " + t.changed;
        if (Ui.is_nonempty (t.message)) sub = (sub == "") ? t.message : sub + " — " + t.message;
        if (sub != "") subtitle = sub;

        if (Ui.is_nonempty (t.packages)) {
            packages_label.label = t.packages;
            packages_label.visible = true;
        }
    }
}
