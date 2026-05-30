using Gtk;
using Adw;
using GLib;
using Gdk;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/details_page.ui")]
public class DetailsPage : Adw.NavigationPage {
    private Data.SourceGroup group;
    private string branch;
    private MainWindow win;

    private Business.PackageManager pkg_mgr = new Business.PackageManager ();

    [GtkChild] private unowned Adw.ToastOverlay   toast_overlay;
    [GtkChild] private unowned Adw.WindowTitle    header_title;
    [GtkChild] private unowned Gtk.Box            header_actions;
    [GtkChild] private unowned Adw.Banner         banner;
    [GtkChild] private unowned Gtk.Revealer       loading_revealer;

    [GtkChild] private unowned Adw.PreferencesGroup hero_group;
    [GtkChild] private unowned Adw.PreferencesGroup info_group;
    [GtkChild] private unowned Adw.PreferencesGroup bins_group;
    [GtkChild] private unowned Adw.PreferencesGroup deps_group;
    [GtkChild] private unowned Adw.PreferencesGroup security_group;
    [GtkChild] private unowned Adw.PreferencesGroup versions_group;
    [GtkChild] private unowned Adw.PreferencesGroup downloads_group;
    [GtkChild] private unowned Adw.PreferencesGroup spec_group;
    [GtkChild] private unowned Adw.PreferencesGroup changelog_group;

    private Gee.HashSet<string> selected_branches = new Gee.HashSet<string> ();
    private Gtk.Button?         compare_btn = null;

    private GLib.Cancellable cancel = new GLib.Cancellable ();

    private const int MAX_CHANGE_PREVIEW = 200;

    public void cancel_loading () {
        if (!cancel.is_cancelled ()) cancel.cancel ();
    }

    private static bool is_nonempty (string? s) {
        return s != null && s.strip ().length > 0;
    }

    private static string normalize_url (string raw) {
        string url = (raw ?? "").strip ();
        if (url.length == 0) return url;
        if (!(url.has_prefix ("http://") || url.has_prefix ("https://")))
            url = "https://" + url;
        return url;
    }

    private static void open_uri (string url) {
        try { AppInfo.launch_default_for_uri (url, null); }
        catch (Error e) { warning ("open url failed: %s", e.message); }
    }

    private void copy_to_clipboard (string text) {
        var disp = Gdk.Display.get_default ();
        if (disp != null) disp.get_clipboard ().set_text (text);
        toast_overlay.add_toast (new Adw.Toast (_("Copied")));
    }

    private static string trim_toast (string s) {
        const int LIMIT = 80;
        var clean = s.replace ("\n", " ").strip ();
        if (clean.length <= LIMIT) return clean;
        return clean.substring (0, LIMIT) + "…";
    }

    private void toast (string s) {
        toast_overlay.add_toast (new Adw.Toast (trim_toast (s)));
    }

    private static Gtk.Label dim_label (string text) {
        var l = new Gtk.Label (text) {
            valign = Gtk.Align.CENTER,
            ellipsize = Pango.EllipsizeMode.END,
            max_width_chars = 24
        };
        l.add_css_class ("dim-label");
        return l;
    }

    private Gtk.ListBox? find_listbox (Gtk.Widget w) {
        for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
            if (c is Gtk.ListBox) return (Gtk.ListBox) c;
            var r = find_listbox (c);
            if (r != null) return r;
        }
        return null;
    }

    private void clear_group (Adw.PreferencesGroup grp) {
        var lb = find_listbox (grp);
        if (lb == null) return;
        var to_remove = new Gee.ArrayList<Gtk.Widget> ();
        for (var c = lb.get_first_child (); c != null; c = c.get_next_sibling ())
            to_remove.add (c);
        foreach (var w in to_remove) grp.remove (w);
    }

    private void clear_box (Gtk.Box box) {
        Gtk.Widget? c;
        while ((c = box.get_first_child ()) != null) box.remove (c);
    }

    private void add_info_row_if_nonempty (string title, string? value) {
        if (is_nonempty (value))
            info_group.add (new Adw.ActionRow () {
                title = title,
                subtitle = GLib.Markup.escape_text (value, -1)
            });
    }

    private static string category_icon (string? grp) {
        var g = (grp ?? "").down ();
        if (g.contains ("librar"))                                 return "application-x-addon-symbolic";
        if (g.has_prefix ("develop"))                              return "applications-engineering-symbolic";
        if (g.has_prefix ("graphic"))                              return "applications-graphics-symbolic";
        if (g.has_prefix ("network") || g.contains ("internet"))   return "applications-internet-symbolic";
        if (g.has_prefix ("game"))                                 return "applications-games-symbolic";
        if (g.has_prefix ("sound") || g.contains ("video") || g.contains ("multimedia"))
                                                                   return "applications-multimedia-symbolic";
        if (g.has_prefix ("editor") || g.has_prefix ("text"))      return "text-editor-symbolic";
        if (g.contains ("font"))                                   return "font-x-generic-symbolic";
        if (g.has_prefix ("scien") || g.contains ("engineering"))  return "applications-science-symbolic";
        if (g.has_prefix ("databas"))                              return "drive-harddisk-symbolic";
        if (g.has_prefix ("office") || g.contains ("publish"))     return "x-office-document-symbolic";
        if (g.has_prefix ("system"))                               return "applications-system-symbolic";
        return "package-x-generic-symbolic";
    }

    private Gtk.Widget build_hero (string name, string? summary, string? grp) {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18) {
            margin_top = 6,
            margin_bottom = 6
        };

        box.append (new Gtk.Image.from_icon_name (category_icon (grp)) {
            pixel_size = 48,
            valign = Gtk.Align.CENTER
        });

        var col = new Gtk.Box (Gtk.Orientation.VERTICAL, 3) {
            valign = Gtk.Align.CENTER,
            hexpand = true
        };

        var name_l = new Gtk.Label (name) {
            xalign = 0,
            ellipsize = Pango.EllipsizeMode.END
        };
        name_l.add_css_class ("title-2");
        col.append (name_l);

        if (is_nonempty (summary)) {
            var sum_l = new Gtk.Label (summary) {
                xalign = 0,
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR
            };
            col.append (sum_l);
        }

        if (is_nonempty (grp)) {
            var grp_l = new Gtk.Label (grp) {
                xalign = 0,
                ellipsize = Pango.EllipsizeMode.END
            };
            grp_l.add_css_class ("caption");
            grp_l.add_css_class ("dim-label");
            col.append (grp_l);
        }

        box.append (col);
        return box;
    }

    private static void mark_installed (Gtk.Button btn) {
        btn.remove_css_class ("suggested-action");
        btn.label = _("Installed");
        btn.tooltip_text = _("Package is already installed");
        btn.sensitive = false;
    }

    public DetailsPage (Data.SourceGroup group, string branch, MainWindow win) {
        this.group  = group;
        this.branch = branch;
        this.win    = win;

        this.title = group.name;
        header_title.set_title (group.name ?? "");
        header_title.set_subtitle (branch);

        loading_revealer.reveal_child = true;

        load_details.begin ();
    }

    private Adw.Dialog new_dialog (string title, string subtitle, int width, int height,
                                   Gtk.Widget content, out Adw.HeaderBar header) {
        var dlg = new Adw.Dialog ();
        if (width > 0)  dlg.set_content_width (width);
        if (height > 0) dlg.set_content_height (height);
        dlg.set_title (title);

        header = new Adw.HeaderBar () { show_end_title_buttons = true };
        header.set_title_widget (new Adw.WindowTitle (title, subtitle));

        var tb = new Adw.ToolbarView ();
        tb.add_top_bar (header);
        tb.set_content (content);
        dlg.set_child (tb);
        return dlg;
    }

    private void show_text_dialog (string head, string body) {
        var tv = new Gtk.TextView () {
            editable = false, cursor_visible = false, monospace = true,
            wrap_mode = Gtk.WrapMode.WORD_CHAR,
            top_margin = 8, bottom_margin = 8, left_margin = 12, right_margin = 12
        };
        tv.buffer.set_text (body ?? "");

        var sw = new Gtk.ScrolledWindow () { vexpand = true };
        sw.set_child (tv);

        Adw.HeaderBar hb;
        var dlg = new_dialog (head, "", 820, 600, sw, out hb);

        var copy_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
            tooltip_text = _("Copy"), valign = Gtk.Align.CENTER
        };
        copy_btn.add_css_class ("flat");
        copy_btn.clicked.connect (() => copy_to_clipboard (body ?? ""));
        hb.pack_end (copy_btn);

        dlg.present (this.get_root () as Gtk.Window);
    }

    private async void install_binary (string pkg_name, Gtk.Button btn,
                                       string? repo_evr, bool is_update) {
        string orig_label = btn.label;
        btn.sensitive = false;
        btn.label = _("Checking…");

        var plan = yield pkg_mgr.simulate_install (pkg_name);
        btn.label = orig_label;

        if (!plan.ok) {
            btn.sensitive = true;
            warning ("[DetailsPage] simulate failed for %s:\n%s", pkg_name, plan.error ?? "(no output)");
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
        if (is_nonempty (plan.summary))  sub = plan.summary;
        if (is_nonempty (plan.download)) sub += (sub == "" ? "" : "\n") + plan.download;
        if (is_nonempty (plan.disk))     sub += (sub == "" ? "" : "\n") + plan.disk;
        if (sub != "") dlg.set_body (sub);

        dlg.set_extra_child (build_plan_widget (plan));

        dlg.add_response ("cancel", _("Cancel"));
        dlg.add_response ("ok", is_update ? _("Update") : _("Install"));
        dlg.set_response_appearance ("ok", plan.remove.size > 0
            ? Adw.ResponseAppearance.DESTRUCTIVE : Adw.ResponseAppearance.SUGGESTED);
        dlg.set_default_response ("ok");
        dlg.set_close_response ("cancel");

        string resp = yield dlg.choose (this, null);
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

        var pdlg = new Adw.Dialog ();
        pdlg.set_content_width (460);
        pdlg.set_can_close (false);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_top = 24, margin_bottom = 24, margin_start = 24, margin_end = 24
        };

        var title_lbl = new Gtk.Label (
            (is_update ? _("Updating %s…") : _("Installing %s…")).printf (pkg_name)) {
            xalign = 0.0f, halign = Gtk.Align.START, wrap = true
        };
        title_lbl.add_css_class ("title-4");

        var pb = new Gtk.ProgressBar () { hexpand = true };

        var status = new Gtk.Label ("") {
            xalign = 0.0f, halign = Gtk.Align.START,
            ellipsize = Pango.EllipsizeMode.END, max_width_chars = 48
        };
        status.add_css_class ("dim-label");
        status.add_css_class ("monospace");

        var cancel_btn = new Gtk.Button.with_label (_("Cancel")) { halign = Gtk.Align.END };
        cancel_btn.clicked.connect (() => {
            cancel_btn.sensitive = false;
            cancellable.cancel ();
        });

        box.append (title_lbl);
        box.append (pb);
        box.append (status);
        box.append (cancel_btn);
        pdlg.set_child (box);
        pdlg.present (this);

        uint pulse_id = Timeout.add (120, () => { pb.pulse (); return Source.CONTINUE; });
        ulong sig_id = pkg_mgr.install_progress.connect ((line) => { status.label = line; });

        string? err = null;
        var result = yield pkg_mgr.run_install (pkg_name, repo_evr, cancellable, out err);

        Source.remove (pulse_id);
        pkg_mgr.disconnect (sig_id);
        pdlg.force_close ();

        if (result == Business.InstallResult.FAILED)
            warning ("[DetailsPage] install failed for %s:\n%s", pkg_name, err ?? "(no output)");
        return result;
    }

    private async void load_details () {
        try {
            var api = new Data.AltRepoClient ();
            var d = yield api.get_source_details (branch, group.name);

            var vr = (d.version ?? "");
            if (is_nonempty (d.release))
                vr = (vr == "") ? d.release : vr + "-" + d.release;
            this.title = (vr != "") ? @"$(group.name) $(vr)" : group.name;
            header_title.set_title (group.name);
            header_title.set_subtitle ((vr != "" ? vr + " · " : "") + branch);

            hero_group.add (build_hero (group.name, d.summary, d.group));

            clear_group (info_group);

            add_info_row_if_nonempty (_("Version"),    d.version);
            add_info_row_if_nonempty (_("Release"),    d.release);
            if (is_nonempty (d.maintainer)) {
                string nick = d.maintainer;
                var row_m = new Adw.ActionRow () {
                    title = _("Maintainer"),
                    subtitle = GLib.Markup.escape_text (nick, -1),
                    activatable = true
                };
                row_m.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
                row_m.activated.connect (() => win.show_maintainer (nick, branch));
                info_group.add (row_m);
            }
            add_info_row_if_nonempty (_("License"),    d.license);

            if (is_nonempty (d.homepage)) {
                string url = normalize_url (d.homepage ?? "");
                if (url.length > 0) {
                    var row_home = new Adw.ActionRow () {
                        title = _("Homepage"),
                        subtitle = GLib.Markup.escape_text (url, -1),
                        activatable = true
                    };
                    row_home.add_suffix (new Gtk.Image.from_icon_name ("adw-external-link-symbolic"));
                    row_home.activated.connect (() => open_uri (url));
                    info_group.add (row_home);
                }
            }

            add_info_row_if_nonempty (_("Description"), d.description);

            yield populate_binaries (d);

            loading_revealer.reveal_child = false;

            yield load_versions ();
        } catch (Error e) {
            loading_revealer.reveal_child = false;
            warning ("[DetailsPage] load failed: %s", e.message);
            toast (_("Failed to load package details"));
        }

        if (cancel.is_cancelled ()) return;
        yield load_changelog ();

        load_dependencies ();
        load_security ();
        load_downloads ();
        load_specfile ();
    }

    private Adw.ActionRow loading_row () {
        var r = new Adw.ActionRow () { title = _("Loading…") };
        var sp = new Gtk.Spinner () { spinning = true, valign = Gtk.Align.CENTER };
        r.add_prefix (sp);
        return r;
    }

    private async void populate_binaries (Data.PackageDetails d) {
        clear_group (bins_group);

        var by_name = new Gee.HashMap<string, Gee.ArrayList<string>> ();
        foreach (var bp in d.binaries) {
            if (bp == null || bp.name == null) continue;
            var arch = bp.arch ?? "";
            if (arch.strip ().length == 0) continue;
            var list = by_name.get (bp.name);
            if (list == null) { list = new Gee.ArrayList<string> (); by_name.set (bp.name, list); }
            if (!list.contains (arch)) list.add (arch);
        }

        var names = new Gee.ArrayList<string> ();
        foreach (var k in by_name.keys) names.add (k);
        names.sort ((a, b) => strcmp (a, b));

        var sys_branch  = yield pkg_mgr.get_system_branch ();
        bool can_install = yield pkg_mgr.is_system_branch (branch);

        if (sys_branch.length > 0 && !can_install) {
            banner.title = _("Install is available only for the system repository (%s)").printf (sys_branch);
            banner.revealed = true;
        } else {
            banner.revealed = false;
        }

        Gee.HashMap<string, string>? installed = null;
        string repo_evr = "";
        if (can_install) {
            installed = yield pkg_mgr.get_installed_packages ();
            if (is_nonempty (d.version)) {
                repo_evr = "0:" + d.version;
                if (is_nonempty (d.release)) repo_evr += "-" + d.release;
            }
        }

        clear_box (header_actions);
        if (can_install && names.contains (group.name)) {
            var install_hero = new Gtk.Button.with_label (_("Install")) {
                valign = Gtk.Align.CENTER,
                tooltip_text = _("Install via apt-get (requires authentication)")
            };
            install_hero.add_css_class ("suggested-action");

            bool is_installed = installed.has_key (group.name);
            bool needs_update = false;
            if (is_installed && repo_evr.length > 0)
                needs_update = Business.VersionCompare.compare_evr (installed.get (group.name), repo_evr) < 0;

            if (is_installed && !needs_update) {
                mark_installed (install_hero);
            } else {
                string captured_evr = repo_evr;
                bool is_update = needs_update;
                if (is_update) {
                    install_hero.label = _("Update");
                    install_hero.tooltip_text = _("Update via apt-get (requires authentication)");
                }
                install_hero.clicked.connect (() => {
                    install_binary.begin (group.name, install_hero, captured_evr, is_update);
                });
            }
            header_actions.append (install_hero);
        }

        foreach (var name in names) {
            var arches = by_name.get (name);
            var row = new Adw.ActionRow () { title = name };

            var arch_str = "";
            foreach (var a in arches) arch_str = (arch_str == "") ? a : arch_str + ", " + a;
            if (arch_str != "") row.add_suffix (dim_label (arch_str));

            if (can_install) {
                var install_btn = new Gtk.Button.with_label (_("Install")) {
                    valign = Gtk.Align.CENTER,
                    tooltip_text = _("Install via apt-get (requires authentication)")
                };
                install_btn.add_css_class ("suggested-action");

                bool is_installed = installed.has_key (name);
                bool needs_update = false;
                if (is_installed && repo_evr.length > 0)
                    needs_update = Business.VersionCompare.compare_evr (installed.get (name), repo_evr) < 0;

                if (is_installed && !needs_update) {
                    mark_installed (install_btn);
                } else {
                    bool is_update = needs_update;
                    string captured_evr = repo_evr;
                    if (is_update) {
                        install_btn.label = _("Update");
                        install_btn.tooltip_text = _("Update via apt-get (requires authentication)");
                    }
                    install_btn.clicked.connect (() => {
                        install_binary.begin (name, install_btn, captured_evr, is_update);
                    });
                }
                row.add_suffix (install_btn);
            }

            bins_group.add (row);
        }

        if (names.size == 0)
            bins_group.add (new Adw.ActionRow () { title = _("No binary packages") });
    }

    private async void load_changelog () {
        var api = new Data.AltRepoClient ();
        clear_group (changelog_group);
        try {
            var log = yield api.get_changelog (branch, group.name, 50);
            bool any = false;
            foreach (var it in log.changelog) {
                any = true;
                string head = "";
                if (is_nonempty (it.date)) head = it.date;
                if (is_nonempty (it.nick)) head = (head == "") ? it.nick : head + " — " + it.nick;

                string preview = (it.message ?? "").strip ();
                int nl = preview.index_of_char ('\n');
                if (nl >= 0) preview = preview.substring (0, nl);
                if (preview.length > MAX_CHANGE_PREVIEW)
                    preview = preview.substring (0, MAX_CHANGE_PREVIEW) + "…";

                var row = new Adw.ActionRow () {
                    title = (head != "") ? head : _("Change"),
                    subtitle = GLib.Markup.escape_text (preview, -1),
                    activatable = true
                };
                row.set_subtitle_lines (1);
                if (is_nonempty (it.evr)) row.add_suffix (dim_label (it.evr));

                string captured_title = row.title;
                string captured_body  = it.message ?? "";
                row.activated.connect (() => show_text_dialog (captured_title, captured_body));
                changelog_group.add (row);
            }
            if (!any)
                changelog_group.add (new Adw.ActionRow () { title = _("No changes found") });
        } catch (Error ce) {
            warning ("[DetailsPage] changelog failed: %s", ce.message);
            changelog_group.add (new Adw.ActionRow () {
                title = _("Changelog unavailable"),
                subtitle = GLib.Markup.escape_text (ce.message, -1)
            });
        }
    }

    private void load_dependencies () {
        clear_group (deps_group);

        var graph_row = new Adw.ActionRow () {
            title = _("Dependency graph"),
            subtitle = _("Visualize what %s needs and what depends on it").printf (group.name),
            activatable = true
        };
        graph_row.add_prefix (new Gtk.Image.from_icon_name ("application-x-addon-symbolic"));
        var graph_btn = new Gtk.Button.with_label (_("Open graph")) {
            valign = Gtk.Align.CENTER
        };
        graph_btn.add_css_class ("flat");
        graph_row.add_suffix (graph_btn);
        graph_row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
        graph_row.activated.connect (() => win.show_dependency_graph (group.name, branch));
        graph_btn.clicked.connect (() => win.show_dependency_graph (group.name, branch));
        deps_group.add (graph_row);

        var build_exp = new Adw.ExpanderRow () {
            title = _("Build dependencies"),
            subtitle = _("Packages required to build %s").printf (group.name)
        };
        var build_ph = loading_row ();
        build_exp.add_row (build_ph);
        bool build_started = false;
        build_exp.notify["expanded"].connect (() => {
            if (build_started || !build_exp.expanded) return;
            build_started = true;
            fill_build_depends.begin (build_exp, build_ph);
        });
        deps_group.add (build_exp);

        var rev_exp = new Adw.ExpanderRow () {
            title = _("Reverse dependencies"),
            subtitle = _("Source packages that depend on %s").printf (group.name)
        };
        var rev_ph = loading_row ();
        rev_exp.add_row (rev_ph);
        bool rev_started = false;
        rev_exp.notify["expanded"].connect (() => {
            if (rev_started || !rev_exp.expanded) return;
            rev_started = true;
            fill_reverse_depends.begin (rev_exp, rev_ph);
        });
        deps_group.add (rev_exp);
    }

    private async void fill_build_depends (Adw.ExpanderRow exp, Adw.ActionRow placeholder) {
        var api = new Data.AltRepoClient ();
        try {
            var builds = yield api.get_direct_build_depends (branch, group.name);
            if (cancel.is_cancelled ()) return;
            exp.remove (placeholder);
            if (builds == null || builds.size == 0) {
                exp.add_row (new Adw.ActionRow () { title = _("No dependencies found") });
            } else {
                exp.set_subtitle (_("%d packages").printf (builds.size));
                foreach (var d in builds) {
                    var vr = (d.version ?? "");
                    if (is_nonempty (d.release)) vr = (vr == "") ? d.release : vr + "-" + d.release;
                    var r = new Adw.ActionRow () { title = d.name };
                    if (vr != "") r.add_suffix (dim_label (vr));
                    exp.add_row (r);
                }
            }
        } catch (Error e) {
            warning ("[DetailsPage] build deps failed: %s", e.message);
            exp.remove (placeholder);
            exp.add_row (new Adw.ActionRow () {
                title = _("Build dependencies unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
    }

    private async void fill_reverse_depends (Adw.ExpanderRow exp, Adw.ActionRow placeholder) {
        var api = new Data.AltRepoClient ();
        try {
            var revs = yield api.get_reverse_depends (branch, group.name, "both");
            if (cancel.is_cancelled ()) return;
            exp.remove (placeholder);
            if (revs == null || revs.size == 0) {
                exp.add_row (new Adw.ActionRow () { title = _("No reverse dependencies") });
            } else {
                exp.set_subtitle (_("%d packages").printf (revs.size));
                foreach (var d in revs) {
                    var r = new Adw.ActionRow () { title = d.name };
                    if (is_nonempty (d.branch)) r.add_suffix (dim_label (d.branch));
                    exp.add_row (r);
                }
            }
        } catch (Error e) {
            warning ("[DetailsPage] reverse deps failed: %s", e.message);
            exp.remove (placeholder);
            exp.add_row (new Adw.ActionRow () {
                title = _("Reverse dependencies unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
    }

    private void load_security () {
        clear_group (security_group);

        var errata_exp = new Adw.ExpanderRow () { title = _("Security advisories") };
        var errata_ph = loading_row ();
        errata_exp.add_row (errata_ph);
        bool errata_started = false;
        errata_exp.notify["expanded"].connect (() => {
            if (errata_started || !errata_exp.expanded) return;
            errata_started = true;
            fill_errata.begin (errata_exp, errata_ph);
        });
        security_group.add (errata_exp);

        var bugs_exp = new Adw.ExpanderRow () { title = _("Bugzilla") };
        var bugs_ph = loading_row ();
        bugs_exp.add_row (bugs_ph);
        bool bugs_started = false;
        bugs_exp.notify["expanded"].connect (() => {
            if (bugs_started || !bugs_exp.expanded) return;
            bugs_started = true;
            fill_bugs.begin (bugs_exp, bugs_ph);
        });
        security_group.add (bugs_exp);
    }

    private async void fill_errata (Adw.ExpanderRow exp, Adw.ActionRow placeholder) {
        var api = new Data.AltRepoClient ();
        try {
            var erratas = yield api.get_errata_for_package (branch, group.name);
            if (cancel.is_cancelled ()) return;
            exp.remove (placeholder);
            int shown = 0;
            if (erratas != null) {
                foreach (var er in erratas) {
                    var row = make_errata_row (er);
                    if (row != null) { exp.add_row (row); shown++; }
                }
            }
            if (shown == 0)
                exp.add_row (new Adw.ActionRow () { title = _("No security advisories") });
            else
                exp.set_subtitle (_("%d advisories").printf (shown));
        } catch (Error e) {
            warning ("[DetailsPage] errata failed: %s", e.message);
            exp.remove (placeholder);
            exp.add_row (new Adw.ActionRow () {
                title = _("Advisories unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
    }

    private static string date_only (string? iso) {
        if (iso == null) return "";
        int t = iso.index_of ("T");
        return (t > 0) ? iso.substring (0, t) : iso;
    }

    private static bool is_vuln_ref (Data.ErrataRef r) {
        if (!is_nonempty (r.id)) return false;
        if ((r.ref_type ?? "").down () == "bug") return false;
        string idu = r.id.up ();
        if (idu.has_prefix ("CVE") || idu.has_prefix ("BDU") || idu.has_prefix ("GHSA"))
            return true;
        return (r.ref_type ?? "").down () == "vuln";
    }

    private Gtk.Widget? make_errata_row (Data.ErrataInfo er) {
        var seen  = new Gee.HashSet<string> ();
        var vulns = new Gee.ArrayList<Data.ErrataRef> ();
        foreach (var r in er.references) {
            if (!is_vuln_ref (r) || seen.contains (r.id)) continue;
            seen.add (r.id);
            vulns.add (r);
        }
        if (vulns.size == 0) return null;

        int cve = 0, bdu = 0;
        foreach (var r in vulns) {
            string idu = r.id.up ();
            if (idu.has_prefix ("CVE")) cve++;
            else if (idu.has_prefix ("BDU")) bdu++;
        }

        string ver = "";
        if (is_nonempty (er.pkg_version)) {
            ver = er.pkg_version;
            if (is_nonempty (er.pkg_release)) ver += "-" + er.pkg_release;
        }
        string title = (ver != "") ? ver : er.id;

        string sub = date_only (er.created);
        string counts = "";
        if (cve > 0) counts = _("%d CVE").printf (cve);
        if (bdu > 0) counts = (counts == "") ? _("%d BDU").printf (bdu)
                                             : counts + " · " + _("%d BDU").printf (bdu);
        if (counts != "") sub = (sub == "") ? counts : sub + " · " + counts;

        var row = new Adw.ExpanderRow () { title = GLib.Markup.escape_text (title, -1) };
        if (sub != "") row.subtitle = GLib.Markup.escape_text (sub, -1);

        foreach (var r in vulns)
            row.add_row (make_reference_row (r));

        return row;
    }

    private Adw.ActionRow make_reference_row (Data.ErrataRef r) {
        string idu = r.id.up ();
        string? url = null;
        if (idu.has_prefix ("CVE")) {
            url = "https://nvd.nist.gov/vuln/detail/" + r.id;
        } else if (idu.has_prefix ("BDU")) {
            string num = r.id.replace ("BDU:", "").replace ("BDU-", "").strip ();
            url = "https://bdu.fstec.ru/vul/" + num;
        } else if (idu.has_prefix ("GHSA")) {
            url = "https://github.com/advisories/" + r.id;
        }

        var row = new Adw.ActionRow () { title = GLib.Markup.escape_text (r.id, -1) };
        if (url != null) {
            row.activatable = true;
            row.add_suffix (new Gtk.Image.from_icon_name ("adw-external-link-symbolic"));
            string captured = url;
            row.activated.connect (() => open_uri (captured));
        }
        return row;
    }

    private async void fill_bugs (Adw.ExpanderRow exp, Adw.ActionRow placeholder) {
        var api = new Data.AltRepoClient ();
        try {
            var bugs = yield api.get_bugs_by_package (group.name);
            if (cancel.is_cancelled ()) return;
            exp.remove (placeholder);
            if (bugs == null || bugs.size == 0) {
                exp.add_row (new Adw.ActionRow () { title = _("No bugs found") });
            } else {
                exp.set_subtitle (_("%d bug(s) found").printf (bugs.size));
                foreach (var b in bugs) {
                    var row = new Adw.ActionRow () {
                        title = "#" + b.id,
                        subtitle = GLib.Markup.escape_text (b.summary ?? "", -1),
                        activatable = true
                    };
                    row.set_subtitle_lines (2);

                    string st = "";
                    if (is_nonempty (b.severity)) st = b.severity;
                    if (is_nonempty (b.status)) st = (st == "") ? b.status : st + " · " + b.status;
                    if (st != "") row.add_suffix (dim_label (st));

                    string captured_id = b.id;
                    row.activated.connect (() => open_uri ("https://bugzilla.altlinux.org/" + captured_id));
                    exp.add_row (row);
                }
            }
        } catch (Error e) {
            warning ("[DetailsPage] bugs failed: %s", e.message);
            exp.remove (placeholder);
            exp.add_row (new Adw.ActionRow () {
                title = _("Bugzilla unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
    }

    private async void load_versions () {
        var api = new Data.AltRepoClient ();
        clear_group (versions_group);
        selected_branches.clear ();

        compare_btn = new Gtk.Button.with_label (_("Compare selected")) {
            valign = Gtk.Align.CENTER
        };
        compare_btn.add_css_class ("suggested-action");
        compare_btn.sensitive = false;
        compare_btn.clicked.connect (() => {
            if (selected_branches.size != 2) return;
            var picks = new string[2];
            int i = 0;
            foreach (var b in selected_branches) picks[i++] = b;
            show_compare_dialog.begin (picks[0], picks[1]);
        });
        versions_group.set_header_suffix (compare_btn);
        versions_group.set_description (_("Open a repository to view the package there, or tick two to compare"));

        try {
            var vs = yield api.get_package_versions_all (group.name);
            if (vs == null || vs.size == 0) {
                versions_group.add (new Adw.ActionRow () { title = _("No versions found") });
                return;
            }
            foreach (var v in vs) {
                string vr = (v.version ?? "");
                if (is_nonempty (v.release)) vr = (vr == "") ? v.release : vr + "-" + v.release;

                bool is_current = (v.branch == branch);
                var row = new Adw.ActionRow () { title = v.branch };
                if (is_current) row.subtitle = _("current");

                var chk = new Gtk.CheckButton () { valign = Gtk.Align.CENTER };
                string captured_branch = v.branch;
                chk.toggled.connect (() => {
                    if (chk.active) {
                        if (selected_branches.size >= 2) {
                            chk.active = false;
                            toast (_("Only two branches can be compared at a time"));
                            return;
                        }
                        selected_branches.add (captured_branch);
                    } else {
                        selected_branches.remove (captured_branch);
                    }
                    if (compare_btn != null)
                        compare_btn.sensitive = (selected_branches.size == 2);
                });
                row.add_prefix (chk);
                if (vr != "") row.add_suffix (dim_label (vr));

                if (!is_current) {
                    row.activatable = true;
                    string nav_branch = v.branch;
                    string? nav_ver = v.version;
                    string? nav_rel = v.release;
                    row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));
                    row.activated.connect (() => {
                        var g = new Data.SourceGroup (group.name);
                        g.version = nav_ver;
                        g.release = nav_rel;
                        win.show_details (g, nav_branch);
                    });
                }

                versions_group.add (row);
            }
        } catch (Error e) {
            warning ("[DetailsPage] versions failed: %s", e.message);
            versions_group.add (new Adw.ActionRow () {
                title = _("Versions unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
    }

    private string evr_string (string? v, string? r) {
        string s = v ?? "";
        if (is_nonempty (r)) s = (s == "") ? r : s + "-" + r;
        return (s == "") ? "—" : s;
    }

    private async void show_compare_dialog (string branch_a, string branch_b) {
        compare_btn.sensitive = false;
        compare_btn.label = _("Loading…");

        var api = new Data.AltRepoClient ();
        Data.PackageDetails? a = null;
        Data.PackageDetails? b = null;
        try {
            a = yield api.get_source_details (branch_a, group.name);
            b = yield api.get_source_details (branch_b, group.name);
        } catch (Error e) {
            warning ("[DetailsPage] compare failed: %s", e.message);
            toast (_("Compare failed: %s").printf (e.message));
            compare_btn.label = _("Compare selected");
            compare_btn.sensitive = (selected_branches.size == 2);
            return;
        }
        compare_btn.label = _("Compare selected");
        compare_btn.sensitive = (selected_branches.size == 2);

        Data.SpecFileInfo? spec_a = null;
        Data.SpecFileInfo? spec_b = null;
        try { spec_a = yield api.get_specfile (branch_a, group.name); }
        catch (Error e) { warning ("[DetailsPage] compare spec %s failed: %s", branch_a, e.message); }
        try { spec_b = yield api.get_specfile (branch_b, group.name); }
        catch (Error e) { warning ("[DetailsPage] compare spec %s failed: %s", branch_b, e.message); }

        var only_diff = new Gtk.ToggleButton () {
            label = _("Only differences"), active = true, valign = Gtk.Align.CENTER
        };

        var equal_widgets = new Gee.ArrayList<Gtk.Widget> ();

        var page = new Adw.PreferencesPage ();

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

        add_compare_row (meta_grp, equal_widgets, _("Maintainer"), a.maintainer ?? "—", b.maintainer ?? "—");
        add_compare_row (meta_grp, equal_widgets, _("License"), a.license ?? "—", b.license ?? "—");
        add_compare_row (meta_grp, equal_widgets, _("Group"), a.group ?? "—", b.group ?? "—");
        add_compare_row (meta_grp, equal_widgets, _("Summary"), a.summary ?? "—", b.summary ?? "—");
        page.add (meta_grp);

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
        page.add (bins_grp);

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

        only_diff.toggled.connect (() => {
            bool on = only_diff.active;
            foreach (var w in equal_widgets) w.visible = !on;
        });
        foreach (var w in equal_widgets) w.visible = false;

        Adw.HeaderBar hb;
        var dlg = new_dialog (_("Compare %s vs %s").printf (branch_a, branch_b),
                              group.name, 820, 640, page, out hb);
        hb.pack_start (only_diff);
        dlg.present (this.get_root () as Gtk.Window);
    }

    private void add_compare_row (Adw.PreferencesGroup grp, Gee.ArrayList<Gtk.Widget> equal_widgets,
                                  string title, string a, string b) {
        var row = make_compare_text_row (title, a, b);
        grp.add (row);
        if (a == b) equal_widgets.add (row);
    }

    private Adw.ActionRow make_compare_text_row (string title, string a, string b) {
        bool differ = (a != b);
        var row = new Adw.ActionRow () { title = title };
        var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            valign = Gtk.Align.CENTER, hexpand = true
        };
        var la = new Gtk.Label (a) {
            xalign = 0.0f, halign = Gtk.Align.START, hexpand = true,
            wrap = true, wrap_mode = Pango.WrapMode.WORD_CHAR, max_width_chars = 36
        };
        var lb = new Gtk.Label (b) {
            xalign = 0.0f, halign = Gtk.Align.START, hexpand = true,
            wrap = true, wrap_mode = Pango.WrapMode.WORD_CHAR, max_width_chars = 36
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

    private void load_downloads () {
        clear_group (downloads_group);

        var src_exp = new Adw.ExpanderRow () { title = _("Source (.src.rpm)") };
        var src_ph = loading_row ();
        src_exp.add_row (src_ph);
        bool src_started = false;
        src_exp.notify["expanded"].connect (() => {
            if (src_started || !src_exp.expanded) return;
            src_started = true;
            fill_src_downloads.begin (src_exp, src_ph);
        });
        downloads_group.add (src_exp);

        var bin_exp = new Adw.ExpanderRow () { title = _("Binaries (.rpm)") };
        var bin_ph = loading_row ();
        bin_exp.add_row (bin_ph);
        bool bin_started = false;
        bin_exp.notify["expanded"].connect (() => {
            if (bin_started || !bin_exp.expanded) return;
            bin_started = true;
            fill_bin_downloads.begin (bin_exp, bin_ph);
        });
        downloads_group.add (bin_exp);
    }

    private async void fill_src_downloads (Adw.ExpanderRow exp, Adw.ActionRow placeholder) {
        var api = new Data.AltRepoClient ();
        try {
            var src_links = yield api.get_source_downloads (branch, group.name);
            if (cancel.is_cancelled ()) return;
            exp.remove (placeholder);
            if (src_links == null || src_links.size == 0) {
                exp.add_row (new Adw.ActionRow () { title = _("No source downloads") });
            } else {
                foreach (var d in src_links) add_download_row (exp, d);
            }
        } catch (Error e) {
            warning ("[DetailsPage] src downloads failed: %s", e.message);
            exp.remove (placeholder);
            exp.add_row (new Adw.ActionRow () {
                title = _("Source downloads unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
    }

    private async void fill_bin_downloads (Adw.ExpanderRow exp, Adw.ActionRow placeholder) {
        var api = new Data.AltRepoClient ();
        try {
            var bin_links = yield api.get_binary_downloads (branch, group.name);
            if (cancel.is_cancelled ()) return;
            exp.remove (placeholder);
            if (bin_links == null || bin_links.size == 0) {
                exp.add_row (new Adw.ActionRow () { title = _("No binary downloads") });
            } else {
                foreach (var d in bin_links) add_download_row (exp, d);
            }
        } catch (Error e) {
            warning ("[DetailsPage] bin downloads failed: %s", e.message);
            exp.remove (placeholder);
            exp.add_row (new Adw.ActionRow () {
                title = _("Binary downloads unavailable"),
                subtitle = GLib.Markup.escape_text (e.message, -1)
            });
        }
    }

    private void add_download_row (Adw.ExpanderRow exp, Data.DownloadLink d) {
        var row = new Adw.ActionRow () { title = d.name, activatable = true };

        string meta = "";
        if (is_nonempty (d.arch)) meta = d.arch;
        if (is_nonempty (d.size)) meta = (meta == "") ? d.size : meta + " · " + d.size;
        if (meta != "") row.add_suffix (dim_label (meta));

        if (is_nonempty (d.url)) {
            string captured_url = d.url;
            row.activated.connect (() => open_uri (captured_url));
            var copy_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic") {
                valign = Gtk.Align.CENTER, tooltip_text = _("Copy download URL")
            };
            copy_btn.add_css_class ("flat");
            copy_btn.clicked.connect (() => copy_to_clipboard (captured_url));
            row.add_suffix (copy_btn);
        }
        exp.add_row (row);
    }

    private void load_specfile () {
        clear_group (spec_group);

        var row = new Adw.ActionRow () { title = _("Spec file"), activatable = true };
        var open_btn = new Gtk.Button.with_label (_("Open")) { valign = Gtk.Align.CENTER };
        open_btn.add_css_class ("flat");
        row.add_suffix (open_btn);

        open_btn.clicked.connect (() => open_specfile.begin (open_btn));
        row.activated.connect (() => open_specfile.begin (open_btn));
        spec_group.add (row);
    }

    private async void open_specfile (Gtk.Button btn) {
        if (!btn.sensitive) return;
        btn.sensitive = false;
        string orig = btn.label;
        btn.label = _("Loading…");

        var api = new Data.AltRepoClient ();
        try {
            var spec = yield api.get_specfile (branch, group.name);
            btn.label = orig;
            btn.sensitive = true;
            if (spec == null || !is_nonempty (spec.content)) {
                toast (_("Spec file not available"));
                return;
            }
            string fname = is_nonempty (spec.name) ? spec.name : group.name + ".spec";
            show_text_dialog (fname, spec.content);
        } catch (Error e) {
            warning ("[DetailsPage] specfile failed: %s", e.message);
            btn.label = orig;
            btn.sensitive = true;
            toast (_("Spec file unavailable"));
        }
    }
}
