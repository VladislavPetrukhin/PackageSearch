using Gtk;
using Adw;
using Intl;
using GLib;

[CCode (cname = "GETTEXT_PACKAGE")]
extern const string GETTEXT_PACKAGE;
[CCode (cname = "LOCALEDIR")]
extern const string LOCALEDIR;

public class PackageSearchApp : Adw.Application {

    public PackageSearchApp () {
        Object (application_id: "space.altlinux.PackageSearch",
                flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void startup () {
        base.startup ();

        var display = Gdk.Display.get_default();
        if (display != null) {
            var theme = Gtk.IconTheme.get_for_display(display);
            theme.add_resource_path ("/space/altlinux/PackageSearch/icons");

            var css = new Gtk.CssProvider ();
            css.load_from_resource ("/space/altlinux/PackageSearch/ui/style.css");
            Gtk.StyleContext.add_provider_for_display (
                display, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }
    }

    protected override void activate () {
        var win = this.active_window as MainWindow;
        if (win == null) win = new MainWindow (this);
        win.present ();
    }
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "");
    Intl.bindtextdomain (GETTEXT_PACKAGE, LOCALEDIR);
    Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain (GETTEXT_PACKAGE);

    return new PackageSearchApp ().run (args);
}
