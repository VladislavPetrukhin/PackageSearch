using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/source_result_row.ui")]
public class SourceResultRow : Adw.ActionRow {
    [GtkChild] private unowned Gtk.Label version_label;

    public Data.SourceGroup group { get; private set; }

    public SourceResultRow (Data.SourceGroup sg) {
        Object ();
        this.group = sg;
        title = sg.name ?? "";
        if (Ui.is_nonempty (sg.subtitle)) subtitle = sg.subtitle;

        var vr = Ui.evr (sg.version, sg.release);
        if (vr != "") {
            version_label.label = vr;
            version_label.visible = true;
        }
    }

    public void mark_removed () {
        add_css_class ("removed-row");
        subtitle = _("Removed from the repository");
        subtitle_lines = 1;
    }
}
