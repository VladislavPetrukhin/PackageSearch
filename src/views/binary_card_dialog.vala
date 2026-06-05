using Gtk;
using Adw;
using GLib;
using Intl;

public class BinaryCardDialog : Adw.Dialog {
    private MainWindow win;
    private string     branch;
    private Data.BinaryPackage bp;

    private bool    can_install;
    private string  repo_evr;
    private string? install_block_reason;

    private Business.PackageManager pkg_mgr = new Business.PackageManager ();

    private Adw.ToastOverlay   toast_overlay = new Adw.ToastOverlay ();
    private Adw.HeaderBar       header = new Adw.HeaderBar ();
    private Adw.PreferencesGroup info_group = new Adw.PreferencesGroup ();
    private Adw.PreferencesGroup deps_group = new Adw.PreferencesGroup ();
    private Gtk.Label           files_title = new Gtk.Label (null);
    private Gtk.SearchBar       search_bar = new Gtk.SearchBar ();
    private Gtk.SearchEntry     search_entry = new Gtk.SearchEntry ();
    private Gtk.Stack           files_stack = new Gtk.Stack ();
    private Gtk.ListBox         files_view = new Gtk.ListBox ();
    private GLib.ListStore      files_store = new GLib.ListStore (typeof (Data.BinaryFile));
    private Gtk.CustomFilter    files_filter;
    private string              files_query = "";

    private GLib.Cancellable cancel = new GLib.Cancellable ();

    public BinaryCardDialog (MainWindow win, string branch, Data.BinaryPackage bp,
                             bool can_install, string repo_evr,
                             string? install_block_reason) {
        this.win          = win;
        this.branch       = branch;
        this.bp           = bp;
        this.can_install  = can_install;
        this.repo_evr     = repo_evr;
        this.install_block_reason = install_block_reason;

        build_ui ();
        load.begin ();
    }

    private void build_ui () {
        title = bp.name;
        set_content_width (820);
        set_content_height (700);

        var ver = Ui.evr (bp.version, bp.release);
        header.title_widget = new Adw.WindowTitle (bp.name, ver);

        setup_install_action.begin ();

        var search_btn = new Gtk.ToggleButton () {
            icon_name = "system-search-symbolic",
            tooltip_text = _("Search files")
        };
        search_btn.bind_property ("active", search_bar, "search-mode-enabled",
                                  GLib.BindingFlags.BIDIRECTIONAL);
        header.pack_start (search_btn);

        var toolbar = new Adw.ToolbarView ();
        toolbar.add_top_bar (header);

        search_bar.set_child (search_entry);
        Ui.attach_find_bar (search_bar, search_entry, null, (q) => {
            files_query = q.down ();
            files_filter.changed (Gtk.FilterChange.DIFFERENT);
            update_files_title ();
        });
        toolbar.add_top_bar (search_bar);

        info_group.margin_top = 12;
        info_group.margin_start = 12;
        info_group.margin_end = 12;
        info_group.visible = false;
        deps_group.margin_start = 12;
        deps_group.margin_end = 12;
        deps_group.margin_top = 12;
        deps_group.visible = false;

        files_title.add_css_class ("heading");
        files_title.xalign = 0.0f;
        files_title.margin_start = 16;
        files_title.margin_end = 12;
        files_title.margin_top = 16;
        files_title.margin_bottom = 4;
        files_title.label = _("Files");

        build_files_view ();

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        content.append (info_group);
        content.append (deps_group);
        content.append (files_title);
        content.append (files_stack);

        toolbar.set_content (content);
        toast_overlay.set_child (toolbar);
        set_child (toast_overlay);

        var sc = new Gtk.ShortcutController ();
        sc.add_shortcut (new Gtk.Shortcut (
            Gtk.ShortcutTrigger.parse_string ("<Control>f"),
            new Gtk.CallbackAction (() => {
                search_bar.search_mode_enabled = !search_bar.search_mode_enabled;
                return true;
            })));
        ((Gtk.Widget) this).add_controller (sc);
    }

    private async void setup_install_action () {
        if (!can_install) return;

        var installed = yield pkg_mgr.get_installed_packages ();
        if (cancel.is_cancelled ()) return;

        bool is_installed = installed.has_key (bp.name);
        bool needs_update = is_installed && repo_evr.length > 0
            && Business.VersionCompare.compare_evr (installed.get (bp.name), repo_evr) < 0;

        var btn = new Gtk.Button () { valign = Gtk.Align.CENTER };

        if (is_installed && !needs_update) {
            InstallController.mark_installed (btn);
            btn.clicked.connect (() => show_toast (_("Package is already installed")));
            header.pack_end (btn);
            return;
        }

        if (install_block_reason != null) {
            string reason = install_block_reason;
            btn.label = _("Install");
            btn.opacity = 0.55;
            btn.tooltip_text = reason;
            btn.clicked.connect (() => show_toast (reason));
            header.pack_end (btn);
            return;
        }

        bool is_update = needs_update;
        btn.label = is_update ? _("Update") : _("Install");
        btn.tooltip_text = is_update
            ? _("Update (requires authentication)")
            : _("Install (requires authentication)");
        btn.add_css_class ("suggested-action");
        win.installer.watch_button (btn);

        string captured_evr = repo_evr;
        string captured_name = bp.name;
        btn.clicked.connect (() => {
            win.installer.set_context (this, toast_overlay);
            win.installer.install.begin (captured_name, btn, captured_evr, is_update, null);
        });
        header.pack_end (btn);
    }

    private void build_files_view () {
        files_view.selection_mode = Gtk.SelectionMode.NONE;
        files_view.add_css_class ("boxed-list");
        files_view.valign = Gtk.Align.START;

        files_filter = new Gtk.CustomFilter ((obj) => {
            if (files_query.length == 0) return true;
            var f = obj as Data.BinaryFile;
            return f != null && f.name.down ().contains (files_query);
        });
        var filtered = new Gtk.FilterListModel (files_store, files_filter);

        files_view.bind_model (filtered, (obj) => {
            var f = obj as Data.BinaryFile;
            var name_lbl = new Gtk.Label (f.name) {
                xalign = 0.0f, hexpand = true,
                ellipsize = Pango.EllipsizeMode.MIDDLE,
                tooltip_text = f.name
            };
            name_lbl.add_css_class ("monospace");
            var size_lbl = new Gtk.Label ((f.size > 0) ? format_size (f.size) : "") {
                xalign = 1.0f
            };
            size_lbl.add_css_class ("dim-label");
            size_lbl.add_css_class ("numeric");
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
                margin_start = 12, margin_end = 12, margin_top = 6, margin_bottom = 6
            };
            box.append (name_lbl);
            box.append (size_lbl);

            var row = new Gtk.ListBoxRow ();
            row.set_child (box);
            string captured = f.name;
            var click = new Gtk.GestureClick ();
            click.released.connect (() => copy_to_clipboard (captured));
            row.add_controller (click);
            row.set_cursor (new Gdk.Cursor.from_name ("pointer", null));
            return row;
        });

        var scroll = new Gtk.ScrolledWindow () {
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vexpand = true,
            margin_start = 12, margin_end = 12, margin_bottom = 12
        };
        scroll.set_child (files_view);

        var spinner = new Gtk.Spinner () {
            spinning = true, width_request = 32, height_request = 32,
            halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER, vexpand = true
        };
        var empty = new Adw.StatusPage () {
            icon_name = "folder-symbolic",
            title = _("No files"),
            vexpand = true
        };
        empty.add_css_class ("compact");

        files_stack.vexpand = true;
        files_stack.hhomogeneous = false;
        files_stack.vhomogeneous = false;
        files_stack.add_named (spinner, "loading");
        files_stack.add_named (scroll, "list");
        files_stack.add_named (empty, "empty");
        files_stack.visible_child_name = "loading";
    }

    private void update_files_title () {
        uint total = files_store.get_n_items ();
        if (files_query.length == 0) {
            files_title.label = _("Files (%u)").printf (total);
        } else {
            uint shown = 0;
            for (uint i = 0; i < total; i++) {
                var f = files_store.get_item (i) as Data.BinaryFile;
                if (f != null && f.name.down ().contains (files_query)) shown++;
            }
            files_title.label = _("Files (%u of %u)").printf (shown, total);
        }
    }

    private async void load () {
        if (!Ui.is_nonempty (bp.pkghash)) {
            files_stack.visible_child_name = "empty";
            return;
        }
        int64 pkghash = int64.parse (bp.pkghash);
        var api = new Data.BinaryApi ();

        try {
            var bi = yield api.get_binary_info (branch, pkghash, cancel);
            if (cancel.is_cancelled ()) return;
            fill_info (bi);
            fill_deps (bi);
        } catch (Error e) {
            if (!(e is GLib.IOError.CANCELLED))
                fill_info (new Data.BinaryInfo ());
        }

        try {
            var files = yield api.get_binary_files (pkghash, cancel);
            if (cancel.is_cancelled ()) return;
            foreach (var f in files) files_store.append (f);
            update_files_title ();
            files_stack.visible_child_name = (files.size > 0) ? "list" : "empty";
        } catch (Error e) {
            if (!(e is GLib.IOError.CANCELLED))
                files_stack.visible_child_name = "empty";
        }
    }

    private void fill_info (Data.BinaryInfo bi) {
        bool any = false;
        if (Ui.is_nonempty (bi.summary)) {
            var r = new Adw.ActionRow () {
                title = _("Summary"), subtitle = bi.summary,
                subtitle_selectable = true
            };
            info_group.add (r);
            any = true;
        }
        if (Ui.is_nonempty (bi.license)) {
            var r = new Adw.ActionRow () {
                title = _("License"), subtitle = bi.license,
                subtitle_selectable = true
            };
            info_group.add (r);
            any = true;
        }
        info_group.visible = any;
    }

    private void fill_deps (Data.BinaryInfo bi) {
        if (bi.deps.size == 0) return;

        var by_type = new Gee.HashMap<string, Gee.ArrayList<Data.BinaryDep>> ();
        var order   = new Gee.ArrayList<string> ();
        foreach (var d in bi.deps) {
            var t = d.dep_type;
            var list = by_type.get (t);
            if (list == null) {
                list = new Gee.ArrayList<Data.BinaryDep> ();
                by_type.set (t, list);
                order.add (t);
            }
            list.add (d);
        }

        deps_group.title = _("Dependencies");
        deps_group.visible = true;
        foreach (var t in order) {
            var list = by_type.get (t);
            var exp = new Adw.ExpanderRow () {
                title = "%s (%d)".printf (dep_type_label (t), list.size)
            };
            foreach (var d in list) {
                var sub = Ui.is_nonempty (d.version) ? d.version : null;
                var dr = new Adw.ActionRow () { title = d.name };
                if (sub != null) dr.subtitle = sub;
                exp.add_row (dr);
            }
            deps_group.add (exp);
        }
    }

    private static string dep_type_label (string t) {
        switch (t.down ()) {
        case "require":  return _("Requires");
        case "provide":  return _("Provides");
        case "conflict": return _("Conflicts");
        case "obsolete": return _("Obsoletes");
        default:         return t;
        }
    }

    private void show_toast (string s) {
        toast_overlay.add_toast (new Adw.Toast (Ui.trim_toast (s)));
    }

    private void copy_to_clipboard (string text) {
        var disp = Gdk.Display.get_default ();
        if (disp != null) disp.get_clipboard ().set_text (text);
        toast_overlay.add_toast (new Adw.Toast (_("Copied")));
    }

    public override void closed () {
        if (!cancel.is_cancelled ()) cancel.cancel ();
    }
}
