using Gtk;
using Adw;
using GLib;
using Intl;

public class DependencyGraphPage : Adw.NavigationPage {

    private class GNode : GLib.Object {
        public string  name;
        public string? evr;
        public string  branch;
        public int     column;
        public int     parent;
        public bool    is_center;
        public bool    expandable;
        public bool    expanded;
        public bool    loading;
        public double  gx;
        public double  gy;
        public double  w;
        public double  h;
    }

    private const double COL_W   = 210.0;
    private const double ROW_H   = 70.0;
    private const double NODE_PAD = 14.0;
    private const double MARGIN  = 48.0;
    private const double MIN_SCALE = 0.4;
    private const double MAX_SCALE = 2.4;

    private MainWindow win;
    private string root_name;
    private string branch;

    private Gee.ArrayList<GNode> nodes = new Gee.ArrayList<GNode> ();
    private Gee.HashSet<string>  present = new Gee.HashSet<string> ();

    private Adw.ViewStack   stack;
    private Gtk.DrawingArea canvas;
    private Gtk.ToggleButton tb_reverse;
    private Gtk.ToggleButton tb_build;

    private double scale    = 1.0;
    private double offset_x = 0.0;
    private double offset_y = 0.0;
    private double drag_ox  = 0.0;
    private double drag_oy  = 0.0;
    private bool   show_build   = true;
    private bool   show_reverse = true;

    private GLib.Cancellable cancel = new GLib.Cancellable ();

    public DependencyGraphPage (MainWindow win, string pkg_name, string branch) {
        this.win       = win;
        this.root_name = pkg_name;
        this.branch    = branch;
        this.title     = _("Dependency graph");

        build_ui ();
        this.hidden.connect (() => {
            if (!cancel.is_cancelled ()) cancel.cancel ();
        });
        load_root.begin ();
    }

    private static bool is_nonempty (string? s) {
        return s != null && s.strip ().length > 0;
    }

    private void build_ui () {
        var header_bar = new Adw.HeaderBar ();
        header_bar.set_title_widget (new Adw.WindowTitle (_("Dependency graph"), root_name + " · " + branch));

        tb_reverse = new Gtk.ToggleButton () {
            icon_name = "go-previous-symbolic",
            active = true, tooltip_text = _("Show packages that depend on it")
        };
        tb_build = new Gtk.ToggleButton () {
            icon_name = "go-next-symbolic",
            active = true, tooltip_text = _("Show build dependencies")
        };
        tb_reverse.toggled.connect (() => { show_reverse = tb_reverse.active; relayout (); fit_to_content (); });
        tb_build.toggled.connect (() => { show_build = tb_build.active; relayout (); fit_to_content (); });

        var sides = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        sides.add_css_class ("linked");
        sides.append (tb_reverse);
        sides.append (tb_build);
        header_bar.pack_start (sides);

        var fit_btn = new Gtk.Button.with_label (_("Fit"));
        fit_btn.add_css_class ("flat");
        fit_btn.clicked.connect (() => fit_to_content ());

        var zoom_out = new Gtk.Button () { icon_name = "zoom-out-symbolic" };
        var zoom_in  = new Gtk.Button () { icon_name = "zoom-in-symbolic" };
        zoom_out.clicked.connect (() => zoom_by (1.0 / 1.2));
        zoom_in.clicked.connect (() => zoom_by (1.2));
        var zoom_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        zoom_box.add_css_class ("linked");
        zoom_box.append (zoom_out);
        zoom_box.append (zoom_in);

        header_bar.pack_end (zoom_box);
        header_bar.pack_end (fit_btn);

        stack = new Adw.ViewStack () { vexpand = true, hexpand = true };

        var spinner = new Gtk.Spinner () {
            spinning = true, width_request = 42, height_request = 42,
            halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER
        };
        stack.add_named (spinner, "loading");

        canvas = new Gtk.DrawingArea () { hexpand = true, vexpand = true };
        canvas.set_draw_func (draw);

        var click = new Gtk.GestureClick ();
        click.released.connect (on_click);
        canvas.add_controller (click);

        var drag = new Gtk.GestureDrag ();
        drag.drag_begin.connect (() => { drag_ox = offset_x; drag_oy = offset_y; });
        drag.drag_update.connect ((g, dx, dy) => {
            offset_x = drag_ox + dx;
            offset_y = drag_oy + dy;
            canvas.queue_draw ();
        });
        canvas.add_controller (drag);

        var scroll = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL);
        scroll.scroll.connect ((c, dx, dy) => {
            zoom_by (dy < 0 ? 1.1 : 1.0 / 1.1);
            return true;
        });
        canvas.add_controller (scroll);

        stack.add_named (canvas, "graph");

        var empty = new Adw.StatusPage () {
            icon_name = "application-x-addon-symbolic",
            title = _("No dependency data"),
            description = _("Could not build a graph for %s.").printf (root_name)
        };
        stack.add_named (empty, "empty");

        stack.set_visible_child_name ("loading");

        var tv = new Adw.ToolbarView ();
        tv.add_top_bar (header_bar);
        tv.set_content (stack);
        this.set_child (tv);
    }

    private void zoom_by (double factor) {
        scale = (scale * factor).clamp (MIN_SCALE, MAX_SCALE);
        canvas.queue_draw ();
    }

    private async void load_root () {
        var api = new Data.AltRepoClient ();

        var center = new GNode ();
        center.name      = root_name;
        center.branch    = branch;
        center.column    = 0;
        center.parent    = -1;
        center.is_center = true;
        nodes.add (center);
        present.add (root_name);

        bool got_any = false;

        try {
            var builds = yield api.get_build_depends (branch, root_name, "x86_64", cancel);
            if (cancel.is_cancelled ()) return;
            if (builds != null) {
                foreach (var d in builds) {
                    if (add_child (d.name, evr_of (d.version, d.release), d.branch ?? branch, 1, 0))
                        got_any = true;
                }
            }
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[GraphPage] build deps failed: %s", e.message);
        }

        try {
            var revs = yield api.get_reverse_depends (branch, root_name, "both", cancel);
            if (cancel.is_cancelled ()) return;
            if (revs != null) {
                foreach (var d in revs) {
                    if (add_child (d.name, null, d.branch ?? branch, -1, 0))
                        got_any = true;
                }
            }
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[GraphPage] reverse deps failed: %s", e.message);
        }

        if (!got_any) {
            stack.set_visible_child_name ("empty");
            return;
        }

        stack.set_visible_child_name ("graph");
        relayout ();
        fit_to_content ();
    }

    private static string? evr_of (string? v, string? r) {
        if (!is_nonempty (v)) return null;
        return is_nonempty (r) ? v + "-" + r : v;
    }

    private bool add_child (string? name, string? evr, string br, int direction, int parent_idx) {
        if (!is_nonempty (name) || present.contains (name)) return false;
        var n = new GNode ();
        n.name       = name;
        n.evr        = evr;
        n.branch     = br;
        n.column     = nodes.get (parent_idx).column + direction;
        n.parent     = parent_idx;
        n.expandable = true;
        nodes.add (n);
        present.add (name);
        return true;
    }

    private void relayout () {
        var by_col = new Gee.HashMap<int, Gee.ArrayList<GNode>> ();
        foreach (var n in nodes) {
            if (!node_visible (n)) continue;
            measure_node (n);
            if (!by_col.has_key (n.column)) by_col.set (n.column, new Gee.ArrayList<GNode> ());
            by_col.get (n.column).add (n);
        }
        foreach (var col in by_col.keys) {
            var list = by_col.get (col);
            int cnt = list.size;
            for (int i = 0; i < cnt; i++) {
                var n = list.get (i);
                n.gx = col * COL_W;
                n.gy = (i - (cnt - 1) / 2.0) * ROW_H;
            }
        }
        canvas.queue_draw ();
    }

    private bool node_visible (GNode n) {
        if (n.is_center) return true;
        if (n.column > 0) return show_build;
        if (n.column < 0) return show_reverse;
        return true;
    }

    private void measure_node (GNode n) {
        var layout = new Pango.Layout (canvas.get_pango_context ());
        layout.set_text (n.name, -1);
        int tw, th;
        layout.get_pixel_size (out tw, out th);
        n.w = double.max (118.0, tw + 2 * NODE_PAD + (n.expandable && !n.expanded ? 16.0 : 0.0));
        n.h = is_nonempty (n.evr) ? 52.0 : 40.0;
    }

    private void node_screen (GNode n, int width, int height, out double cx, out double cy) {
        cx = width  / 2.0 + offset_x + n.gx * scale;
        cy = height / 2.0 + offset_y + n.gy * scale;
    }

    private void draw (Gtk.DrawingArea da, Cairo.Context cr, int width, int height) {
        Gdk.RGBA fg     = lookup ("window_fg_color",  0.18, 0.20, 0.21, 1.0);
        Gdk.RGBA accent = lookup ("accent_bg_color",  0.21, 0.52, 0.89, 1.0);
        Gdk.RGBA acc_fg = lookup ("accent_fg_color",  1.0,  1.0,  1.0,  1.0);
        Gdk.RGBA card   = lookup ("card_bg_color",    1.0,  1.0,  1.0,  1.0);
        Gdk.RGBA build  = lookup ("success_color",    0.18, 0.76, 0.49, 1.0);
        Gdk.RGBA reverse = { 0.75f, 0.38f, 0.80f, 1.0f };

        foreach (var n in nodes) {
            if (n.is_center || !node_visible (n)) continue;
            if (n.parent < 0) continue;
            var p = nodes.get (n.parent);
            if (!node_visible (p)) continue;
            double px, py, nx, ny;
            node_screen (p, width, height, out px, out py);
            node_screen (n, width, height, out nx, out ny);
            var col = (n.column > 0) ? build : reverse;
            cr.set_source_rgba (col.red, col.green, col.blue, 0.55);
            cr.set_line_width (2.0);
            double mx = (px + nx) / 2.0;
            cr.move_to (px, py);
            cr.curve_to (mx, py, mx, ny, nx, ny);
            cr.stroke ();
        }

        foreach (var n in nodes) {
            if (!node_visible (n)) continue;
            double cx, cy;
            node_screen (n, width, height, out cx, out cy);
            draw_node (cr, n, cx, cy, fg, accent, acc_fg, card, build, reverse);
        }
    }

    private void draw_node (Cairo.Context cr, GNode n, double cx, double cy,
                            Gdk.RGBA fg, Gdk.RGBA accent, Gdk.RGBA acc_fg,
                            Gdk.RGBA card, Gdk.RGBA build, Gdk.RGBA reverse) {
        double w = n.w, h = n.h;
        double x = cx - w / 2.0, y = cy - h / 2.0;
        double r = 12.0;

        rounded_rect (cr, x, y, w, h, r);
        if (n.is_center) {
            cr.set_source_rgba (accent.red, accent.green, accent.blue, 0.14);
        } else {
            cr.set_source_rgba (card.red, card.green, card.blue, 1.0);
        }
        cr.fill_preserve ();

        if (n.is_center) {
            cr.set_source_rgba (accent.red, accent.green, accent.blue, 1.0);
            cr.set_line_width (2.0);
        } else {
            var edge = (n.column > 0) ? build : reverse;
            cr.set_source_rgba (edge.red, edge.green, edge.blue, 0.55);
            cr.set_line_width (1.0);
        }
        cr.stroke ();

        if (!n.is_center) {
            var dot = (n.column > 0) ? build : reverse;
            cr.set_source_rgba (dot.red, dot.green, dot.blue, 1.0);
            cr.arc (x + 12.0, y + h / 2.0, 4.0, 0, 2 * Math.PI);
            cr.fill ();
        }

        double text_x = x + (n.is_center ? NODE_PAD : NODE_PAD + 10.0);
        var name_layout = new Pango.Layout (canvas.get_pango_context ());
        name_layout.set_text (n.name, -1);
        var fd = canvas.get_pango_context ().get_font_description ().copy ();
        fd.set_weight (Pango.Weight.BOLD);
        name_layout.set_font_description (fd);
        int nw, nh;
        name_layout.get_pixel_size (out nw, out nh);

        if (n.is_center)
            cr.set_source_rgba (accent.red, accent.green, accent.blue, 1.0);
        else
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 1.0);

        double name_y = is_nonempty (n.evr) ? y + 8.0 : cy - nh / 2.0;
        cr.move_to (text_x, name_y);
        Pango.cairo_show_layout (cr, name_layout);

        if (is_nonempty (n.evr)) {
            var ev = new Pango.Layout (canvas.get_pango_context ());
            ev.set_text (n.evr, -1);
            var sfd = canvas.get_pango_context ().get_font_description ().copy ();
            sfd.set_size ((int) (sfd.get_size () * 0.82));
            ev.set_font_description (sfd);
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.55);
            cr.move_to (text_x, name_y + nh + 2.0);
            Pango.cairo_show_layout (cr, ev);
        }

        if (n.expandable && !n.expanded) {
            double bx = x + w - 16.0, by = cy;
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.10);
            cr.arc (bx, by, 9.0, 0, 2 * Math.PI);
            cr.fill ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.75);
            cr.set_line_width (1.6);
            if (n.loading) {
                cr.arc (bx, by, 5.0, 0, 1.4 * Math.PI);
                cr.stroke ();
            } else {
                cr.move_to (bx - 4.0, by); cr.line_to (bx + 4.0, by);
                cr.move_to (bx, by - 4.0); cr.line_to (bx, by + 4.0);
                cr.stroke ();
            }
        }
    }

    private static void rounded_rect (Cairo.Context cr, double x, double y, double w, double h, double r) {
        cr.new_sub_path ();
        cr.arc (x + w - r, y + r,     r, -0.5 * Math.PI, 0);
        cr.arc (x + w - r, y + h - r, r, 0,              0.5 * Math.PI);
        cr.arc (x + r,     y + h - r, r, 0.5 * Math.PI,  Math.PI);
        cr.arc (x + r,     y + r,     r, Math.PI,        1.5 * Math.PI);
        cr.close_path ();
    }

    private Gdk.RGBA lookup (string name, double r, double g, double b, double a) {
        Gdk.RGBA c = { (float) r, (float) g, (float) b, (float) a };
        var ctx = canvas.get_style_context ();
        Gdk.RGBA found;
        if (ctx.lookup_color (name, out found)) return found;
        return c;
    }

    private void on_click (Gtk.GestureClick g, int n_press, double px, double py) {
        int width  = canvas.get_width ();
        int height = canvas.get_height ();
        for (int i = nodes.size - 1; i >= 0; i--) {
            var n = nodes.get (i);
            if (!node_visible (n)) continue;
            double cx, cy;
            node_screen (n, width, height, out cx, out cy);
            double x = cx - n.w / 2.0, y = cy - n.h / 2.0;
            if (px < x || px > x + n.w || py < y || py > y + n.h) continue;

            if (n.expandable && !n.expanded && !n.loading) {
                double bx = x + n.w - 16.0;
                if (px >= bx - 11.0 && py >= cy - 11.0 && py <= cy + 11.0) {
                    expand_node.begin (i);
                    return;
                }
            }
            win.show_details (new Data.SourceGroup (n.name), n.branch);
            return;
        }
    }

    private async void expand_node (int idx) {
        var n = nodes.get (idx);
        if (n.expanded || n.loading) return;
        n.loading = true;
        canvas.queue_draw ();

        int direction = (n.column >= 0) ? 1 : -1;
        var api = new Data.AltRepoClient ();
        bool added = false;
        try {
            if (direction > 0) {
                var builds = yield api.get_build_depends (n.branch, n.name, "x86_64", cancel);
                if (cancel.is_cancelled ()) return;
                if (builds != null)
                    foreach (var d in builds)
                        if (add_child (d.name, evr_of (d.version, d.release), d.branch ?? n.branch, 1, idx))
                            added = true;
            } else {
                var revs = yield api.get_reverse_depends (n.branch, n.name, "both", cancel);
                if (cancel.is_cancelled ()) return;
                if (revs != null)
                    foreach (var d in revs)
                        if (add_child (d.name, null, d.branch ?? n.branch, -1, idx))
                            added = true;
            }
        } catch (Error e) {
            if (cancel.is_cancelled ()) return;
            warning ("[GraphPage] expand failed: %s", e.message);
        }

        n.loading = false;
        n.expanded = true;
        if (!added) n.expandable = false;
        relayout ();
    }

    private void fit_to_content () {
        int width  = canvas.get_width ();
        int height = canvas.get_height ();
        if (width <= 0 || height <= 0) return;

        bool any = false;
        double min_x = 0, max_x = 0, min_y = 0, max_y = 0;
        foreach (var n in nodes) {
            if (!node_visible (n)) continue;
            if (!any) { min_x = max_x = n.gx; min_y = max_y = n.gy; any = true; }
            min_x = double.min (min_x, n.gx); max_x = double.max (max_x, n.gx);
            min_y = double.min (min_y, n.gy); max_y = double.max (max_y, n.gy);
        }
        if (!any) return;

        double span_x = double.max (1.0, max_x - min_x);
        double span_y = double.max (1.0, max_y - min_y);
        double avail_w = width  - 2 * MARGIN - COL_W;
        double avail_h = height - 2 * MARGIN - ROW_H;
        double s = double.min (avail_w / span_x, avail_h / span_y);
        scale = s.clamp (MIN_SCALE, 1.0);

        double mid_x = (min_x + max_x) / 2.0;
        double mid_y = (min_y + max_y) / 2.0;
        offset_x = -mid_x * scale;
        offset_y = -mid_y * scale;
        canvas.queue_draw ();
    }
}
