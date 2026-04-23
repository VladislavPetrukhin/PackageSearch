using Gtk;
using Gdk;

// Central place for app-wide CSS. Loaded once at first use.
public class Style : GLib.Object {
    private static bool loaded = false;

    private const string CSS = """
    /* ---- Tags / pill badges ---- */
    .tag {
        padding: 2px 8px;
        border-radius: 9999px;
        font-size: 0.82em;
        font-weight: 600;
        background: alpha(@accent_bg_color, 0.15);
        color: @accent_color;
    }
    .tag.neutral   { background: alpha(currentColor, 0.10); color: inherit; opacity: 0.8; }
    .tag.success   { background: alpha(@success_color, 0.18); color: @success_color; }
    .tag.warning   { background: alpha(@warning_color, 0.20); color: @warning_color; }
    .tag.error     { background: alpha(@error_color, 0.20);   color: @error_color;   }
    .tag.accent    { background: alpha(@accent_bg_color, 0.22); color: @accent_color; }

    /* ---- Card list ---- */
    .results-scroll,
    .results-scroll > .frame,
    .results-scroll > viewport,
    .results-scroll > viewport > listview,
    .results-scroll > listview,
    .results-scroll listview.view {
        background-color: transparent;
        background: transparent;
        box-shadow: none;
    }
    .big-card {
        border-radius: 14px;
        border: 1px solid alpha(currentColor, 0.10);
        transition: border-color 140ms ease, background-color 140ms ease;
    }
    .big-card > box { padding: 14px 14px; min-height: 56px; }
    .big-card .subtitle { opacity: 0.7; font-size: 0.92em; }
    .big-card.hover {
        border-color: alpha(@accent_color, 0.7);
        background-color: alpha(@accent_bg_color, 0.07);
    }
    .result-icon {
        color: @accent_color;
        opacity: 0.85;
    }

    /* ---- Hero block on DetailsPage ---- */
    .pkg-hero {
        padding: 18px;
        margin: 10px 0 6px 0;
        border-radius: 16px;
        background: linear-gradient(160deg,
            alpha(@accent_bg_color, 0.22),
            alpha(@accent_bg_color, 0.04));
        border: 1px solid alpha(@accent_color, 0.20);
    }
    .pkg-hero .pkg-icon {
        color: @accent_color;
        background: alpha(@accent_bg_color, 0.28);
        border-radius: 16px;
        padding: 14px;
        -gtk-icon-size: 48px;
    }
    .pkg-hero .pkg-name { font-weight: 800; }
    .pkg-hero .pkg-summary { opacity: 0.8; }

    /* ---- Install button animation ---- */
    @keyframes ps-install-pulse {
        0%   { box-shadow: 0 0 0 0 alpha(@success_color, 0.55); }
        70%  { box-shadow: 0 0 0 8px alpha(@success_color, 0); }
        100% { box-shadow: 0 0 0 0 alpha(@success_color, 0); }
    }
    button.ps-installing {
        background: alpha(@success_color, 0.18);
        color: @success_color;
        animation: ps-install-pulse 1.2s ease-out infinite;
    }
    button.ps-installed {
        background: alpha(@success_color, 0.14);
        color: mix(@success_color, @window_fg_color, 0.5);
    }

    /* ---- Skeleton shimmer ---- */
    @keyframes ps-shimmer {
        0%   { opacity: 0.35; }
        50%  { opacity: 0.85; }
        100% { opacity: 0.35; }
    }
    .skeleton { animation: ps-shimmer 1.4s ease-in-out infinite; }
    .skeleton-line {
        background: alpha(currentColor, 0.18);
        border-radius: 6px;
        min-height: 10px;
    }

    /* ---- Spec file viewer ---- */
    .spec-view {
        font-family: monospace;
        font-size: 0.92em;
    }
    .spec-view text { padding: 10px 14px; }

    /* ---- Compact headerbar ---- */
    headerbar {
        min-height: 40px;
        padding-top: 0;
        padding-bottom: 0;
    }

    /* ---- Subtle sidebar selection highlight ---- */
    .sidebar listview row:selected .big-card {
        border-color: @accent_color;
        background: alpha(@accent_bg_color, 0.15);
    }

    /* ---- Version row current-branch accent ---- */
    .current-branch-row {
        background: alpha(@accent_bg_color, 0.10);
        border-left: 3px solid @accent_color;
    }
    """;

    public static void ensure () {
        if (loaded) return;
        var p = new Gtk.CssProvider ();
        p.load_from_string (CSS);
        var disp = Gdk.Display.get_default ();
        if (disp != null) {
            Gtk.StyleContext.add_provider_for_display (
                disp, p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }
        loaded = true;
    }

    // Build a GtkLabel styled as a small pill. tag_class is "" / "neutral" /
    // "success" / "warning" / "error" / "accent".
    public static Gtk.Label make_tag (string? text, string? tag_class = null) {
        var l = new Gtk.Label (text ?? "") { valign = Gtk.Align.CENTER };
        l.add_css_class ("tag");
        if (tag_class != null && tag_class.length > 0)
            l.add_css_class (tag_class);
        return l;
    }
}
