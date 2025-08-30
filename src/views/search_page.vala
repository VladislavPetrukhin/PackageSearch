using Gtk;
using Adw;

namespace Views {

public class SearchPage : Adw.Bin {
    private void toast (string msg) {
    var w = (Gtk.Widget) this;
    while (w != null) {
        if (w is Adw.ToastOverlay) {
            ((Adw.ToastOverlay) w).add_toast (new Adw.Toast (msg));
            return;
        }
        w = w.get_parent ();
    }
    warning (msg);
}

    private Data.AltRepoClient client = new Data.AltRepoClient ();
    private GLib.ListStore store;

    private Gtk.SearchEntry search_entry;
    private Gtk.Button      search_btn;
    private Gtk.ListView    list_view;

    public SearchPage () {
        Object ();

        store = new GLib.ListStore (typeof (Data.SourceGroup));

        search_entry = new Gtk.SearchEntry ();
        search_btn   = new Gtk.Button.with_label ("Search");

        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((obj) => {
            var item = (Gtk.ListItem) obj;
            var row = new Gtk.Label ("");
            row.xalign = 0.0f;
            item.set_child (row);
        });

      factory.bind.connect ((obj) => {
        var item = (Gtk.ListItem) obj;
        var row = (Gtk.Label) item.get_child ();
        var sg  = item.get_item () as Data.SourceGroup;
        row.label = (sg != null) ? sg.src_name : "";
    });



        var selection = new Gtk.SingleSelection (store);
        list_view = new Gtk.ListView (selection, factory);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        var hb  = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        hb.append (search_entry);
        hb.append (search_btn);
        box.append (hb);
        box.append (list_view);

        this.set_child (box);

        search_btn.clicked.connect (() => { do_search.begin (); });
        search_entry.activate.connect (() => { do_search.begin (); });

        do_search.begin ();
    }

    private string current_branch () {
        return "sisyphus";
    }

private async void do_search () {
    var term = search_entry.get_text ().strip ();
    stdout.printf ("[SearchPage] do_search term='%s' branch='%s'\n", term, current_branch ());

    if (term.length == 0) {
        toast ("Введите запрос");
        return;
    }

    try {
        var results = yield client.search_source (term, current_branch ());
        stdout.printf ("[SearchPage] search_source returned %u results\n", results.size);

        store.remove_all ();
        foreach (var g in results) {
            store.append (g);
            stdout.printf ("[SearchPage] appended result: %s\n", g.src_name);
        }

        if (results.size == 0) {
            toast ("Ничего не найдено");
        }
    } catch (Error e) {
        warning (@"[SearchPage] search failed: $(e.message)");
        toast ("Ошибка поиска");
    }
}

}

}

