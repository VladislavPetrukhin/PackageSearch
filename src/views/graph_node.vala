using GLib;

public enum GraphDir { ROOT, BUILD, REVERSE }

public class GraphNode : GLib.Object {
    public string   name;
    public string   branch;
    public int      depth;
    public GraphDir dir;
    public bool    is_root;
    public bool    is_more;
    public bool    expandable;
    public bool    expanded;
    public bool    loading;
    public bool    virtual;
    public bool    probed;
    public Gee.ArrayList<Data.DependencyPackage>? cached_children;
    public Gee.ArrayList<GraphNode> parents = new Gee.ArrayList<GraphNode> ();
    public GraphNode? more_parent;
    public Gee.ArrayList<Data.DependencyPackage> pending = new Gee.ArrayList<Data.DependencyPackage> ();
    public double  gx;
    public double  gy;
    public double  w;
    public double  h;
}
