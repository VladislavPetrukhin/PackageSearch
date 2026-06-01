using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/dependency_graph_page.ui")]
public class DependencyGraphPage : Adw.NavigationPage {

    private enum Mode { BUILD, REVERSE }

    private class GNode : GLib.Object {
        public string  name;
        public string  branch;
        public int     depth;
        public bool    is_root;
        public bool    is_more;
        public bool    expandable;
        public bool    expanded;
        public bool    loading;
        public bool    virtual;
        public bool    probed;
        public Gee.ArrayList<Data.DependencyPackage>? cached_children;
        public Gee.ArrayList<GNode> parents = new Gee.ArrayList<GNode> ();
        public GNode?   more_parent;
        public Gee.ArrayList<Data.DependencyPackage> pending = new Gee.ArrayList<Data.DependencyPackage> ();
        public double  gx;
        public double  gy;
        public double  w;
        public double  h;
    }

    private const double COL_W      = 215.0;
    private const double ROW_H      = 50.0;
    private const double NODE_H     = 34.0;
    private const double NODE_MINW  = 110.0;
    private const double NODE_MAXW  = 210.0;
    private const double MARGIN     = 60.0;
    private const double MIN_SCALE  = 0.25;
    private const double MAX_SCALE  = 2.2;
    private const int    CHILD_LIMIT = 14;

    private MainWindow win;
    private string root_name;
    private string branch;
    private Mode   mode = Mode.BUILD;

    private Gee.ArrayList<GNode>           nodes   = new Gee.ArrayList<GNode> ();
    private Gee.HashMap<string, GNode>     present = new Gee.HashMap<string, GNode> ();

    [GtkChild] private unowned Adw.WindowTitle  title_widget;
    [GtkChild] private unowned Adw.ViewStack    stack;
    [GtkChild] private unowned Gtk.DrawingArea  canvas;
    [GtkChild] private unowned Gtk.ToggleButton mode_build;
    [GtkChild] private unowned Gtk.ToggleButton mode_reverse;
    [GtkChild] private unowned Gtk.Button       zoom_out;
    [GtkChild] private unowned Gtk.Button       zoom_in;
    [GtkChild] private unowned Gtk.Button       fit_btn;
    [GtkChild] private unowned Adw.StatusPage   empty_status;

    private double scale    = 1.0;
    private double offset_x = 0.0;
    private double offset_y = 0.0;
    private double drag_ox  = 0.0;
    private double drag_oy  = 0.0;
    private bool   fitted   = false;
    private int    generation = 0;

    private Gee.ArrayList<GNode> probe_queue = new Gee.ArrayList<GNode> ();
    private bool probing = false;

    private GLib.Cancellable cancel = new GLib.Cancellable ();

    public DependencyGraphPage (MainWindow win, string pkg_name, string branch) {
        this.win       = win;
        this.root_name = pkg_name;
        this.branch    = branch;
        this.title     = _("Dependency graph");

        wire_ui ();
        this.hidden.connect (() => {
            if (!cancel.is_cancelled ()) cancel.cancel ();
        });
        load_root.begin ();
    }

    private void wire_ui () {
        title_widget.title = _("Dependency graph");
        title_widget.subtitle = root_name + " · " + branch;
        empty_status.description = _("Could not build a graph for %s.").printf (root_name);

        mode_build.toggled.connect (() => {
            if (mode_build.active && mode != Mode.BUILD) { mode = Mode.BUILD; reset_and_load (); }
        });
        mode_reverse.toggled.connect (() => {
            if (mode_reverse.active && mode != Mode.REVERSE) { mode = Mode.REVERSE; reset_and_load (); }
        });

        fit_btn.clicked.connect (() => { fit_to_content (); });
        zoom_out.clicked.connect (() => zoom_by (1.0 / 1.2));
        zoom_in.clicked.connect (() => zoom_by (1.2));

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

        stack.set_visible_child_name ("loading");
    }

    private void zoom_by (double factor) {
        scale = (scale * factor).clamp (MIN_SCALE, MAX_SCALE);
        canvas.queue_draw ();
    }

    private void reset_and_load () {
        generation++;
        nodes.clear ();
        present.clear ();
        probe_queue.clear ();
        fitted = false;
        stack.set_visible_child_name ("loading");
        load_root.begin ();
    }

    private async void load_root () {
        int g = generation;
        var root = new GNode ();
        root.name    = root_name;
        root.branch  = branch;
        root.depth   = 0;
        root.is_root = true;
        nodes.add (root);
        present.set (root_name, root);

        yield expand_into (root);
        if (g != generation) return;

        if (nodes.size <= 1) {
            stack.set_visible_child_name ("empty");
            return;
        }
        stack.set_visible_child_name ("graph");
        fitted = false;
        relayout ();
    }

    private async Gee.ArrayList<Data.DependencyPackage> fetch_deps (GNode n) {
        var api = new Data.AltRepoClient ();
        try {
            Gee.ArrayList<Data.DependencyPackage>? r;
            if (mode == Mode.BUILD)
                r = yield api.get_direct_build_depends (branch, n.name, cancel);
            else
                r = yield api.get_reverse_depends (branch, n.name, "both", cancel);
            return r ?? new Gee.ArrayList<Data.DependencyPackage> ();
        } catch (Error e) {
            if (!cancel.is_cancelled ())
                warning ("[GraphPage] deps %s failed: %s", n.name, e.message);
            return new Gee.ArrayList<Data.DependencyPackage> ();
        }
    }

    private async void expand_into (GNode n) {
        int g = generation;
        Gee.ArrayList<Data.DependencyPackage> kids;
        if (n.probed && n.cached_children != null) {
            kids = n.cached_children;
        } else {
            n.loading = true;
            canvas.queue_draw ();
            kids = yield fetch_deps (n);
            n.loading = false;
            if (cancel.is_cancelled () || g != generation) return;
            n.probed = true;
            n.cached_children = kids;
        }

        n.expanded = true;
        materialize (n, kids);
        relayout ();
    }

    private void materialize (GNode n, Gee.ArrayList<Data.DependencyPackage> kids) {
        int shown = 0;
        var overflow = new Gee.ArrayList<Data.DependencyPackage> ();
        foreach (var d in kids) {
            if (!Ui.is_nonempty (d.name)) continue;
            if (shown < CHILD_LIMIT) {
                add_child (n, d.name, d.branch ?? branch);
                shown++;
            } else {
                overflow.add (d);
            }
        }
        if (overflow.size > 0) {
            var more = new GNode ();
            more.is_more = true;
            more.depth = n.depth + 1;
            more.more_parent = n;
            more.pending = overflow;
            nodes.add (more);
        }
    }

    private void add_child (GNode parent, string name, string br) {
        if (present.has_key (name)) {
            var existing = present.get (name);
            if (existing != parent && !existing.parents.contains (parent))
                existing.parents.add (parent);
            return;
        }
        var n = new GNode ();
        n.name       = name;
        n.branch     = br;
        n.depth      = parent.depth + 1;
        n.virtual    = !Data.Validation.is_valid_package_name (name);
        n.expandable = false;
        n.parents.add (parent);
        nodes.add (n);
        present.set (name, n);
        enqueue_probe (n);
    }

    private void enqueue_probe (GNode n) {
        if (n.is_root || n.is_more || n.virtual || n.probed) return;
        probe_queue.add (n);
        if (!probing) run_probe.begin ();
    }

    private async void run_probe () {
        probing = true;
        while (probe_queue.size > 0) {
            if (cancel.is_cancelled ()) break;
            var n = probe_queue.remove_at (0);
            if (n.probed || n.expanded || n.loading) continue;
            int g = generation;
            var kids = yield fetch_deps (n);
            if (cancel.is_cancelled () || g != generation) break;
            n.cached_children = kids;
            n.probed = true;
            n.expandable = has_real_children (kids);
            canvas.queue_draw ();
        }
        probing = false;
    }

    private static bool has_real_children (Gee.ArrayList<Data.DependencyPackage> kids) {
        foreach (var d in kids)
            if (Ui.is_nonempty (d.name)) return true;
        return false;
    }

    private void reveal_more (GNode more) {
        foreach (var d in more.pending) {
            if (Ui.is_nonempty (d.name))
                add_child (more.more_parent, d.name, d.branch ?? branch);
        }
        nodes.remove (more);
        relayout ();
    }

    private void relayout () {
        var by_depth = new Gee.HashMap<int, Gee.ArrayList<GNode>> ();
        int max_depth = 0;
        foreach (var n in nodes) {
            measure_node (n);
            if (!by_depth.has_key (n.depth)) by_depth.set (n.depth, new Gee.ArrayList<GNode> ());
            by_depth.get (n.depth).add (n);
            if (n.depth > max_depth) max_depth = n.depth;
        }

        for (int depth = 0; depth <= max_depth; depth++) {
            if (!by_depth.has_key (depth)) continue;
            var list = by_depth.get (depth);

            foreach (var n in list) {
                n.gx = depth * COL_W;
                if (depth == 0) { n.gy = 0; continue; }
                double sum = 0; int cnt = 0;
                foreach (var p in n.parents) { sum += p.gy; cnt++; }
                if (n.is_more && n.more_parent != null) { sum += n.more_parent.gy; cnt++; }
                n.gy = (cnt > 0) ? sum / cnt : 0;
            }

            list.sort ((a, b) => {
                if (a.gy < b.gy) return -1;
                if (a.gy > b.gy) return 1;
                return 0;
            });

            int cnt2 = list.size;
            double center = 0;
            foreach (var n in list) center += n.gy;
            center = (cnt2 > 0) ? center / cnt2 : 0;
            double start = center - (cnt2 - 1) * ROW_H / 2.0;
            for (int i = 0; i < cnt2; i++)
                list.get (i).gy = start + i * ROW_H;
        }
        canvas.queue_draw ();
    }

    private void measure_node (GNode n) {
        if (n.is_more) {
            var l = new Pango.Layout (canvas.get_pango_context ());
            l.set_text (more_label (n), -1);
            int tw, th;
            l.get_pixel_size (out tw, out th);
            n.w = tw + 28;
            n.h = 28;
            return;
        }
        var layout = new Pango.Layout (canvas.get_pango_context ());
        layout.set_text (n.name, -1);
        int tw2, th2;
        layout.get_pixel_size (out tw2, out th2);
        double extras = (n.is_root ? 28.0 : 40.0)
                      + (!n.is_root && n.expandable && !n.expanded ? 22.0 : 0.0)
                      + (n.parents.size >= 2 ? 26.0 : 0.0);
        n.w = (tw2 + extras).clamp (NODE_MINW, NODE_MAXW);
        n.h = NODE_H;
    }

    private static string more_label (GNode n) {
        return _("show %d more").printf (n.pending.size) + "  →";
    }

    private struct Palette {
        Gdk.RGBA text; Gdk.RGBA dim; Gdk.RGBA card; Gdk.RGBA brd;
        Gdk.RGBA accent; Gdk.RGBA accent_brd; Gdk.RGBA edge;
    }

    private static Gdk.RGBA rgb (double r, double g, double b, double a = 1.0) {
        return { (float) r, (float) g, (float) b, (float) a };
    }

    private Palette palette () {
        bool dark = Adw.StyleManager.get_default ().dark;
        var p = Palette ();
        if (dark) {
            p.text       = rgb (0.95, 0.95, 0.96);
            p.dim        = rgb (0.95, 0.95, 0.96, 0.55);
            p.card       = rgb (0.21, 0.21, 0.23);
            p.brd        = rgb (0.40, 0.40, 0.44);
            p.accent     = rgb (0.47, 0.68, 1.0);
            p.accent_brd = rgb (0.21, 0.52, 0.89);
        } else {
            p.text       = rgb (0.12, 0.12, 0.13);
            p.dim        = rgb (0.12, 0.12, 0.13, 0.55);
            p.card       = rgb (1.0, 1.0, 1.0);
            p.brd        = rgb (0.82, 0.82, 0.84);
            p.accent     = rgb (0.11, 0.44, 0.85);
            p.accent_brd = rgb (0.21, 0.52, 0.89);
        }
        p.edge = (mode == Mode.BUILD)
            ? rgb (0.16, 0.74, 0.46) : rgb (0.76, 0.45, 0.82);
        return p;
    }

    private void draw (Gtk.DrawingArea da, Cairo.Context cr, int width, int height) {
        if (!fitted && width > 0 && height > 0 && nodes.size > 1) {
            fit_to_content_in (width, height);
            fitted = true;
        }

        var p = palette ();

        cr.save ();
        cr.translate (width / 2.0 + offset_x, height / 2.0 + offset_y);
        cr.scale (scale, scale);

        foreach (var n in nodes) {
            if (n.is_root) continue;
            cr.set_source_rgba (p.edge.red, p.edge.green, p.edge.blue, 0.5);
            if (n.is_more && n.more_parent != null) {
                draw_edge (cr, n.more_parent, n);
            } else {
                foreach (var par in n.parents) {
                    bool hub = n.parents.size >= 2;
                    cr.set_line_width (hub ? 2.0 : 1.4);
                    cr.set_source_rgba (p.edge.red, p.edge.green, p.edge.blue, hub ? 0.8 : 0.45);
                    draw_edge (cr, par, n);
                }
            }
        }

        foreach (var n in nodes) {
            if (n.is_more) draw_more (cr, n, p);
            else draw_node (cr, n, p);
        }

        cr.restore ();
    }

    private void draw_edge (Cairo.Context cr, GNode from, GNode to) {
        double x1 = from.gx + from.w / 2.0, y1 = from.gy;
        double x2 = to.gx - to.w / 2.0,     y2 = to.gy;
        double mx = (x1 + x2) / 2.0;
        cr.move_to (x1, y1);
        cr.curve_to (mx, y1, mx, y2, x2, y2);
        cr.stroke ();
    }

    private void draw_node (Cairo.Context cr, GNode n, Palette p) {
        bool hub = n.parents.size >= 2;
        double x = n.gx - n.w / 2.0, y = n.gy - n.h / 2.0;

        rounded_rect (cr, x, y, n.w, n.h, 9.0);
        if (n.is_root || hub)
            cr.set_source_rgba (p.accent_brd.red, p.accent_brd.green, p.accent_brd.blue, 0.16);
        else
            cr.set_source_rgba (p.card.red, p.card.green, p.card.blue, 1.0);
        cr.fill_preserve ();

        if (n.is_root || hub) {
            cr.set_source_rgba (p.accent_brd.red, p.accent_brd.green, p.accent_brd.blue, 1.0);
            cr.set_line_width (2.0);
        } else {
            cr.set_source_rgba (p.brd.red, p.brd.green, p.brd.blue, 1.0);
            cr.set_line_width (1.0);
        }
        cr.stroke ();

        double tx = x + 12.0;
        if (!n.is_root && !n.virtual) {
            cr.set_source_rgba (p.edge.red, p.edge.green, p.edge.blue, 1.0);
            cr.arc (x + 11.0, n.gy, 3.5, 0, 2 * Math.PI);
            cr.fill ();
            tx = x + 22.0;
        }

        double right_reserve = 10.0
            + (!n.is_root && n.expandable && !n.expanded ? 20.0 : 0.0)
            + (hub ? 24.0 : 0.0);
        double avail = n.w - (tx - x) - right_reserve;

        var layout = new Pango.Layout (canvas.get_pango_context ());
        var fd = canvas.get_pango_context ().get_font_description ().copy ();
        fd.set_weight (n.is_root ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
        if (n.virtual) fd.set_style (Pango.Style.ITALIC);
        fd.set_absolute_size (13 * Pango.SCALE);
        layout.set_font_description (fd);
        layout.set_text (n.name, -1);
        layout.set_ellipsize (Pango.EllipsizeMode.END);
        layout.set_width ((int) (avail * Pango.SCALE));
        int lw, lh;
        layout.get_pixel_size (out lw, out lh);

        Gdk.RGBA name_col = n.is_root ? p.accent : (n.virtual ? p.dim : p.text);
        cr.set_source_rgba (name_col.red, name_col.green, name_col.blue, name_col.alpha);
        cr.move_to (tx, n.gy - lh / 2.0);
        Pango.cairo_show_layout (cr, layout);

        if (hub) {
            var deg = new Pango.Layout (canvas.get_pango_context ());
            var dfd = canvas.get_pango_context ().get_font_description ().copy ();
            dfd.set_weight (Pango.Weight.BOLD);
            dfd.set_absolute_size (11 * Pango.SCALE);
            deg.set_font_description (dfd);
            deg.set_text ("×%d".printf (n.parents.size), -1);
            int dw, dh;
            deg.get_pixel_size (out dw, out dh);
            double dx = x + n.w - (n.expandable && !n.expanded ? 22.0 : 8.0) - dw;
            cr.set_source_rgba (p.accent.red, p.accent.green, p.accent.blue, 1.0);
            cr.move_to (dx, n.gy - dh / 2.0);
            Pango.cairo_show_layout (cr, deg);
        }

        if (!n.is_root && n.expandable && !n.expanded) {
            double bx = x + n.w - 13.0;
            cr.set_source_rgba (p.text.red, p.text.green, p.text.blue, 0.10);
            cr.arc (bx, n.gy, 8.0, 0, 2 * Math.PI);
            cr.fill ();
            cr.set_source_rgba (p.text.red, p.text.green, p.text.blue, 0.75);
            cr.set_line_width (1.5);
            if (n.loading) {
                cr.arc (bx, n.gy, 5.0, 0, 1.4 * Math.PI);
                cr.stroke ();
            } else {
                cr.move_to (bx - 3.5, n.gy); cr.line_to (bx + 3.5, n.gy);
                cr.move_to (bx, n.gy - 3.5); cr.line_to (bx, n.gy + 3.5);
                cr.stroke ();
            }
        }
    }

    private void draw_more (Cairo.Context cr, GNode n, Palette p) {
        double x = n.gx - n.w / 2.0, y = n.gy - n.h / 2.0;
        rounded_rect (cr, x, y, n.w, n.h, 14.0);
        cr.set_source_rgba (p.brd.red, p.brd.green, p.brd.blue, 1.0);
        cr.set_line_width (1.0);
        cr.set_dash ({ 4.0, 3.0 }, 0);
        cr.stroke ();
        cr.set_dash ({}, 0);

        var layout = new Pango.Layout (canvas.get_pango_context ());
        var fd = canvas.get_pango_context ().get_font_description ().copy ();
        fd.set_absolute_size (12 * Pango.SCALE);
        layout.set_font_description (fd);
        layout.set_text (more_label (n), -1);
        int lw, lh;
        layout.get_pixel_size (out lw, out lh);
        cr.set_source_rgba (p.dim.red, p.dim.green, p.dim.blue, 1.0);
        cr.move_to (n.gx - lw / 2.0, n.gy - lh / 2.0);
        Pango.cairo_show_layout (cr, layout);
    }

    private static void rounded_rect (Cairo.Context cr, double x, double y, double w, double h, double r) {
        cr.new_sub_path ();
        cr.arc (x + w - r, y + r,     r, -0.5 * Math.PI, 0);
        cr.arc (x + w - r, y + h - r, r, 0,              0.5 * Math.PI);
        cr.arc (x + r,     y + h - r, r, 0.5 * Math.PI,  Math.PI);
        cr.arc (x + r,     y + r,     r, Math.PI,        1.5 * Math.PI);
        cr.close_path ();
    }

    private void on_click (Gtk.GestureClick g, int n_press, double px, double py) {
        int width  = canvas.get_width ();
        int height = canvas.get_height ();
        double gx = (px - width / 2.0 - offset_x) / scale;
        double gy = (py - height / 2.0 - offset_y) / scale;

        for (int i = nodes.size - 1; i >= 0; i--) {
            var n = nodes.get (i);
            double x = n.gx - n.w / 2.0, y = n.gy - n.h / 2.0;
            if (gx < x || gx > x + n.w || gy < y || gy > y + n.h) continue;

            if (n.is_more) { reveal_more (n); return; }

            if (n.virtual) { resolve_and_open.begin (n); return; }

            if (!n.is_root && n.expandable && !n.expanded && !n.loading) {
                double bx = x + n.w - 13.0;
                if ((gx - bx) * (gx - bx) + (gy - n.gy) * (gy - n.gy) <= 12.0 * 12.0) {
                    expand_into.begin (n);
                    return;
                }
            }
            win.show_details (new Data.SourceGroup (n.name), n.branch);
            return;
        }
    }

    private async void resolve_and_open (GNode n) {
        if (n.loading) return;
        n.loading = true;
        var api = new Data.AltRepoClient ();
        string? real = null;
        try {
            real = yield api.resolve_capability_source (branch, n.name, cancel);
        } catch (Error e) {
            warning ("[GraphPage] resolve %s failed: %s", n.name, e.message);
        }
        n.loading = false;
        if (cancel.is_cancelled ()) return;
        if (real != null)
            win.show_details (new Data.SourceGroup (real), branch);
    }

    private void fit_to_content () {
        fit_to_content_in (canvas.get_width (), canvas.get_height ());
        canvas.queue_draw ();
    }

    private void fit_to_content_in (int width, int height) {
        if (width <= 0 || height <= 0 || nodes.size == 0) return;

        bool any = false;
        double min_x = 0, max_x = 0, min_y = 0, max_y = 0;
        foreach (var n in nodes) {
            double l = n.gx - n.w / 2.0, r = n.gx + n.w / 2.0;
            double t = n.gy - n.h / 2.0, b = n.gy + n.h / 2.0;
            if (!any) { min_x = l; max_x = r; min_y = t; max_y = b; any = true; }
            min_x = double.min (min_x, l); max_x = double.max (max_x, r);
            min_y = double.min (min_y, t); max_y = double.max (max_y, b);
        }
        if (!any) return;

        double span_x = double.max (1.0, max_x - min_x);
        double span_y = double.max (1.0, max_y - min_y);
        double s = double.min ((width - 2 * MARGIN) / span_x,
                               (height - 2 * MARGIN) / span_y);
        scale = s.clamp (MIN_SCALE, MAX_SCALE);

        double mid_x = (min_x + max_x) / 2.0;
        double mid_y = (min_y + max_y) / 2.0;
        offset_x = -mid_x * scale;
        offset_y = -mid_y * scale;
    }
}
