using Gtk;
using Adw;
using GLib;
using Pango;

[GtkTemplate (ui = "/org/example/PackageSearch/ui/search_page.ui")]
public class SearchPage : Adw.NavigationPage {
    [GtkChild] private unowned Gtk.SearchEntry search_entry;
    [GtkChild] private unowned Gtk.DropDown    branch_dropdown;
    [GtkChild] private unowned Gtk.ListView    list_view;

    private GLib.ListStore store;
    private Gtk.SingleSelection sel;


    construct {
        // модель списка
        store = new GLib.ListStore (typeof (Data.SourceGroup));
        sel = new Gtk.SingleSelection (store);
        sel.autoselect = false;
        sel.can_unselect = true;
        list_view.model = sel;

        // Активировать по одиночному клику
        var click = new Gtk.GestureClick ();
        click.released.connect ((n_press, x, y) => {
            // Одиночный ЛКМ
            if (n_press == 1) {
                int idx = (int) sel.selected;
                if (idx >= 0) {
                    list_view.activate ((uint) idx);
                }
            }
        });
        list_view.add_controller (click);


        // выпадающий список веток
        try {
            var branches_model = new Gtk.StringList (null);
            string[] branch_names = { "sisyphus", "p11"};
            foreach (string b in branch_names) {
                branches_model.append (b);
                debug ("[SearchPage] добавлена ветка: %s", b);
            }
            branch_dropdown.model = branches_model;
            branch_dropdown.selected = 0;
        } catch (Error e) {
            warning ("[SearchPage] не удалось инициализировать список веток: %s", e.message);
        }

        // фабрика строк
        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((obj) => {
            var item = obj as Gtk.ListItem;
            if (item == null) { warning ("[SearchPage] setup: obj is not Gtk.ListItem"); return; }

            var row = new Gtk.Box (Orientation.VERTICAL, 0);
            row.margin_top = 8; row.margin_bottom = 8; row.margin_start = 12; row.margin_end = 12;

            var title = new Gtk.Label ("");
            title.halign = Align.START;
            title.ellipsize = Pango.EllipsizeMode.END;
            title.add_css_class ("title-3");

            var subtitle = new Gtk.Label ("");
            subtitle.halign = Align.START;
            subtitle.ellipsize = Pango.EllipsizeMode.END;
            subtitle.add_css_class ("dim-label");

            row.append (title);
            row.append (subtitle);
            item.set_child (row);
        });

        factory.bind.connect ((obj) => {
            var item = obj as Gtk.ListItem;
            if (item == null) { warning ("[SearchPage] bind: obj is not Gtk.ListItem"); return; }

            var row = item.get_child () as Gtk.Box;
            if (row == null) return;

            var title = row.get_first_child () as Gtk.Label;
            var subtitle = (title != null) ? (title.get_next_sibling () as Gtk.Label) : null;

            var sg = item.get_item () as Data.SourceGroup;
            if (sg == null) { warning ("[SearchPage] bind: item.get_item() null/invalid"); return; }

            if (title != null) title.label = sg.name;

            string vr = "";
            if (sg.version != null && sg.version.strip () != "") vr = sg.version;
            if (sg.release != null && sg.release.strip () != "")
                vr = (vr == "") ? sg.release : vr + "-" + sg.release;

            if (subtitle != null) subtitle.label = vr;
        });

        list_view.factory = factory;

        // активация строки
        list_view.activate.connect ((pos) => {
            uint position = (uint) pos;
            debug ("[SearchPage] activate: pos=%u", position);
            var obj = store.get_item ((int) position);
            var sg = obj as Data.SourceGroup;
            if (sg == null) { warning ("[SearchPage] activate: выбранный элемент null/invalid"); return; }
            var branch = current_branch ();
            debug ("[SearchPage] открыть детали: %s, branch=%s", sg.name, branch);

            var win = this.get_root () as MainWindow;
            if (win != null) win.show_details (sg, branch);
            else warning ("[SearchPage] MainWindow не найден — детали не открыты");
        });

        // события поиска/ветки
        search_entry.search_changed.connect (() => { debug ("[SearchPage] search_changed: %s", search_entry.text); do_search.begin (); });
        search_entry.activate.connect (() => { debug ("[SearchPage] activate (Enter) на поиске"); do_search.begin (); });
        branch_dropdown.notify["selected"].connect (() => { debug ("[SearchPage] ветка выбрана: %s", current_branch ()); do_search.begin (); });
    }

    private string current_branch () {
        int idx = (int) branch_dropdown.selected;
        var m = branch_dropdown.model as Gtk.StringList;
        if (m == null || idx < 0) return "sisyphus";
        return m.get_string ((uint) idx);
    }

    private static bool is_reasonable_term (string? s) {
        if (s == null) return false;
        string term = s.strip ();
        if (term.length < 2) return false;
        try {
            var re = new Regex ("^[A-Za-z0-9._+-]+$");
            return re.match (term);
        } catch (Error e) {
            // если Regex недоступен — просто проверим длину
            return term.length >= 2;
        }
    }

    private async void do_search () {
        var term = (search_entry.text ?? "").strip ();
        var branch = current_branch ();
        debug ("[SearchPage] do_search(): term='%s', branch='%s'", term, branch);

        if (!is_reasonable_term (term)) {
            debug ("[SearchPage] term too short/invalid -> clear list");
            store.remove_all ();
            return;
        }

        var api = new Data.AltRepoClient ();
        try {
            message ("[AltRepoClient] search_source term='%s', branch='%s'", term, branch);
            var results = yield api.search_source (branch, term);
            debug ("[SearchPage] получено результатов: %lu", (results != null) ? results.size : 0);

            Idle.add (() => {
                store.remove_all ();
                if (results != null) {
                    foreach (var g in results) if (g != null) store.append (g);
                }
                debug ("[SearchPage] список обновлён, всего: %u", store.get_n_items ());
                return Source.REMOVE;
            });
        } catch (Error e) {
            warning ("[SearchPage] do_search(): ошибка поиска: %s", e.message);
            store.remove_all ();
        }
    }
}

