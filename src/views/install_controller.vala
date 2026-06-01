using Gtk;
using Adw;
using GLib;
using Intl;

public class InstallController : GLib.Object {
    private Gtk.Widget            parent;
    private Adw.ToastOverlay      toast_overlay;
    private Business.PackageManager pkg_mgr;

    public InstallController (Gtk.Widget parent, Adw.ToastOverlay toast_overlay,
                              Business.PackageManager pkg_mgr) {
        this.parent        = parent;
        this.toast_overlay = toast_overlay;
        this.pkg_mgr       = pkg_mgr;
    }

    public static void mark_installed (Gtk.Button btn) {
        btn.remove_css_class ("suggested-action");
        btn.label = _("Installed");
        btn.tooltip_text = _("Package is already installed");
        btn.sensitive = false;
    }

    private void toast (string s) {
        toast_overlay.add_toast (new Adw.Toast (Ui.trim_toast (s)));
    }

    public async void install (string pkg_name, Gtk.Button btn,
                               string? repo_evr, bool is_update) {
        string orig_label = btn.label;
        btn.sensitive = false;
        btn.label = _("Checking…");

        var plan = yield pkg_mgr.simulate_install (pkg_name);
        btn.label = orig_label;

        if (!plan.ok) {
            btn.sensitive = true;
            warning ("[InstallController] simulate failed for %s:\n%s", pkg_name, plan.error ?? "(no output)");
            toast (_("Could not compute changes for %s").printf (pkg_name));
            return;
        }
        if (plan.is_empty ()) {
            btn.sensitive = true;
            toast (_("Nothing to do"));
            return;
        }

        bool confirmed = yield confirm_plan (pkg_name, is_update, plan);
        if (!confirmed) {
            btn.sensitive = true;
            toast (_("Installation cancelled"));
            return;
        }

        btn.label = is_update ? _("Updating…") : _("Installing…");
        var result = yield run_with_progress (pkg_name, repo_evr, is_update);

        switch (result) {
        case Business.InstallResult.SUCCESS:
            mark_installed (btn);
            toast ((is_update ? _("Updated %s") : _("Installed %s")).printf (pkg_name));
            break;
        case Business.InstallResult.CANCELLED:
            btn.label = orig_label;
            btn.sensitive = true;
            toast (_("Installation cancelled"));
            break;
        case Business.InstallResult.FAILED:
            btn.label = orig_label;
            btn.sensitive = true;
            toast ((is_update ? _("Failed to update %s") : _("Failed to install %s")).printf (pkg_name));
            break;
        }
    }

    private async bool confirm_plan (string pkg_name, bool is_update, Business.InstallPlan plan) {
        var dlg = new Adw.AlertDialog (
            (is_update ? _("Update %s?") : _("Install %s?")).printf (pkg_name), null);

        string sub = "";
        if (Ui.is_nonempty (plan.summary))  sub = plan.summary;
        if (Ui.is_nonempty (plan.download)) sub += (sub == "" ? "" : "\n") + plan.download;
        if (Ui.is_nonempty (plan.disk))     sub += (sub == "" ? "" : "\n") + plan.disk;
        if (sub != "") dlg.set_body (sub);

        dlg.set_extra_child (build_plan_widget (plan));

        dlg.add_response ("cancel", _("Cancel"));
        dlg.add_response ("ok", is_update ? _("Update") : _("Install"));
        dlg.set_response_appearance ("ok", plan.remove.size > 0
            ? Adw.ResponseAppearance.DESTRUCTIVE : Adw.ResponseAppearance.SUGGESTED);
        dlg.set_default_response ("ok");
        dlg.set_close_response ("cancel");

        string resp = yield dlg.choose (parent, null);
        return resp == "ok";
    }

    private Gtk.Widget build_plan_widget (Business.InstallPlan plan) {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        add_plan_section (box, _("New packages"),     plan.install, false);
        add_plan_section (box, _("Will be upgraded"), plan.upgrade, false);
        add_plan_section (box, _("Will be REMOVED"),  plan.remove,  true);

        var sw = new Gtk.ScrolledWindow () {
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            max_content_height = 240,
            propagate_natural_height = true
        };
        sw.set_child (box);
        return sw;
    }

    private void add_plan_section (Gtk.Box box, string title,
                                   Gee.ArrayList<string> items, bool danger) {
        if (items.size == 0) return;

        var head = new Gtk.Label (title) { xalign = 0.0f, halign = Gtk.Align.START };
        head.add_css_class ("heading");
        if (danger) head.add_css_class ("error");
        box.append (head);

        string names = "";
        foreach (var n in items) names = (names == "") ? n : names + ", " + n;
        var lbl = new Gtk.Label (names) {
            xalign = 0.0f, halign = Gtk.Align.START,
            wrap = true, wrap_mode = Pango.WrapMode.WORD_CHAR
        };
        lbl.add_css_class ("dim-label");
        box.append (lbl);
    }

    private async Business.InstallResult run_with_progress (string pkg_name,
                                                            string? repo_evr, bool is_update) {
        var cancellable = new GLib.Cancellable ();

        var pdlg = new InstallProgressDialog ();
        pdlg.set_package_label (
            (is_update ? _("Updating %s…") : _("Installing %s…")).printf (pkg_name));
        pdlg.cancel_requested.connect (() => cancellable.cancel ());
        pdlg.present (parent);

        uint pulse_id = Timeout.add (120, () => { pdlg.pulse (); return Source.CONTINUE; });
        ulong sig_id = pkg_mgr.install_progress.connect ((line) => pdlg.set_status (line));

        string? err = null;
        var result = yield pkg_mgr.run_install (pkg_name, repo_evr, cancellable, out err);

        Source.remove (pulse_id);
        pkg_mgr.disconnect (sig_id);
        pdlg.force_close ();

        if (result == Business.InstallResult.FAILED)
            warning ("[InstallController] install failed for %s:\n%s", pkg_name, err ?? "(no output)");
        return result;
    }
}
