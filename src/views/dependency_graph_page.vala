using Gtk;
using Adw;
using GLib;
using Intl;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/dependency_graph_page.ui")]
public class DependencyGraphPage : Adw.NavigationPage {

    private const double COL_W      = 215.0;
    private const double ROW_H      = 50.0;
    private const double MARGIN     = 60.0;
    private const double MIN_SCALE  = 0.25;
    private const double MAX_SCALE  = 2.2;
    private const int    CHILD_LIMIT = 14;

    private MainWindow win;
    private string root_name;
    private string branch;
    private GraphMode   mode = GraphMode.BUILD;

    private Gee.ArrayList<GraphNode>           nodes   = new Gee.ArrayList<GraphNode> ();
    private Gee.HashMap<string, GraphNode>     present = new Gee.HashMap<string, GraphNode> ();

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

    private Gee.ArrayList<GraphNode> probe_queue = new Gee.ArrayList<GraphNode> ();
    private bool probing = false;

    private GraphRenderer renderer;

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
        renderer = new GraphRenderer (canvas);

        title_widget.title = _("Dependency graph");
        title_widget.subtitle = root_name + " · " + branch;
        empty_status.description = _("Could not build a graph for %s.").printf (root_name);

        mode_build.toggled.connect (() => {
            if (mode_build.active && mode != GraphMode.BUILD) { mode = GraphMode.BUILD; reset_and_load (); }
        });
        mode_reverse.toggled.connect (() => {
            if (mode_reverse.active && mode != GraphMode.REVERSE) { mode = GraphMode.REVERSE; reset_and_load (); }
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
        var root = new GraphNode ();
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

    private async Gee.ArrayList<Data.DependencyPackage> fetch_deps (GraphNode n) {
        var api = new Data.DependencyApi ();
        try {
            Gee.ArrayList<Data.DependencyPackage>? r;
            if (mode == GraphMode.BUILD)
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

    private async void expand_into (GraphNode n) {
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

    private void materialize (GraphNode n, Gee.ArrayList<Data.DependencyPackage> kids) {
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
            var more = new GraphNode ();
            more.is_more = true;
            more.depth = n.depth + 1;
            more.more_parent = n;
            more.pending = overflow;
            nodes.add (more);
        }
    }

    private void add_child (GraphNode parent, string name, string br) {
        if (present.has_key (name)) {
            var existing = present.get (name);
            if (existing != parent && !existing.parents.contains (parent))
                existing.parents.add (parent);
            return;
        }
        var n = new GraphNode ();
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

    private void enqueue_probe (GraphNode n) {
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

    private void reveal_more (GraphNode more) {
        foreach (var d in more.pending) {
            if (Ui.is_nonempty (d.name))
                add_child (more.more_parent, d.name, d.branch ?? branch);
        }
        nodes.remove (more);
        relayout ();
    }

    private void relayout () {
        var by_depth = new Gee.HashMap<int, Gee.ArrayList<GraphNode>> ();
        int max_depth = 0;
        foreach (var n in nodes) {
            renderer.measure_node (n);
            if (!by_depth.has_key (n.depth)) by_depth.set (n.depth, new Gee.ArrayList<GraphNode> ());
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

    private void draw (Gtk.DrawingArea da, Cairo.Context cr, int width, int height) {
        if (!fitted && width > 0 && height > 0 && nodes.size > 1) {
            fit_to_content_in (width, height);
            fitted = true;
        }
        renderer.render (cr, nodes, mode, scale, offset_x, offset_y, width, height);
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

    private async void resolve_and_open (GraphNode n) {
        if (n.loading) return;
        n.loading = true;
        var api = new Data.DependencyApi ();
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
