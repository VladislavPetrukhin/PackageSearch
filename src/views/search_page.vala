using Gtk;
using Adw;

[GtkTemplate (ui = "/org/example/PackageSearch/ui/search_page.ui")]
public class SearchPage : Adw.NavigationPage {
    [GtkChild] private unowned Gtk.SearchEntry search_entry;
    [GtkChild] private unowned Gtk.DropDown    branch_dropdown;
    [GtkChild] private unowned Gtk.ListView    list_view;

    private GLib.ListStore store;

    construct {
        store = new GLib.ListStore (typeof (Data.SourceGroup));
        var sel = new Gtk.SingleSelection (store);
        list_view.set_model (sel);

        // открытие деталей по activate
        list_view.activate.connect ((pos) => {
            var item = sel.get_selected_item ();
            var sg = item as Data.SourceGroup;
            if (sg == null) return;

            var w = this.get_root () as MainWindow;
            if (w != null) w.show_details (sg, current_branch ());
        });

        // поиск: по вводу и по Enter
        search_entry.search_changed.connect (() => do_search.begin ());
        search_entry.activate.connect       (() => do_search.begin ());
    }

    private string current_branch () {
        // TODO: прочитать реальную ветку из branch_dropdown
        return "sisyphus";
    }

    private async void do_search () {
        var term = (search_entry.get_text () ?? "").strip ();
        var api = new Data.AltRepoClient ();
        try {
            var results = yield api.search_source (current_branch (), term);
            store.remove_all ();
            foreach (var g in results) store.append (g);
        } catch (Error e) {
            warning (@"[SearchPage] search failed: $(e.message)");
        }
    }
}

