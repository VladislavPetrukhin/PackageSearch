using Gtk;
using Adw;
using GLib;

[GtkTemplate (ui = "/space/altlinux/PackageSearch/ui/package_hero.ui")]
public class PackageHero : Gtk.Box {
    [GtkChild] private unowned Gtk.Image icon;
    [GtkChild] private unowned Gtk.Label name_label;
    [GtkChild] private unowned Gtk.Label summary_label;
    [GtkChild] private unowned Gtk.Label group_label;

    public PackageHero (string name, string? summary, string? grp) {
        Object ();
        icon.icon_name = category_icon (grp);
        name_label.label = name;

        if (Ui.is_nonempty (summary)) {
            summary_label.label = summary;
            summary_label.visible = true;
        }
        if (Ui.is_nonempty (grp)) {
            group_label.label = grp;
            group_label.visible = true;
        }
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
}
