using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/version_compare_dialog.ui")]
public class VersionCompareDialog : Adw.Dialog {
    [GtkChild] private unowned Adw.WindowTitle    window_title;
    [GtkChild] private unowned Gtk.ToggleButton   only_diff;
    [GtkChild] private unowned Adw.PreferencesPage page;

    private Gee.ArrayList<Gtk.Widget> equal_widgets = new Gee.ArrayList<Gtk.Widget> ();
    private string branch_a;
    private string branch_b;

    public VersionCompareDialog (string pkg_name, string branch_a, string branch_b,
                                 Data.PackageDetails a, Data.PackageDetails b,
                                 Data.SpecFileInfo? spec_a, Data.SpecFileInfo? spec_b) {
        Object ();
        this.branch_a = branch_a;
        this.branch_b = branch_b;

        string head = _("Compare %s vs %s").printf (branch_a, branch_b);
        set_title (head);
        window_title.title = head;
        window_title.subtitle = pkg_name;

        build_meta (a, b);
        build_binaries (a, b);
        build_spec (spec_a, spec_b);

        only_diff.toggled.connect (() => {
            bool on = only_diff.active;
            foreach (var w in equal_widgets) w.visible = !on;
        });
        foreach (var w in equal_widgets) w.visible = false;
    }

    private static string evr_string (string? v, string? r) {
        string s = Ui.evr (v, r);
        return (s == "") ? "—" : s;
    }

    private void build_meta (Data.PackageDetails a, Data.PackageDetails b) {
        var meta_grp = new Adw.PreferencesGroup () { title = _("Metadata") };

        string evr_a = evr_string (a.version, a.release);
        string evr_b = evr_string (b.version, b.release);
        var ver_row = make_compare_text_row (_("Version"), evr_a, evr_b);
        if (evr_a != "—" && evr_b != "—") {
            int c = Business.VersionCompare.compare_evr (evr_a, evr_b);
            if (c > 0)      ver_row.subtitle = _("%s is newer").printf (branch_a);
            else if (c < 0) ver_row.subtitle = _("%s is newer").printf (branch_b);
            else            ver_row.subtitle = _("Same version");
        }
        meta_grp.add (ver_row);

        add_compare_row (meta_grp, _("Maintainer"), a.maintainer ?? "—", b.maintainer ?? "—");
        add_compare_row (meta_grp, _("License"), a.license ?? "—", b.license ?? "—");
        add_compare_row (meta_grp, _("Group"), a.group ?? "—", b.group ?? "—");
        add_compare_row (meta_grp, _("Summary"), a.summary ?? "—", b.summary ?? "—");
        page.add (meta_grp);
    }

    private void add_compare_row (Adw.PreferencesGroup grp, string title, string a, string b) {
        var row = make_compare_text_row (title, a, b);
        grp.add (row);
        if (a == b) equal_widgets.add (row);
    }

    private Adw.ActionRow make_compare_text_row (string title, string a, string b) {
        bool differ = (a != b);
        var row = new Adw.ActionRow () { title = title };
        var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18) {
            valign = Gtk.Align.CENTER
        };
        var la = new Gtk.Label (a) {
            xalign = 0.0f, halign = Gtk.Align.START,
            wrap = true, wrap_mode = Pango.WrapMode.WORD_CHAR,
            width_chars = 16, max_width_chars = 16
        };
        var lb = new Gtk.Label (b) {
            xalign = 0.0f, halign = Gtk.Align.START,
            wrap = true, wrap_mode = Pango.WrapMode.WORD_CHAR,
            width_chars = 16, max_width_chars = 16
        };
        if (!differ) {
            la.add_css_class ("dim-label");
            lb.add_css_class ("dim-label");
        }
        content.append (la);
        content.append (lb);
        row.add_suffix (content);
        return row;
    }

    private void build_binaries (Data.PackageDetails a, Data.PackageDetails b) {
        var names_a = new Gee.HashSet<string> ();
        var names_b = new Gee.HashSet<string> ();
        foreach (var bp in a.binaries) if (bp.name != null) names_a.add (bp.name);
        foreach (var bp in b.binaries) if (bp.name != null) names_b.add (bp.name);

        var only_a = new Gee.ArrayList<string> ();
        var only_b = new Gee.ArrayList<string> ();
        var common = new Gee.ArrayList<string> ();
        foreach (var n in names_a) {
            if (names_b.contains (n)) common.add (n); else only_a.add (n);
        }
        foreach (var n in names_b) if (!names_a.contains (n)) only_b.add (n);
        only_a.sort ((x, y) => strcmp (x, y));
        only_b.sort ((x, y) => strcmp (x, y));
        common.sort ((x, y) => strcmp (x, y));

        var bins_grp = new Adw.PreferencesGroup () {
            title = _("Binary packages"),
            description = _("%d common · %d only in %s · %d only in %s").printf (
                common.size, only_a.size, branch_a, only_b.size, branch_b)
        };
        if (only_a.size > 0) {
            var r = new Adw.ExpanderRow () {
                title = _("Only in %s").printf (branch_a),
                subtitle = _("%d packages").printf (only_a.size)
            };
            foreach (var n in only_a) r.add_row (new Adw.ActionRow () { title = n });
            bins_grp.add (r);
        }
        if (only_b.size > 0) {
            var r = new Adw.ExpanderRow () {
                title = _("Only in %s").printf (branch_b),
                subtitle = _("%d packages").printf (only_b.size)
            };
            foreach (var n in only_b) r.add_row (new Adw.ActionRow () { title = n });
            bins_grp.add (r);
        }
        if (common.size > 0) {
            var r = new Adw.ExpanderRow () {
                title = _("In both branches"),
                subtitle = _("%d packages").printf (common.size)
            };
            foreach (var n in common) r.add_row (new Adw.ActionRow () { title = n });
            bins_grp.add (r);
            equal_widgets.add (r);
        }
        if (only_a.size == 0 && only_b.size == 0 && common.size == 0)
            bins_grp.add (new Adw.ActionRow () { title = _("No binary packages reported") });
        if (only_a.size == 0 && only_b.size == 0)
            equal_widgets.add (bins_grp);
        page.add (bins_grp);
    }

    private void build_spec (Data.SpecFileInfo? spec_a, Data.SpecFileInfo? spec_b) {
        var spec_grp = new Adw.PreferencesGroup () { title = _("Spec file") };
        string sa = (spec_a != null && spec_a.content != null) ? spec_a.content : "";
        string sb = (spec_b != null && spec_b.content != null) ? spec_b.content : "";
        if (sa.strip () == "" && sb.strip () == "") {
            spec_grp.add (new Adw.ActionRow () { title = _("Spec file not available") });
        } else if (sa == sb) {
            spec_grp.add (new Adw.ActionRow () { title = _("Spec files are identical") });
        } else {
            string diff = Business.TextDiff.only_differences (sa, sb);
            string diff_head = _("Spec diff: %s ↔ %s").printf (branch_a, branch_b);
            var srow = new Adw.ActionRow () {
                title = _("Spec file"),
                subtitle = _("Differences between %s and %s").printf (branch_a, branch_b),
                activatable = true
            };
            var sbtn = new Gtk.Button.with_label (_("Show diff")) { valign = Gtk.Align.CENTER };
            sbtn.add_css_class ("flat");
            sbtn.clicked.connect (() => show_text_dialog (diff_head, diff));
            srow.add_suffix (sbtn);
            srow.activated.connect (() => show_text_dialog (diff_head, diff));
            spec_grp.add (srow);
        }
        page.add (spec_grp);
    }

    private void show_text_dialog (string head, string body) {
        new TextDialog (head, body).present (this);
    }

}
