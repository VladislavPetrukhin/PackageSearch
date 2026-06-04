using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/install_progress_dialog.ui")]
public class InstallProgressDialog : Adw.Dialog {
    [GtkChild] private unowned Gtk.Label       title_label;
    [GtkChild] private unowned Gtk.ProgressBar progress_bar;
    [GtkChild] private unowned Gtk.Label       status_label;
    [GtkChild] private unowned Gtk.Button      cancel_button;

    public signal void cancel_requested ();

    construct {
        cancel_button.clicked.connect (() => {
            cancel_button.sensitive = false;
            cancel_requested ();
        });
    }

    public void set_package_label (string text) { title_label.label = text; }

    public void set_status (string text) { status_label.label = text; }

    public void pulse () { progress_bar.pulse (); }

    public void set_fraction (double f) {
        if (f < 0.0) f = 0.0;
        if (f > 1.0) f = 1.0;
        progress_bar.fraction = f;
    }
}
