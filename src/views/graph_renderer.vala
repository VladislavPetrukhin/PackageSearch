using Gtk;
using Adw;
using GLib;
using Intl;

public class GraphRenderer : GLib.Object {
    private const double NODE_H    = 34.0;
    private const double NODE_MINW = 110.0;
    private const double NODE_MAXW = 210.0;

    private Gtk.Widget widget;

    public GraphRenderer (Gtk.Widget widget) {
        this.widget = widget;
    }

    private Pango.Context pango () {
        return widget.get_pango_context ();
    }

    public void measure_node (GraphNode n) {
        if (n.is_more) {
            var l = new Pango.Layout (pango ());
            l.set_text (more_label (n), -1);
            int tw, th;
            l.get_pixel_size (out tw, out th);
            n.w = tw + 28;
            n.h = 28;
            return;
        }
        var layout = new Pango.Layout (pango ());
        layout.set_text (n.name, -1);
        int tw2, th2;
        layout.get_pixel_size (out tw2, out th2);
        double extras = (n.is_root ? 28.0 : 40.0)
                      + (!n.is_root && n.expandable && !n.expanded ? 22.0 : 0.0)
                      + (n.parents.size >= 2 ? 26.0 : 0.0);
        n.w = (tw2 + extras).clamp (NODE_MINW, NODE_MAXW);
        n.h = NODE_H;
    }

    private static string more_label (GraphNode n) {
        return _("show %d more").printf (n.pending.size) + "  →";
    }

    private struct Palette {
        Gdk.RGBA text; Gdk.RGBA dim; Gdk.RGBA card; Gdk.RGBA brd;
        Gdk.RGBA accent; Gdk.RGBA accent_brd; Gdk.RGBA edge;
    }

    private static Gdk.RGBA rgb (double r, double g, double b, double a = 1.0) {
        return { (float) r, (float) g, (float) b, (float) a };
    }

    private Palette palette (GraphMode mode) {
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
        p.edge = (mode == GraphMode.BUILD)
            ? rgb (0.16, 0.74, 0.46) : rgb (0.76, 0.45, 0.82);
        return p;
    }

    public void render (Cairo.Context cr, Gee.ArrayList<GraphNode> nodes, GraphMode mode,
                        double scale, double offset_x, double offset_y, int width, int height) {
        var p = palette (mode);

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

    private void draw_edge (Cairo.Context cr, GraphNode from, GraphNode to) {
        double x1 = from.gx + from.w / 2.0, y1 = from.gy;
        double x2 = to.gx - to.w / 2.0,     y2 = to.gy;
        double mx = (x1 + x2) / 2.0;
        cr.move_to (x1, y1);
        cr.curve_to (mx, y1, mx, y2, x2, y2);
        cr.stroke ();
    }

    private void draw_node (Cairo.Context cr, GraphNode n, Palette p) {
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

        var layout = new Pango.Layout (pango ());
        var fd = pango ().get_font_description ().copy ();
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
            var deg = new Pango.Layout (pango ());
            var dfd = pango ().get_font_description ().copy ();
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

    private void draw_more (Cairo.Context cr, GraphNode n, Palette p) {
        double x = n.gx - n.w / 2.0, y = n.gy - n.h / 2.0;
        rounded_rect (cr, x, y, n.w, n.h, 14.0);
        cr.set_source_rgba (p.brd.red, p.brd.green, p.brd.blue, 1.0);
        cr.set_line_width (1.0);
        cr.set_dash ({ 4.0, 3.0 }, 0);
        cr.stroke ();
        cr.set_dash ({}, 0);

        var layout = new Pango.Layout (pango ());
        var fd = pango ().get_font_description ().copy ();
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
}
