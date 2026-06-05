using Gtk;
using Adw;
using GLib;
using Intl;

public class InstallController : GLib.Object {
    private Gtk.Widget?           parent = null;
    private Adw.ToastOverlay?     toast_overlay = null;
    private Business.PackageManager pkg_mgr = new Business.PackageManager ();
    private GLib.Cancellable?     active_cancellable = null;
    private Adw.Dialog?           active_dialog = null;
    private bool                  user_cancelled = false;
    private Business.InstallResult last_result = Business.InstallResult.SUCCESS;

    public bool busy { get; private set; default = false; }

    public signal void install_finished (bool success);

    public void set_context (Gtk.Widget parent, Adw.ToastOverlay toast_overlay) {
        this.parent        = parent;
        this.toast_overlay = toast_overlay;
    }

    public void watch_button (Gtk.Button btn) {
        this.bind_property ("busy", btn, "sensitive", GLib.BindingFlags.SYNC_CREATE,
            (b, src, ref tgt) => {
                tgt.set_boolean (btn.has_css_class ("ps-installed") || !src.get_boolean ());
                return true;
            });
    }

    private void set_active (GLib.Cancellable? c) {
        active_cancellable = c;
        busy = (c != null);
    }

    public void cancel_active () {
        if (active_dialog != null) active_dialog.force_close ();
        if (active_cancellable != null && !active_cancellable.is_cancelled ())
            active_cancellable.cancel ();
    }

    public static void mark_installed (Gtk.Button btn) {
        btn.remove_css_class ("suggested-action");
        btn.add_css_class ("ps-installed");
        btn.label = _("Installed");
        btn.tooltip_text = _("Package is already installed");
        btn.opacity = 0.55;
    }

    private void toast (string s) {
        if (toast_overlay != null)
            toast_overlay.add_toast (new Adw.Toast (Ui.trim_toast (s)));
    }

    private static void group_label (Gee.List<Gtk.Button> group, string label) {
        foreach (var b in group) b.label = label;
    }

    private static void group_sensitive (Gee.List<Gtk.Button> group, bool sensitive) {
        foreach (var b in group) b.sensitive = sensitive;
    }

    private static void group_mark_installed (Gee.List<Gtk.Button> group) {
        foreach (var b in group) mark_installed (b);
    }

    public async void install (string pkg_name, Gtk.Button btn,
                               string? repo_evr, bool is_update,
                               Gee.List<Gtk.Button>? siblings = null) {
        if (active_cancellable != null) return;
        if (parent == null) return;

        var flow = new GLib.Cancellable ();
        set_active (flow);

        var group = new Gee.ArrayList<Gtk.Button> ();
        group.add (btn);
        if (siblings != null)
            foreach (var s in siblings)
                if (s != btn) group.add (s);

        string orig_label = btn.label;
        group_sensitive (group, false);
        group_label (group, _("Checking…"));

        var plan = yield pkg_mgr.simulate_install (pkg_name);
        if (flow.is_cancelled ()) { set_active (null); return; }
        group_label (group, orig_label);

        if (!plan.ok) {
            set_active (null);
            group_sensitive (group, true);
            warning ("[InstallController] simulate failed for %s:\n%s", pkg_name, plan.error ?? "(no output)");
            toast (plan.not_available
                ? _("%s is not available in the enabled repositories").printf (pkg_name)
                : _("Could not compute changes for %s").printf (pkg_name));
            return;
        }
        if (plan.is_empty ()) {
            set_active (null);
            pkg_mgr.invalidate_installed_cache ();
            group_mark_installed (group);
            toast (_("Already up to date"));
            return;
        }

        bool confirmed = yield confirm_plan (pkg_name, is_update, plan);
        if (flow.is_cancelled ()) { set_active (null); return; }
        if (!confirmed) {
            set_active (null);
            group_sensitive (group, true);
            toast (_("Installation cancelled"));
            return;
        }

        group_label (group, is_update ? _("Updating…") : _("Installing…"));
        yield run_with_progress (pkg_name, repo_evr, is_update, flow);
        var result = last_result;
        set_active (null);

        switch (result) {
        case Business.InstallResult.SUCCESS:
            pkg_mgr.invalidate_installed_cache ();
            group_mark_installed (group);
            toast ((is_update ? _("Updated %s") : _("Installed %s")).printf (pkg_name));
            install_finished (true);
            break;
        case Business.InstallResult.CANCELLED:
            group_label (group, orig_label);
            group_sensitive (group, true);
            toast (_("Installation cancelled"));
            break;
        case Business.InstallResult.UNTRUSTED:
            group_label (group, orig_label);
            group_sensitive (group, true);
            toast (_("%s is not signed — installation refused").printf (pkg_name));
            break;
        case Business.InstallResult.FAILED:
            group_label (group, orig_label);
            group_sensitive (group, true);
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

        active_dialog = dlg;
        string resp = yield dlg.choose (parent, null);
        active_dialog = null;
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
                                                            string? repo_evr, bool is_update,
                                                            GLib.Cancellable cancellable) {
        user_cancelled = false;

        var pdlg = new InstallProgressDialog ();
        pdlg.set_package_label (
            (is_update ? _("Updating %s…") : _("Installing %s…")).printf (pkg_name));
        pdlg.cancel_requested.connect (() => {
            user_cancelled = true;
            cancellable.cancel ();
        });
        active_dialog = pdlg;
        pdlg.present (parent);

        bool determinate = false;
        uint pulse_id = Timeout.add (120, () => {
            if (!determinate) pdlg.pulse ();
            return Source.CONTINUE;
        });
        ulong sig_id = pkg_mgr.install_progress.connect ((line) => pdlg.set_status (line));
        ulong pct_id = pkg_mgr.install_percentage.connect ((pct) => {
            determinate = true;
            pdlg.set_fraction (pct / 100.0);
        });

        string? err = null;
        var raw = yield pkg_mgr.run_install (pkg_name, repo_evr, cancellable, out err);
        bool cancelled = user_cancelled || cancellable.is_cancelled ();
        var result = cancelled ? Business.InstallResult.CANCELLED : raw;
        last_result = result;

        Source.remove (pulse_id);
        pkg_mgr.disconnect (sig_id);
        pkg_mgr.disconnect (pct_id);
        pdlg.force_close ();
        active_dialog = null;

        if (result == Business.InstallResult.FAILED)
            warning ("[InstallController] install failed for %s:\n%s", pkg_name, err ?? "(no output)");
        return result;
    }
}
