using Gee;
using AltRepo;

namespace Data {

public class TaskApi : RepoApiBase {

    private static string subtask_display_name (AltRepo.SubTaskInfoElement st) {
        if (st.src_pkg_name != null && st.src_pkg_name.length > 0) return st.src_pkg_name;
        if (st.subtask_srpm_name != null && st.subtask_srpm_name.length > 0) return st.subtask_srpm_name;
        if (st.subtask_package != null && st.subtask_package.length > 0) return st.subtask_package;
        if (st.subtask_dir != null && st.subtask_dir.length > 0) {
            var b = GLib.Path.get_basename (st.subtask_dir);
            if (b.has_suffix (".git")) b = b.substring (0, b.length - 4);
            return b;
        }
        return "";
    }

    public async TaskDetails get_task_details (
        int64 task_id, GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        var key = "taskinfo|%lld".printf (task_id);
        var cached = cache_get (key);
        if (cached != null && cached.obj is TaskDetails)
            return (TaskDetails) cached.obj;

        yield throttle ();
        var d = new TaskDetails ();
        var info = yield cli.get_task_progress_task_info_id_async (
            task_id, Priority.DEFAULT, null
        );

        d.task_id   = info.task_id;
        d.state     = info.task_state ?? "";
        d.owner     = info.task_owner ?? "";
        d.repo      = info.task_repo ?? "";
        d.changed   = info.task_changed ?? "";
        d.message   = info.task_message ?? "";
        d.stage     = info.task_stage ?? "";
        d.try_num   = info.task_try;
        d.iteration = info.task_iter;
        d.testonly  = info.task_testonly != 0;

        foreach (var st in info.subtasks) {
            var ts = new TaskSubtask ();
            ts.id       = st.subtask_id;
            ts.name     = subtask_display_name (st);
            ts.kind     = st.subtask_type ?? "";
            ts.pkg_from = st.subtask_pkg_from ?? "";
            if (st.subtask_srpm_evr != null && st.subtask_srpm_evr.length > 0)
                ts.evr = st.subtask_srpm_evr;
            else if (st.subtask_tag_name != null)
                ts.evr = st.subtask_tag_name;
            d.subtasks.add (ts);
        }
        foreach (var dep in info.dependencies) d.dependencies.add (dep);

        cache_put_obj (key, d);
        return d;
    }
}

}
