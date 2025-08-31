using Gtk;
using Adw;
using GLib;

public class PrefsWindow : Adw.PreferencesWindow {
    private Adw.ComboRow lang_row;
    private weak MainWindow parent_win;
    private bool applying = false;

    public PrefsWindow (MainWindow parent) {
        Object (modal: true, transient_for: parent);
        this.parent_win = parent;

        this.set_title (_("Preferences"));

        var page = new Adw.PreferencesPage ();
        var grp_general = new Adw.PreferencesGroup () { title = _("General") };

        lang_row = new Adw.ComboRow () {
            title = _("Language"),
            subtitle = _("Language switch"),
        };

        var langs = new Gtk.StringList (null);
        langs.append (_("System"));   // 0
        langs.append ("English");     // 1
        langs.append ("Русский");     // 2
        lang_row.set_model (langs);
        lang_row.set_selected (_current_lang_index ());
        grp_general.add (lang_row);

        page.add (grp_general);
        this.add (page);

        lang_row.notify["selected"].connect (() => {
            if (applying) return;

            string? code = null;
            switch (lang_row.get_selected ()) {
                case 0: code = null; break;
                case 1: code = "en"; break;
                case 2: code = "ru"; break;
                default: return;
            }

            var cur = Environment.get_variable ("LANGUAGE");
            if ((code == null && (cur == null || cur == "")) ||
                (code != null && cur != null && cur.has_prefix (code)))
                return;

            applying = true;

            this.close ();

            Idle.add (() => {
                if (parent_win != null) parent_win.apply_language (code);
                applying = false;
                return Source.REMOVE;
            });
        });
    }

    private uint _current_lang_index () {
        var lang = Environment.get_variable ("LANGUAGE");
        if (lang == null || lang == "") return 0;
        if (lang.has_prefix ("en"))    return 1;
        if (lang.has_prefix ("ru"))    return 2;
        return 0;
    }
}

