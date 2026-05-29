using Gtk;
using Adw;
using GLib;
using Intl;

public class MaintainerPage : Adw.NavigationPage {
    private MainWindow win;
    private string nick;
    private string branch;

    private Adw.ViewStack stack;
    private Gtk.ListBox   list;
    private Gtk.Label     header;
    private GLib.Cancellable cancel = new GLib.Cancellable ();

    public MaintainerPage (MainWindow win, string nick, string branch) {
        this.win    = win;
        this.nick   = nick;
        this.branch = branch;

        this.title = nick;
        this.tag   = "maintainer";

        build_ui ();
        this.hidden.connect (() => {
            if (!cancel.is_cancelled ()) cancel.cancel ();
        });
        load.begin ();
    }

    private static bool is_nonempty (string? s) {
        return s != null && s.strip ().length > 0;
    }

    private void build_ui () {
        var header_bar = new Adw.HeaderBar ();
        header_bar.set_title_widget (new Adw.WindowTitle (nick, branch));

        stack = new Adw.ViewStack () { vexpand = true };

        var spinner = new Gtk.Spinner () {
            spinning = true, width_request = 42, height_request = 42,
            halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER
        };
        stack.add_named (spinner, "loading");

        header = new Gtk.Label ("") {
            xalign = 0.0f, halign = Gtk.Align.START, margin_start = 4
        };
        header.add_css_class ("dim-label");

        list = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.NONE, valign = Gtk.Align.START
        };
        list.add_css_class ("boxed-list");

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        box.append (header);
        box.append (list);

        var clamp = new Adw.Clamp () {
            maximum_size = 800,
            margin_start = 12, margin_end = 12, margin_top = 12, margin_bottom = 12
        };
        clamp.set_child (box);

        var sw = new Gtk.ScrolledWindow () {
            hscrollbar_policy = Gtk.PolicyType.NEVER, vexpand = true
        };
        sw.set_child (clamp);
        stack.add_named (sw, "results");

        var empty = new Adw.StatusPage () {
            icon_name = "system-users-symbolic",
            title = _("No packages"),
            description = _("This maintainer has no packages in %s.").printf (branch)
        };
        stack.add_named (empty, "empty");

        stack.set_visible_child_name ("loading");

        var tv = new Adw.ToolbarView ();
        tv.add_top_bar (header_bar);
        tv.set_content (stack);
        this.set_child (tv);
    }

    private async void load () {
        var api = new Data.AltRepoClient ();
        try {
            var pkgs = yield api.search_by_maintainer (branch, nick, cancel);
            if (cancel.is_cancelled ()) return;
            if (pkgs == null || pkgs.size == 0) {
                stack.set_visible_child_name ("empty");
                return;
            }
            header.label = _("%d packages by %s").printf (pkgs.size, nick);
            foreach (var g in pkgs) {
                if (g == null) continue;
                list.append (make_row (g));
            }
            stack.set_visible_child_name ("results");
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[MaintainerPage] load failed: %s", e.message);
            stack.set_visible_child_name ("empty");
        }
    }

    private Adw.ActionRow make_row (Data.SourceGroup g) {
        string vr = (g.version ?? "");
        if (is_nonempty (g.release)) vr = (vr == "") ? g.release : vr + "-" + g.release;

        var row = new Adw.ActionRow () { title = g.name ?? "", activatable = true };
        if (vr != "") {
            var l = new Gtk.Label (vr) { valign = Gtk.Align.CENTER };
            l.add_css_class ("dim-label");
            l.add_css_class ("numeric");
            row.add_suffix (l);
        }
        row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));

        string captured = g.name;
        string? cv = g.version;
        string? cr = g.release;
        row.activated.connect (() => {
            var sg = new Data.SourceGroup (captured);
            sg.version = cv;
            sg.release = cr;
            win.show_details (sg, branch);
        });
        return row;
    }
}
