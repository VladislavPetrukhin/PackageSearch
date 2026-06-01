using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/maintainer_page.ui")]
public class MaintainerPage : Adw.NavigationPage, Ui.Findable {
    private MainWindow win;
    private string nick;
    private string branch;

    [GtkChild] private unowned Adw.WindowTitle title_widget;
    [GtkChild] private unowned Adw.ViewStack   stack;
    [GtkChild] private unowned Gtk.Label       header;
    [GtkChild] private unowned Gtk.ListBox     list;
    [GtkChild] private unowned Adw.StatusPage  empty_status;
    [GtkChild] private unowned Gtk.SearchBar   find_bar;
    [GtkChild] private unowned Gtk.SearchEntry find_entry;

    private GLib.Cancellable cancel = new GLib.Cancellable ();

    public MaintainerPage (MainWindow win, string nick, string branch) {
        this.win    = win;
        this.nick   = nick;
        this.branch = branch;

        this.title = nick;
        title_widget.title = nick;
        title_widget.subtitle = branch;
        empty_status.description = _("This maintainer has no packages in %s.").printf (branch);

        find_bar.connect_entry (find_entry);
        find_bar.set_key_capture_widget (this);
        find_entry.search_changed.connect (() => Ui.filter_listbox (list, find_entry.text));
        find_bar.notify["search-mode-enabled"].connect (() => {
            if (!find_bar.search_mode_enabled) Ui.filter_listbox (list, "");
        });

        this.hidden.connect (() => {
            if (!cancel.is_cancelled ()) cancel.cancel ();
        });
        load.begin ();
    }

    public void begin_find () {
        find_bar.search_mode_enabled = true;
        find_entry.grab_focus ();
    }

    private async void load () {
        var api = new Data.SearchApi ();
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
        if (Ui.is_nonempty (g.release)) vr = (vr == "") ? g.release : vr + "-" + g.release;

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
