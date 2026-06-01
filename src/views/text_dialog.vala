using Gtk;
using Adw;
using GLib;
using Gdk;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/text_dialog.ui")]
public class TextDialog : Adw.Dialog {
    [GtkChild] private unowned Adw.WindowTitle  window_title;
    [GtkChild] private unowned Gtk.Button       copy_button;
    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
    [GtkChild] private unowned Gtk.TextView     text_view;

    public TextDialog (string head, string body) {
        Object ();
        set_title (head);
        window_title.title = head;
        text_view.buffer.set_text (body ?? "");

        string captured = body ?? "";
        copy_button.clicked.connect (() => {
            var disp = Gdk.Display.get_default ();
            if (disp != null) disp.get_clipboard ().set_text (captured);
            toast_overlay.add_toast (new Adw.Toast (_("Copied")));
        });
    }
}
